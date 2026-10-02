## tests/test_wsclient.nim
##
## Проверяет cdp/wsclient.nim на mock_cdp_server: handshake, фрагментация
## сообщений, пропуск ping, защиту от недопустимой длины фрейма, реакцию
## на close-фрейм и отказ от неподдерживаемых схем URL.

import std/[asyncdispatch, json, strutils]
import ../cdp/wsclient
import ./mock_cdp_server

const testPort = 9334

proc roundTrip(ws: WebSocket, id: int, meth: string): Future[string] {.async.} =
  ## Отправляет команду {"id", "method"} и возвращает сырой текст
  ## следующего входящего сообщения.
  await send(ws, $(%*{"id": id, "method": meth}))
  result = await receiveMessage(ws)

proc connect(): Future[WebSocket] {.async.} =
  result = await newWebSocket("ws://127.0.0.1:" & $testPort & "/devtools/page/T")

proc runTest() {.async.} =
  asyncCheck serve(testPort)
  await sleepAsync(200) # время на начало прослушивания порта

  # 1. Handshake и простой обмен.
  block:
    let ws = await connect()
    let raw = await roundTrip(ws, 1, "Foo.bar")
    doAssert parseJson(raw)["result"]["echo"].getStr() == "Foo.bar", raw
    await close(ws)
    echo "OK: handshake и обмен сообщениями"

  # 2. Сообщение, разрезанное на text + continuation, собирается целиком.
  block:
    let ws = await connect()
    let raw = await roundTrip(ws, 2, "Test.fragmented")
    doAssert parseJson(raw)["result"]["echo"].getStr() == "Test.fragmented", raw
    await close(ws)
    echo "OK: фрагментированное сообщение собрано"

  # 3. Ping сервера пропускается, следующее сообщение приходит целым.
  block:
    let ws = await connect()
    let raw = await roundTrip(ws, 3, "Test.pingFirst")
    doAssert parseJson(raw)["result"]["echo"].getStr() == "Test.pingFirst", raw
    await close(ws)
    echo "OK: ping пропущен"

  # 4. Недопустимая длина фрейма отвергается, а не вызывает выделение памяти.
  block:
    let ws = await connect()
    var failed = false
    try:
      discard await roundTrip(ws, 4, "Test.hugeFrame")
    except WebSocketError:
      failed = true
    doAssert failed, "ожидался WebSocketError для длины фрейма 2^62"
    echo "OK: недопустимая длина фрейма отвергнута"

  # 5. Close-фрейм: пустая строка, соединение помечено закрытым.
  block:
    let ws = await connect()
    let raw = await roundTrip(ws, 5, "Test.closeFrame")
    doAssert raw == "", "после close ожидалась пустая строка, получено: " & raw
    doAssert ws.closed, "ws.closed должен быть true после close-фрейма"
    echo "OK: close-фрейм обработан"

  # 6. Неподдерживаемые схемы отвергаются до попытки подключения.
  for url in ["wss://127.0.0.1:1/x", "http://127.0.0.1:1/x"]:
    var failed = false
    try:
      discard await newWebSocket(url)
    except WebSocketError:
      failed = true
    doAssert failed, "схема должна быть отвергнута: " & url
  echo "OK: wss:// и http:// отвергнуты"

  echo "Все проверки WebSocket-клиента пройдены успешно."

waitFor runTest()
