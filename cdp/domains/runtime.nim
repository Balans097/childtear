## cdp/domains/runtime.nim
##
## Обёртка над доменом Runtime:
## https://chromedevtools.github.io/devtools-protocol/tot/Runtime/
##
## Исполнение JavaScript на странице — запасной путь, когда для задачи нет
## отдельной команды (например, чтение document.title).

import std/[asyncdispatch, json]
import ../transport

proc enable*(session: CDPSession) {.async.} =
  ## Включает домен Runtime — обязательно перед evaluate() и подпиской
  ## на "Runtime.consoleAPICalled"/"Runtime.exceptionThrown"/
  ## "Runtime.executionContextCreated" и т.п.
  discard await call(session, "Runtime.enable")

proc disable*(session: CDPSession) {.async.} =
  ## Отключает домен Runtime.
  discard await call(session, "Runtime.disable")

proc evaluate*(session: CDPSession, expression: string, awaitPromise = false,
                returnByValue = true, contextId = 0): Future[JsonNode] {.async.} =
  ## Исполняет JS-выражение в контексте страницы и возвращает
  ## Runtime.RemoteObject (result); при ошибке в самом выражении в ответе
  ## есть "exceptionDetails". contextId выбирает execution context: 0 —
  ## основной контекст главного фрейма, иной id — контекст конкретного
  ## iframe (Page.createIsolatedWorld в page.nim, см. Frame.evalJS()).
  let params = %*{
    "expression": expression,
    "returnByValue": returnByValue,
    "awaitPromise": awaitPromise,
  }
  if contextId != 0:
    params["contextId"] = %contextId
  result = await call(session, "Runtime.evaluate", params)

proc evaluateValue*(session: CDPSession, expression: string, awaitPromise = false,
                     contextId = 0): Future[JsonNode] {.async.} =
  ## Удобный вариант evaluate(), сразу возвращающий JSON-значение
  ## результата (result.value), а не весь конверт RemoteObject.
  ## contextId — см. evaluate().
  let res = await evaluate(session, expression, awaitPromise = awaitPromise, contextId = contextId)
  if hasKey(res, "exceptionDetails"):
    raise newException(ValueError, "JS-исключение: " & $res["exceptionDetails"])
  let remote = res["result"]
  # getOrDefault(remote, "value") без ключа "value" возвращает nil-ссылку, а
  # не JsonNode с kind == JNull. CDP не кладёт "value" ни для JS null, ни
  # для undefined (например, el.value у contenteditable-div). Проверка
  # ".kind == JNull" на nil-ссылке даёт SIGSEGV вместо ловимой ошибки,
  # поэтому nil и JNull различаются явно.
  let raw = getOrDefault(remote, "value")
  result = if raw.isNil: newJNull() else: raw

proc callFunctionOn*(session: CDPSession, objectId: string, functionDeclaration: string,
                      arguments: seq[JsonNode] = @[], awaitPromise = false): Future[JsonNode] {.async.} =
  ## Вызывает функцию в контексте конкретного объекта (например,
  ## DOM-узла, полученного через DOM.resolveNode) — используется для
  ## click()/focus()/value= и т.п. без глобального querySelector.
  var argsNode = newJArray()
  for a in arguments:
    add(argsNode, %*{"value": a})
  let params = %*{
    "objectId": objectId,
    "functionDeclaration": functionDeclaration,
    "arguments": argsNode,
    "returnByValue": true,
    "awaitPromise": awaitPromise,
  }
  result = await call(session, "Runtime.callFunctionOn", params)

proc getProperties*(session: CDPSession, objectId: string, ownProperties = true): Future[JsonNode] {.async.} =
  ## Список свойств объекта (аналог Object.getOwnPropertyNames + доступ
  ## к значениям) — используется, когда нужно инспектировать
  ## произвольный RemoteObject, не сериализуя его целиком в JSON.
  result = await call(session, "Runtime.getProperties", %*{
    "objectId": objectId,
    "ownProperties": ownProperties,
  })

proc releaseObject*(session: CDPSession, objectId: string) {.async.} =
  ## Освобождает RemoteObject на стороне браузера. RemoteObject'ы,
  ## полученные без returnByValue (например, из resolveNode), держат
  ## ссылку на живой JS-объект, пока их явно не отпустить — на
  ## долгоживущей сессии с большим числом evaluate() их стоит убирать.
  discard await call(session, "Runtime.releaseObject", %*{"objectId": objectId})

proc releaseObjectGroup*(session: CDPSession, objectGroup: string) {.async.} =
  ## Как releaseObject(), но разом для всех объектов, полученных с
  ## общим "objectGroup" (см. параметр objectGroup у Runtime.evaluate —
  ## здесь не обёрнутый, так как childtear.nim им не пользуется).
  discard await call(session, "Runtime.releaseObjectGroup", %*{"objectGroup": objectGroup})

proc discardConsoleEntries*(session: CDPSession) {.async.} =
  ## Очищает буфер уже накопленных сообщений консоли на стороне
  ## браузера (аналог кнопки "Clear console" в DevTools).
  discard await call(session, "Runtime.discardConsoleEntries")

proc awaitPromise*(session: CDPSession, promiseObjectId: string, returnByValue = true): Future[JsonNode] {.async.} =
  ## Дожидается разрешения промиса (RemoteObject которого уже получен,
  ## например, через evaluate(expr, awaitPromise=false)) и возвращает
  ## его итоговое значение.
  result = await call(session, "Runtime.awaitPromise", %*{
    "promiseObjectId": promiseObjectId,
    "returnByValue": returnByValue,
  })

proc addBinding*(session: CDPSession, name: string, executionContextName = ""): Future[void] {.async.} =
  ## Добавляет глобальную функцию `name` в window каждого контекста —
  ## её вызов из JS страницы приходит сюда событием
  ## "Runtime.bindingCalled". Это низкоуровневая основа для
  ## Tab.exposeFunction() в childtear.nim (аналог page.exposeFunction()
  ## в Puppeteer).
  var params = %*{"name": name}
  if len(executionContextName) > 0:
    params["executionContextName"] = %executionContextName
  discard await call(session, "Runtime.addBinding", params)

proc removeBinding*(session: CDPSession, name: string) {.async.} =
  ## Убирает функцию, добавленную addBinding() — сам JS-шим в window
  ## (если он уже был инжектирован в childtear.exposeFunction()) при
  ## этом не удаляется, только низкоуровневый мост перестаёт работать.
  discard await call(session, "Runtime.removeBinding", %*{"name": name})
