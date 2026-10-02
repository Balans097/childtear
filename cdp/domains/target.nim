## cdp/domains/target.nim
##
## Обёртка над доменом Target:
## https://chromedevtools.github.io/devtools-protocol/tot/Target/
##
## В отличие от остальных domains/*.nim, эти команды имеет смысл слать
## не в сессию конкретной вкладки, а в *browser-level* сессию —
## WebSocket, полученный из "webSocketDebuggerUrl" ответа /json/version
## (см. cdp/browser.nim -> browserVersion()). Домен Target нужен, когда
## недостаточно HTTP /json/new|list|close — например, чтобы получать
## уведомления о новых вкладках, открытых пользователем/страницей
## (targetCreated), или работать в "flattened" режиме с sessionId.

import std/[asyncdispatch, json]
import ../transport

proc getTargets*(session: CDPSession): Future[seq[JsonNode]] {.async.} =
  ## Список всех целей (вкладок, воркеров и т.д.), видимых браузеру —
  ## аналог HTTP /json/list, но по протоколу.
  let res = await call(session, "Target.getTargets")
  result = getElems(res["targetInfos"])

proc getTargetInfo*(session: CDPSession, targetId = ""): Future[JsonNode] {.async.} =
  ## Без targetId возвращает информацию о цели, к которой относится
  ## сама сессия (актуально при вызове на attached-сессии).
  var params = newJObject()
  if len(targetId) > 0:
    params["targetId"] = %targetId
  let res = await call(session, "Target.getTargetInfo", params)
  result = res["targetInfo"]

proc setDiscoverTargets*(session: CDPSession, discover = true) {.async.} =
  ## Включает уведомления Target.targetCreated/targetInfoChanged/targetDestroyed
  ## обо всех целях браузера, даже тех, к которым мы не присоединены.
  discard await call(session, "Target.setDiscoverTargets", %*{"discover": discover})

proc activateTarget*(session: CDPSession, targetId: string) {.async.} =
  ## Делает вкладку активной на экране (аналог Page.bringToFront,
  ## но вызывается с browser-level сессии по targetId, без attach).
  discard await call(session, "Target.activateTarget", %*{"targetId": targetId})

proc createTarget*(session: CDPSession, url: string, width = 0, height = 0,
                    browserContextId = "", newWindow = false, background = false): Future[string] {.async.} =
  ## Создаёт новую вкладку и возвращает её targetId. browserContextId
  ## позволяет открыть вкладку в изолированном (инкогнито-подобном)
  ## профиле, созданном через createBrowserContext().
  var params = %*{"url": url}
  if width > 0:
    params["width"] = %width
  if height > 0:
    params["height"] = %height
  if len(browserContextId) > 0:
    params["browserContextId"] = %browserContextId
  if newWindow:
    params["newWindow"] = %true
  if background:
    params["background"] = %true
  let res = await call(session, "Target.createTarget", params)
  result = getStr(res["targetId"])

proc closeTarget*(session: CDPSession, targetId: string) {.async.} =
  ## Закрывает вкладку/цель по её id — протокольный аналог HTTP
  ## /json/close/<id> (см. cdp/browser.nim -> closeTarget()); childtear.nim
  ## по умолчанию использует именно HTTP-вариант (см. заголовок модуля),
  ## этот остаётся для тех, кто явно работает через домен Target.
  discard await call(session, "Target.closeTarget", %*{"targetId": targetId})

proc createBrowserContext*(session: CDPSession): Future[string] {.async.} =
  ## Создаёт изолированный профиль (свои куки/localStorage/кэш,
  ## отдельно от основного и других контекстов) — аналог
  ## browser.createIncognitoBrowserContext() в Puppeteer. Возвращает
  ## browserContextId для передачи в createTarget().
  let res = await call(session, "Target.createBrowserContext")
  result = getStr(res["browserContextId"])

proc getBrowserContexts*(session: CDPSession): Future[seq[string]] {.async.} =
  ## Список id всех изолированных профилей (см. createBrowserContext()),
  ## созданных за время жизни браузера и ещё не уничтоженных.
  let res = await call(session, "Target.getBrowserContexts")
  result = @[]
  for c in getElems(res["browserContextIds"]):
    add(result, getStr(c))

proc disposeBrowserContext*(session: CDPSession, browserContextId: string) {.async.} =
  ## Уничтожает профиль и закрывает все его вкладки.
  discard await call(session, "Target.disposeBrowserContext", %*{"browserContextId": browserContextId})

proc attachToTarget*(session: CDPSession, targetId: string, flatten = true): Future[string] {.async.} =
  ## Присоединяется к цели и возвращает sessionId — в "плоском" (flatten)
  ## режиме этот sessionId нужно прикладывать к каждой последующей
  ## команде (см. callWithSession ниже), что позволяет мультиплексировать
  ## несколько вкладок через одно browser-level WebSocket-соединение.
  let res = await call(session, "Target.attachToTarget", %*{"targetId": targetId, "flatten": flatten})
  result = getStr(res["sessionId"])

proc detachFromTarget*(session: CDPSession, sessionId: string) {.async.} =
  ## Отсоединяется от цели, к которой ранее присоединились через
  ## attachToTarget() — сама вкладка при этом не закрывается, только
  ## прекращается мультиплексирование её команд/событий через sessionId.
  discard await call(session, "Target.detachFromTarget", %*{"sessionId": sessionId})

proc setAutoAttach*(session: CDPSession, autoAttach = true, waitForDebuggerOnStart = false) {.async.} =
  ## Подписывает на автоматическое присоединение ко всем новым целям —
  ## удобно, чтобы ловить всплывающие окна (window.open, target=_blank).
  discard await call(session, "Target.setAutoAttach", %*{
    "autoAttach": autoAttach,
    "waitForDebuggerOnStart": waitForDebuggerOnStart,
    "flatten": true,
  })

proc callWithSession*(session: CDPSession, sessionId: string, meth: string,
                       params: JsonNode = newJObject()): Future[JsonNode] {.async.} =
  ## Отправляет команду конкретной присоединённой (attachToTarget)
  ## вкладке через общее browser-level соединение, в "плоском" режиме
  ## (см. https://chromedevtools.github.io/devtools-protocol/#flattened).
  ## Домены page/dom/runtime/... рассчитаны на отдельный WebSocket на
  ## вкладку, поэтому это — самостоятельный низкоуровневый примитив
  ## для тех, кто явно выбирает мультиплексирование одним соединением.
  result = await call(session, meth, params, sessionId)
