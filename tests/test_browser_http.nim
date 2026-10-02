## tests/test_browser_http.nim
##
## Проверяет cdp/browser.nim на локальном HTTP-сервере, имитирующем
## DevTools: «действующие» эндпоинты (/json/new, /json/close,
## /json/activate) принимают только PUT, ошибки сервера (не 2xx)
## превращаются в исключение, URL кодируется как %20, а не '+'.

import std/[asyncdispatch, asynchttpserver, json, strutils]
import ../cdp/browser

const testPort = 9336

var requests: seq[string] = @[]
  ## Журнал запросов сервера в виде "МЕТОД путь?запрос" — по нему тест
  ## проверяет, какой метод и какое кодирование использовал клиент.

proc handler(req: Request) {.async, gcsafe.} =
  ## Имитация DevTools: PUT на /json/new|close|activate, GET на
  ## /json/list и /json/version; на GET к «действующим» — 405.
  {.cast(gcsafe).}:
    add(requests, $req.reqMethod & " " & req.url.path &
                  (if len(req.url.query) > 0: "?" & req.url.query else: ""))
    let path = req.url.path
    let isPut = req.reqMethod == HttpPut
    if startsWith(path, "/json/new"):
      if not isPut:
        await respond(req, Http405, "Method Not Allowed")
      else:
        await respond(req, Http200, $(%*{"id": "NEW1",
          "webSocketDebuggerUrl": "ws://127.0.0.1:1/devtools/page/NEW1"}))
    elif startsWith(path, "/json/close/"):
      if not isPut:
        await respond(req, Http405, "Method Not Allowed")
      elif endsWith(path, "/MISSING"):
        await respond(req, Http404, "No such target id")
      else:
        await respond(req, Http200, "Target is closing")
    elif startsWith(path, "/json/activate/"):
      await respond(req, Http200, "Target activated")
    elif path == "/json/list":
      await respond(req, Http200, $(%*[{"id": "A"}, {"id": "B"}]))
    elif path == "/json/version":
      await respond(req, Http200, $(%*{"Browser": "TestChrome/1.0"}))
    else:
      await respond(req, Http404, "not found")

proc runTest() {.async.} =
  let server = newAsyncHttpServer()
  asyncCheck serve(server, Port(testPort), handler)
  await sleepAsync(200)
  let bc = newBrowserConnection("127.0.0.1", testPort)

  # 1. Чтение: GET /json/list и /json/version.
  let tabs = await listTargets(bc)
  doAssert len(tabs) == 2 and tabs[0]["id"].getStr() == "A"
  let ver = await browserVersion(bc)
  doAssert ver["Browser"].getStr() == "TestChrome/1.0"
  echo "OK: GET /json/list и /json/version"

  # 2. /json/new — только PUT, пробел в URL кодируется как %20.
  let info = await newTarget(bc, "http://example.com/a b")
  doAssert info["id"].getStr() == "NEW1"
  doAssert requests[^1].startsWith("PUT /json/new?") and
           "%20" in requests[^1] and '+' notin requests[^1],
    "неверный запрос: " & requests[^1]
  echo "OK: /json/new использует PUT и %20"

  # 3. close/activate используют PUT и принимают текстовый (не JSON) ответ.
  await closeTarget(bc, "NEW1")
  doAssert requests[^1] == "PUT /json/close/NEW1", requests[^1]
  await activateTarget(bc, "NEW1")
  doAssert requests[^1] == "PUT /json/activate/NEW1", requests[^1]
  echo "OK: /json/close и /json/activate"

  # 4. Ответ не 2xx превращается в исключение с телом ответа.
  var message = ""
  try:
    await closeTarget(bc, "MISSING")
  except CatchableError as e:
    message = e.msg
  doAssert "404" in message and "No such target id" in message,
    "ожидалась ошибка с кодом и телом ответа, получено: " & message
  echo "OK: ответ 404 превращён в исключение"

  echo "Все проверки HTTP-обвязки пройдены успешно."

waitFor runTest()
