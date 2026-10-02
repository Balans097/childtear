## siteworkers/mavedigital.nim
##
## Автоматизация загрузки эпизода подкаста на https://app.mave.digital
## поверх childtear: переключиться на нужный канал (MaveChannel), нажать
## "Добавить выпуск", прикрепить аудио, дождаться обработки, заполнить
## номер выпуска на вкладке "Дополнительно" (touchEpisodeNumber(): без
## него публикация не проходит), название и тайминги, опубликовать.
##
##   import siteworkers/mavedigital
##   waitFor uploadToMave(mcHistory, "Гость — Название", "00:00 — интро", "Файл.mp3")
##
## Как и siteworkers/redcircle.nim, использует постоянный профиль Chromium
## (~/.cache/mavedigital/profile), переиспользуемый между вызовами
## (browser_lifecycle.ensureBrowser()/stopBrowser()). Сама не логинится:
## вход выполняется заранее через loginMave(). У аккаунта четыре канала в
## одном логине, между ними переключаются перед загрузкой.
##
## Селекторы строятся по видимому тексту, а не по нестабильным CSS-классам;
## общие примитивы (unmark(), pageHasText(), markByButtonText(),
## markBySelectorText(), markFieldByLabel(), markFieldByAnyLabel(),
## markInputByAccept()) — в ./siteworker_common.nim.
##
## Метки полей после прикрепления файла: "Заголовок выпуска" и "Описание
## выпуска". markFieldByLabel() сравнивает метку точно, поэтому
## fillEpisodeTitle()/fillEpisodeTimings() перебирают формулировки из
## TitleFieldLabelCandidates/TimingsFieldLabelCandidates; при смене
## формулировки добавьте новую в этот список.




import std/[os, strutils, strformat, asyncdispatch, json, times, sequtils, unicode]
import ../childtear
import ./siteworker_common
import ./browser_lifecycle




# ---------------------------------------------------------------------------
# Ошибки модуля
# ---------------------------------------------------------------------------
#
# Используется общий SiteWorkerError из ./siteworker_common.nim; ошибки
# childtear (ChildTearError) пробрасываются как есть.


type
  MaveChannel* = enum
    ## Четыре канала аккаунта app.mave.digital. Строка —
    ## точный текст пункта в переключателе канала и в заголовке дашборда
    ## ("Axonic — <значение>"); по ней находится пункт списка
    ## (selectChannel) и проверяется переключение (waitForChannelSelected).
    mcNews = "НОВОСТИ"
    mcHistory = "ИСТОРИЯ"
    mcScience = "НАУКА и ТЕХНОЛОГИИ"
    mcArt = "КЛАССИЧЕСКОЕ ИСКУССТВО"

proc parseMaveChannel*(text: string): MaveChannel =
  ## Разбирает ответ Qwen с названием канала без учёта регистра и
  ## пробелов по краям. Бросает ValueError с перечнем допустимых значений,
  ## если text не совпал ни с одним каналом (ответ модели вне списка — не
  ## сбой сети, вызывающему стоит ловить его отдельно). Используется
  ## unicode.toLower(): toLowerAscii() не трогает кириллицу.
  let needle = unicode.toLower(strutils.strip(text))
  for channel in MaveChannel:
    if unicode.toLower($channel) == needle:
      return channel
  raise newException(ValueError,
    &"неизвестный канал mave.digital: '{text}' (ожидался один из: " &
    mapIt(MaveChannel, $it).join(", ") & ")")


const
  MaveBaseUrl = "https://app.mave.digital"
  DashboardUrl* = MaveBaseUrl & "/dashboard"
    ## Экспортирован — та же точка входа пригодна внешним CLI-инструментам
    ## для первичного ручного входа в сохранённый профиль (см. пояснение
    ## про авторизацию в шапке файла).

  AddEpisodeButtonText = "Добавить выпуск"
  NewEpisodeHeaderText = "Новый выпуск"
  ChooseFileButtonText = "Выбрать файл"
  UploadFileButtonText = "Загрузить файл"
    ## Кнопка внутри модального окна "Новый выпуск", подтверждающая
    ## прикрепление файла (см. скриншот модального окна) — неактивна,
    ## пока файл не выбран (см. waitUntilEnabled() в attachEpisodeFile()).

  TitleFieldLabelCandidates = @[
    "Заголовок выпуска", "Название", "Название выпуска", "Заголовок", "Title", "Episode Title"
  ]
    ## Реальная метка поля — полная фраза "Заголовок выпуска": сравнение в
    ## markFieldByLabel() точное, короткое "Заголовок" не находится. Первым
    ## стоит самый вероятный вариант, остальные — на случай смены разметки.
    ## @[...] (seq): markFieldByAnyLabel() принимает seq[string].
  TitleFieldSelector = "[aria-label=\"Заголовок выпуска\"]"
    ## То же поле, но как CSS-селектор, а не метка для
    ## markFieldByAnyLabel(): используется в publishEpisode() для проверки,
    ## что форма редактирования выпуска закрылась после публикации
    ## (проверка pageHasText(tab, title) давала ложные срабатывания).
    ## Разметка: `<input ... aria-label="Заголовок выпуска" ...>`.
  TimingsFieldLabelCandidates = @[
    "Описание выпуска", "Тайминги", "Главы", "Таймкоды", "Описание", "Chapters", "Description"
  ]
    ## "Описание выпуска" — то же поле, что и для TitleFieldLabelCandidates
    ## (точное, а не частичное сравнение в markFieldByLabel()). Отдельного
    ## поля таймингов на экране нет: тайминги пишутся целиком в единственное
    ## текстовое поле описания.
  PublishButtonTextCandidates = [
    "Опубликовать", "Сохранить", "Готово", "Publish", "Save", "Save Episode"
  ]

  MainTabButtonText = "Основное"
  AdditionalTabButtonText = "Дополнительно"
    ## Вкладки формы выпуска ("Основное | Дополнительно | Главы | Обложка |
    ## Пейволл") — это <li role="button">, их находит тот же
    ## markByButtonText(), что и кнопки.
    ##
    ## Вкладка "Дополнительно" обязательна (класс "list__item required"):
    ## пока поле "Выпуск" на ней (EpisodeNumberFieldLabelCandidates) не
    ## тронуто, клиентская валидация молча блокирует "Опубликовать" — без
    ## смены URL и ошибок в консоли, до исчерпания PublishConfirmTimeoutMs.
    ## См. touchEpisodeNumber().
  EpisodeNumberFieldLabelCandidates = @[
    "Выпуск", "Номер выпуска", "Episode", "Episode Number", "Episode number"
  ]
  EpisodeNumberValue = "1"
    ## Нумерация выпусков не используется, значение неважно: нужно только,
    ## чтобы поле было изменено. fill() сначала выделяет содержимое, затем
    ## вставляет через Input.insertText, поэтому input/change срабатывают
    ## даже при совпадении с текущим значением. "1" — обычное ручное значение.

  MarkAttr = "data-mave-mark"
    ## Свой markAttr (а не DefaultMarkAttr из ./siteworker_common.nim) —
    ## на случай, если вызывающий код параллельно использует siteworker_common.mark*() для
    ## чего-то ещё на той же вкладке.

  ModalTimeoutMs = 20_000
    ## Ожидание появления модального окна "Новый выпуск" после клика по
    ## "Добавить выпуск".
  FieldTimeoutMs* = 10_000
    ## Ожидание появления полей/кнопок в уже открытом модальном окне или
    ## на экране, следующем за ним. Экспортирован — та же величина
    ## пригодна внешним CLI-инструментам для ожидания кнопки
    ## 'Добавить выпуск'.
  ContentAckTimeoutMs = 60_000
    ## Ожидание признака "файл принят" (кнопка "Загрузить файл" стала
    ## активной) после назначения файла инпуту — для больших аудиофайлов
    ## может занимать время.
  EditScreenTimeoutMs = 15_000
    ## Ожидание формы редактирования эпизода (вкладки "Основное"/
    ## "Дополнительно") после закрытия модалки "Новый выпуск" (см.
    ## modalGone() в confirmUpload()). Закрытие модалки не доказывает, что
    ## форма открылась: приложение иногда возвращается на голый /dashboard,
    ## и без проверки сбой всплывает позже как "не нашлась вкладка". См.
    ## checkEditScreenOpened().
  ProcessingTimeoutMs = 300_000
    ## Нижний порог ожидания перехода от модалки загрузки файла к экрану
    ## названия/таймингов после "Загрузить файл": сервер обрабатывает аудио,
    ## для крупных файлов это долго. В вызовах берётся max(значение,
    ## оценка по размеру файла) — см. uploadTimeoutForFile() и
    ## MaveUploadRateBytesPerSec.
  PublishConfirmTimeoutMs = 120_000
    ## Ожидание подтверждения публикации после нажатия кнопки из
    ## PublishButtonTextCandidates. Та же оговорка про нижний порог, что
    ## у ProcessingTimeoutMs выше, — см. uploadTimeoutForFile().
  PublishClickRegisterTimeoutMs = 2_500
  PublishClickAttempts = 3
    ## См. clickRegistered() в publishEpisode(): кнопка "Опубликовать"
    ## реагирует на клик (текст/disabled) на клиенте почти мгновенно, задолго
    ## до ответа сервера. 2.5 сек достаточно, чтобы отличить "клик дошёл" от
    ## "клик потерялся", и повторное нажатие в этот срок безопасно: сервер не
    ## успел бы принять публикацию.
  MaveUploadRateBytesPerSec = 128 * 1024
    ## Пессимистичная оценка скорости приёма файла сервером mave.digital:
    ## наблюдалось проседание до ~72 КБ/с при живой загрузке. 128 КБ/с даёт
    ## ~2-кратный запас, вместе с x2 в waitForFileUploadComplete() — ~4-
    ## кратный. Служит нижним пределом ожидания для файла данного размера
    ## (запас — UploadTimeoutMarginMs). Если на крупных файлах таймауты всё
    ## ещё впритык, уменьшите константу (например, до 64*1024).
  UploadTimeoutMarginMs = 120_000
    ## Запас поверх чисто расчётного времени передачи файла — на его
    ## обработку сервером ПОСЛЕ приёма (транскодирование и т.п.), которая
    ## тоже требует времени и не сводится к одной лишь передаче байт.
  DefaultDashboardReadyTimeoutMs* = 30_000
    ## После перехода на DashboardUrl SPA показывает полноэкранный лоадер
    ## (<div id="app"><div class="loader">...). gotoWithRetry()/newPage()
    ## ждут только навигацию, поэтому markChannelSwitcher() сразу после неё
    ## не нашёл бы сайдбар (см. waitForDashboardReady()). 30 сек. — оценка
    ## для обычной сети; значение переопределяется параметром
    ## dashboardReadyTimeoutMs у selectChannel()/uploadToMave().
  ChannelSwitchTimeoutMs = 10_000
  ChannelSwitchAttempts = 3
  UploadRetryAttempts = 2
    ## Сколько раз пробовать цепочку clickAddEpisode() -> attachEpisodeFile()
    ## -> confirmUpload(), если после закрытия окна "Новый выпуск" приложение
    ## возвращается на /dashboard вместо формы эпизода (см.
    ## editScreenOpened()). Случалось без JS-ошибок и сетевых сбоев, то есть
    ## это разовый глюк навигации, который не лечится ожиданием на месте.
    ## Аналогично ChannelSwitchAttempts: клик по помеченному пункту меню (по
    ## вычисленным координатам) иногда не переключал канал вовсе — вероятно,
    ## из-за CSS-перехода при раскрытии списка. Поэтому вся
    ## последовательность (открыть, выбрать, подтвердить) повторяется до
    ## ChannelSwitchAttempts раз (см. selectChannel()).

  DebugPort* = 9227
    ## Отдельный от Qwen/Kimi/RedCircle порт (см. одноимённые константы
    ## в siteworkers/qwen.nim, siteworkers/kimi.nim,
    ## siteworkers/redcircle.nim) — чтобы отдельные профили/вкладки этих
    ## сайтов не пересекались при параллельной работе. Экспортирован по
    ## той же причине, что и в siteworkers/redcircle.nim.
  ProfileDir* = getHomeDir() / ".cache" / "mavedigital" / "profile"
    ## См. пояснение про авторизацию в шапке файла.

  LoginPageButtonText = "Войти в платформу"
    ## Текст кнопки экрана входа (title страницы — "Войти в аккаунт mave").
    ## Показывается вместо дашборда, когда сессия в ProfileDir истекла (см.
    ## DashboardState/waitForDashboardReady): без отдельного распознавания
    ## это неотличимо от зависшего лоадера, а ждать таймаут бессмысленно.

  WelcomePromoMarkerText = "Добро пожаловать в mave"
    ## Одноразовый промо-оверлей mave+ ("Добро пожаловать в mave" /
    ## "Расширь свои возможности с подпиской mave+"), который сервер
    ## показывает поверх дашборда после свежего логина. Дашборд уже готов,
    ## но кнопка "Добавить выпуск" перекрыта, и без распознавания это
    ## выглядит как dsTimeout (зависший лоадер).

type
  DashboardState = enum
    ## Результат waitForDashboardReady(). Варианты разделены, потому что
    ## "сессия протухла" (войти вручную в ProfileDir) и "SPA зависла"
    ## (разбираться с приложением/сетью) лечатся по-разному, и
    ## selectChannel() сообщает именно то, что произошло.
    dsReady        ## дашборд отрисовался, можно работать дальше
    dsLoginRequired ## сервер вернул экран входа — сессия не авторизована
    dsTimeout      ## не дождались ни дашборда, ни экрана входа

proc dismissWelcomePromo(tab: Tab, verbose: bool) {.async.} =
  ## Пытается закрыть промо-оверлей WelcomePromoMarkerText, не зная точной
  ## разметки крестика. По очереди (best-effort, ошибки глушатся): Escape,
  ## затем клик по вероятным селекторам крестика
  ## (CloseModalSelectorCandidates). Исключений не бросает: следующий тик
  ## опроса в waitForDashboardReady() покажет, помогло ли.
  if verbose: echo "  Обнаружен промо-оверлей mave+ — пробую закрыть..."
  try:
    await pressKey(tab, "Escape")
  except CatchableError:
    discard
  const CloseModalSelectorCandidates = [
    "[aria-label=\"Закрыть\"]", "[aria-label=\"Close\"]",
    ".m-modal__close", ".modal__close", "button.close",
  ]
  for selector in CloseModalSelectorCandidates:
    try:
      await click(tab, selector)
      break
    except CatchableError:
      continue

proc waitForDashboardReady(tab: Tab, timeoutMs: int, verbose: bool = false): Future[DashboardState] {.async.} =
  ## Ждёт, пока дашборд app.mave.digital отрисуется поверх лоадера SPA (см.
  ## DefaultDashboardReadyTimeoutMs). Признак готовности — текст кнопки
  ## "Добавить выпуск": она нужна дальше (clickAddEpisode()), и её наличие
  ## означает, что сайдбар с переключателем канала уже в DOM.
  ##
  ## В том же опросе отслеживаются:
  ##  * экран входа (LoginPageButtonText): сессия истекла, возвращается
  ##    dsLoginRequired сразу, без ожидания timeoutMs;
  ##  * промо-оверлей WelcomePromoMarkerText поверх готового дашборда: кнопка
  ##    перекрыта, оверлей закрывается (dismissWelcomePromo()), опрос
  ##    продолжается.
  ##
  ## Перезагрузка на середине бюджета: бывало, что SPA не показывала никаких
  ## признаков жизни весь таймаут (в <head> не появлялось ссылок на чанки
  ## экранов, то есть зависала загрузка стартового бандла — например, из-за
  ## протухшего Service Worker или битого кэша в долгоживущем профиле).
  ## Увеличение timeoutMs не помогает, поэтому бюджет делится пополам: если
  ## первая половина не дала признаков жизни, выполняется одна жёсткая
  ## перезагрузка (reload(tab, ignoreCache = true)) и ждётся вторая половина.
  ## Если проблема на стороне сервера, перезагрузка не поможет, но и не вредит.
  var loginSeen = false
  var promoDismissAttempted = false
  proc check(): Future[bool] {.async.} =
    if await pageHasText(tab, LoginPageButtonText):
      loginSeen = true
      return true
    if await pageHasText(tab, AddEpisodeButtonText):
      return true
    if not promoDismissAttempted and await pageHasText(tab, WelcomePromoMarkerText):
      promoDismissAttempted = true  # пробуем закрыть только один раз, не долбим Escape/клик на каждый тик опроса
      await dismissWelcomePromo(tab, verbose)
    result = false

  let firstHalfMs = timeoutMs div 2
  var settled = await waitUntilTrue(check, firstHalfMs, 300)
  if not settled and not loginSeen:
    if verbose:
      echo "  Дашборд не подал признаков жизни за первую половину отведённого " &
           "времени — пробую жёстко перезагрузить страницу (минуя кэш) и жду ещё раз..."
    try:
      await reload(tab, ignoreCache = true)
      promoDismissAttempted = false  # страница свежая — оверлей, если появится, ещё не пытались закрывать
    except CatchableError as e:
      if verbose: echo "  Перезагрузка не удалась (", e.msg, ") — продолжаю опрос без неё."
    settled = await waitUntilTrue(check, timeoutMs - firstHalfMs, 300)

  if loginSeen:
    result = dsLoginRequired
  elif settled:
    result = dsReady
  else:
    result = dsTimeout


# ---------------------------------------------------------------------------
# Диагностика: скриншоты по шагам и дамп при ошибке
# ---------------------------------------------------------------------------
#
# Тот же приём, что в siteworkers/redcircle.nim (StepRecorder/dumpOnFailure);
# не вынесен в ./siteworker_common.nim, так как завязан на screenshotDir.

type
  StepRecorder = ref object
    dir: string
    index: int
    recordSteps: bool
      ## Пошаговые скриншоты нужны только для отладки и включаются явно:
      ## это лишний I/O на каждый шаг. dumpOnFailure() срабатывает при
      ## ошибке всегда, независимо от флага, поэтому dir передаётся
      ## вызывающей стороной постоянно, а recordSteps управляет только
      ## частотой (каждый шаг или только сбой).

proc newStepRecorder(dir: string, recordSteps: bool): StepRecorder =
  result = StepRecorder(dir: dir, index: 0, recordSteps: recordSteps)
  if len(dir) > 0:
    createDir(dir)

proc step(rec: StepRecorder, tab: Tab, label: string) {.async.} =
  if len(rec.dir) == 0 or not rec.recordSteps:
    return
  inc(rec.index)
  let safeLabel = multiReplace(label, {" ": "-", "/": "-", "\\": "-"})
  let path = rec.dir / (&"{rec.index:02}-{safeLabel}.png")
  try:
    await screenshot(tab, path, fullPage = true)
    let url = await currentUrl(tab)
    echo "  [скриншот] ", path, "  (URL: ", url, ")"
  except CatchableError as e:
    echo "  [скриншот] не удалось сохранить ", path, ": ", e.msg

proc dumpOnFailure(tab: Tab, prefix: string, screenshotDir: string = "") {.async.} =
  ## В отличие от step(), не зависит от recordSteps: при ошибке дамп нужен
  ## всегда, условие одно — непустой screenshotDir. Кроме screenshot/html/
  ## console сохраняет текущий URL в .url-файл и печатает его: по нему
  ## сразу видно, на форме эпизода ли мы или нас откинуло на /dashboard
  ## (по сообщению это выглядит как "не нашёлся элемент").
  if len(screenshotDir) == 0:
    return
  try:
    createDir(screenshotDir)
    let fullPrefix = screenshotDir / prefix
    discard await dumpDebugInfo(tab, fullPrefix)
    let url = await currentUrl(tab)
    writeFile(fullPrefix & ".url", url)
    echo "Отладочные файлы сохранены: ", fullPrefix, ".png, ", fullPrefix, ".html, ", fullPrefix, "-console.json"
    echo "  URL на момент сбоя: ", url
    if url == DashboardUrl or url == (DashboardUrl & "/"):
      echo "  ВНИМАНИЕ: это URL дашборда — похоже, приложение успело полностью " &
        "уйти со страницы редактирования эпизода до этого шага (не просто не " &
        "нашёлся элемент на нужном экране)."
  except CatchableError:
    discard


proc uploadTimeoutForFile(path: string, baseTimeoutMs: int): int =
  ## max(baseTimeoutMs, оценка времени передачи файла по каналу
  ## ~2 Мбит/с (MaveUploadRateBytesPerSec/UploadTimeoutMarginMs)).
  ## Используется везде, где ожидание зависит от времени приёма аудио
  ## сервером. Если размер файла узнать не удалось, возвращает
  ## baseTimeoutMs без изменений.
  try:
    let sizeBytes = getFileSize(path)
    let estimatedMs = int((sizeBytes.float / MaveUploadRateBytesPerSec.float) * 1000.0) + UploadTimeoutMarginMs
    result = max(baseTimeoutMs, estimatedMs)
  except OSError:
    result = baseTimeoutMs


proc waitForFileUploadComplete(tab: Tab, absPath: string, verbose: bool,
                                screenshotDir: string = "") {.async.} =
  ## Причина клика "Опубликовать", который проходит все проверки (не
  ## перекрыт, не disabled, координаты верны), но не вызывает сетевых
  ## запросов: загрузка аудио на сервер продолжается в фоне и после
  ## открытия формы /create-episode (сайдбар показывает "Загружается... N%
  ## X МБ из Y МБ" до появления плеера с длительностью). Для файла ~111 МБ
  ## это заняло больше 7 минут — на порядок дольше остального сценария.
  ## Пока файл не догрузился, "Опубликовать" молча ничего не делает, поэтому
  ## ждать нужно ДО клика, а не только после него.
  const UploadingMarkerText = "Загружается"
  proc stillUploading(): Future[bool] {.async.} = result = await pageHasText(tab, UploadingMarkerText)
  if not await stillUploading():
    return # обычный случай для небольших файлов — уже успело догрузиться
  if verbose: echo "  Аудиофайл ещё догружается на сервер в фоне — жду завершения..."
  # x2 к оценке по размеру файла: mave.digital иногда сбрасывает загрузку
  # на 100% и передаёт файл заново с нуля; со второй попытки обычно
  # докачивает, но одной оценки "размер / скорость" на это не хватает.
  let timeoutMs = uploadTimeoutForFile(absPath, ProcessingTimeoutMs) * 2
  proc uploadDone(): Future[bool] {.async.} = result = not (await stillUploading())
  if not await waitUntilTrue(uploadDone, timeoutMs, 2_000):
    await dumpOnFailure(tab, "mave-debug-upload-still-in-progress", screenshotDir)
    raise newException(SiteWorkerError,
      &"аудиофайл так и не догрузился на сервер за {timeoutMs div 1000} сек (в сайдбаре всё ещё " &
      &"'{UploadingMarkerText}...') — публикация в этом состоянии не пройдёт, пока догрузка не завершится")
  if verbose: echo "  Аудиофайл догружен, можно публиковать."


# ---------------------------------------------------------------------------
# Переключение канала
# ---------------------------------------------------------------------------
#
# Каналы переключаются виджетом в верху сайдбара. Разметка:
#
#   <div id="selectControl" class="podcast-select__control ...">
#     <span class="... label">Axonic — <канал></span>
#   </div>
#   <div class="podcast-select__menu ...">
#     <ul class="menu-list">
#       <li class="menu-item"><span class="... menu-item__label">Axonic — <канал></span></li>
#     </ul>
#   </div>
#
# Текст в обоих местах — "Axonic — <канал>" (с префиксом аккаунта), поэтому
# название канала ищется подстрокой, а не сравнением на равенство.
#
# Пункты списка (.podcast-select__menu .menu-item) остаются в DOM и при
# закрытом списке (скрыты CSS), а pageHasText()/textContent не отличает
# скрытый текст от видимого: проверка "канал уже выбран?" по всей странице
# ложно сработала бы на скрытом пункте. Поэтому используется getText() по
# точному селектору активного лейбла (ChannelSwitcherLabelSelector): он
# читает innerText и скрытого текста не видит.

const
  ChannelSwitcherControlSelector = "#selectControl"
    ## Сам кликабельный виджет-переключатель в шапке сайдбара.
  ChannelSwitcherLabelSelector = "#selectControl .label"
    ## Текст АКТИВНОГО канала внутри виджета (см. пояснение выше).
  ChannelMenuItemSelector = ".podcast-select__menu .menu-item"
    ## Пункты уже ОТКРЫТОГО выпадающего списка — используется только
    ## после клика по ChannelSwitcherControlSelector, когда список
    ## действительно раскрыт (и потому видим) — см. markChannelMenuItem().

proc currentChannelLabel(tab: Tab): Future[string] {.async.} =
  ## Текст активного канала в виджете-переключателе ("Axonic — <канал>"),
  ## или "" — если сам виджет ещё не отрисовался (страница ещё грузится)
  ## или пропал по какой-то другой причине. getText() читает innerText —
  ## поэтому, в отличие от pageHasText()/document.body.textContent, не
  ## видит скрытых CSS-ом элементов (см. пояснение выше про закрытый
  ## список каналов).
  try:
    result = await getText(tab, ChannelSwitcherLabelSelector)
  except ChildTearError:
    result = ""

proc channelAlreadySelected(tab: Tab, channel: MaveChannel): Future[bool] {.async.} =
  let cur = unicode.toLower(strutils.strip(await currentChannelLabel(tab)))
  result = len(cur) > 0 and (unicode.toLower($channel) in cur)

proc markChannelMenuItem(tab: Tab, channel: MaveChannel): Future[bool] {.async.} =
  ## Ищет пункт ЦЕЛЕВОГО канала в уже открытом выпадающем списке
  ## переключателя (ChannelMenuItemSelector). Вызывать только после
  ## клика по ChannelSwitcherControlSelector: пока список закрыт,
  ## элементы есть в DOM, но скрыты.
  result = await markBySelectorText(tab, ChannelMenuItemSelector,
    $channel, exact = false, markAttr = MarkAttr)

proc waitForChannelSelected(tab: Tab, channel: MaveChannel, timeoutMs: int): Future[bool] {.async.} =
  proc selected(): Future[bool] {.async.} = result = await channelAlreadySelected(tab, channel)
  result = await waitUntilTrue(selected, timeoutMs, 200)


proc selectChannel*(tab: Tab, channel: MaveChannel, verbose: bool,
                     screenshotDir: string = "",
                     dashboardReadyTimeoutMs: int = DefaultDashboardReadyTimeoutMs): Future[void] {.async.} =
  ## Переключает текущий выбранный канал аккаунта на channel. Не делает
  ## ничего (кроме проверки), если channel уже выбран — избегаем
  ## лишнего клика по уже открытому состоянию свитчера.
  ##
  ## Экспортирован — пригоден для вызова отдельно от uploadToMave(),
  ## например для диагностики самого переключения без создания эпизода.
  case await waitForDashboardReady(tab, dashboardReadyTimeoutMs, verbose)
  of dsReady:
    discard
  of dsLoginRequired:
    await dumpOnFailure(tab, "mave-debug-login-required", screenshotDir)
    raise newException(SiteWorkerError,
      &"app.mave.digital перенаправил на страницу входа ('{LoginPageButtonText}') вместо " &
      &"дашборда — сохранённая сессия профиля Chromium ({ProfileDir}) истекла или была " &
      "разлогинена. Это не сбой конвейера и не проблема с сетью/селекторами: автоматика не " &
      "умеет логиниться сама (см. пояснение про авторизацию в шапке siteworkers/" &
      "mavedigital.nim) — нужно вручную войти в аккаунт mave.digital ЗАНОВО в этом же " &
      "профиле (например, запустив Chromium интерактивно с тем же --user-data-dir), после " &
      "чего повторный запуск должен пройти дальше этого шага.")
  of dsTimeout:
    await dumpOnFailure(tab, "mave-debug-dashboard-not-ready", screenshotDir)
    raise newException(SiteWorkerError,
      &"дашборд app.mave.digital не прогрузился за {dashboardReadyTimeoutMs div 1000} сек " &
      &"после навигации (ни кнопка '{AddEpisodeButtonText}', ни экран входа " &
      &"('{LoginPageButtonText}') так и не появились), несмотря на одну жёсткую " &
      "перезагрузку страницы на середине этого времени (см. waitForDashboardReady()) — " &
      "SPA, похоже, застряла уже не на разовой просадке сети, раз даже перезагрузка не " &
      "помогла (см. параметр dashboardReadyTimeoutMs, " &
      "если проблема повторяется систематически, есть смысл поднять его ещё — а заодно " &
      "посмотреть mave-debug-dashboard-not-ready.html/.png И mave-debug-dashboard-not-ready-" &
      "network.json, если он появился рядом, — сбои загрузки конкретных файлов (JS/CSS-" &
      "чанков) там будут видны, даже если console.json пуст, см. installNetworkFailureLog() " &
      "в childtear.nim); дело не в " &
      "переключателе канала ниже и не в " &
      "авторизации, до них в этом случае даже не доходит")

  if await channelAlreadySelected(tab, channel):
    if verbose: echo "Канал '", $channel, "' уже выбран."
    return

  if verbose: echo "Переключаюсь на канал '", $channel, "'..."
  var switched = false
  for attempt in 1 .. ChannelSwitchAttempts:
    proc switcherAppeared(): Future[bool] {.async.} = result = await exists(tab, ChannelSwitcherControlSelector)
    if not await waitUntilTrue(switcherAppeared, FieldTimeoutMs, 200):
      await dumpOnFailure(tab, "mave-debug-no-switcher", screenshotDir)
      raise newException(SiteWorkerError,
        &"не нашёлся переключатель канала в сайдбаре (искали по селектору " &
        &"'{ChannelSwitcherControlSelector}' — см. ChannelSwitcherControlSelector)")
    await click(tab, ChannelSwitcherControlSelector)

    proc menuItemAppeared(): Future[bool] {.async.} = result = await markChannelMenuItem(tab, channel)
    if not await waitUntilTrue(menuItemAppeared, ChannelSwitchTimeoutMs, 200):
      await dumpOnFailure(tab, "mave-debug-no-channel-menu-item", screenshotDir)
      raise newException(SiteWorkerError,
        &"после клика по переключателю канала не появился пункт '{$channel}' " &
        "в выпадающем списке")
    # Пауза перед кликом по уже помеченному пункту: список раскрывается
    # с CSS-переходом, и настоящий клик мышью по координатам
    # getBoundingClientRect() может попасть мимо, пока пункт не дошёл до
    # конечной позиции. Тогда переключатель молча остаётся на прежнем
    # канале.
    await sleepAsync(250)
    await click(tab, "[" & MarkAttr & "]")

    if await waitForChannelSelected(tab, channel, ChannelSwitchTimeoutMs):
      switched = true
      break
    if verbose:
      echo "  Выбор канала '", $channel, "' не подтвердился с попытки ", $attempt,
           " из ", $ChannelSwitchAttempts, " — пробую заново..."

  if not switched:
    await dumpOnFailure(tab, "mave-debug-channel-not-selected", screenshotDir)
    raise newException(SiteWorkerError,
      &"после {ChannelSwitchAttempts} попыток выбрать канал '{$channel}' в списке " &
      &"переключатель так и не подтвердил переключение (текст '{$channel}' не " &
      &"появился в {ChannelSwitcherLabelSelector})")
  if verbose: echo "  Канал переключён."


# ---------------------------------------------------------------------------
# Шаги сценария создания эпизода
# ---------------------------------------------------------------------------

proc clickAddEpisode(tab: Tab, verbose: bool, screenshotDir: string = "") {.async.} =
  ## Как и clickNewEpisode() в siteworkers/redcircle.nim — ищет и кликает
  ## кнопку ПОВТОРНО, пока не откроется модальное окно, а не один раз:
  ## та же причина (метка может "протухнуть" между пометкой и кликом,
  ## если страница успеет перерисоваться).
  if verbose: echo "Ищу и кликаю кнопку '", AddEpisodeButtonText, "'..."
  proc modalOpened(): Future[bool] {.async.} = result = await pageHasText(tab, NewEpisodeHeaderText)

  let deadline = epochTime() + (ModalTimeoutMs.float / 1000.0)
  var opened = false
  var sawButton = false
  while epochTime() < deadline:
    if await markByButtonText(tab, AddEpisodeButtonText, markAttr = MarkAttr):
      sawButton = true
      await click(tab, "[" & MarkAttr & "]")
    if await modalOpened():
      opened = true
      break
    await sleepAsync(300)

  if not opened:
    await dumpOnFailure(tab, "mave-debug-no-modal", screenshotDir)
    if not sawButton:
      raise newException(SiteWorkerError,
        &"не нашлась кнопка '{AddEpisodeButtonText}' на странице дашборда")
    raise newException(SiteWorkerError,
      &"после клика(ов) по '{AddEpisodeButtonText}' не появился текст '{NewEpisodeHeaderText}' — " &
      "модальное окно создания выпуска, похоже, не открылось")

proc contentFileAttached(tab: Tab): Future[bool] {.async.} =
  ## Проверяет напрямую через DOM (input.files.length > 0) — тот же
  ## приём, что и contentFileAttached() в siteworkers/redcircle.nim (см.
  ## пояснение там о том, почему это источник истины, а не текст на
  ## странице).
  let js = &"""(function() {{
    var el = document.querySelector('[{MarkAttr}]');
    return !!(el && el.files && el.files.length > 0);
  }})()"""
  let res = await evalJS(tab, js)
  result = res.kind == JBool and getBool(res)

proc attachEpisodeFile(tab: Tab, absPath: string, verbose: bool,
                        screenshotDir: string = "") {.async.} =
  if verbose: echo "Прикрепляю аудиофайл: ", absPath
  var attached = false
  for attempt in 1 .. 3:
    if attempt > 1 and verbose:
      echo "  Попытка прикрепления #", attempt, " — предыдущая не подтвердилась через DOM."

    var found = await markInputByAccept(tab, "audio", markAttr = MarkAttr)
    if not found:
      # Возможно, инпут монтируется в DOM только после клика по кнопке
      # "Выбрать файл" (как у некоторых дропзон, см. аналогичный
      # приём в attachContent() в siteworkers/redcircle.nim).
      proc tryAgain(): Future[bool] {.async.} = result = await markInputByAccept(tab, "audio", markAttr = MarkAttr)
      found = await waitUntilTrue(tryAgain, FieldTimeoutMs, 200)
    if not found:
      if await markByButtonText(tab, ChooseFileButtonText, markAttr = MarkAttr):
        await click(tab, "[" & MarkAttr & "]")
        proc tryAfterClick(): Future[bool] {.async.} = result = await markInputByAccept(tab, "audio", markAttr = MarkAttr)
        found = await waitUntilTrue(tryAfterClick, FieldTimeoutMs, 200)
    if not found:
      # Последний резерв: если на модальном окне ровно один
      # input[type="file"] без accept="audio/..." (например, атрибут
      # accept вовсе не выставлен) — берём его.
      if (await count(tab, "input[type=\"file\"]")) == 1:
        discard await evalJS(tab, &"""(function() {{
          document.querySelector('input[type="file"]').setAttribute({escapeJson(MarkAttr)}, '1');
          return true;
        }})()""")
        found = true
    if not found:
      if attempt == 3:
        await dumpOnFailure(tab, "mave-debug-no-file-input", screenshotDir)
        raise newException(SiteWorkerError, "не нашёлся input[type=file] для загрузки аудио")
      continue

    await uploadFile(tab, "[" & MarkAttr & "]", @[absPath])
    attached = await contentFileAttached(tab)
    if attached:
      if verbose: echo "  Подтверждено через DOM: input.files содержит файл."
      break
    await sleepAsync(500)

  if not attached:
    await dumpOnFailure(tab, "mave-debug-file-not-attached", screenshotDir)
    raise newException(SiteWorkerError,
      "аудиофайл не был назначен полю загрузки (input.files пуст) после нескольких попыток " &
      "— загрузка остановлена, чтобы не создать выпуск без аудио")

proc confirmUpload(tab: Tab, absPath: string, verbose: bool, screenshotDir: string = "") {.async.} =
  ## Ждёт, пока кнопка "Загрузить файл" станет активной (файл принят
  ## формой), кликает по ней, затем ждёт исчезновения текста
  ## NewEpisodeHeaderText — сигнала о том, что модальное окно загрузки
  ## закрылось и начался (или уже завершился) переход к следующему шагу.
  proc buttonReady(): Future[bool] {.async.} =
    if not await markByButtonText(tab, UploadFileButtonText, exact = true, markAttr = MarkAttr):
      return false
    result = not await isDisabled(tab, "[" & MarkAttr & "]")
  if not await waitUntilTrue(buttonReady, ContentAckTimeoutMs, 300):
    await dumpOnFailure(tab, "mave-debug-upload-button-disabled", screenshotDir)
    raise newException(SiteWorkerError,
      &"кнопка '{UploadFileButtonText}' не стала активной за отведённое время " &
      "— похоже, файл не был принят формой")

  if verbose: echo "Нажимаю '", UploadFileButtonText, "'..."
  await click(tab, "[" & MarkAttr & "]")

  let timeoutMs = uploadTimeoutForFile(absPath, ProcessingTimeoutMs)
  proc modalGone(): Future[bool] {.async.} = result = not await pageHasText(tab, NewEpisodeHeaderText)
  if verbose: echo "  Жду обработки файла на сервере (может занять время для крупных файлов)..."
  if not await waitUntilTrue(modalGone, timeoutMs, 500):
    await dumpOnFailure(tab, "mave-debug-modal-still-open", screenshotDir)
    raise newException(SiteWorkerError,
      &"после нажатия '{UploadFileButtonText}' окно '{NewEpisodeHeaderText}' не закрылось " &
      &"за {timeoutMs div 1000} сек")

  # Модалка закрылась — но это ещё не значит, что открылась форма
  # редактирования эпизода: как минимум дважды на практике после этого
  # приложение оказывалось обратно на голом /dashboard (см.
  # EditScreenTimeoutMs выше). Проверяем это ЗДЕСЬ, сразу, с понятной
  # диагностикой — вместо того чтобы дать сбою всплыть на несколько
  # шагов позже как "не нашлась вкладка"/"не нашлось поле".
  proc editScreenOpened(): Future[bool] {.async.} =
    result = (await markByButtonText(tab, MainTabButtonText, exact = true, markAttr = MarkAttr)) or
             (await markByButtonText(tab, AdditionalTabButtonText, exact = true, markAttr = MarkAttr)) or
             (await exists(tab, TitleFieldSelector))
  if verbose: echo "  Проверяю, что открылась форма редактирования эпизода..."
  if not await waitUntilTrue(editScreenOpened, EditScreenTimeoutMs, 300):
    await dumpOnFailure(tab, "mave-debug-no-edit-screen", screenshotDir)
    let url = await currentUrl(tab)
    raise newException(SiteWorkerError,
      &"окно '{NewEpisodeHeaderText}' закрылось, но форма редактирования эпизода " &
      &"(вкладки '{MainTabButtonText}'/'{AdditionalTabButtonText}') не появилась за " &
      &"{EditScreenTimeoutMs div 1000} сек — похоже, приложение вернулось на другой " &
      &"экран вместо перехода к редактированию (текущий URL: {url})")

proc fillEpisodeTitle(tab: Tab, title: string, verbose: bool,
                       screenshotDir: string = "") {.async.} =
  if verbose: echo "Заполняю название выпуска..."
  proc tryMark(): Future[string] {.async.} = result = await markFieldByAnyLabel(tab, TitleFieldLabelCandidates, MarkAttr)
  var usedLabel = ""
  proc found(): Future[bool] {.async.} =
    usedLabel = await tryMark()
    result = len(usedLabel) > 0
  if not await waitUntilTrue(found, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "mave-debug-no-title-field", screenshotDir)
    let url = await currentUrl(tab)
    var msg = "не нашлось поле названия выпуска — испробованные метки: " &
      TitleFieldLabelCandidates.join(", ") &
      " (см. предупреждение в шапке siteworkers/mavedigital.nim про неподтверждённую разметку " &
      "этого экрана — добавьте актуальную метку в TitleFieldLabelCandidates)"
    if url == DashboardUrl or url == (DashboardUrl & "/"):
      # Поле "Выпуск" на вкладке "Дополнительно" уже заполнено, но поле
      # названия не находится, а HTML-дамп показывает голый /dashboard:
      # приложение успело уйти со страницы редактирования. Это не
      # проблема формулировки метки (TitleFieldLabelCandidates).
      msg &= &" — ВАЖНО: текущий URL ({url}) это URL дашборда, а не формы " &
        "эпизода. Поле не 'переименовалось' — приложение целиком ушло со " &
        "страницы редактирования между предыдущим шагом (заполнение номера " &
        "выпуска) и этим. Дело не в TitleFieldLabelCandidates."
    raise newException(SiteWorkerError, msg)
  if verbose: echo "  Поле найдено по метке: ", usedLabel
  await fill(tab, "[" & MarkAttr & "]", title)

proc fillEpisodeTimings(tab: Tab, timings: string, verbose: bool,
                         screenshotDir: string = "") {.async.} =
  if verbose: echo "Заполняю тайминги..."
  var usedLabel = ""
  proc found(): Future[bool] {.async.} =
    usedLabel = await markFieldByAnyLabel(tab, TimingsFieldLabelCandidates, MarkAttr)
    result = len(usedLabel) > 0
  if not await waitUntilTrue(found, FieldTimeoutMs, 200):
    # В отличие от названия — отсутствие поля таймингов не считается
    # фатальной ошибкой всего сценария (эпизод всё ещё можно
    # опубликовать без них); сохраняем диагностику и продолжаем.
    await dumpOnFailure(tab, "mave-debug-no-timings-field", screenshotDir)
    if verbose:
      echo "  ПРЕДУПРЕЖДЕНИЕ: не нашлось поле для таймингов — испробованные метки: ",
        TimingsFieldLabelCandidates.join(", "), ". Публикую без них."
    return
  if verbose: echo "  Поле найдено по метке: ", usedLabel
  await fill(tab, "[" & MarkAttr & "]", timings)

proc touchEpisodeNumber(tab: Tab, verbose: bool, screenshotDir: string = "") {.async.} =
  ## Переключается на вкладку "Дополнительно", перезаписывает поле
  ## "Выпуск" (EpisodeNumberValue) и возвращается на "Основное". Нужна до
  ## publishEpisode(): иначе "Опубликовать" не подтвердится никогда (см.
  ## AdditionalTabButtonText).
  ##
  ## Возврат обязателен: содержимое вкладок монтируется в DOM только при
  ## переключении, и пока открыта "Дополнительно", поля "Основное"
  ## (включая TitleFieldSelector) в DOM нет. confirmedByFormClosed() в
  ## publishEpisode() опирается на исчезновение TitleFieldSelector и без
  ## возврата сработало бы ложно.
  if verbose: echo "Переключаюсь на вкладку '", AdditionalTabButtonText, "'..."
  # waitUntilTrue, а не однократная проверка: сразу после confirmUpload()
  # экран редактирования уже подтверждён отдельной проверкой
  # (editScreenOpened() в confirmUpload()), но САМА вкладка "Дополнительно"
  # внутри него может смонтироваться на долю секунды позже — однократная
  # проверка в этом узком окне ненадёжна.
  proc additionalTabFound(): Future[bool] {.async.} =
    result = await markByButtonText(tab, AdditionalTabButtonText, exact = true, markAttr = MarkAttr)
  if not await waitUntilTrue(additionalTabFound, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "mave-debug-no-additional-tab", screenshotDir)
    raise newException(SiteWorkerError,
      &"не нашлась вкладка '{AdditionalTabButtonText}' в форме выпуска")
  await click(tab, "[" & MarkAttr & "]")

  if verbose: echo "Заполняю номер выпуска..."
  var usedLabel = ""
  proc found(): Future[bool] {.async.} =
    usedLabel = await markFieldByAnyLabel(tab, EpisodeNumberFieldLabelCandidates, MarkAttr)
    result = len(usedLabel) > 0
  if not await waitUntilTrue(found, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "mave-debug-no-episode-number-field", screenshotDir)
    raise newException(SiteWorkerError,
      "не нашлось поле номера выпуска на вкладке '" & AdditionalTabButtonText &
      "' — испробованные метки: " & EpisodeNumberFieldLabelCandidates.join(", "))
  if verbose: echo "  Поле найдено по метке: ", usedLabel
  await fill(tab, "[" & MarkAttr & "]", EpisodeNumberValue)

  if verbose: echo "Возвращаюсь на вкладку '", MainTabButtonText, "'..."
  proc mainTabFound(): Future[bool] {.async.} =
    result = await markByButtonText(tab, MainTabButtonText, exact = true, markAttr = MarkAttr)
  if not await waitUntilTrue(mainTabFound, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "mave-debug-no-main-tab", screenshotDir)
    raise newException(SiteWorkerError,
      &"не нашлась вкладка '{MainTabButtonText}' в форме выпуска (для возврата после ввода номера)")
  await click(tab, "[" & MarkAttr & "]")

  # Дожидаемся, что поле заголовка снова смонтировано в DOM (после
  # возврата на "Основное") — иначе confirmedByFormClosed() в
  # publishEpisode() рискует опросить DOM в промежуточном кадре
  # переключения вкладки, ещё до того, как React/Vue успеет её
  # перерисовать.
  proc titleBack(): Future[bool] {.async.} = result = await exists(tab, TitleFieldSelector)
  if not await waitUntilTrue(titleBack, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "mave-debug-title-not-back", screenshotDir)
    raise newException(SiteWorkerError,
      "после возврата на вкладку '" & MainTabButtonText & "' поле " &
      TitleFieldSelector & " не появилось в DOM")

proc captureXhrResponses(tab: Tab, windowMs: int): Future[JsonNode] {.async.} =
  ## Диагностика для publishEpisode(): в течение windowMs после вызова
  ## собирает ответы XHR/Fetch (url, статус и, если тело небольшое, само
  ## тело) в порядке получения; картинки, шрифты и аналитика отбрасываются
  ## по params["type"].
  ##
  ## Нужна для случая, когда форма валидна, "Опубликовать" нажимается, а
  ## публикации нет: единственный источник ответа — то, что сервер вернул
  ## на запрос от клика. responseBody() работает, пока Chromium не вытеснил
  ## тело из памяти, поэтому сбор идёт параллельно с confirmed() в
  ## publishEpisode(), а не постфактум по таймауту.
  ##
  ## Никогда не бросает исключение (в том числе при сбое enableNetwork()):
  ## future не await-ится при быстрой успешной публикации, а необработанная
  ## ошибка дала бы "Future exception was not retrieved".
  result = newJArray()
  try:
    await enableNetwork(tab)
    let deadline = epochTime() + (windowMs.float / 1000.0)
    while true:
      let remainingMs = int((deadline - epochTime()) * 1000.0)
      if remainingMs <= 0:
        break
      var params: JsonNode
      try:
        params = await waitForResponse(tab, "", remainingMs)
      except CatchableError:
        break # таймаут ожидания следующего ответа — сеть затихла, и ладно
      let typ = getStr(params{"type"}, "")
      if typ != "XHR" and typ != "Fetch":
        continue
      let requestId = getStr(params{"requestId"}, "")
      var entry = %*{
        "url": params{"response"}{"url"},
        "status": getInt(params{"response"}{"status"}, 0),
        "type": typ,
      }
      try:
        let (body, isB64) = await responseBody(tab, requestId)
        if not isB64 and len(body) <= 4000:
          entry["body"] = %body
        else:
          entry["bodyBytes"] = %len(body)
      except CatchableError:
        discard # тело уже вытолкнуто из памяти или запрос не завершился
      add(result, entry)
  except CatchableError:
    discard # см. пояснение выше — эта proc не имеет права бросать наружу

proc checkNotOccluded(tab: Tab, markAttr: string): Future[JsonNode] {.async.} =
  ## Проверяет, что помеченный markAttr'ом элемент — самый верхний в точке
  ## своего центра (там же click() делает настоящий клик через Input).
  ## Если поверх лежит невидимый оверлей, тултип или панель календаря
  ## (рядом с "Опубликовать" есть иконка-календарь), настоящий клик
  ## попадёт в него: без JS-ошибки и запроса, как и наблюдалось (click()
  ## отрабатывает, captureXhrResponses() запросов не видит).
  ## Возвращает {"occluded": bool, "topTag", "topClass", "topId": string}.
  let markLit = escapeJson("[" & markAttr & "]")
  let js = &"""(function() {{
    var el = document.querySelector({markLit});
    if (!el) return {{"occluded": false, "topTag": "", "topClass": "", "topId": "", "note": "элемент не найден"}};
    var r = el.getBoundingClientRect();
    var cx = (r.left + r.right) / 2;
    var cy = (r.top + r.bottom) / 2;
    var top = document.elementFromPoint(cx, cy);
    var isOurs = top && (top === el || el.contains(top) || (top.contains && top.contains(el)));
    return {{
      "occluded": !isOurs,
      "topTag": top ? top.tagName : "",
      "topClass": top ? (top.className || "") : "",
      "topId": top ? (top.id || "") : ""
    }};
  }})()"""
  result = await evalJS(tab, js)

proc publishEpisode(tab: Tab, title: string, absPath: string, verbose: bool,
                     screenshotDir: string = "") {.async.} =
  if verbose: echo "Ищу кнопку публикации..."
  var usedText = ""
  proc tryMark(): Future[bool] {.async.} =
    for candidate in PublishButtonTextCandidates:
      if await markByButtonText(tab, candidate, exact = true, markAttr = MarkAttr):
        usedText = candidate
        return true
    result = false
  if not await waitUntilTrue(tryMark, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "mave-debug-no-publish-button", screenshotDir)
    raise newException(SiteWorkerError,
      "не нашлась кнопка публикации — испробованные варианты текста: " &
      PublishButtonTextCandidates.join(", "))

  if verbose: echo "  Нажимаю '", usedText, "'..."
  let prePublishUrl = await currentUrl(tab)
  let occlusionCheck = await checkNotOccluded(tab, MarkAttr)
  if getBool(occlusionCheck{"occluded"}, false) and verbose:
    echo "  ⚠ Элемент кнопки '", usedText, "' перекрыт другим элементом на экране: <",
      getStr(occlusionCheck{"topTag"}, "?"), " class=\"", getStr(occlusionCheck{"topClass"}, ""),
      "\" id=\"", getStr(occlusionCheck{"topId"}, ""), "\"> — настоящий клик мышью попадёт именно в него."
  await click(tab, "[" & MarkAttr & "]")

  # Быстрая проверка "клик что-то изменил" до долгого ожидания публикации:
  # настоящий клик мгновенно переводит "Опубликовать" в состояние загрузки
  # (текст "Загрузка...", кнопка заблокирована) ещё до ответа сервера. Если
  # за пару секунд реакции нет, клик почти наверняка не долетел (нулевая
  # длительность нажатия иногда отфильтровывается, см. holdMs в
  # cdp/domains/input.nim), и повтор в эти секунды безопасен: сервер не
  # успел бы принять публикацию, дубля не будет. Без проверки такой сбой
  # обнаруживался бы лишь через минуты.
  proc clickRegistered(): Future[bool] {.async.} =
    let js = &"""(function() {{
      var el = document.querySelector('[{MarkAttr}]');
      if (!el) return true; // элемент исчез/перерисовался — что-то точно произошло
      var txt = (el.innerText || el.textContent || '').trim();
      var busy = el.getAttribute('aria-disabled') === 'true' || el.disabled === true ||
        el.getAttribute('aria-busy') === 'true';
      return busy || txt !== {escapeJson(usedText)};
    }})()"""
    let r = await evalJS(tab, js)
    result = r.kind == JBool and getBool(r)
  var clickTookEffect = await waitUntilTrue(clickRegistered, PublishClickRegisterTimeoutMs, 150)
  var clickAttempt = 1
  while not clickTookEffect and clickAttempt < PublishClickAttempts:
    inc(clickAttempt)
    if verbose:
      echo "  Кнопка '", usedText, "' никак не отреагировала на клик за ",
        PublishClickRegisterTimeoutMs div 1000, " сек — пробую ещё раз (клик ", clickAttempt,
        " из ", PublishClickAttempts, ")..."
    await click(tab, "[" & MarkAttr & "]")
    clickTookEffect = await waitUntilTrue(clickRegistered, PublishClickRegisterTimeoutMs, 150)
  if not clickTookEffect and verbose:
    echo "  ВНИМАНИЕ: кнопка так и не показала видимой реакции ни на одну из ", PublishClickAttempts,
      " попыток клика — проверка ниже (сеть/URL/закрытие формы), скорее всего, тоже не подтвердит " &
      "публикацию, но на случай ошибки самой этой проверки продолжаю ждать."

  # См. captureXhrResponses() выше — запускаем СРАЗУ после клика и НЕ
  # await-им сейчас же: должна выполняться параллельно с обычным
  # ожиданием ниже, а не после него (тело ответа иначе будет потеряно).
  # 60 сек. с запасом — если сервер вообще отвечает на этот клик, ответ
  # придёт за секунды, а не будет тянуться минутами (в отличие от самой
  # публикации, см. PublishConfirmTimeoutMs/uploadTimeoutForFile ниже).
  let networkCaptureFut = captureXhrResponses(tab, 60_000)

  proc confirmedByUrl(): Future[bool] {.async.} = result = (await currentUrl(tab)) != prePublishUrl
  proc confirmedByFormClosed(): Future[bool] {.async.} = result = not (await exists(tab, TitleFieldSelector))
  proc confirmed(): Future[bool] {.async.} = result = (await confirmedByUrl()) or (await confirmedByFormClosed())

  # confirmedByTitle() = pageHasText(tab, title) для подтверждения не
  # годится: заголовок остаётся в самой форме после fillEpisodeTitle(),
  # поэтому проверка срабатывает на первом опросе независимо от успеха, и
  # тихо провалившаяся публикация (например, отказ валидации на сервере)
  # считалась бы успешной. Надёжнее confirmedByFormClosed(): исчезновение из
  # DOM поля "Заголовок выпуска" (TitleFieldSelector) означает закрытие
  # формы; пока она открыта, публикация не завершилась.
  #
  # Таймаут долгий: mave.digital ограничивает приём файла примерно 2 Мбит/с,
  # и передача байтов, похоже, завершается уже после клика "Опубликовать", а
  # не только в confirmUpload(). Поэтому таймаут считается по размеру файла
  # (uploadTimeoutForFile(), MaveUploadRateBytesPerSec), а не фиксированным
  # числом.
  let timeoutMs = uploadTimeoutForFile(absPath, PublishConfirmTimeoutMs)
  if verbose: echo "  Жду подтверждения публикации..."
  if not await waitUntilTrue(confirmed, timeoutMs, 500):
    var apiResponseCount = -1 # -1 = не удалось даже сохранить дамп
    try:
      let captured = await networkCaptureFut
      # Аналитика (Gleap и т.п.) не считается "ответом API" для целей
      # этого сообщения: массив из одной такой записи и ничего больше
      # практически равносилен полному отсутствию сетевой активности на
      # сам клик.
      apiResponseCount = 0
      for entry in captured:
        let entryUrl = getStr(entry{"url"}, "")
        if not entryUrl.contains("gleap."):
          inc(apiResponseCount)
      if len(screenshotDir) > 0:
        createDir(screenshotDir)
        writeFile(screenshotDir / "mave-debug-not-confirmed-publish-network.json", pretty(captured))
        echo "  Сетевые ответы на клик 'Опубликовать' (", len(captured), " шт., из них к самому mave.digital: ",
          apiResponseCount, ") сохранены в " & screenshotDir / "mave-debug-not-confirmed-publish-network.json"
        writeFile(screenshotDir / "mave-debug-not-confirmed-occlusion.json", pretty(occlusionCheck))
    except CatchableError as e:
      echo "  Не удалось сохранить дамп сетевых ответов: ", e.msg
    await dumpOnFailure(tab, "mave-debug-not-confirmed", screenshotDir)
    var msg = &"после нажатия '{usedText}' публикация выпуска '{title}' не подтвердилась за " &
      &"{timeoutMs div 1000} сек (ни смена URL, ни закрытие формы " &
      &"выпуска — поле {TitleFieldSelector} всё ещё в DOM)"
    if apiResponseCount == 0:
      # За 60 сек после клика не было ни одного запроса к mave.digital
      # (кроме аналитики), хотя кнопка не перекрыта и не disabled: обработчик
      # клика, похоже, ничего не сделал (см. settleActiveField() и debounce в
      # touchEpisodeNumber()). Клик автоматически НЕ повторяется: если запрос
      # всё же ушёл, а ответ не успел попасть в captureXhrResponses() (публикация
      # занимает минуты из-за лимита скорости), повтор создал бы второй,
      # реально опубликованный дубликат, что хуже ручной проверки сайта.
      msg &= " — за это время не было НИ ОДНОГО сетевого запроса к самому mave.digital " &
        "(см. mave-debug-not-confirmed-publish-network.json), похоже, обработчик клика " &
        "не выполнил ничего. Перед повторным запуском стоит вручную проверить черновики/" &
        "выпуски на mave.digital — возможно, эпизод там уже есть и повторная публикация " &
        "создаст дубликат."
    raise newException(SiteWorkerError, msg)
  if verbose: echo "Готово: выпуск опубликован."


# ---------------------------------------------------------------------------
# Публичная функция: uploadToMave
# ---------------------------------------------------------------------------

proc settleActiveField(tab: Tab) {.async.} =
  ## mave.digital коммитит текст из Input.insertText() во внутреннее
  ## (Vue) состояние с небольшим debounce. Клик или переключение вкладки
  ## сразу после ввода попадает на ещё не закоммиченное состояние: клик по
  ## "Опубликовать" точен (occlusion чистый), но порождает только
  ## аналитический маячок и тихо ничего не делает.
  ##
  ## dispatchEvent('change')/blur() на активном поле (то, что делает
  ## пользователь, убирая курсор) и короткая пауза дают debounce сработать.
  ## Это безопасно, в отличие от автоматического повтора клика по
  ## "Опубликовать" (риск дубля, см. publishEpisode()).
  let js = """(function() {
    var el = document.activeElement;
    if (el && el !== document.body) {
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.blur();
    }
    return true;
  })()"""
  try:
    discard await evalJS(tab, js)
  except CatchableError:
    discard
  await sleepAsync(800)

proc uploadToMave*(channel: MaveChannel, title: string, timings: string, file: string,
                    headless = true, verbose = true,
                    screenshotDir: string = "", proxyUrl: string = "",
                    recordSteps: bool = true,
                    dashboardReadyTimeoutMs: int = DefaultDashboardReadyTimeoutMs): Future[void] {.async.} =
  ## Загружает эпизод на app.mave.digital: переключается на channel,
  ## открывает окно "Новый выпуск", прикрепляет аудио file, дожидается
  ## обработки, заполняет название title и тайминги timings, публикует.
  ##
  ## Использует сохранённый профиль Chromium (ProfileDir); если сессия не
  ## авторизована, войдите через loginMave(). proxyUrl передаётся как
  ## --proxy-server, если вызов сам поднимает браузер (см.
  ## launchDetachedChromium()); на уже запущенный браузер не действует.
  ## Браузер переиспользуется: функция открывает вкладку и закрывает
  ## только её.
  ##
  ## recordSteps включает пошаговые скриншоты; дамп при ошибке пишется в
  ## screenshotDir всегда, если каталог задан. При медленной сети
  ## увеличивайте dashboardReadyTimeoutMs (см.
  ## DefaultDashboardReadyTimeoutMs), а не меняйте код.
  ##
  ## Бросает SiteWorkerError, если элемент/текст не найден, и
  ## ChildTearError при низкоуровневых сбоях; при ошибке сохраняет снимок
  ## (mave-debug-*.png/.html/-console.json).
  if len(strutils.strip(title)) == 0:
    raise newException(ValueError, "title не должен быть пустым")
  if not fileExists(file):
    raise newException(IOError, "файл не найден: " & file)
  let absPath = absolutePath(file)

  let handle = await ensureBrowser(ProfileDir, DebugPort, headless = headless, proxyUrl = proxyUrl)
  if verbose:
    echo (if handle.attached: "Подключаюсь к уже работающему Chromium (mave.digital)..."
          else: "Запускаю headless-Chromium (mave.digital) с сохранённым профилем...")

  let rec = newStepRecorder(screenshotDir, recordSteps)
  if len(screenshotDir) > 0 and recordSteps and verbose:
    echo "Пошаговые скриншоты будут сохранены в: ", screenshotDir

  var tab: Tab
  try:
    tab = await gotoWithRetry(handle.browser, DashboardUrl, verbose = verbose)
    # Журнал сетевых сбоев (installNetworkFailureLog() в childtear.nim)
    # ловит ошибки загрузки любых ресурсов, включая <script>/<link>, которых
    # нет в -console.json; пригодится dumpOnFailure(), если дашборд завис на
    # лоадере. Ставится после первой навигации, поэтому сбои первого перехода
    # не видит, но видит перезагрузки внутри waitForDashboardReady().
    await installNetworkFailureLog(tab)
    await step(rec, tab, "dashboard")

    await selectChannel(tab, channel, verbose, screenshotDir, dashboardReadyTimeoutMs)
    await step(rec, tab, "channel-selected")

    await clickAddEpisode(tab, verbose, screenshotDir)
    await step(rec, tab, "new-episode-modal-open")

    await attachEpisodeFile(tab, absPath, verbose, screenshotDir)
    await step(rec, tab, "file-attached")

    # Повтор всей цепочки "модалка -> файл -> ждём форму" при сбое
    # confirmUpload(): к моменту его ошибки приложение уже на /dashboard,
    # модалки "Новый выпуск" нет, поэтому достаточно заново выполнить
    # clickAddEpisode + attachEpisodeFile + confirmUpload. Сбой — разовый
    # глюк сайта (окно закрылось, /create-episode не открылась).
    var uploadOk = false
    for attempt in 1 .. UploadRetryAttempts:
      try:
        await confirmUpload(tab, absPath, verbose, screenshotDir)
        uploadOk = true
        break
      except SiteWorkerError as e:
        if attempt >= UploadRetryAttempts:
          raise
        if verbose:
          echo "  Форма редактирования эпизода не открылась (попытка ", attempt, " из ",
            UploadRetryAttempts, ") — начинаю загрузку файла заново: ", e.msg
        await clickAddEpisode(tab, verbose, screenshotDir)
        await attachEpisodeFile(tab, absPath, verbose, screenshotDir)
    doAssert uploadOk # недостижимо: цикл выше либо ставит true, либо бросает исключение выше
    await step(rec, tab, "upload-processed")

    # touchEpisodeNumber() выполняется ДО заголовка и таймингов:
    # переключение вкладок перемонтирует "Основное", а текст из
    # Input.insertText коммитится в состояние сайта с debounce, поэтому
    # быстрое переключение теряло ещё не сохранённые поля (черновики "Нет
    # названия" при заполненной форме). Когда номер заполнен первым, вкладки
    # после ввода заголовка/таймингов больше не переключаются вплоть до клика
    # "Опубликовать".
    await touchEpisodeNumber(tab, verbose, screenshotDir)
    await step(rec, tab, "episode-number-touched")

    await fillEpisodeTitle(tab, title, verbose, screenshotDir)
    await step(rec, tab, "title-filled")

    await fillEpisodeTimings(tab, timings, verbose, screenshotDir)
    await step(rec, tab, "timings-filled")

    await settleActiveField(tab)

    await waitForFileUploadComplete(tab, absPath, verbose, screenshotDir)
    await step(rec, tab, "upload-fully-complete")

    await publishEpisode(tab, title, absPath, verbose, screenshotDir)
    await step(rec, tab, "published-confirmed")

  except CatchableError as e:
    if verbose: echo "Ошибка: ", e.msg
    if not isNil(tab):
      await step(rec, tab, "error")
      await dumpOnFailure(tab, "mave-debug-failure", screenshotDir)
    raise
  finally:
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard

proc loginMave*(): Future[void] {.async.} =
  ## Интерактивный вход в app.mave.digital — см. подробное пояснение у
  ## аналогичной loginQwen() в siteworkers/qwen.nim (тот же приём:
  ## ensureBrowserForLogin() вместо обычного ensureBrowser(), иначе
  ## переиспользовался бы headless-процесс от автоматического
  ## прогона — без видимого окна пользователю было бы не во что войти).
  let handle = await ensureBrowserForLogin(ProfileDir, DebugPort)
  var tab: Tab
  try:
    tab = await gotoWithRetry(handle.browser, DashboardUrl, verbose = false)
    echo "Открыт app.mave.digital в видимом окне Chromium."
    echo "Профиль: ", ProfileDir
    echo "Войдите в аккаунт в открывшемся окне (закройте промо-баннер " &
         "\"Добро пожаловать в mave\", если он появится), затем нажмите Enter здесь..."
    discard readLine(stdin)

    # Короткий (не полный DefaultDashboardReadyTimeoutMs) опрос — вход
    # уже состоялся к моменту Enter, здесь только распознаём, ЧТО сейчас
    # показано (dsReady/dsLoginRequired), а не ждём отрисовки с нуля.
    let state = await waitForDashboardReady(tab, timeoutMs = 5_000, verbose = false)
    case state
    of dsReady:
      echo "✓ Дашборд открыт — похоже, вход выполнен успешно."
    of dsLoginRequired:
      echo "⚠ Всё ещё показан экран входа ('", LoginPageButtonText, "') — похоже, войти не удалось."
    of dsTimeout:
      echo "⚠ Не удалось за 5 сек. однозначно распознать состояние страницы " &
           "(ни дашборд, ни экран входа) — проверьте вручную в открытом окне."
  finally:
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard
    # Освобождаем порт: следующий обычный (автоматический) вызов
    # uploadToMave() поднимет свежий headless-процесс сам и прочитает
    # уже обновлённые на диске cookies с нуля.
    await stopBrowser(DebugPort)
