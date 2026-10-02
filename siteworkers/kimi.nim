## siteworkers/kimi.nim
##
## Автоматизация Kimi (kimi.ai) поверх childtear: отправить промпт (с
## приложенными файлами или без) и получить ответ текстом и/или
## скриншотом. Аналог siteworkers/qwen.nim (общие пояснения по API — в его
## шапке; AskResult/SiteWorkerPref — в ./siteworker_common.nim, функции
## представления результата — в ./clipboard.nim).
##
##   import siteworkers/kimi
##
##   let answer = waitFor askKimi("Резюмируй документ", @["/путь/к/файлу.pdf"])
##   aiText2Clipboard(answer.text)
##   aiScreenshot2Clipboard(answer.screenshotData, answer.screenshotFormat)
##
## Авторизация: askKimi() сама не логинится, а использует сохранённый
## профиль Chromium (~/.cache/kimiclient/profile). Если профиля нет или
## сессия истекла, бросает SiteWorkerError (нужен повторный вход).




import std/[os, strutils, asyncdispatch, json, times]
import ../childtear
import ./siteworker_common
import ./browser_lifecycle
import ./clipboard




# Kimi (kimi.ai)
# ===========================================================================
#
# Селекторы и последовательность действий рассчитаны на текущую вёрстку
# kimi.ai и могут разойтись с сайтом при его обновлении — см. текст
# ошибок ниже (они указывают, какой именно селектор перестал совпадать).

const
  KimiChatUrl = "https://www.kimi.ai/?chat_enter_method=new_chat"
    ## Домен kimi.ai, не kimi.com: для аккаунтов, мигрированных на kimi.ai,
    ## www.kimi.com показывает поверх той же страницы оверлей "Kimi has
    ## been rebranded as Kimi.ai" (class="region-migration-mask"), который
    ## ломает сценарий отправки. Разметка (тот же <title>, тот же
    ## URL-паттерн /?chat_enter_method=new_chat) идентична — сменился
    ## только домен, поэтому остальные селекторы ниже не тронуты.
  KimiDebugPort = 9224
    ## См. пояснение у QwenDebugPort в siteworkers/qwen.nim — отдельный
    ## порт ради безопасного параллельного вызова askQwen()/askKimi().
  KimiProfileDir = getHomeDir() / ".cache" / "kimiclient" / "profile"
    ## См. пояснение про авторизацию в шапке файла.

  KimiPromptInputSelector = "div.chat-input-editor[contenteditable='true']"
  KimiPromptInputFallbackSelector = "div[data-lexical-editor='true']"
  KimiPromptInputTimeoutMs = 10_000
  KimiPromptInputPollMs = 300
  KimiSendButtonSelector = "div.send-button-container"
  KimiLoginModalSelector = "div.login-modal-mask, div.login-modal"
  KimiAttachButtonSelector = "div.toolkit-trigger-btn"
  KimiFileInputSelector = "input[type='file']"
  KimiFileCardSelector = "div.file-card-container"
  KimiFileAnalyzeTimeoutMs = 120_000
  KimiFileAnalyzePollMs = 500
  KimiLastAssistantMessageSelector = ".segment.segment-assistant .markdown-container:not(.toolcall-content-text)"
  KimiAssistantSegmentSelector = ".segment.segment-assistant"

  KimiNotificationModalSelector = "div.modal-mask div.modal-container"
    ## Системная модалка Kimi (не логин), например "Слишком много людей
    ## сейчас общаются с Kimi. Подпишитесь...": нотис о лимитах поверх
    ## композера вместо начала генерации. Отличается от
    ## KimiLoginModalSelector. Опасна тем, что поле ввода очищается (Enter
    ## "сработал"), но .segment-assistant не появляется: сообщение не
    ## отправлялось.
  KimiNotificationDismissSelector = KimiNotificationModalSelector & " .bottom button.km-button-secondary"
    ## Кнопка закрытия ("Понятно" и т.п.) — вторичная (secondary) кнопка
    ## внизу модалки; первичная (primary) обычно ведёт на апгрейд плана и
    ## её кликать не нужно.

proc kimiResolvePromptInputSelector(tab: Tab): Future[string] {.async.} =
  ## Ждёт появления основного селектора поля ввода Kimi
  ## (KimiPromptInputSelector) либо, если сайт отрендерил другую
  ## разметку, запасного (KimiPromptInputFallbackSelector), и
  ## возвращает тот, что реально появился в DOM.
  var resolved = ""
  proc found(): Future[bool] {.async.} =
    if await exists(tab, KimiPromptInputSelector):
      resolved = KimiPromptInputSelector
      return true
    if await exists(tab, KimiPromptInputFallbackSelector):
      resolved = KimiPromptInputFallbackSelector
      return true
    result = false
  if await waitUntilTrue(found, KimiPromptInputTimeoutMs, KimiPromptInputPollMs):
    return resolved
  raise newException(ChildTearError,
    "не найдено ни " & KimiPromptInputSelector & ", ни " & KimiPromptInputFallbackSelector &
    " спустя " & $(KimiPromptInputTimeoutMs div 1000) & " секунд ожидания гидратации Kimi")

proc kimiClearPromptField(tab: Tab, selector: string): Future[void] {.async.} =
  ## fill() печатает поверх существующего текста, а Kimi восстанавливает
  ## черновик прошлой сессии (постоянный профиль), поэтому поле может быть
  ## непустым уже на первой попытке; признак — содержимое после fill()
  ## вдвое-втрое длиннее промпта. Поле очищается явно: выделение через
  ## Selection API и удаление через execCommand доходят до состояния
  ## Lexical-редактора, а обнуление textContent/innerHTML он не заметит и
  ## восстановит прежний текст.
  let selectorLiteral = escapeJson(selector)
  let js = "(function () {\n" &
    "    var el = document.querySelector(" & selectorLiteral & ");\n" &
    "    if (!el) { return false; }\n" &
    "    el.focus();\n" &
    "    var sel = window.getSelection();\n" &
    "    var range = document.createRange();\n" &
    "    range.selectNodeContents(el);\n" &
    "    sel.removeAllRanges();\n" &
    "    sel.addRange(range);\n" &
    "    document.execCommand('delete', false);\n" &
    "    return true;\n" &
    "  })()"
  discard await evalJS(tab, js)
  await sleepAsync(150)

proc kimiIsFileStillProcessing(tab: Tab): Future[bool] {.async.} =
  ## true, пока карточка прикреплённого файла показывает класс
  ## "uploading"/"parsing" — то есть Kimi ещё обрабатывает вложение
  ## и предложенный ему вопрос пока задавать рано.
  let
    selectorLiteral = escapeJson(KimiFileCardSelector)
    js = "(function () {\n" &
    "    var card = document.querySelector(" & selectorLiteral & ");\n" &
    "    if (!card) { return false; }\n" &
    "    var cls = (card.className || '').toLowerCase();\n" &
    "    return cls.indexOf('uploading') !== -1 || cls.indexOf('parsing') !== -1;\n" &
    "  })()"
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc kimiIsLoginWalled(tab: Tab): Future[bool] {.async.} =
  ## true, если Kimi показал модальное окно требования входа в
  ## аккаунт (KimiLoginModalSelector) вместо ответа на запрос.
  result = await exists(tab, KimiLoginModalSelector)

proc kimiReadNotificationModal(tab: Tab): Future[tuple[present: bool, title: string, body: string]] {.async.} =
  ## Если сейчас показана общая системная модалка Kimi
  ## (KimiNotificationModalSelector — не логин, см. её пояснение выше),
  ## возвращает её заголовок и текст (для внятного сообщения об
  ## ошибке). Не трогает DOM, только читает.
  if not (await exists(tab, KimiNotificationModalSelector)):
    return (false, "", "")
  let
    selectorLiteral = escapeJson(KimiNotificationModalSelector)
    js = "(function () {\n" &
      "    var m = document.querySelector(" & selectorLiteral & ");\n" &
      "    if (!m) { return {t: '', b: ''}; }\n" &
      "    var t = m.querySelector('.title');\n" &
      "    var b = m.querySelector('.body');\n" &
      "    return {t: t ? t.textContent.trim() : '', b: b ? b.textContent.trim() : ''};\n" &
      "  })()"
  let res = await evalJS(tab, js)
  let
    title = if res.kind == JObject and hasKey(res, "t"): getStr(res["t"]) else: ""
    body = if res.kind == JObject and hasKey(res, "b"): getStr(res["b"]) else: ""
  result = (true, title, body)

proc kimiDismissNotificationModal(tab: Tab): Future[bool] {.async.} =
  ## Закрывает общую системную модалку Kimi, если она открыта (кликает
  ## по вторичной кнопке — "Понятно" и т.п., см. KimiNotificationDismissSelector),
  ## и ждёт, пока она пропадёт из DOM. Возвращает true, если модалка
  ## вообще была показана (независимо от того, удалось ли её закрыть
  ## кликом — например, если кнопка успела измениться).
  if not (await exists(tab, KimiNotificationModalSelector)):
    return false
  if await exists(tab, KimiNotificationDismissSelector):
    await click(tab, KimiNotificationDismissSelector)
    proc gone(): Future[bool] {.async.} = result = not (await exists(tab, KimiNotificationModalSelector))
    discard await waitUntilTrue(gone, 5_000, 200)
  result = true

proc kimiWaitForResponseStable(tab: Tab, containerSelector: string,
                                pollMs = 500, stableForMs = 2_000,
                                inactivityTimeoutMs = 90_000,
                                hardTimeoutMs = 1_200_000): Future[string] {.async.} =
  ## Следит одновременно за "пульсом" всего сегмента ответа (включая ещё
  ## свёрнутое "Обдумывание" — у Kimi оно меняется в DOM даже тогда, когда
  ## текст финального ответа ещё не появился) и за стабилизацией самого
  ## финального текста: только текст без учёта "пульса" дал бы ложное
  ## срабатывание на паузах внутри "Обдумывания"; hardTimeoutMs — аварийный
  ## потолок на случай, если пульс никогда не затихает.
  let hardDeadline = epochTime() + (hardTimeoutMs.float / 1000.0)
  var
    lastActivityAt = epochTime()
    lastActivityText = ""
    lastAnswerText = ""
    answerStableMs = 0

  while epochTime() < hardDeadline:
    var activityText = ""
    try:
      activityText = await getText(tab, KimiAssistantSegmentSelector)
    except CatchableError:
      discard
    if activityText != lastActivityText:
      lastActivityText = activityText
      lastActivityAt = epochTime()

    let current = await getLastText(tab, containerSelector)
    if len(strip(current)) > 0:
      if current == lastAnswerText:
        inc(answerStableMs, pollMs)
        if answerStableMs >= stableForMs:
          return current
      else:
        lastAnswerText = current
        answerStableMs = 0
        lastActivityAt = epochTime()

    if epochTime() - lastActivityAt > (inactivityTimeoutMs.float / 1000.0):
      break

    await sleepAsync(pollMs)

  let fallback = await getLastText(tab, containerSelector)
  if len(strip(fallback)) > 0:
    return fallback

  raise newException(ChildTearError,
    "не дождались финального ответа Kimi: либо " & $(inactivityTimeoutMs div 1000) &
    " секунд подряд не было активности в " & KimiAssistantSegmentSelector &
    ", либо вышел общий предохранительный таймаут в " & $(hardTimeoutMs div 1000) & " секунд")

proc kimiAttachFiles(tab: Tab, absPaths: seq[string], pref: set[SiteWorkerPref]) {.async.} =
  ## Как qwenAttachFiles(), но под особенности Kimi: <input type="file">
  ## монтируется в DOM только на время открытого поповера toolkit-меню.
  vecho(pref, "Прикрепляю файлы: ", join(absPaths, ", "))

  var fileInputReady = await exists(tab, KimiFileInputSelector)
  if not fileInputReady:
    if not (await exists(tab, KimiAttachButtonSelector)):
      await dumpDebugInfoVerbose(tab, "kimi-debug-attach-menu", pref)
      raise newException(ChildTearError,
        "не нашлось ни " & KimiFileInputSelector & ", ни кнопки " & KimiAttachButtonSelector &
        " у Kimi — вероятно, разметка снова поменялась")

    vecho(pref, "  Прямого input[type=file] не видно — открываю toolkit-меню...")
    for attempt in 1 .. 3:
      await click(tab, KimiAttachButtonSelector)
      for _ in 1 .. 10:
        fileInputReady = await exists(tab, KimiFileInputSelector)
        if fileInputReady:
          break
        await sleepAsync(200)
      if fileInputReady:
        break
      vecho(pref, "  input[type=file] не появился с попытки ", $attempt, " — повторяю клик...")
    await dumpDebugInfoVerbose(tab, "kimi-debug-attach-menu", pref)

  if not fileInputReady:
    raise newException(ChildTearError,
      "input[type=file] Kimi так и не появился в DOM после клика по " & KimiAttachButtonSelector)

  await uploadFile(tab, KimiFileInputSelector, absPaths)
  await dumpDebugInfoVerbose(tab, "kimi-debug-attach", pref)

  if await kimiIsFileStillProcessing(tab):
    vecho(pref, "  Жду завершения анализа вложения(й) на сервере...")
    proc doneProcessing(): Future[bool] {.async.} = result = not await kimiIsFileStillProcessing(tab)
    let finished = await waitUntilTrue(doneProcessing, KimiFileAnalyzeTimeoutMs, KimiFileAnalyzePollMs)

    if not finished:
      await dumpDebugInfoVerbose(tab, "kimi-debug-attach-still-analyzing", pref)
      raise newException(ChildTearError,
        "вложение(я) Kimi так и не закончили анализ на сервере спустя " &
        $(KimiFileAnalyzeTimeoutMs div 1000) & " секунд ожидания.")
    vecho(pref, "  Вложение(я) готовы.")
  else:
    await sleepAsync(1_500)

proc askKimi*(prompt: string, files: seq[string] = @[],
              pref: set[SiteWorkerPref] = {}): Future[AskResult] {.async.} =
  ## Как askQwen(), но для Kimi (kimi.ai), с уже сохранённым профилем
  ## ~/.cache/kimiclient/profile.
  if len(strip(prompt)) == 0:
    raise newException(ValueError, "prompt не должен быть пустым")

  var absPaths: seq[string] = @[]
  for path in files:
    if not fileExists(path):
      raise newException(IOError, "файл не найден: " & path)
    add(absPaths, absolutePath(path))

  let handle = await ensureBrowser(KimiProfileDir, KimiDebugPort, headless = pVisible notin pref)
  vecho(pref, if handle.attached: "Подключаюсь к уже работающему Chromium (Kimi)..."
             else: "Запускаю headless-Chromium (Kimi) с сохранённым профилем...")
  var tab: Tab

  try:
    tab = await gotoWithRetry(handle.browser, KimiChatUrl, verbose = pVerbose in pref)
    await installDiagnostics(tab)

    discard await kimiResolvePromptInputSelector(tab) # ждём гидратации композера
    await sleepAsync(3_000)

    if await kimiIsLoginWalled(tab):
      let hint = "профиль Chromium (~/.cache/kimiclient/profile) не авторизован — войдите в Kimi в этом профиле вручную и повторите"
      warnLoggedOut("Kimi", hint)
      raise newException(SiteWorkerError,
        "похоже, сессия Kimi не авторизована (открылось модальное окно логина) — " & hint)

    # На случай, если системная модалка (перегрузка/лимиты — см.
    # KimiNotificationModalSelector) осталась с предыдущей сессии в этом
    # же профиле/вкладке и перекрывает композер ещё до печати промпта.
    discard await kimiDismissNotificationModal(tab)

    if len(absPaths) > 0:
      await kimiAttachFiles(tab, absPaths, pref)

    proc kimiTypeAndSendOnce(): Future[bool] {.async.} =
      ## Печатает prompt, отправляет и ждёт сегмент ответа ассистента.
      ## Возвращает true при успехе; false — если вместо ответа появилась
      ## системная модалка Kimi (лимиты): её стоит закрыть и повторить
      ## попытку, а не считать поломкой селекторов.
      # Селектор поля ввода переразрешается на случай, если он изменился
      # после прикрепления файла; клик по полю закрывает toolkit-поповер и
      # переводит фокус перед печатью.
      let liveSelector = await kimiResolvePromptInputSelector(tab)
      await click(tab, liveSelector)
      await sleepAsync(300)
      await kimiClearPromptField(tab, liveSelector)

      vecho(pref, "Ввожу промпт...")
      if not (await withTimeout(fill(tab, liveSelector, prompt), 30_000)):
        raise newException(ChildTearError, "ввод промпта в Kimi завис (не завершился за 30 секунд)")

      var typedValue = await getText(tab, liveSelector)
      if strip(typedValue) != strip(prompt):
        # Скорее всего в поле опять был не полностью очищенный
        # черновик (см. kimiClearPromptField) — пробуем ещё раз чище,
        # прежде чем просто предупреждать и отправлять как есть.
        vecho(pref, "Содержимое поля (", $len(typedValue),
          " симв.) не совпадает с промптом (", $len(prompt), " симв.) — переочищаю и печатаю заново...")
        await kimiClearPromptField(tab, liveSelector)
        if not (await withTimeout(fill(tab, liveSelector, prompt), 30_000)):
          raise newException(ChildTearError, "ввод промпта в Kimi завис (не завершился за 30 секунд)")
        typedValue = await getText(tab, liveSelector)
        if strip(typedValue) != strip(prompt):
          vecho(pref, "Предупреждение: содержимое поля (", $len(typedValue),
            " симв.) всё ещё не совпадает с промптом (", $len(prompt), " симв.) — отправляю как есть")

      vecho(pref, "Отправляю (Enter)...")
      await pressEnter(tab, liveSelector)

      var sentConfirmed = await waitUntilCleared(tab, liveSelector, 5_000, 250)

      if not sentConfirmed:
        vecho(pref, "Поле не очистилось после Enter — пробую клик по кнопке отправки...")
        var sendButtonReady = false
        try:
          discard await waitForSelector(tab, KimiSendButtonSelector, timeoutMs = 5_000)
          sendButtonReady = true
        except CatchableError:
          discard
        if sendButtonReady:
          await click(tab, KimiSendButtonSelector)
          sentConfirmed = await waitUntilCleared(tab, liveSelector, 5_000, 250)

      if not sentConfirmed:
        raise newException(ChildTearError,
          "похоже, отправка промпта в Kimi не сработала: поле ввода не " &
          "очистилось ни после Enter, ни после клика по кнопке отправки")

      proc kimiGenerating(): Future[bool] {.async.} = result = await exists(tab, KimiAssistantSegmentSelector)
      result = await waitUntilTrue(kimiGenerating, 10_000, 250)

    const
      KimiCongestionMaxAttempts = 3
        ## Первая попытка + до двух повторов. Больше — не имеет смысла
        ## гонять внутри одного вызова askKimi(); при исчерпании
        ## поднимаем понятную ошибку, и вызывающий код сам решает,
        ## стоит ли повторять запрос позже.
      KimiCongestionBackoffMs = [3_000, 8_000]
        ## Пауза перед 2-й и 3-й попыткой соответственно. "Слишком
        ## много людей сейчас общаются с Kimi" — это временная
        ## перегрузка сервера, а не разъехавшийся селектор: слишком
        ## короткая пауза почти гарантированно натыкается на ту же самую
        ## перегрузку повторно.

    var
      sendOk = false
      lastNotice: tuple[present: bool, title: string, body: string] = (false, "", "")

    for attempt in 1 .. KimiCongestionMaxAttempts:
      sendOk = await kimiTypeAndSendOnce()
      if sendOk:
        break

      lastNotice = await kimiReadNotificationModal(tab)
      if not lastNotice.present:
        # Ответ не начался не из-за congestion-модалки — дальше гонять
        # попытки бессмысленно, это что-то другое (см. ветку ниже).
        break

      vecho(pref, "Kimi показал системное уведомление вместо ответа: \"",
        lastNotice.title, ": ", lastNotice.body, "\"")
      discard await kimiDismissNotificationModal(tab)

      if attempt < KimiCongestionMaxAttempts:
        let backoffMs = KimiCongestionBackoffMs[attempt - 1]
        vecho(pref, "  Похоже на временную перегрузку — жду ", $(backoffMs div 1000),
          " сек. и пробую снова (попытка ", $(attempt + 1), " из ", $KimiCongestionMaxAttempts, ")...")
        await sleepAsync(backoffMs)

    if not sendOk:
      if lastNotice.present:
        raise newException(SiteWorkerError,
          "Kimi отклонил запрос " & $KimiCongestionMaxAttempts &
          " раз(а) подряд с одним и тем же системным уведомлением (\"" &
          lastNotice.title & ": " & lastNotice.body & "\") — похоже на длительную " &
          "перегрузку/лимит тарифа, а не на сломанные селекторы; попробуйте позже")
      else:
        raise newException(ChildTearError,
          "поле ввода очистилось, но узел ответа ассистента Kimi за 10 секунд так и не появился в DOM")

    vecho(pref, "Жду ответ...")
    let answerText = await kimiWaitForResponseStable(tab, KimiLastAssistantMessageSelector)

    let (shotData, shotFormat, hasShot) =
      await captureAnswerScreenshot(tab, KimiLastAssistantMessageSelector, pref)

    result = AskResult(text: answerText, screenshotData: shotData,
                        screenshotFormat: shotFormat, hasScreenshot: hasShot)

  except CatchableError as e:
    vecho(pref, "Ошибка: ", e.msg)
    if not isNil(tab):
      await dumpDebugInfoVerbose(tab, "kimi-debug-ask", pref)
    raise e
  finally:
    # Закрываем только свою вкладку — общий процесс Chromium (см. модель
    # владения выше) не трогаем ни при успехе, ни при ошибке.
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard

