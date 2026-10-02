## siteworkers/qwen.nim
##
## Автоматизация chat.qwen.ai поверх childtear: отправить промпт (с
## приложенными файлами или без) и получить ответ текстом и/или скриншотом.
##
##   import siteworkers/qwen
##
##   let answer = waitFor askQwen("Сформулируй план на неделю")
##   aiText2File(answer.text, "ответ.txt")
##   aiScreenshot2File(answer.screenshotData, "ответ.png", answer.screenshotFormat)
##
## aiText2File/aiText2Clipboard/aiScreenshot2File/aiScreenshot2Clipboard —
## в ./clipboard.nim; AskResult, SiteWorkerPref и общая инфраструктура — в
## ./siteworker_common.nim.
##
## Авторизация: askQwen() сама не логинится, а использует сохранённый
## профиль Chromium (~/.cache/qwenclient/profile). Если профиля нет или
## сессия истекла, бросает SiteWorkerError (нужен повторный вход).
##
## Общие решения API для AI-чатов (qwen, kimi):
##  * флаги поведения — множество set[SiteWorkerPref]; {} означает
##    значения по умолчанию (headless, без debug-файлов, скриншот PNG);
##  * askQwen() возвращает AskResult: текст и скриншот ответа, снятый в той
##    же сессии после стабилизации;
##  * Chromium запускается один раз и переиспользуется
##    (browser_lifecycle.ensureBrowser()/stopBrowser()); после вызова
##    закрывается только своя вкладка;
##  * профиль, cookies и localStorage общие между вызовами, поэтому в начале
##    каждого вызова диалог при необходимости сбрасывается
##    (qwenStartNewChatIfNeeded()), иначе ответ смешался бы с прошлыми
##    обменами.

import std/[os, strutils, strformat, asyncdispatch, json, times]
import ../childtear
import ./siteworker_common
import ./browser_lifecycle
import ./clipboard




# ===========================================================================
# Qwen (chat.qwen.ai)
# ===========================================================================
#
# Селекторы рассчитаны на текущую вёрстку chat.qwen.ai; при её изменении
# тексты ошибок указывают, какой именно селектор перестал совпадать.

type
  QwenAutomationError* = object of ChildTearError
    ## Расхождение с разметкой сайта (селектор переименован или пропал,
    ## сменилась иконка), а не недоступность сети. Подтип ChildTearError,
    ## поэтому askQwen() повторяет попытку с чистой вкладки. Повтор сам по
    ## себе не поможет: сервис доступен, а селектор в этом файле устарел.

  QwenCaptchaError* = object of SiteWorkerError
    ## chat.qwen.ai показал слайдер-проверку (антибот-виджет Alibaba
    ## nc-captcha) вместо чата: DOM чата на странице отсутствует, поэтому
    ## любой шаг askQwen() заведомо проваливается. Подтип SiteWorkerError,
    ## а не ChildTearError: капча привязана к IP/профилю, повтор с чистой
    ## вкладки не поможет, и askQwen() его не делает.

const
  QwenChatUrl = "https://chat.qwen.ai/"
  QwenDebugPort = 9223
    ## Отдельный от Kimi порт (KimiDebugPort в kimi.nim): askQwen() и
    ## askKimi() можно вызывать параллельно, каждый в своём процессе.
  QwenProfileDir = getHomeDir() / ".cache" / "qwenclient" / "profile"
    ## См. пояснение про авторизацию в шапке файла.

  QwenPromptInputSelector = "textarea.message-input-textarea"
  QwenSendButtonSelector = ".chat-prompt-send-button button"
  QwenAttachButtonSelector = "div.mode-select-open"
    ## Кнопка рядом с полем ввода. В текущей вёрстке промежуточного меню
    ## нет: клик (если он нужен) сразу открывает файловый диалог поверх
    ## QwenFileInputSelector. Поэтому в qwenAttachFiles() клик по ней —
    ## необязательный шаг; если меню вернётся, это проявится на
    ## следующем шаге (карточка вложения не появится) и будет описано
    ## диагностикой qwenReadBackFileInputState()/warnSelectorMismatch().
  QwenFileInputSelector = "#filesUpload"
  QwenFileAnalyzingSpinnerSelector = ".file-content-icon .fileitem-loading-icon"
    ## Спиннер "Анализ..." на карточке вложения. Пока он виден, промпт
    ## отправлять нельзя: Qwen молча игнорирует Enter и клик по кнопке
    ## отправки (поле не очищается).
  QwenFileAnalyzeTimeoutMs = 120_000
  QwenFileAnalyzePollMs = 500
  QwenLastAssistantMessageSelector = "div.qwen-chat-message-assistant div.chat-response-message-right"
    ## Контейнер последнего ответа ассистента. Текст в нём перемешан со
    ## служебными узлами: спиннером .response-loading (во время
    ## генерации) и подвалом .message-hoc-container (действия над
    ## ответом). qwenGetLastAssistantText() берёт контейнер целиком и
    ## вычищает служебные узлы перед чтением текста.
  QwenLoginIndicatorTag = "button"
  QwenLoginIndicatorText = "Log in"
  QwenCaptchaIndicatorTag = "div"
  QwenCaptchaIndicatorPhrases = [
    "перетащите ползунок для проверки",
    "проведите вправо",
  ]
    ## Тексты слайдер-капчи Qwen (регистр не важен: existsWithText
    ## сравнивает в нижнем регистре). Тег/класс контейнера не зашит
    ## намеренно: стабилен именно текст заголовка. Для отладки снимите
    ## document.body.outerHTML в момент капчи (dumpDebugInfoVerbose).
  QwenFeedbackWidgetCloseSelector = "span.satisfaction-rating__close"
  QwenAttachedFileCardSelector = "div.file-content-icon"
    ## Контейнер карточки вложения (тот же, где сидит спиннер анализа).
    ## Не исчезает при успешном прикреплении, поэтому служит признаком
    ## "карточка вложения есть на странице" (см. qwenAttachFiles()).
  QwenAttachErrorIndicatorSelector = "div.file-content-icon [class*=\"error\" i], " &
                                      "div.file-content-icon [class*=\"fail\" i]"
    ## Любой элемент внутри карточки вложения с классом, содержащим
    ## "error"/"fail" (так antd помечает ошибки). Подходит и под кнопку
    ## fileitem-error-icon-wrapper, но для подтверждённого случая "Загрузка
    ## не удалась" есть более сильная реакция (qwenAttachFiles()); общее
    ## совпадение остаётся мягким предупреждением.
  QwenAttachUploadFailedTextSelector = "span.fileitem-file-error"
    ## Элемент с текстом "Загрузка не удалась" на карточке вложения при
    ## сбое передачи файла. Рядом появляется кнопка "Повторить загрузку"
    ## (QwenAttachRetryButtonSelector), которой qwenAttachFiles()
    ## пользуется вместо отправки промпта с неприкреплённым файлом.
  QwenAttachRetryButtonSelector = "button[aria-label=\"Повторить загрузку\"]"
  QwenAttachUploadRetries = 2
    ## Сколько раз дополнительно нажимать "Повторить загрузку" (всего
    ## попыток — QwenAttachUploadRetries + 1), прежде чем поднять ошибку:
    ## кратковременный сетевой сбой при загрузке крупного файла не должен
    ## валить весь вызов.
  QwenAskAttempts = 2
    ## Сколько раз выполнять сценарий askQwen() целиком (от открытия чата
    ## до ответа). Обрыв CDP, экран сравнения черновиков с ошибкой
    ## подключения и "не дождались стабилизации" обычно проходят при повторе
    ## на свежей вкладке (сценарий, включая вложения, выполняется заново).
    ## Постоянные сбои (SiteWorkerError: нет авторизации, квота вложений)
    ## не повторяются.
  QwenNewChatHints = ["new chat", "новый чат"]
    ## Видимый текст элемента, которым Qwen предлагает начать новый диалог
    ## (иконка "+"/перо в шапке списка чатов слева). Ищем по тексту, а не
    ## по CSS-классу — по той же причине, что и в остальных qwenMark*()/
    ## markByButtonText()-подобных функциях этого файла и redcircle.nim:
    ## хэшированные классы нестабильны между сборками сайта.
  QwenDualMessageSelector = ".qwen-chat-message-dual-message"
    ## Экран Qwen Studio "Какой ответ вы предпочитаете?": A/B-сравнение двух
    ## черновиков с кнопками "Предпочитаю этот ответ" вместо одного ответа.
    ## Появляется не всегда (эксперимент сайта). Содержимое лежит не в
    ## QwenLastAssistantMessageSelector, а в .smrm-card
    ## .chat-response-message внутри этого контейнера (см.
    ## qwenDualResponseState()).
  QwenDualMessageStatusSelector = ".qwen-messsage-status-description"
    ## Баннер ошибки в карточке варианта ответа, например "Oops! There was
    ## an issue connecting to Qwen3.7-Plus..." — наблюдался в обоих
    ## вариантах сразу (запрос не обработан вовсе). Необязателен: нужен
    ## только чтобы добавить текст ошибки к сообщению; обнаружение экрана
    ## от него не зависит.

proc qwenIsGenerating(tab: Tab): Future[bool] {.async.} =
  ## true, пока кнопка отправки промпта показывает состояние "стоп"
  ## (Qwen ещё генерирует ответ) — определяется по классу/aria-label
  ## кнопки, отдельного признака в DOM для этого CDP не даёт.
  let js = """(function () {
    var btn = document.querySelector('.chat-prompt-send-button button');
    if (!btn) { return false; }
    var cls = (btn.className || '').toLowerCase();
    var label = (btn.getAttribute('aria-label') || '').toLowerCase();
    return cls.indexOf('stop') !== -1 || label.indexOf('стоп') !== -1 || label.indexOf('stop') !== -1;
  })()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc qwenDualResponseState(tab: Tab): Future[tuple[found: bool, errorText: string]] {.async.} =
  ## Проверяет, показал ли Qwen вместо ответа экран сравнения двух
  ## черновиков (QwenDualMessageSelector). Автоматика не может выбрать
  ## вариант, поэтому qwenWaitForResponseStable() сразу сообщает об этом
  ## отдельной ошибкой, а не ждёт таймаут и не списывает на устаревший
  ## селектор (см. QwenDualMessageStatusSelector).
  let js = """(function () {
    var el = document.querySelector('""" & QwenDualMessageSelector & """');
    if (!el) { return { found: false, errorText: '' }; }
    var statusEl = el.querySelector('""" & QwenDualMessageStatusSelector & """');
    return { found: true, errorText: statusEl ? (statusEl.textContent || '').trim() : '' };
  })()"""
  let res = await evalJS(tab, js)
  if res.kind == JObject:
    result = (getBool(res{"found"}, false), getStr(res{"errorText"}, ""))
  else:
    result = (false, "")

proc qwenGetLastAssistantText(tab: Tab, containerSelector: string): Future[string] {.async.} =
  ## Замена childtear.getLastText() для ответа Qwen (см.
  ## QwenLastAssistantMessageSelector): отдельного класса "только текст
  ## ответа" нет, текст рендерится внутри containerSelector вместе со
  ## служебными узлами (спиннер .response-loading, подвал с действиями
  ## .message-hoc-container), и getLastText() добавил бы их подписи к ответу.
  ## Поэтому клонируется последний подходящий узел, из клона вычищаются
  ## известные служебные блоки, и читается текст. Это переживает смену
  ## разметки самого текста, пока остаётся структура "контейнер ответа +
  ## служебные блоки".
  let js = """(function() {
    var nodes = document.querySelectorAll('""" & containerSelector & """');
    if (nodes.length === 0) return null;
    var el = nodes[nodes.length - 1].cloneNode(true);
    var junk = el.querySelectorAll('.response-loading, .message-hoc-container');
    for (var i = 0; i < junk.length; i++) {
      if (junk[i].parentNode) junk[i].parentNode.removeChild(junk[i]);
    }
    return (el.innerText !== undefined) ? el.innerText : el.textContent;
  })()"""
  let value = await evalJS(tab, js)
  result = if value.kind == JString: getStr(value) else: ""

proc qwenWaitForResponseStable(tab: Tab, containerSelector: string,
                                pollMs = 500, stableForMs = 2_000,
                                timeoutMs = 180_000): Future[string] {.async.} =
  ## Ответ завершён, когда кнопка отправки вышла из состояния "Стоп"
  ## (qwenIsGenerating), а не когда стабилен текст: ответ — набор
  ## независимо растущих markdown-блоков, и каждый может ненадолго
  ## "застыть", пока дописываются другие.
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  var
    sawGenerating = false
    lastSeenText = ""
    stableMs = 0

  while epochTime() < deadline:
    let (dualFound, dualError) = await qwenDualResponseState(tab)
    if dualFound:
      raise newException(ChildTearError,
        "Qwen вместо обычного ответа показал экран сравнения двух " &
        "черновиков ('Какой ответ вы предпочитаете?', см. " &
        "QwenDualMessageSelector в siteworkers/qwen.nim) — автоматика не " &
        "умеет выбирать между ними, так что дожидаться тут больше нечего" &
        (if len(dualError) > 0: &"; текст ошибки внутри варианта ответа: {dualError}"
         else: "") &
        ". Это не проблема устаревшего селектора — сам ответ Qwen в " &
        "этот раз пришёл в другом виде.")
    let generating = await qwenIsGenerating(tab)
    if generating:
      sawGenerating = true
      stableMs = 0
    elif sawGenerating:
      await sleepAsync(1_000)
      let final = await qwenGetLastAssistantText(tab, containerSelector)
      if len(strip(final)) > 0:
        return final
    else:
      let current = await qwenGetLastAssistantText(tab, containerSelector)
      if len(strip(current)) > 0:
        if current == lastSeenText:
          inc(stableMs, pollMs)
          if stableMs >= stableForMs:
            return current
        else:
          lastSeenText = current
          stableMs = 0
    await sleepAsync(pollMs)

  let fallback = await qwenGetLastAssistantText(tab, containerSelector)
  if len(strip(fallback)) > 0:
    return fallback

  raise newException(ChildTearError,
    "не дождались стабилизации ответа Qwen за отведённое время — " &
    "возможно, устарел QwenLastAssistantMessageSelector, либо " &
    "QwenSendButtonSelector (на нём основан qwenIsGenerating) больше не " &
    "совпадает с разметкой страницы")

const
  QwenFileInputCandidateMarkAttr = "data-siteworker-file-input-candidate"
    ## Временный data-атрибут с индексом, которым размечается каждый
    ## <input type="file">: id таких элементов ненадёжен для повторной
    ## адресации (может повторяться или переехать на другой элемент), а
    ## атрибут даёт гарантированно уникальный CSS-селектор для повтора.

proc qwenCollectFileInputCandidates(tab: Tab):
    Future[seq[tuple[selector: string, id: string, detail: string]]] {.async.} =
  ## Диагностика и запасной путь: вызывается, когда uploadFile() на
  ## QwenFileInputSelector ("#filesUpload") прошёл без исключения, но
  ## карточка вложения (QwenAttachedFileCardSelector) не появилась (файл
  ## выставлен не на тот <input>). Помечает каждый input[type="file"] на
  ## странице data-атрибутом с индексом (QwenFileInputCandidateMarkAttr),
  ## получая надёжный CSS-селектор для повторного uploadFile(): id таких
  ## элементов может повторяться или не совпасть с QwenFileInputSelector.
  let js = """(function() {
    var inputs = document.querySelectorAll('input[type="file"]');
    var out = [];
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      el.setAttribute('data-siteworker-file-input-candidate', String(i));
      out.push({
        index: i,
        id: el.id || '',
        name: el.getAttribute('name') || '',
        accept: el.getAttribute('accept') || '',
        hidden: !!(el.hidden || (el.style && el.style.display === 'none'))
      });
    }
    return out;
  })()"""
  result = @[]
  let res = await evalJS(tab, js)
  if res.kind != JArray:
    return
  for item in res:
    let index = getInt(item{"index"}, -1)
    let id = getStr(item{"id"}, "")
    let name = getStr(item{"name"}, "")
    let accept = getStr(item{"accept"}, "")
    let hidden = getBool(item{"hidden"}, false)
    if index < 0:
      continue
    var detailParts: seq[string] = @[]
    add(detailParts, "id=\"" & id & "\"")
    if len(name) > 0:
      add(detailParts, "name=\"" & name & "\"")
    if len(accept) > 0:
      add(detailParts, "accept=\"" & accept & "\"")
    add(detailParts, if hidden: "скрыт" else: "виден")
    let selector = "[" & QwenFileInputCandidateMarkAttr & "=\"" & $index & "\"]"
    add(result, (selector: selector, id: id, detail: join(detailParts, "; ")))

proc qwenReadBackFileInputState(tab: Tab, selector: string):
    Future[tuple[filesCount: int, names: seq[string]]] {.async.} =
  ## Читает реальное состояние <input> после uploadFile() (el.files так,
  ## как их видит браузер). Различает: (а) el.files пуст — DOM.
  ## setFileInputFiles не применился (например, узел устарел между
  ## findNode() и вызовом CDP); (б) el.files не пуст, но страница не
  ## отреагировала — change/input не дошли до обработчика React (см.
  ## qwenDispatchInputChangeEvents()).
  let js = "(function() { var el = document.querySelector('" & selector & "'); " &
    "if (!el) return { exists: false, filesCount: 0, names: [] }; " &
    "var names = []; for (var i = 0; i < el.files.length; i++) { names.push(el.files[i].name); } " &
    "return { exists: true, filesCount: el.files.length, names: names }; })()"
  let res = await evalJS(tab, js)
  result = (filesCount: getInt(res{"filesCount"}, 0), names: @[])
  if res{"names"}.kind == JArray:
    for n in res{"names"}:
      add(result.names, getStr(n, ""))

proc qwenDispatchInputChangeEvents(tab: Tab, selector: string) {.async.} =
  ## Принудительно рассылает 'input' и 'change' (bubbles: true, как их
  ## ждут делегированные React-обработчики) на узле, уже заполненном
  ## uploadFile(). По спецификации DOM.setFileInputFiles делает это сам,
  ## но у сайтов с кастомной обвязкой файлового инпута события иногда не
  ## доходят до обработчика. Вызывается дополнительно к CDP; повторный
  ## 'change' с тем же содержимым безвреден (лишний ре-рендер).
  let js = "(function() { var el = document.querySelector('" & selector & "'); " &
    "if (!el) return false; " &
    "el.dispatchEvent(new Event('input', { bubbles: true })); " &
    "el.dispatchEvent(new Event('change', { bubbles: true })); " &
    "return true; })()"
  discard await evalJS(tab, js)

proc qwenCaptchaPresent(tab: Tab): Future[bool] {.async.}
  ## Опережающее объявление: нужна в qwenAttachFiles() ниже, определена
  ## вместе с остальной логикой капчи дальше по файлу.
proc raiseQwenCaptchaError()
  ## Опережающее объявление — см. выше.

proc qwenAttachFiles(tab: Tab, absPaths: seq[string], pref: set[SiteWorkerPref],
                      debugPrefix: string) {.async.} =
  ## Прикрепляет файлы (absPaths — абсолютные пути) через кнопку вложения
  ## Qwen; несколько файлов выставляются одним вызовом uploadFile()
  ## (DOM.setFileInputFiles принимает список).
  ##
  ## Клик по QwenAttachButtonSelector необязателен: без кнопки файл грузится
  ## прямо в QwenFileInputSelector. Если появится обязательный промежуточный
  ## шаг, карточка вложения (QwenAttachedFileCardSelector) не появится, и
  ## сработает диагностика ниже (qwenReadBackFileInputState(),
  ## qwenCollectFileInputCandidates(), warnSelectorMismatch()).
  vecho(pref, "Прикрепляю файлы: ", join(absPaths, ", "))

  if await exists(tab, QwenAttachButtonSelector):
    await click(tab, QwenAttachButtonSelector)
    await sleepAsync(300)
  else:
    vecho(pref, "  ВНИМАНИЕ: кнопка вложения Qwen (", QwenAttachButtonSelector,
                ") не найдена — гружу файл напрямую в ", QwenFileInputSelector)

  await uploadFile(tab, QwenFileInputSelector, absPaths)
  await qwenDispatchInputChangeEvents(tab, QwenFileInputSelector)
    # Подстраховка на случай, если событие change/input от самого CDP
    # DOM.setFileInputFiles почему-то не долетело до делегированного
    # обработчика React (см. qwenDispatchInputChangeEvents() выше) —
    # безвредно, даже если событие и так уже сработало штатно.
  await dumpDebugInfoVerbose(tab, debugPrefix & "-attach", pref)

  vecho(pref, "  Жду завершения анализа вложения(й) на сервере...")
  let analyzed = await waitForSelectorGone(tab, QwenFileAnalyzingSpinnerSelector,
                                            QwenFileAnalyzeTimeoutMs, QwenFileAnalyzePollMs)

  if not analyzed:
    await dumpDebugInfoVerbose(tab, debugPrefix & "-attach-still-analyzing", pref)
    raise newException(ChildTearError,
      "вложение(я) Qwen так и не закончили анализ на сервере спустя " &
      $(QwenFileAnalyzeTimeoutMs div 1000) & " секунд ожидания.")

  # Исчезновение спиннера не гарантирует, что файл прикреплён: Qwen может
  # считать анализ завершённым и ответить, что аудио у него нет (сбой
  # загрузки, не пойманный спиннером). Снимок делается в момент "спиннер
  # пропал", до решения "вложение готово", чтобы в
  # qwen-debug-*-attach-done.html было видно карточку файла (или её
  # отсутствие). Пишется только при pDumpDebug (dumpDebugInfoVerbose).
  await dumpDebugInfoVerbose(tab, debugPrefix & "-attach-done", pref)

  let cardStillThere = await exists(tab, QwenAttachedFileCardSelector)
  if not cardStillThere:
    # Слайдер-проверка перекрывает страницу модальным окном и молча
    # блокирует вложение: uploadFile() не падает, карточка не появляется.
    # Капча проверяется первой (QwenCaptchaError): её нужно пройти вручную
    # через login-хелпер, программно она не обходится.
    #
    # Если карточки нет и капчи нет, это систематический сбой (Qwen ответит,
    # что файла нет). Реакция: (1) диагностика; (2) запасной путь —
    # QwenFileInputSelector мог указывать не на тот <input>, поэтому
    # пробуются остальные input[type="file"]; (3) иначе QwenAutomationError,
    # без минут анализа несуществующего вложения.
    if await qwenCaptchaPresent(tab):
      raiseQwenCaptchaError()
    let readback = await qwenReadBackFileInputState(tab, QwenFileInputSelector)
    if readback.filesCount == 0:
      vecho(pref, "  Диагностика: el.files на " & QwenFileInputSelector & " пуст ПОСЛЕ " &
        "uploadFile() — браузер не принял файл на этот узел вовсе (не проблема " &
        "события change/input, а самого CDP-присвоения).")
    else:
      vecho(pref, "  Диагностика: el.files на " & QwenFileInputSelector & " СОДЕРЖИТ " &
        $readback.filesCount & " файл(ов) (" & join(readback.names, ", ") & ") ПОСЛЕ " &
        "uploadFile() — браузер файл принял, но карточка вложения в чате всё равно не " &
        "появилась: похоже, дело не в узле/селекторе, а в том, что событие change/input " &
        "не долетает до обработчика страницы (или обработчик проверяет что-то ещё, " &
        "кроме факта наличия файла).")

    # Один повтор на том же узле перед перебором других input: el.files
    # пуст (возможна гонка между findNode() и присвоением) либо не пуст, но
    # событие не долетело (см. qwenDispatchInputChangeEvents()) — оба случая
    # стоит просто повторить. Перебор альтернатив ниже оставлен на случай
    # разметки с несколькими input.
    vecho(pref, "  Пробую ещё раз тот же " & QwenFileInputSelector & " (с принудительной " &
                "рассылкой событий)...")
    await sleepAsync(500)
    await uploadFile(tab, QwenFileInputSelector, absPaths)
    await qwenDispatchInputChangeEvents(tab, QwenFileInputSelector)
    discard await waitForSelectorGone(tab, QwenFileAnalyzingSpinnerSelector,
                                       QwenFileAnalyzeTimeoutMs, QwenFileAnalyzePollMs)
    await dumpDebugInfoVerbose(tab, debugPrefix & "-attach-retry-same-input", pref)

    let inputCandidates = await qwenCollectFileInputCandidates(tab)
    var displayCandidates: seq[tuple[label: string, detail: string]] = @[]
    for c in inputCandidates:
      add(displayCandidates, (label: c.selector & " (было: " & QwenFileInputSelector & ")",
                               detail: c.detail))

    var recovered = await exists(tab, QwenAttachedFileCardSelector)
    if recovered:
      vecho(pref, "  Повтор на том же input сработал — карточка вложения появилась.")
    else:
      warnSelectorMismatch("Qwen",
        "QwenFileInputSelector = \"" & QwenFileInputSelector & "\" — после uploadFile() и " &
        "исчезновения спиннера анализа карточка вложения (" & QwenAttachedFileCardSelector &
        ") в DOM так и не появилась (проверено дважды, с принудительной рассылкой " &
        "change/input между попытками)",
        "константа QwenFileInputSelector в siteworkers/qwen.nim (используется в " &
        "вызове uploadFile() внутри qwenAttachFiles()) — но, судя по диагностике el.files " &
        "выше, дело, возможно, не в самом селекторе, а в чём-то ещё на стороне сайта",
        displayCandidates)

      for cand in inputCandidates:
        if cand.id == "filesUpload":
          continue  # это тот же элемент, что уже пробовали через QwenFileInputSelector
        vecho(pref, "  Пробую запасной input[type=\"file\"] (", cand.selector, ", ",
                    cand.detail, ")...")
        try:
          await uploadFile(tab, cand.selector, absPaths)
          await qwenDispatchInputChangeEvents(tab, cand.selector)
        except CatchableError as e:
          vecho(pref, "  Запасной input не сработал: ", e.msg, " — пробую следующий, если есть...")
          continue
        discard await waitForSelectorGone(tab, QwenFileAnalyzingSpinnerSelector,
                                           QwenFileAnalyzeTimeoutMs, QwenFileAnalyzePollMs)
        if await exists(tab, QwenAttachedFileCardSelector):
          vecho(pref, "  Запасной input сработал — карточка вложения появилась.")
          recovered = true
          break

    if not recovered:
      raise newException(QwenAutomationError,
        "после uploadFile()/исчезновения спиннера анализа карточка вложения (" &
        QwenAttachedFileCardSelector & ") так и не появилась в DOM — ни для " &
        QwenFileInputSelector & ", ни для запасных input[type=\"file\"] (см. диагностику " &
        "выше и " & debugPrefix & "-attach-done.html/-console.json). Файл, судя по всему, " &
        "по факту не прикрепляется ни на один известный элемент, хотя сам вызов " &
        "uploadFile() не бросает исключение — похоже, устарел QwenFileInputSelector.")
  elif await exists(tab, QwenAttachUploadFailedTextSelector):
    # Подтверждённый сбой загрузки (QwenAttachUploadFailedTextSelector):
    # наблюдался на крупном mp3 ([xhr-failed] к oss-accelerate.aliyuncs.com
    # — обрыв сети при передаче). Qwen предлагает кнопку "Повторить
    # загрузку", ею и пользуемся: краткая просадка сети не должна валить
    # весь вызов.
    var uploadOk = false
    for retryAttempt in 1 .. QwenAttachUploadRetries:
      if not await exists(tab, QwenAttachRetryButtonSelector):
        vecho(pref, "  ВНИМАНИЕ: карточка файла показывает «Загрузка не удалась», но " &
          "кнопки «Повторить загрузку» рядом не нашлось — прекращаю попытки повтора.")
        break
      vecho(pref, "  ВНИМАНИЕ: загрузка вложения не удалась (карточка файла: «Загрузка " &
        "не удалась», см. " & debugPrefix & "-attach-done.html) — нажимаю «Повторить " &
        "загрузку» (попытка ", $retryAttempt, " из ", $QwenAttachUploadRetries, ")...")
      await click(tab, QwenAttachRetryButtonSelector)
      let reanalyzed = await waitForSelectorGone(tab, QwenFileAnalyzingSpinnerSelector,
                                                  QwenFileAnalyzeTimeoutMs, QwenFileAnalyzePollMs)
      await dumpDebugInfoVerbose(tab, debugPrefix & "-attach-retry" & $retryAttempt, pref)
      if reanalyzed and not await exists(tab, QwenAttachUploadFailedTextSelector):
        uploadOk = true
        break
    if not uploadOk:
      raise newException(ChildTearError,
        "загрузка вложения в Qwen не удалась (карточка файла показывает «Загрузка не " &
        "удалась», рядом кнопка «Повторить загрузку») — после начальной попытки и " &
        $QwenAttachUploadRetries & " повторов через саму кнопку сайта сбой так и не " &
        "устранился. Это не баг автоматики и не устаревший селектор — реальный обрыв " &
        "передачи файла на сервер Qwen (см. также [xhr-failed] к " &
        "oss-accelerate.aliyuncs.com в " & debugPrefix & "-attach-done-console.json, " &
        "если он там есть) — эпизод имеет смысл просто повторить позже.")
  elif await exists(tab, QwenAttachErrorIndicatorSelector):
    vecho(pref, "  ВНИМАНИЕ: рядом с карточкой вложения найден элемент, похожий на " &
      "индикатор ошибки (см. " & debugPrefix & "-attach-done.html) — вложение могло " &
      "не загрузиться, хотя спиннер анализа исчез. Продолжаю, т.к. признак не " &
      "подтверждён живой разметкой ошибки — не хочу ложно обрывать конвейер по " &
      "непроверенной догадке.")

  vecho(pref, "  Вложение(я) готовы.")

proc qwenTrySend(tab: Tab): Future[bool] {.async.} =
  ## Один виток отправки текущего содержимого поля: Enter, а если поле не
  ## очистилось — клик по кнопке отправки. Возвращает true, если поле
  ## подтверждённо очистилось (byValue). Выделена, потому что вызывается
  ## несколько раз подряд (см. askQwen): Enter и клик срабатывают
  ## нестабильно, иногда лишь со 2-й или 4-й попытки.
  await pressEnter(tab, QwenPromptInputSelector)
  result = await waitUntilCleared(tab, QwenPromptInputSelector, 5_000, 250, byValue = true)
  if result:
    return true
  if await exists(tab, QwenSendButtonSelector):
    await click(tab, QwenSendButtonSelector)
    result = await waitUntilCleared(tab, QwenPromptInputSelector, 5_000, 250, byValue = true)

proc qwenTrySendWithRetries(tab: Tab, pref: set[SiteWorkerPref],
                             attempts = 3, label = ""): Future[bool] {.async.} =
  ## Несколько витков qwenTrySend() с растущей паузой: одной попытки
  ## часто недостаточно (см. её комментарий), нужное число заранее
  ## неизвестно. label — только для сообщений в консоль.
  for attempt in 1 .. attempts:
    result = await qwenTrySend(tab)
    if result:
      return true
    if attempt < attempts:
      vecho(pref, "  Попытка отправки", label, " ", $attempt, "/", $attempts,
        " не сработала — жду и пробую снова...")
      # Перед следующей попыткой на всякий случай ещё раз сверяем
      # controlled-состояние поля с реальным DOM: если Enter/клик всё же
      # частично повлияли на страницу (например, начали, но не завершили
      # какой-то внутренний ре-рендер Qwen), это не помешает, а если
      # именно это и было причиной прошлой неудачи — поможет.
      discard await syncControlledValue(tab, QwenPromptInputSelector)
      await sleepAsync(500 * attempt)

proc qwenStartNewChatIfNeeded(tab: Tab, pref: set[SiteWorkerPref]) {.async.} =
  ## Chromium и профиль общие между вызовами, поэтому переход на
  ## QwenChatUrl не гарантирует пустой диалог: сайт может открыть последний
  ## чат, и вопрос с файлом дописался бы в старый диалог. Если сброс не
  ## подтверждён (ни кликом, ни резервной перезагрузкой), бросается
  ## ChildTearError: подмену не поймал бы разбор ответа, а ChildTearError
  ## запускает штатный повтор askQwen() на чистой вкладке.
  if not await exists(tab, QwenLastAssistantMessageSelector):
    return  # диалог уже пуст — сбрасывать нечего
  vecho(pref, "Обнаружен диалог, оставшийся от предыдущего вызова, — начинаю новый чат...")
  let js = """(function (needles) {
    var nodes = document.querySelectorAll('button, a, div[role="button"]');
    for (var i = 0; i < nodes.length; i++) {
      var text = (nodes[i].textContent || '').trim().toLowerCase();
      for (var j = 0; j < needles.length; j++) {
        if (text === needles[j] || text.indexOf(needles[j]) !== -1) {
          nodes[i].click();
          return true;
        }
      }
    }
    return false;
  })(""" & $(%QwenNewChatHints) & ")"
  let clicked = await evalJS(tab, js)

  proc oldMessageGone(): Future[bool] {.async.} =
    result = not (await exists(tab, QwenLastAssistantMessageSelector))

  if clicked.kind == JBool and getBool(clicked):
    let resetConfirmed = await waitUntilTrue(oldMessageGone, 5_000, 200)
    if not resetConfirmed:
      # Клик формально нашёл и нажал нужный элемент, но старое сообщение
      # за 5 секунд так и не пропало из DOM. Даём странице последний
      # шанс — полную перезагрузку — прежде чем считать попытку
      # проваленной.
      vecho(pref, "  Клик по 'новый чат' сработал, но старый диалог не " &
                  "исчез за 5 секунд — перезагружаю страницу для надёжности...")
      await goto(tab, QwenChatUrl)
      discard await waitForSelector(tab, QwenPromptInputSelector, timeoutMs = 20_000)
      await sleepAsync(2_000)
      if await exists(tab, QwenLastAssistantMessageSelector):
        raise newException(ChildTearError,
          "не удалось начать новый диалог в Qwen: старое сообщение всё ещё " &
          "видно после клика 'новый чат' и последующей перезагрузки " &
          "страницы. Прикреплять новый файл в диалог с неясным состоянием " &
          "опасно (риск смешения контекста с предыдущим анализом) — " &
          "прерываю эту попытку, чтобы сработал повтор с чистой вкладки.")
  else:
    # Кнопка нового чата не нашлась по видимому тексту (needles устарели
    # или сайт использует другой способ) — запасной, надёжный вариант:
    # полная перезагрузка вкладки на QwenChatUrl. Если сайт всё равно
    # восстановит старый диалог и после этого, значит needles/сама схема
    # обнаружения устарели и их нужно поправить по актуальной разметке.
    vecho(pref, "  Кнопка нового чата не найдена по тексту — перезагружаю страницу...")
    await goto(tab, QwenChatUrl)
    discard await waitForSelector(tab, QwenPromptInputSelector, timeoutMs = 20_000)
    await sleepAsync(2_000)
    if await exists(tab, QwenLastAssistantMessageSelector):
      raise newException(ChildTearError,
        "не удалось начать новый диалог в Qwen: старое сообщение всё ещё " &
        "видно даже после перезагрузки страницы (кнопка 'новый чат' не " &
        "нашлась по тексту) — прикреплять новый файл в диалог с неясным " &
        "состоянием опасно (риск смешения контекста с предыдущим анализом), " &
        "поэтому это фатальная ошибка попытки: должен сработать повтор с " &
        "чистой вкладки, а не публикация перепутанного контента.")

proc qwenCaptchaPresent(tab: Tab): Future[bool] {.async.} =
  ## Есть ли на странице слайдер-проверка («Перетащите ползунок для
  ## проверки»). Опрос нескольких фраз — на случай локализации/смены
  ## формулировки антибот-виджета (см. QwenCaptchaIndicatorPhrases).
  for phrase in QwenCaptchaIndicatorPhrases:
    if await existsWithText(tab, QwenCaptchaIndicatorTag, phrase):
      return true
  result = false

proc raiseQwenCaptchaError() =
  ## Единая точка падения при обнаружении капчи: безусловное предупреждение
  ## в stderr (по образцу warnLoggedOut() — «разлогинен» здесь было бы
  ## вводящей в заблуждение формулировкой) + исключение, которое askQwen()
  ## не повторяет (см. QwenCaptchaError выше).
  let hint = "откройте chat.qwen.ai в видимом окне с тем же профилем " &
    "(" & QwenProfileDir & " — флаг --visible у вызывающего приложения, " &
    "либо логин-хелпер поверх loginQwen()), " &
    "пройдите проверку вручную и повторите запуск; неопубликованные " &
    "эпизоды останутся в pending.txt"
  stderr.writeLine("⚠ Qwen требует пройти проверку (слайдер-капча): " & hint)
  raise newException(QwenCaptchaError,
    "chat.qwen.ai показывает проверку на робота вместо чата — " & hint)

proc askQwen*(prompt: string, files: seq[string] = @[],
              pref: set[SiteWorkerPref] = {},
              debugPrefix: string = "qwen-debug",
              proxyUrl: string = ""): Future[AskResult] {.async.} =
  ## Отправляет prompt (с приложенными files или без) в chat.qwen.ai через
  ## headless- (при pVisible — видимый) Chromium с профилем
  ## ~/.cache/qwenclient/profile и возвращает AskResult: текст ответа и (если
  ## не задан pNoScreenshot) скриншот блока с ответом.
  ##
  ## proxyUrl передаётся как --proxy-server, если вызов сам поднимает
  ## браузер (см. launchDetachedChromium()); на запущенный браузер не
  ## действует. debugPrefix — префикс файлов dumpDebugInfoVerbose()
  ## (<debugPrefix>-attach.html, -attach-done.html, -ask.html и их
  ## -console.json); пишутся только при pDumpDebug.
  if len(strip(prompt)) == 0:
    raise newException(ValueError, "prompt не должен быть пустым")

  var absPaths: seq[string] = @[]
  for path in files:
    if not fileExists(path):
      raise newException(IOError, "файл не найден: " & path)
    add(absPaths, absolutePath(path))

  let handle = await ensureBrowser(QwenProfileDir, QwenDebugPort, headless = pVisible notin pref,
                                    proxyUrl = proxyUrl)
  vecho(pref, if handle.attached: "Подключаюсь к уже работающему Chromium (Qwen)..."
             else: "Запускаю headless-Chromium (Qwen) с сохранённым профилем...")
  var tab: Tab

  try:
    for attempt in 1 .. QwenAskAttempts:
      if attempt > 1:
        vecho(pref, &"Попытка {attempt}/{QwenAskAttempts}: предыдущая сорвалась из-за сбоя " &
          "соединения или разового сбоя страницы Qwen (см. сообщение выше) — закрываю " &
          "вкладку и начинаю askQwen() заново, с чистого листа (включая повторное " &
          "прикрепление файлов, если они были)...")
        if not isNil(tab):
          try:
            await close(tab)
          except CatchableError:
            discard
          tab = nil

      tab = await gotoWithRetry(handle.browser, QwenChatUrl, verbose = pVerbose in pref)
      await installDiagnostics(tab)

      # Капча проверяется на каждом тике ожидания поля ввода: при её
      # показе поля на странице нет, и без проверки ожидание молча
      # истекло бы, а сбой выглядел бы как смена разметки.
      var promptInputFound = false
      for tick in 0 ..< 40:  # суммарно до ~20 секунд
        if await qwenCaptchaPresent(tab):
          raiseQwenCaptchaError()
        if await exists(tab, QwenPromptInputSelector):
          promptInputFound = true
          break
        await sleepAsync(500)
      # Пауза даёт странице пережить гидратационную пересборку DOM: сам
      # QwenPromptInputSelector уже появляется в разметке до того, как
      # React полностью гидратировал страницу, и клик в этом окне может
      # напороться на React error #418 (сброс дерева) вместо реального ввода.
      await sleepAsync(3_000)

      if not promptInputFound and await qwenCaptchaPresent(tab):
        # Капча могла появиться уже ПОСЛЕ 40-й проверки, но до конца
        # 3-секундной паузы выше — последний шанс поймать её явно, прежде
        # чем ниже она будет молча принята за разлогиненный профиль.
        raiseQwenCaptchaError()

      if await existsWithText(tab, QwenLoginIndicatorTag, QwenLoginIndicatorText):
        let hint = "профиль Chromium (~/.cache/qwenclient/profile) не авторизован — войдите в chat.qwen.ai в этом профиле вручную и повторите"
        warnLoggedOut("Qwen", hint)
        raise newException(SiteWorkerError,
          "похоже, сессия Qwen не авторизована — " & hint)
        # SiteWorkerError не подтип ChildTearError/CDPError — except ниже
        # его не перехватывает, и попытка НЕ повторяется: смена вкладки
        # не решает проблему разлогиненного профиля, только тратит время.

      if await qwenCaptchaPresent(tab):
        raiseQwenCaptchaError()
        # Капча может всплыть поверх уже загруженного чата (после проверки
        # логина) или появиться с задержкой на гидратацию — эта проверка
        # безопасна по построению: выполняется до отправки промпта, когда
        # ответа Qwen на странице ещё нет, так что не спутает свой же
        # текст ответа со словами капчи.

      if await exists(tab, QwenFeedbackWidgetCloseSelector):
        vecho(pref, "Закрываю всплывающий опрос об оценке Qwen Studio...")
        await click(tab, QwenFeedbackWidgetCloseSelector)
        await sleepAsync(500)

      try:
        await qwenStartNewChatIfNeeded(tab, pref)

        if len(absPaths) > 0:
          await qwenAttachFiles(tab, absPaths, pref, debugPrefix)

        vecho(pref, "Ввожу промпт...")
        if not (await withTimeout(fill(tab, QwenPromptInputSelector, prompt), 30_000)):
          raise newException(ChildTearError, "ввод промпта в Qwen завис (не завершился за 30 секунд)")

        # QwenPromptInputSelector — управляемый (controlled) React-компонент:
        # fill() меняет .value в обход его собственного сеттера (см.
        # childtear.syncControlledValue), так что без этого вызова React ещё
        # не в курсе введённого текста — и тогда даже первая попытка Enter
        # обречена (обработчик смотрит на своё, всё ещё пустое, состояние),
        # а не только запасной клик по кнопке отправки ниже.
        discard await syncControlledValue(tab, QwenPromptInputSelector)
        # Пауза даёт React закоммитить ре-рендер после dispatchEvent
        # (обновить state, разблокировать кнопку отправки): без неё
        # pressEnter()/клик иногда выполняются раньше, чем страница
        # "увидела" введённый текст.
        await sleepAsync(300)

        let typedValue = await getValue(tab, QwenPromptInputSelector)
        if strip(typedValue) != strip(prompt):
          vecho(pref, "Предупреждение: содержимое поля (", $len(typedValue),
            " симв.) не совпадает с промптом (", $len(prompt), " симв.)")

        vecho(pref, "Отправляю (Enter/кнопка, с повторами)...")
        var sentConfirmed = await qwenTrySendWithRetries(tab, pref, attempts = 3)

        if not sentConfirmed:
          # Ни Enter, ни клик по кнопке не срабатывают за несколько попыток:
          # события долетают до страницы, но fill()+insertText+синтетический
          # 'input' обновляют el.value, а не то "истинное" состояние черновика,
          # которое проверяет обработчик отправки. Перепечатываем промпт
          # посимвольно настоящими событиями клавиатуры (type()) — это не
          # задействует insertText/синтетический 'input' вовсе.
          vecho(pref, "Кнопка тоже не сработала — перепечатываю промпт посимвольно (type) и пробую снова...")

          # clearValue() здесь не годится: присваивание el.value = '' идёт
          # через инстанс-сеттер React и обновляет его внутренний трекер, поэтому
          # syncControlledValue() не видит рассинхронизации и onChange не
          # срабатывает. setControlledValue() пишет через сеттер прототипа в
          # обход перехватчика, и React замечает изменение.
          discard await setControlledValue(tab, QwenPromptInputSelector, "")

          # typeText() печатает реальными событиями клавиатуры (на каждую
          # руну keyDown+char+keyUp и пауза delayMs=15), поэтому время
          # ввода растёт с длиной текста, а ре-рендер textarea замедляет
          # его ещё сильнее. Таймаут пропорционален длине промпта: при
          # настоящем зависании ошибка всё равно сработает.
          let retypeTimeoutMs = max(60_000, len(prompt) * 120 + 20_000)
          if not (await withTimeout(typeText(tab, QwenPromptInputSelector, prompt, delayMs = 15), retypeTimeoutMs)):
            raise newException(ChildTearError,
              &"повторный посимвольный ввод промпта в Qwen не уложился в отведённые " &
              &"{retypeTimeoutMs div 1000} сек (длина промпта: {len(prompt)} симв.)")

          let retypedValue = await getValue(tab, QwenPromptInputSelector)
          if strip(retypedValue) != strip(prompt):
            vecho(pref, "Предупреждение: после перепечатки содержимое поля (", $len(retypedValue),
              " симв.) всё ещё не совпадает с промптом (", $len(prompt), " симв.)")

          vecho(pref, "Отправляю повторно (Enter/кнопка, с повторами)...")
          sentConfirmed = await qwenTrySendWithRetries(tab, pref, attempts = 3, label = " после перепечатки")

        if not sentConfirmed:
          raise newException(ChildTearError,
            "похоже, отправка промпта в Qwen не сработала: поле ввода не очистилось " &
            "ни после Enter/клика (несколько попыток), ни после повторной посимвольной " &
            "перепечатки промпта (тоже несколько попыток)")

        proc qwenGenerating(): Future[bool] {.async.} = result = await qwenIsGenerating(tab)
        if not await waitUntilTrue(qwenGenerating, 10_000, 250):
          raise newException(ChildTearError,
            "поле ввода очистилось, но генерация ответа Qwen за 10 секунд так и не началась")

        vecho(pref, "Жду ответ...")
        let answerText = await qwenWaitForResponseStable(tab, QwenLastAssistantMessageSelector)

        let (shotData, shotFormat, hasShot) =
          await captureAnswerScreenshot(tab, QwenLastAssistantMessageSelector, pref)

        result = AskResult(text: answerText, screenshotData: shotData,
                            screenshotFormat: shotFormat, hasScreenshot: hasShot)
        break  # успех — дальше по циклу попыток идти не нужно, tab остаётся как есть
      except CatchableError as e:
        # Решение "повторять или нет" принимается здесь по типу ошибки.
        # Повторяются два класса временных сбоев:
        #  - ChildTearError — распознанные неполадки сайта (экран сравнения
        #    черновиков с ошибкой подключения, "не дождались стабилизации
        #    ответа", сбой отправки и т.п.);
        #  - CDPError — обрыв CDP-соединения посреди работы (вкладка могла
        #    умереть по причине вне логики сайта, например нехватка памяти
        #    Chromium после долгого прогона).
        # Остальное (прежде всего SiteWorkerError: нет авторизации, квота
        # вложений) повтор не исправит и летит наружу без второй попытки.
        if not (e of ChildTearError or e of CDPError) or attempt >= QwenAskAttempts:
          raise
        vecho(pref, "  Попытка ", $attempt, "/", $QwenAskAttempts, " не удалась: ", e.msg)
        # переходим к следующей итерации for — она сама закроет эту
        # вкладку и откроет новую (см. начало тела цикла выше)

  except CatchableError as e:
    vecho(pref, "Ошибка: ", e.msg)
    if not isNil(tab):
      await dumpDebugInfoVerbose(tab, debugPrefix & "-ask", pref)
    raise e
  finally:
    # Закрываем только свою вкладку — общий процесс Chromium (см. модель
    # владения выше) не трогаем ни при успехе, ни при ошибке.
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard

proc loginQwen*(): Future[void] {.async.} =
  ## Интерактивный вход в chat.qwen.ai: поднимает видимый Chromium с тем
  ## же профилем (QwenProfileDir), что у askQwen(), открывает чат и ждёт,
  ## пока пользователь войдёт вручную и нажмёт Enter. Нужна, когда сессия
  ## слетела. Не ensureBrowser(..., headless = false): при живом
  ## headless-процессе на QwenDebugPort он подключился бы к нему, и окно
  ## входа не появилось бы (см. ensureBrowserForLogin()).
  let handle = await ensureBrowserForLogin(QwenProfileDir, QwenDebugPort)
  var tab: Tab
  try:
    tab = await gotoWithRetry(handle.browser, QwenChatUrl, verbose = false)
    echo "Открыт chat.qwen.ai в видимом окне Chromium."
    echo "Профиль: ", QwenProfileDir
    echo "Войдите в аккаунт в открывшемся окне, затем нажмите Enter здесь..."
    discard readLine(stdin)

    # Даём странице время среагировать на только что состоявшийся
    # логин (переход/ре-рендер шапки), прежде чем проверять индикатор.
    await sleepAsync(1_000)
    if await qwenCaptchaPresent(tab):
      echo "⚠ Видна слайдер-проверка («Перетащите ползунок для проверки») — ",
           "пройдите её в открывшемся окне, затем нажмите Enter здесь ещё раз."
    elif await existsWithText(tab, QwenLoginIndicatorTag, QwenLoginIndicatorText):
      echo "⚠ Кнопка входа ('", QwenLoginIndicatorText, "') всё ещё видна — похоже, войти не удалось."
    else:
      echo "✓ Похоже, вход выполнен успешно."
  finally:
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard
    # Освобождаем порт: следующий обычный (автоматический) вызов
    # askQwen() поднимет свежий headless-процесс сам и прочитает уже
    # обновлённые на диске cookies с нуля — не оставляем видимое окно
    # висеть фоном до следующего запуска.
    await stopBrowser(QwenDebugPort)
