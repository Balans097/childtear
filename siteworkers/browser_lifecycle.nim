## siteworkers/browser_lifecycle.nim
##
## Запуск и переиспользование Chromium с постоянным профилем — общая для
## siteworkers/*.nim инфраструктура без привязки к сайту. Соседние модули:
## ./siteworker_common.nim (типы) и ./clipboard.nim (скриншот ответа,
## буфер обмена).

import std/[asyncdispatch, os, osproc, strformat, strutils, tables, sequtils, json, times]
import ../childtear
import ./siteworker_common

# ---------------------------------------------------------------------------
# Запуск и переиспользование Chromium с постоянным профилем
# ---------------------------------------------------------------------------
#
# Модуль работает только с profileDir/port/headless; специфика сайтов
# остаётся в siteworkers/*.nim. Модель владения процессом:
#
# * ensureBrowser() сначала быстро проверяет (DefaultAliveProbeTimeoutMs),
#   отвечает ли CDP на порту (прошлый вызов, другой CLI или браузер,
#   поднятый вручную); если да — подключается, не создавая процесс.
# * Иначе запускается новый Chromium, который намеренно не завершается
#   после askQwen()/askKimi(): следующие вызовы находят его живым и просто
#   открывают вкладку, не платя за холодный старт.
# * Завершает общий экземпляр stopBrowser(port) (CDP-команда Browser.close
#   тому, кто слушает порт). Вызывающий код открывает и закрывает только
#   свои вкладки.
# * stdout/stderr Chromium уходят в /dev/null (`sh -c ... </dev/null
#   >/dev/null 2>&1`): без читателя долгоживущий процесс рано или поздно
#   забьёт буфер вывода и зависнет. Хэндл Process не сохраняется:
#   osproc.close() на живом процессе его убивает, а цель — оставить
#   Chromium жить.
# * Гонку параллельных ensureBrowser() на один порт внутри одного процесса
#   ОС гасит кэш текущего запуска (launching); между процессами ОС — сам
#   Chromium (SingletonLock/SingletonSocket профиля).

type
  BrowserHandle* = object
    browser*: Browser
    port*: int
    profileDir*: string
    attached*: bool
      ## true, если ensureBrowser() подключилась к уже работавшему
      ## экземпляру, false — если запустила новый. Чисто информационное
      ## поле для вызывающего кода (например, для сообщения в консоль) —
      ## на дальнейшую работу с browser/вкладками не влияет.

const
  DefaultAliveProbeTimeoutMs* = 800
    ## Короткий таймаут для проверки "уже ли отвечает CDP на этом
    ## порту" — типичный случай (порт свободен, нужно запускать новый
    ## процесс) не должен платить за это полным waitForReady().
  DefaultBrowserReadyTimeoutMs* = 15_000
    ## Таймаут ожидания готовности CDP-порта только что запущенного
    ## нами процесса (см. waitForReady() в childtear.nim).

var launching: Table[int, Future[BrowserHandle]]
  ## port -> незавершённый вызов ensureBrowser() в рамках текущего
  ## процесса ОС (см. пояснение про гонки выше). Ключ — именно порт, а
  ## не (profileDir, port): порт и так однозначно определяет площадку,
  ## поскольку каждый сайт держит свой отдельный фиксированный порт
  ## (см. *DebugPort в конкретных siteworkers/*.nim).

proc findChromiumBinary(): string =
  ## Ищет бинарник Chromium/Chrome под разными именами, под которыми он
  ## обычно ставится в разных дистрибутивах.
  const candidates = [
    "chromium-browser", "chromium",
    "google-chrome", "google-chrome-stable"
  ]
  for name in candidates:
    result = findExe(name)
    if len(result) > 0:
      return result
  raise newException(SiteWorkerError,
    "не найден исполняемый файл chromium/chrome в PATH — " &
    "установите chromium-browser или google-chrome")

proc isBrowserAlive(port: int): Future[bool] {.async.} =
  ## Быстрая (см. DefaultAliveProbeTimeoutMs) проверка "отвечает ли уже что-то
  ## CDP-протоколом на этом порту" — в отличие от waitForReady(), не
  ## повторяет попытки, а даёт один быстрый ответ да/нет.
  let browser = newBrowser(port = port)
  try:
    result = await withTimeout(version(browser), DefaultAliveProbeTimeoutMs)
  except CatchableError:
    result = false

proc findChromiumProfileForPort(port: int): string =
  ## Ищет по /proc/*/cmdline (только Linux) Chromium, запущенный с
  ## --remote-debugging-port=port, и возвращает его --user-data-dir. Пустая
  ## строка — процесс не найден, запущен без --user-data-dir или нет
  ## доступа к /proc/<pid>/cmdline.
  ##
  ## Нужна, потому что при живом CDP ensureBrowserImpl() подключается к
  ## процессу, не зная его профиля: если там чужой или самый первый процесс,
  ## автоматика молча работала бы в другом профиле, что выглядит как "сайт
  ## снова не пускает". Явная ошибка лучше тихого использования не того
  ## профиля.
  result = ""
  let portFlag = &"--remote-debugging-port={port}"
  try:
    for pidDir in walkDir("/proc"):
      if pidDir.kind != pcDir:
        continue
      let pidStr = extractFilename(pidDir.path)
      if not allCharsInSet(pidStr, {'0'..'9'}):
        continue
      let cmdlinePath = pidDir.path / "cmdline"
      var raw: string
      try:
        raw = readFile(cmdlinePath)
      except CatchableError:
        continue
      let args = split(raw, '\0')
      if portFlag notin args:
        continue
      for a in args:
        if startsWith(a, "--user-data-dir="):
          return a[len("--user-data-dir=") .. ^1]
      return ""  # нашли процесс с этим портом, но без явного --user-data-dir
  except CatchableError:
    discard


proc launchDetachedChromium(profileDir: string, port: int, headless: bool,
                             proxyUrl: string = "") =
  ## Запускает Chromium с профилем profileDir и портом отладки port,
  ## отвязав stdout/stderr (`sh -c '... </dev/null >/dev/null 2>&1'`, sh
  ## делает exec в Chromium, PID тот же): процесс живёт независимо от
  ## нашего, хэндл Process не сохраняется (см. модель владения выше).
  ##
  ## proxyUrl (если непусто) передаётся как --proxy-server. Переменные
  ## окружения http_proxy/https_proxy/ALL_PROXY Chromium читает
  ## ненадёжно, поэтому прокси задаётся только этим параметром.
  createDir(profileDir)
  let
    binary = findChromiumBinary()
    args = @[
      &"--remote-debugging-port={port}",
      &"--user-data-dir={profileDir}",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-notifications",
      # Фиксированный размер окна: у headless-Chromium без явного
      # --window-size окно по умолчанию узкое, из-за чего адаптивная
      # вёрстка сайта смещает элементы и клики по координатам
      # (childtear кликает по getBoundingClientRect()) промахиваются.
      "--window-size=1440,900",
    ] & (if headless: @["--headless=new", "--no-sandbox", "--disable-blink-features=AutomationControlled"]
         else: newSeq[string]()) & (if len(proxyUrl) > 0: @["--proxy-server=" & proxyUrl]
         else: newSeq[string]())
    shellCmd = quoteShellPosix(binary) & " " & join(map(args, quoteShellPosix), " ") &
               " </dev/null >/dev/null 2>&1"
  discard startProcess("/bin/sh", args = ["-c", shellCmd], options = {})

proc stopBrowser*(port: int): Future[void] {.async.}
  ## Опережающее объявление: нужна уже в ensureBrowserImpl() ниже, чтобы
  ## самостоятельно перезапускать процесс с устаревшим (относительно
  ## диска) cookie jar — полностью определяется чуть ниже, у остального
  ## жизненного цикла браузера, где ей самое место по смыслу.

proc cookiesFilePath(profileDir: string): string =
  ## Путь к файлу базы cookies профиля (расположение зависит от версии
  ## Chromium). Пустая строка — профиль ещё ни разу не логинился.
  for rel in ["Default" / "Network" / "Cookies", "Default" / "Cookies"]:
    let path = profileDir / rel
    if fileExists(path):
      return path
  result = ""

proc cookiesMtimeMarkerPath(profileDir: string): string =
  profileDir / ".ensureBrowser-cookies-mtime"

proc recordCookiesMtimeMarker(profileDir: string) =
  ## Запоминает текущее время изменения базы cookies профиля — точку
  ## отсчёта, с которой сверяется свежесть уже запущенного процесса при
  ## следующем подключении (см. isAttachedBrowserStale() ниже). Вызывать
  ## сразу после (пере)запуска Chromium с этим профилем.
  let cookiesPath = cookiesFilePath(profileDir)
  if len(cookiesPath) == 0:
    return
  try:
    writeFile(cookiesMtimeMarkerPath(profileDir), $toUnix(getLastModificationTime(cookiesPath)))
  except CatchableError:
    discard  # не смогли записать маркер — не критично, просто следующая проверка сочтёт профиль "неизвестным" и на всякий случай перезапустит

proc isAttachedBrowserStale(profileDir: string): bool =
  ## true, если cookies на диске менялись после последнего известного нам
  ## (пере)запуска Chromium с этим профилем, то есть вход выполнен уже
  ## после того, как процесс на порту прочитал cookie jar. Chromium читает
  ## базу cookies только при старте, и переиспользование такого процесса
  ## выглядит как "профиль снова разлогинен"; проверка заменяет ручной
  ## kill. Если маркер не записан, процесс считается устаревшим: лишний
  ## перезапуск дешевле долгой отладки.
  let cookiesPath = cookiesFilePath(profileDir)
  if len(cookiesPath) == 0:
    return false  # профиль ещё не логинился вообще — сверять не с чем, перезапуск ничего не изменит
  let markerPath = cookiesMtimeMarkerPath(profileDir)
  if not fileExists(markerPath):
    return true
  try:
    let recordedMtime = parseBiggestInt(strutils.strip(readFile(markerPath)))
    let currentMtime = toUnix(getLastModificationTime(cookiesPath))
    result = currentMtime != recordedMtime
  except CatchableError:
    result = true  # не смогли разобрать маркер — на всякий случай считаем устаревшим

proc restartOnPort(port: int, waitSteps: int) {.async.} =
  ## Останавливает Chromium на порту и ждёт (до waitSteps * 250 мс), пока
  ## порт освободится, — Browser.close закрывает процесс асинхронно.
  ## Если порт так и не освободился, бросает SiteWorkerError: запуск
  ## второго процесса на занятый порт молча ушёл бы в старый браузер.
  await stopBrowser(port)
  for _ in 1 .. waitSteps:
    if not await isBrowserAlive(port):
      return
    await sleepAsync(250)
  raise newException(SiteWorkerError,
    &"Chromium на порту {port} не завершился за {waitSteps * 250} мс — остановите его вручную")

proc launchAndWait(profileDir: string, port: int, headless: bool,
                   proxyUrl: string): Future[BrowserHandle] {.async.} =
  ## Запускает новый Chromium, ждёт готовности CDP и запоминает время
  ## изменения cookies профиля (см. isAttachedBrowserStale()).
  launchDetachedChromium(profileDir, port, headless, proxyUrl)
  let browser = newBrowser(port = port)
  await waitForReady(browser, timeoutMs = DefaultBrowserReadyTimeoutMs)
  recordCookiesMtimeMarker(profileDir)
  result = BrowserHandle(browser: browser, port: port, profileDir: profileDir, attached: false)

proc ensureBrowserImpl(profileDir: string, port: int, headless: bool,
                        proxyUrl: string = ""): Future[BrowserHandle] {.async.} =
  ## Переиспользует Chromium на port, если он жив, его профиль совпадает с
  ## profileDir (findChromiumProfileForPort()) и cookie jar не устарел
  ## (isAttachedBrowserStale()); иначе (пере)запускает процесс. Результат —
  ## BrowserHandle (attached = true, если процесс уже работал).
  ##
  ## При переиспользовании proxyUrl игнорируется: существующий процесс не
  ## перезапускается с новыми флагами. После смены прокси остановите
  ## браузер вручную (stopBrowser(port)).
  if await isBrowserAlive(port):
    let actualProfile = findChromiumProfileForPort(port)
    # Пустая строка — findChromiumProfileForPort() не смогла определить
    # профиль процесса (не Linux, нет доступа к /proc/<pid>/cmdline и
    # т.п.) — в этом случае молча доверяем существующему процессу, а не
    # блокируем работу диагностикой, которая сама не сработала.
    if len(actualProfile) > 0 and actualProfile != profileDir:
      raise newException(SiteWorkerError,
        &"на порту {port} уже отвечает CDP, но это Chromium с ДРУГИМ профилем " &
        &"({actualProfile}), а не ожидаемым ({profileDir}) — вероятно, завис " &
        "процесс от предыдущего/чужого запуска (например, после аварийного " &
        "завершения без остановки браузера). Все действия в чужом профиле " &
        "прошли бы мимо реальных cookies/сессии — останавливаю до того, как " &
        &"наделаю запросов не туда. Завершите его вручную (kill, или см. " &
        "stopBrowser() в childtear.nim) и запустите заново.")
    if not isAttachedBrowserStale(profileDir):
      return BrowserHandle(browser: newBrowser(port = port), port: port,
                            profileDir: profileDir, attached: true)
    # cookies на диске обновились уже ПОСЛЕ старта этого процесса (см.
    # isAttachedBrowserStale()) — его in-memory сессия заведомо не
    # видит свежий логин. Перезапускаем процесс сами, а не оставляем
    # вызывающему коду находить и убивать PID вручную.
    await restartOnPort(port, 20)
  result = await launchAndWait(profileDir, port, headless, proxyUrl)

proc ensureBrowser*(profileDir: string, port: int, headless: bool,
                     proxyUrl: string = ""): Future[BrowserHandle] {.async.} =
  ## Возвращает подключение к Chromium на port с профилем profileDir: к
  ## работающему (attached = true) или только что запущенному (attached =
  ## false). Безопасна при параллельных вызовах на один порт внутри одного
  ## процесса ОС (см. launching). proxyUrl — см. ensureBrowserImpl(); по
  ## умолчанию пусто (без прокси).
  if hasKey(launching, port):
    return await launching[port]
  let fut = ensureBrowserImpl(profileDir, port, headless, proxyUrl)
  launching[port] = fut
  try:
    result = await fut
  finally:
    del(launching, port)

proc stopBrowser*(port: int): Future[void] {.async.} =
  ## Завершает Chromium, слушающий port, независимо от того, кто его
  ## запустил; если порт пуст, ничего не делает. Вызывается также из
  ## ensureBrowserImpl(), когда процесс на порту устарел относительно диска
  ## (isAttachedBrowserStale()). В остальном жизненным циклом общего
  ## экземпляра управляет вызывающий код (например, командой 'stop').
  if not await isBrowserAlive(port):
    return
  await close(newBrowser(port = port))

proc ensureBrowserForLogin*(profileDir: string, port: int): Future[BrowserHandle] {.async.} =
  ## Готовит Chromium для интерактивного входа в профиль profileDir: в
  ## отличие от ensureBrowser() безусловно останавливает процесс на порту
  ## (stopBrowser()) и запускает свежий с headless = false. Иначе при живом
  ## фоновом headless-процессе произошло бы подключение к нему, и окно
  ## входа не появилось бы. Для интерактивных команд входа (loginQwen(),
  ## loginMave()); обычный путь askQwen()/uploadToMave() видимый браузер не
  ## использует, и перезапуск на каждый вызов лишь замедлил бы работу.
  await restartOnPort(port, 40)
  result = await launchAndWait(profileDir, port, false, "")

proc gotoWithRetry*(browser: Browser, url: string,
                     attempts = 3, delayMs = 2_000, verbose = true): Future[Tab] {.async.} =
  ## newPageWithRetry() с печатью прогресса между попытками (при verbose).
  ## Нужна, потому что на холодном старте первый переход изредка падает с
  ## net::ERR_TUNNEL_CONNECTION_FAILED, пока Chromium разрешает прокси.
  proc report(attempt, total: int, msg: string) {.gcsafe.} =
    if verbose:
      echo "Переход не удался (попытка ", attempt, "/", total, "): ", msg
      echo "Пробую снова через ", delayMs div 1000, " сек..."
  result = await newPageWithRetry(browser, url, attempts, delayMs, report)

proc dumpDebugInfoVerbose*(tab: Tab, prefix: string, pref: set[SiteWorkerPref]) {.async.} =
  ## Сохраняет снимок страницы (screenshot + HTML + консоль) через
  ## childtear.dumpDebugInfo() и при pVerbose печатает краткую сводку.
  ## Без pDumpDebug не делает ничего (ни записи, ни печати), даже из
  ## ветки ошибки: библиотека по умолчанию не должна оставлять файлы.
  if pDumpDebug notin pref:
    return
  let diag = await dumpDebugInfo(tab, prefix)
  vecho(pref, "Отладочные файлы сохранены: ", prefix, ".png, ", prefix, ".html, ", prefix, "-console.json")
  if pVerbose in pref and diag.kind == JArray and len(diag) > 0:
    echo "В ", prefix, "-console.json есть записи (", len(diag), ") — JS-ошибки и/или неуспешные " &
      "сетевые запросы, зафиксированные на странице:"
    for i, entry in getElems(diag):
      if i >= 5:
        echo "  ... и ещё ", len(diag) - 5, " запис(ей), см. файл целиком"
        break
      let
        kind = if hasKey(entry, "kind"): getStr(entry["kind"]) else: "?"
        detail = if hasKey(entry, "detail"): getStr(entry["detail"]) else: $entry
      echo "  [", kind, "] ", detail


