## cdp/domains/page.nim
##
## Тонкая типобезопасная обёртка над доменом Page спецификации CDP:
## https://chromedevtools.github.io/devtools-protocol/tot/Page/
##
## Каждая процедура здесь — это просто "собрать JSON параметров,
## вызвать session.call(...), вернуть результат", без какой-либо
## дополнительной логики (ожидание событий и т.п. остаётся на
## усмотрение childtear.nim).

import std/[asyncdispatch, json]
import ../transport

proc enable*(session: CDPSession) {.async.} =
  ## Включает домен Page — обязательно перед подпиской на его события
  ## (loadEventFired, frameNavigated и т.д.).
  discard await call(session, "Page.enable")

proc disable*(session: CDPSession) {.async.} =
  ## Отключает домен Page — подписки на его события (loadEventFired и
  ## т.п.) перестают срабатывать.
  discard await call(session, "Page.disable")

proc navigate*(session: CDPSession, url: string, referrer = "",
                transitionType = ""): Future[JsonNode] {.async.} =
  ## Открывает URL в текущей вкладке. Возвращает {"frameId", "loaderId", ...},
  ## а при неудачной навигации (например, DNS не резолвится) — ещё и
  ## "errorText" с причиной, которую проверяет вызывающий код в
  ## childtear.nim, не дожидаясь полного таймаута Page.loadEventFired.
  var params = %*{"url": url}
  if len(referrer) > 0:
    params["referrer"] = %referrer
  if len(transitionType) > 0:
    params["transitionType"] = %transitionType
  result = await call(session, "Page.navigate", params)

proc reload*(session: CDPSession, ignoreCache = false, scriptToEvaluateOnLoad = "") {.async.} =
  ## Перезагружает текущую страницу. ignoreCache = true — то же самое,
  ## что Ctrl+Shift+R (жёсткая перезагрузка мимо HTTP-кэша).
  ## scriptToEvaluateOnLoad — однократный JS, выполняемый сразу после
  ## создания нового документа, до остальных скриптов страницы.
  var params = %*{"ignoreCache": ignoreCache}
  if len(scriptToEvaluateOnLoad) > 0:
    params["scriptToEvaluateOnLoad"] = %scriptToEvaluateOnLoad
  discard await call(session, "Page.reload", params)

proc stopLoading*(session: CDPSession) {.async.} =
  ## Останавливает текущую загрузку страницы (аналог кнопки "стоп" в
  ## браузере). Уже загруженная часть DOM остаётся как есть.
  discard await call(session, "Page.stopLoading")

proc close*(session: CDPSession) {.async.} =
  ## Закрывает вкладку так же, как это делает пользователь (кнопкой
  ## "закрыть таб"), в отличие от HTTP /json/close — может, например,
  ## запустить beforeunload-диалог.
  discard await call(session, "Page.close")

proc bringToFront*(session: CDPSession) {.async.} =
  ## Делает вкладку активной (аналог Puppeteer page.bringToFront()).
  discard await call(session, "Page.bringToFront")

proc getFrameTree*(session: CDPSession): Future[JsonNode] {.async.} =
  ## Дерево фреймов страницы: {"frame": {...}, "childFrames": [...]} —
  ## каждый узел содержит "frame": {"id", "url", "name", ...} и
  ## рекурсивно "childFrames" для вложенных iframe.
  result = await call(session, "Page.getFrameTree")

proc setDocumentContent*(session: CDPSession, frameId, html: string) {.async.} =
  ## Заменяет содержимое документа фрейма целиком, без навигации по URL
  ## (frameId — из getFrameTree()) — основа page.setContent() в Puppeteer.
  discard await call(session, "Page.setDocumentContent", %*{"frameId": frameId, "html": html})

proc getNavigationHistory*(session: CDPSession): Future[JsonNode] {.async.} =
  ## Возвращает {"currentIndex", "entries": [...]}.
  result = await call(session, "Page.getNavigationHistory")

proc navigateToHistoryEntry*(session: CDPSession, entryId: int) {.async.} =
  ## Переходит к конкретной записи истории по её id (см.
  ## getNavigationHistory()) — основа goBack()/goForward() в childtear.nim.
  discard await call(session, "Page.navigateToHistoryEntry", %*{"entryId": entryId})

proc resetNavigationHistory*(session: CDPSession) {.async.} =
  ## Очищает всю историю навигации вкладки, оставляя только текущую
  ## запись — после этого goBack()/goForward() возвращают false, пока
  ## не появятся новые записи.
  discard await call(session, "Page.resetNavigationHistory")

proc setLifecycleEventsEnabled*(session: CDPSession, enabled = true) {.async.} =
  ## Включает более гранулярные события "Page.lifecycleEvent"
  ## (networkIdle, DOMContentLoaded и т.п.) — полезно для более точного
  ## waitForNavigation, чем просто loadEventFired.
  discard await call(session, "Page.setLifecycleEventsEnabled", %*{"enabled": enabled})

proc setBypassCSP*(session: CDPSession, enabled = true) {.async.} =
  ## Отключает Content-Security-Policy страницы — нужно, например,
  ## чтобы addScriptTag() мог инжектить произвольные скрипты на сайтах
  ## со строгим CSP.
  discard await call(session, "Page.setBypassCSP", %*{"enabled": enabled})

proc addScriptToEvaluateOnNewDocument*(session: CDPSession, source: string,
                                        worldName = ""): Future[string] {.async.} =
  ## Скрипт будет выполняться при создании *каждого* нового документа
  ## этой вкладки (до того, как выполнится любой другой JS страницы) —
  ## основа page.evaluateOnNewDocument() в Puppeteer. Возвращает
  ## identifier для последующего removeScriptToEvaluateOnNewDocument.
  var params = %*{"source": source}
  if len(worldName) > 0:
    params["worldName"] = %worldName
  let res = await call(session, "Page.addScriptToEvaluateOnNewDocument", params)
  result = getStr(res["identifier"])

proc removeScriptToEvaluateOnNewDocument*(session: CDPSession, identifier: string) {.async.} =
  ## Отменяет скрипт, добавленный addScriptToEvaluateOnNewDocument(), по
  ## его identifier — на уже загруженные документы не влияет, только на
  ## следующие навигации.
  discard await call(session, "Page.removeScriptToEvaluateOnNewDocument", %*{"identifier": identifier})

proc createIsolatedWorld*(session: CDPSession, frameId: string, worldName = "",
                           grantUniversalAccess = false): Future[int] {.async.} =
  ## Возвращает executionContextId изолированного JS-контекста для
  ## указанного фрейма — контекст не виден скриптам самой страницы
  ## (полезно для расширений/инструментов автоматизации, которым не
  ## стоит "светиться" в window).
  let res = await call(session, "Page.createIsolatedWorld", %*{
    "frameId": frameId,
    "worldName": worldName,
    "grantUniversalAccess": grantUniversalAccess,
  })
  result = getInt(res["executionContextId"])

proc handleJavaScriptDialog*(session: CDPSession, accept: bool, promptText = "") {.async.} =
  ## Отвечает на alert()/confirm()/prompt()/beforeunload, приостановивший
  ## страницу — см. событие "Page.javascriptDialogOpening".
  var params = %*{"accept": accept}
  if len(promptText) > 0:
    params["promptText"] = %promptText
  discard await call(session, "Page.handleJavaScriptDialog", params)

proc setInterceptFileChooserDialog*(session: CDPSession, enabled = true) {.async.} =
  ## После включения системный диалог выбора файла не открывается —
  ## вместо этого приходит событие "Page.fileChooserOpened" с backendNodeId
  ## инпута, которому затем нужно назначить файлы через DOM.setFileInputFiles.
  discard await call(session, "Page.setInterceptFileChooserDialog", %*{"enabled": enabled})

proc setDownloadBehavior*(session: CDPSession, behavior: string, downloadPath = "") {.async.} =
  ## behavior: "deny" | "allow" | "default". Указывать downloadPath
  ## нужно только при behavior == "allow".
  var params = %*{"behavior": behavior}
  if len(downloadPath) > 0:
    params["downloadPath"] = %downloadPath
  discard await call(session, "Page.setDownloadBehavior", params)

proc getLayoutMetrics*(session: CDPSession): Future[JsonNode] {.async.} =
  ## {"layoutViewport", "visualViewport", "contentSize", "cssContentSize"} —
  ## реальные размеры страницы, полезно для screenshot(fullPage=true).
  result = await call(session, "Page.getLayoutMetrics")

proc captureScreenshot*(session: CDPSession, format = "png", quality = 100,
                         clip: JsonNode = nil, captureBeyondViewport = false,
                         fromSurface = true): Future[string] {.async.} =
  ## Возвращает содержимое скриншота, закодированное в base64
  ## (как оно приходит от браузера, без декодирования).
  ## clip — необязательный {"x","y","width","height","scale"} для
  ## обрезки конкретной области (см. childtear.screenshot(fullPage=true)).
  var params = %*{"format": format, "fromSurface": fromSurface, "captureBeyondViewport": captureBeyondViewport}
  if format == "jpeg":
    params["quality"] = %quality
  if clip != nil:
    params["clip"] = clip
  let res = await call(session, "Page.captureScreenshot", params)
  result = getStr(res["data"])

proc printToPDF*(session: CDPSession, landscape = false, printBackground = true,
                  paperWidth = 8.5, paperHeight = 11.0, marginTop = 0.4,
                  marginBottom = 0.4, marginLeft = 0.4, marginRight = 0.4,
                  pageRanges = ""): Future[string] {.async.} =
  ## Возвращает PDF страницы в base64. Размеры бумаги и поля — в дюймах,
  ## как того требует сам протокол.
  var params = %*{
    "landscape": landscape,
    "printBackground": printBackground,
    "paperWidth": paperWidth,
    "paperHeight": paperHeight,
    "marginTop": marginTop,
    "marginBottom": marginBottom,
    "marginLeft": marginLeft,
    "marginRight": marginRight,
  }
  if len(pageRanges) > 0:
    params["pageRanges"] = %pageRanges
  let res = await call(session, "Page.printToPDF", params)
  result = getStr(res["data"])
