## cdp/transport.nim
##
## Транспортный уровень CDP: превращает WebSocket в сессию, которая (1)
## отправляет команды и сопоставляет ответы по числовому id и (2) рассылает
## входящие события ("Page.loadEventFired" и т.п.) подписчикам. Только здесь
## известен JSON-конверт протокола ({"id", "method", "params", "result",
## "error"}); модули cdp/domains/*.nim работают в терминах методов.


import std/[asyncdispatch, json, tables, sequtils]
import ./wsclient


type
  CDPError* = object of CatchableError
    ## Поднимается, когда браузер вернул {"error": ...} на команду.

  EventHandler* = proc(params: JsonNode) {.gcsafe.}

  HandlerEntry = tuple[id: int, handler: EventHandler]
    ## id нужен только для точечного удаления конкретного обработчика
    ## (см. removeHandler) — постоянные подписки on()/onSession() его
    ## игнорируют и живут, пока жива сама сессия.

  CDPSession* = ref object
    ws: WebSocket
    nextId: int
    nextHandlerId: int
    pending: Table[int, Future[JsonNode]]
    handlers: Table[(string, string), seq[HandlerEntry]]
      ## Ключ — (sessionId, method). sessionId == "" — обычная сессия
      ## (один WebSocket на вкладку) или browser-level соединение. Непустой
      ## sessionId нужен, когда несколько вкладок мультиплексируются через
      ## одно browser-level соединение (Target.attachToTarget в
      ## cdp/domains/target.nim): события вкладки приходят с полем
      ## "sessionId" и не должны смешиваться с событиями других.
    listener: Future[void]
    dead: bool
      ## true после завершения listenLoop(): новые команды уже никто не
      ## сможет разрешить, поэтому call() сразу падает с CDPError.

# -----------------------------------------------------------------
# Внутренняя работа с таблицей обработчиков
# -----------------------------------------------------------------

proc addHandler(session: CDPSession, key: (string, string), handler: EventHandler): int =
  ## Регистрирует обработчик под ключом (sessionId, method) и
  ## возвращает его id — постоянным подпискам (on/onSession) он не
  ## нужен, а waitForEvent() использует его, чтобы снять себя из
  ## таблицы сразу после однократного срабатывания или таймаута.
  result = session.nextHandlerId
  inc session.nextHandlerId
  if not hasKey(session.handlers, key):
    session.handlers[key] = @[]
  add(session.handlers[key], (id: result, handler: handler))

proc removeHandler(session: CDPSession, key: (string, string), id: int) =
  ## Снимает конкретный обработчик по id. Без этого одноразовые
  ## подписки waitForEvent() копились бы в таблице до конца жизни
  ## сессии — на сессии с частыми повторными ожиданиями (например,
  ## в цикле навигаций) это была бы медленная, но настоящая утечка
  ## памяти: каждый вызов waitForEvent() навсегда держал бы в таблице
  ## закрытие вместе со своим Future, даже давно завершённым.
  if hasKey(session.handlers, key):
    keepIf(session.handlers[key], proc(e: HandlerEntry): bool = e.id != id)
    if len(session.handlers[key]) == 0:
      del(session.handlers, key)

# -----------------------------------------------------------------
# Фоновый цикл чтения сообщений
# -----------------------------------------------------------------

proc dispatchEvent(session: CDPSession, sessionId, meth: string, params: JsonNode) =
  ## Рассылает params всем обработчикам под ключом (sessionId, meth).
  ## Вызывается из listenLoop() на каждое событие (сообщение с полем
  ## "method"; у ответов на команды вместо него поле "id").
  ## Итерация идёт по копии списка: обработчик вправе вызвать on() или
  ## снять подписку. Исключение в одном обработчике не должно обрывать
  ## сессию и остальных подписчиков, поэтому оно гасится.
  let key = (sessionId, meth)
  if not hasKey(session.handlers, key):
    return
  let entries = session.handlers[key]
  for entry in entries:
    try:
      entry.handler(params)
    except CatchableError:
      discard

proc failAllPending(session: CDPSession, reason: string) =
  ## Завершает ошибкой все ещё не разрешённые call(), чтобы вызывающие
  ## не ждали вечно, если соединение закрыто нами или оборвано
  ## удалённой стороной. После вызова сессия считается мёртвой.
  session.dead = true
  for id, fut in session.pending:
    if not finished(fut):
      fail(fut, newException(CDPError, reason))
  clear(session.pending)

proc listenLoop(session: CDPSession) {.async.} =
  ## Фоновый цикл (asyncCheck) на всё время жизни сессии: ответы на
  ## команды уходят в Future из `pending`, события — подписчикам.
  ## Исключения чтения гасятся: необработанное исключение из future,
  ## запущенной через asyncCheck, роняет процесс, а закрытие соединения
  ## (close() или обрыв) — штатная ситуация. В finally все ожидающие
  ## команды завершаются ошибкой.
  try:
    while not session.ws.closed:
      let raw = await receiveMessage(session.ws)
      if len(raw) == 0:
        break # соединение закрыто
      let msg = parseJson(raw)

      if hasKey(msg, "id"):
        let id = getInt(msg["id"])
        if hasKey(session.pending, id):
          let fut = session.pending[id]
          del(session.pending, id)
          if hasKey(msg, "error"):
            fail(fut, newException(CDPError, $msg["error"]))
          else:
            complete(fut, getOrDefault(msg, "result"))
      elif hasKey(msg, "method"):
        let sid = getStr(getOrDefault(msg, "sessionId"), "")
        dispatchEvent(session, sid, getStr(msg["method"]), getOrDefault(msg, "params"))
  except CatchableError:
    discard # соединение оборвалось — ниже все ожидающие запросы будут провалены
  finally:
    failAllPending(session, "CDP-соединение закрыто")

# -----------------------------------------------------------------
# Публичный API сессии
# -----------------------------------------------------------------

proc newCDPSession*(wsUrl: string): Future[CDPSession] {.async.} =
  ## Открывает WebSocket к конкретной вкладке (webSocketDebuggerUrl,
  ## полученный через HTTP /json/new или /json/list) и запускает
  ## фоновый цикл чтения.
  let ws = await newWebSocket(wsUrl)
  result = CDPSession(
    ws: ws,
    nextId: 1,
    nextHandlerId: 1,
    pending: initTable[int, Future[JsonNode]](),
    handlers: initTable[(string, string), seq[HandlerEntry]](),
  )
  result.listener = listenLoop(result)
  asyncCheck(result.listener)

proc call*(session: CDPSession, meth: string, params: JsonNode = newJObject(),
           sessionId = ""): Future[JsonNode] {.async.} =
  ## Отправляет команду CDP (например "Page.navigate") и ждёт ответа с тем
  ## же id. Основной примитив, на котором построены обёртки
  ## cdp/domains/*.nim. sessionId нужен только в flatten-режиме
  ## мультиплексирования вкладок через browser-level соединение
  ## (Target.attachToTarget); при "один WebSocket на вкладку" не передаётся.
  if session.dead:
    raise newException(CDPError, "CDP-соединение закрыто")

  let id = session.nextId
  inc session.nextId

  var envelope = %*{
    "id": id,
    "method": meth,
    "params": params,
  }
  if len(sessionId) > 0:
    envelope["sessionId"] = %sessionId

  var fut = newFuture[JsonNode]("CDPSession.call")
  session.pending[id] = fut
  try:
    await send(session.ws, $envelope)
  except CatchableError:
    # Команда не ушла: ответа не будет, запись в pending не должна висеть.
    del(session.pending, id)
    raise
  result = await fut

proc isAlive*(session: CDPSession): bool =
  ## true, пока соединение открыто и фоновый цикл чтения работает.
  result = not session.dead and not session.ws.closed

proc on*(session: CDPSession, event: string, handler: EventHandler) =
  ## Регистрирует обработчик события основной ("корневой") сессии,
  ## например: session.on("Page.loadEventFired", proc (p: JsonNode) = ...).
  ## Подписка постоянна — живёт, пока жива сессия. Для событий вкладки,
  ## присоединённой через Target.attachToTarget в flatten-режиме,
  ## используйте onSession() — иначе события чужих вкладок на том же
  ## browser-level соединении будут неотличимы друг от друга.
  discard addHandler(session, ("", event), handler)

proc onSession*(session: CDPSession, sessionId, event: string, handler: EventHandler) =
  ## Как on(), но только для событий конкретной присоединённой вкладки
  ## (sessionId, полученный из Target.attachToTarget) — нужно при
  ## мультиплексировании нескольких вкладок через одно browser-level
  ## соединение.
  discard addHandler(session, (sessionId, event), handler)

proc waitForEvent*(session: CDPSession, event: string, timeoutMs = 30_000,
                    sessionId = ""): Future[JsonNode] {.async.} =
  ## Однократно ждёт событие (например "Page.loadEventFired") с таймаутом.
  ## sessionId — для события конкретной вкладки в flatten-режиме (см.
  ## onSession). В отличие от on()/onSession(), обработчик снимается всегда
  ## (и при срабатывании, и по таймауту), чтобы повторные ожидания не
  ## копились в таблице подписчиков.
  if session.dead:
    raise newException(CDPError, "CDP-соединение закрыто")
  var fut = newFuture[JsonNode]("CDPSession.waitForEvent")

  proc handler(params: JsonNode) {.gcsafe.} =
    if not finished(fut):
      complete(fut, params)

  let
    key = (sessionId, event)
    handlerId = addHandler(session, key, handler)
  try:
    if await withTimeout(fut, timeoutMs):
      result = read(fut)
    else:
      raise newException(CDPError, "таймаут ожидания события " & event)
  finally:
    removeHandler(session, key, handlerId)

proc close*(session: CDPSession) {.async.} =
  ## Закрывает WebSocket и дожидается штатного завершения фонового
  ## listenLoop, чтобы после return из close() в системе не оставалось
  ## "подвешенных" detached-futures с этим соединением.
  await close(session.ws)
  try:
    await session.listener
  except CatchableError:
    discard
