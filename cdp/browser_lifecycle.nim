## cdp/browser_lifecycle.nim
##
## Запуск и переиспользование Chromium с постоянным профилем — общая для
## всех siteworkers/*.nim инфраструктура, ничего специфичного для
## конкретного сайта здесь нет (см. пояснение к разделу ниже про модель
## владения процессом). Соседний слой той же общей инфраструктуры —
## ../siteworkers/siteworker_common.nim (типы) и ../cdp/clipboard.nim
## (скриншот ответа, буфер обмена).

import std/[asyncdispatch, os, osproc, strformat, strutils, tables, sequtils, json, times]
import ../childtear
import ../siteworkers/siteworker_common

# ---------------------------------------------------------------------------
# Site workers: запуск и переиспользование Chromium с постоянным профилем
# ---------------------------------------------------------------------------
#
# Ничего специфичного для конкретного сайта здесь нет — работает только с
# profileDir/port/headless, а сама специфика остаётся в siteworkers/*.nim
# (askQwen()/askKimi() в siteworkers/qwen.nim и siteworkers/kimi.nim,
# uploadToRedcircle() в siteworkers/redcircle.nim и т.д. для будущих
# модулей). Вынесено сюда из бывшего общего siteworker.nim, когда он был
# разделён на отдельные модули по сайтам.
#
# Модель владения процессом:
#
# * ensureBrowser() сперва быстро проверяет (DefaultAliveProbeTimeoutMs), отвечает
#   ли уже что-то CDP на нужном порту (более ранний вызов, отдельный
#   CLI-клиент или браузер, поднятый вручную) — если да, просто
#   подключается к нему, не создавая новый процесс.
#
# * Если нет — запускается новый процесс Chromium, который намеренно НЕ
#   завершается по окончании askQwen()/askKimi(): он остаётся жить в
#   фоне, чтобы следующие обращения находили его уже поднятым и просто
#   открывали новую вкладку, не платя заново за холодный старт.
#
# * За явное завершение общего экземпляра отвечает stopBrowser(port) —
#   шлёт CDP-команду Browser.close тому, что слушает порт, вне
#   зависимости от того, кто его запустил. ensureBrowser() её не
#   вызывает — вызывающий код (askQwen()/askKimi()/uploadToRedcircle()
#   и т.п.) открывает и закрывает только СВОИ вкладки.
#
# * stdout/stderr дочернего Chromium уводятся в /dev/null через
#   `sh -c ... </dev/null >/dev/null 2>&1`: без читателя долгоживущий
#   процесс рано или поздно забьёт буфер вывода и зависнет на записи в
#   него (см. предупреждение std/osproc.waitForExit про deadlock без
#   poParentStreams). По той же причине хэндл Process после запуска не
#   сохраняется: std/osproc.close() на живом процессе принудительно его
#   убивает, что противоположно цели оставить Chromium жить дальше.
#
# * Гонка при параллельном вызове ensureBrowser() на один порт в рамках
#   ОДНОГО процесса ОС разрешается кэшем "текущий незавершённый запуск"
#   (см. launching ниже). Гонку между разными процессами ОС гасит
#   встроенный в сам Chromium singleton-механизм профиля
#   (SingletonLock/SingletonSocket).

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
  ## Ищет среди процессов (через /proc/*/cmdline — только Linux, как и
  ## findChromiumBinary() выше по PATH) Chromium, запущенный с
  ## --remote-debugging-port=port, и возвращает значение его
  ## --user-data-dir. Пустая строка — не нашли подходящий процесс, либо
  ## он был запущен без --user-data-dir в cmdline (не Linux, permission
  ## denied на /proc/<pid>/cmdline чужого пользователя — тоже тихо даёт
  ## пустую строку).
  ##
  ## ЗАЧЕМ: ensureBrowserImpl() ниже при живом CDP на port ПОДКЛЮЧАЕТСЯ
  ## к нему, не проверяя вообще, с каким --user-data-dir этот процесс
  ## был когда-то запущен — если на порту завис/остался чужой или
  ## просто самый первый когда-либо запущенный этим кодом процесс
  ## (например, из-за упавшего вручную/аварийно предыдущего прогона,
  ## после которого Chromium не закрылся), все дальнейшие вызовы молча
  ## работают в СОВЕРШЕННО ДРУГОМ профиле, чем ожидает вызывающий
  ## код — включая тот, в который вы только что вручную залогинились
  ## через SiteProfileSetup. Итог неотличим от "сайт снова не пускает":
  ## дашборд/чат по-прежнему не грузится, хотя реальный профиль на диске
  ## давно в порядке — просто автоматика ходит не в него. См. её
  ## использование в ensureBrowserImpl() — при обнаруженном расхождении
  ## явная ошибка лучше тихого использования не того профиля.
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
  ## Запускает Chromium с постоянным профилем profileDir и открытым
  ## remote-debugging-портом port, отвязывая stdout/stderr от нашего
  ## процесса через `sh -c '... </dev/null >/dev/null 2>&1'` (sh делает
  ## exec в сам Chromium, тот же PID) — процесс живёт независимо от
  ## нашего, хэндл Process сознательно не сохраняется (см. пояснение выше).
  ##
  ## proxyUrl (если непусто) передаётся Chromium как --proxy-server —
  ## В ОТЛИЧИЕ от yt-dlp (см. ProxyVars в yt2mave.nim), Chromium НЕ читает
  ## http_proxy/https_proxy/ALL_PROXY из окружения процесса надёжным
  ## образом на всех платформах, так что для сайт-воркеров (Qwen,
  ## mave.digital, RedCircle, Kimi) прокси нужно явно указывать через этот
  ## параметр, а не полагаться на переменные окружения, как для yt-dlp.
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
  ## Путь к файлу базы cookies профиля — см. пояснение в
  ## hasCookiesForDomain() у SiteProfileSetup.nim про два возможных
  ## расположения в зависимости от версии Chromium. Пустая строка —
  ## профиль ещё ни разу не логинился (файла попросту нет).
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
  ## true, если cookies на диске менялись ПОСЛЕ последнего известного
  ## этому коду (пере)запуска Chromium с этим профилем — то есть кто-то
  ## залогинился (например, вручную через SiteProfileSetup.nim) уже
  ## после того, как уже отвечающий на порту процесс поднял в память
  ## свой cookie jar при СВОЁМ старте.
  ##
  ## ЗАЧЕМ ЭТО ВАЖНО: Chromium читает базу cookies с диска только при
  ## запуске процесса — дальше работает с cookie jar в памяти и не
  ## перечитывает файл только потому, что его изменил кто-то другой.
  ## Поэтому "профиль на диске давно залогинен" и "уже отвечающий на
  ## порту процесс тоже залогинен" — РАЗНЫЕ утверждения: PID может
  ## висеть с прошлого запуска (даже прошлой недели), не зная о входе,
  ## сделанном намного позже него — и тогда переиспользование этого
  ## процесса (см. ensureBrowserImpl ниже) выглядит один в один как
  ## "профиль снова разлогинен", хотя реальная причина совсем другая.
  ## Без этой проверки единственным выходом было бы вручную найти и
  ## убить процесс (kill) — она делает то же самое автоматически.
  ##
  ## Если маркер ещё не записан (профиль никогда не запускался этим
  ## кодом, либо запись маркера тогда не удалась) — считаем процесс
  ## неподтверждённым и, для безопасности, тоже "устаревшим": лишний
  ## перезапуск дешевле часов непонятных сбоев.
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

proc ensureBrowserImpl(profileDir: string, port: int, headless: bool,
                        proxyUrl: string = ""): Future[BrowserHandle] {.async.} =
  ## Переиспользует уже запущенный на port Chromium (если жив, его
  ## профиль совпадает с profileDir — см. findChromiumProfileForPort() —
  ## и его cookie jar не устарел относительно диска — см.
  ## isAttachedBrowserStale()), иначе (пере)запускает процесс с
  ## профилем profileDir и возвращает описатель BrowserHandle с флагом
  ## attached (был ли процесс уже запущен кем-то другим, или его
  ## подняли только что).
  ##
  ## ВАЖНО: если Chromium на port уже жив и его переиспользуют
  ## (attached = true), proxyUrl этого вызова ИГНОРИРУЕТСЯ —
  ## переподключение не перезапускает существующий процесс с новыми
  ## флагами. Если поменяли proxyUrl в config.ini, а Chromium остался
  ## от предыдущего запуска без прокси — эта функция сама его не
  ## тронет (в отличие от случая устаревших cookies ниже, тут нет
  ## сигнала "что-то изменилось", по которому можно было бы решить
  ## перезапустить) — используйте stopBrowser(port) вручную.
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
        "прошли бы мимо реальных cookies/сессии — останавливаю раньше, чем " &
        &"наделаю запросов не туда. Завершите его вручную (kill, или см. " &
        "stopBrowser() в childtear.nim) и запустите заново.")
    if not isAttachedBrowserStale(profileDir):
      return BrowserHandle(browser: newBrowser(port = port), port: port,
                            profileDir: profileDir, attached: true)
    # cookies на диске обновились уже ПОСЛЕ старта этого процесса (см.
    # isAttachedBrowserStale()) — его in-memory сессия заведомо не
    # видит свежий логин. Перезапускаем процесс сами, а не оставляем
    # вызывающему коду находить и убивать PID вручную.
    await stopBrowser(port)
    # Close() закрывает браузер асинхронно — процесс может не успеть
    # полностью выйти и освободить порт мгновенно; даём немного времени,
    # прежде чем пытаться запустить на этом же порту новый процесс.
    for _ in 1 .. 20:
      if not await isBrowserAlive(port):
        break
      await sleepAsync(250)
  launchDetachedChromium(profileDir, port, headless, proxyUrl)
  let browser = newBrowser(port = port)
  await waitForReady(browser, timeoutMs = DefaultBrowserReadyTimeoutMs)
  recordCookiesMtimeMarker(profileDir)
  result = BrowserHandle(browser: browser, port: port, profileDir: profileDir, attached: false)

proc ensureBrowser*(profileDir: string, port: int, headless: bool,
                     proxyUrl: string = ""): Future[BrowserHandle] {.async.} =
  ## Возвращает подключение к Chromium на порту port с профилем
  ## profileDir: либо к уже работающему (attached = true в результате),
  ## либо к только что запущенному этим самым вызовом (attached =
  ## false). Безопасна при параллельных вызовах на один и тот же порт в
  ## рамках текущего процесса ОС — см. launching и пояснение про гонки
  ## выше.
  ##
  ## proxyUrl — см. пояснение в launchDetachedChromium()/ensureBrowserImpl()
  ## про --proxy-server и про то, что он не действует на уже запущенный
  ## процесс. По умолчанию пусто — прежнее поведение (без прокси) не
  ## меняется для вызывающих, которые этот параметр не передают.
  if hasKey(launching, port):
    return await launching[port]
  let fut = ensureBrowserImpl(profileDir, port, headless, proxyUrl)
  launching[port] = fut
  try:
    result = await fut
  finally:
    del(launching, port)

proc stopBrowser*(port: int): Future[void] {.async.} =
  ## Явно завершает Chromium, слушающий данный порт, — вне зависимости
  ## от того, кто и когда его запустил (см. пояснение выше). Если порт
  ## уже пуст (никто не отвечает) — ничего не делает.
  ##
  ## Также вызывается САМОЙ ensureBrowserImpl() выше — при обнаружении,
  ## что уже запущенный на порту процесс устарел относительно диска
  ## (см. isAttachedBrowserStale()) — прежде чем поднять взамен свежий.
  ## Кроме этого случая, ни ensureBrowser(), ни askQwen()/askKimi() эту
  ## функцию сами не вызывают: явное управление жизненным циклом общего
  ## экземпляра в остальном — дело вызывающего кода (например, отдельной
  ## CLI-команды 'stop').
  if not await isBrowserAlive(port):
    return
  await close(newBrowser(port = port))

proc ensureBrowserForLogin*(profileDir: string, port: int): Future[BrowserHandle] {.async.} =
  ## Готовит Chromium для ИНТЕРАКТИВНОГО входа в постоянный профиль
  ## profileDir на этом порту. В ОТЛИЧИЕ от ensureBrowser() выше — не
  ## переиспользует то, что уже отвечает CDP на порту, а безусловно
  ## останавливает это (см. stopBrowser()) и поднимает взамен свежий
  ## процесс с headless = false.
  ##
  ## ЗАЧЕМ ОТДЕЛЬНАЯ ФУНКЦИЯ, А НЕ ensureBrowser(profileDir, port,
  ## headless = false): если на порту уже фоново живёт headless-процесс
  ## от предыдущего автоматического прогона (типичная ситуация — см.
  ## модель владения процессом в шапке файла), обычный ensureBrowser()
  ## просто ПОДКЛЮЧИЛСЯ бы к нему как есть, никак не запуская новое
  ## видимое окно — пользователь, ожидающий увидеть браузер для входа,
  ## ничего бы не увидел, хотя вызов формально завершился бы успешно.
  ##
  ## Предназначена для интерактивных CLI-команд входа (например,
  ## yt2mave --login-qwen/--login-mave — см. loginQwen()/loginMave() в
  ## соответствующих siteworkers/*.nim), а НЕ для обычного пути
  ## askQwen()/uploadToMave(): тем видимый браузер не нужен, а
  ## безусловный перезапуск процесса на каждый вызов был бы там просто
  ## медленнее без всякой пользы.
  await stopBrowser(port)
  # Close() закрывает браузер асинхронно (см. тот же приём в
  # ensureBrowserImpl() выше) — даём немного времени освободить порт,
  # прежде чем поднимать на нём новый процесс.
  for _ in 1 .. 40:
    if not await isBrowserAlive(port):
      break
    await sleepAsync(250)
  launchDetachedChromium(profileDir, port, headless = false)
  let browser = newBrowser(port = port)
  await waitForReady(browser, timeoutMs = DefaultBrowserReadyTimeoutMs)
  recordCookiesMtimeMarker(profileDir)
  result = BrowserHandle(browser: browser, port: port, profileDir: profileDir, attached: false)

proc gotoWithRetry*(browser: Browser, url: string,
                     attempts = 3, delayMs = 2_000, verbose = true): Future[Tab] {.async.} =
  ## Тонкая обёртка над newPage(): на холодном старте первый переход
  ## изредка падает с net::ERR_TUNNEL_CONNECTION_FAILED, пока Chromium
  ## ещё разрешает прокси-настройки, хотя сеть в целом рабочая — эта
  ## версия дополнительно печатает прогресс между попытками (при verbose).
  ## Без зависимости от SiteWorkerPref — используется всеми модулями
  ## siteworkers/*.nim, а не только "AI-чат" (askQwen/askKimi).
  ##
  ## Ловит CatchableError целиком, а не только ChildTearError — см.
  ## подробное объяснение у newPageWithRetry() (тот же newPage() внутри,
  ## та же категория транспортных сбоев HTTP-вызова к /json/new мимо
  ## ChildTearError, если ловить только его).
  for attempt in 1 .. attempts:
    try:
      return await newPage(browser, url)
    except CatchableError as e:
      if attempt == attempts:
        raise e
      if verbose:
        echo "Переход не удался (попытка ", $attempt, "/", $attempts, "): ", e.msg
        echo "Пробую снова через ", $(delayMs div 1000), " сек..."
      await sleepAsync(delayMs)

proc dumpDebugInfoVerbose*(tab: Tab, prefix: string, pref: set[SiteWorkerPref]) {.async.} =
  ## Сохраняет снимок страницы (screenshot + HTML + консоль браузера)
  ## через childtear.dumpDebugInfo() и, при pVerbose, печатает краткую
  ## сводку. Сама запись файлов на диск, в свою очередь,
  ## происходит только при pDumpDebug — без него функция не делает
  ## вообще ничего (ни записи, ни печати), даже если вызвана из ветки
  ## обработки ошибки: молчаливость по умолчанию для этой библиотеки
  ## важнее удобства постфактум-отладки (см. пояснение к pDumpDebug).
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


