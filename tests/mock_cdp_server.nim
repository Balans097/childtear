## tests/mock_cdp_server.nim
##
## Игрушечный сервер, эмулирующий WebSocket-эндпоинт Chromium DevTools
## ровно настолько, чтобы прогнать через него wsclient.nim и
## transport.nim: HTTP Upgrade handshake + приём/отправка маскированных
## фреймов + простейшая логика "id -> result" и одно тестовое событие.
## Реальный протокол CDP здесь не эмулируется — только транспорт.

import std/[asyncdispatch, asyncnet, json, strutils, base64]
import checksums/sha1

const magicGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

proc acceptKeyFor*(clientKey: string): string =
  ## Считает Sec-WebSocket-Accept по RFC 6455: SHA1(clientKey & magicGuid)
  ## в base64 — сервер должен вернуть его в ответ на handshake-запрос.
  let digest = secureHash(clientKey & magicGuid)
  base64.encode(parseHexStr($digest))

proc sendServerFrame*(client: AsyncSocket, opcode: int, payload: string) {.async.} =
  ## Серверные фреймы, в отличие от клиентских, не маскируются (RFC 6455).
  var header: seq[byte] = @[byte(0x80 or opcode)]
  let length = len(payload)
  if length <= 125:
    add(header, byte(length))
  elif length <= 0xFFFF:
    add(header, byte(126))
    add(header, byte((length shr 8) and 0xFF))
    add(header, byte(length and 0xFF))
  else:
    add(header, byte(127))
    for shift in countdown(56, 0, 8):
      add(header, byte((length.int64 shr shift) and 0xFF))
  var headerStr = newString(len(header))
  for i, b in header:
    headerStr[i] = char(b)
  await send(client, headerStr & payload)

proc sendRawFrame*(client: AsyncSocket, firstByte: int, payload: string) {.async.} =
  ## Серверный фрейм с произвольным первым байтом (FIN + opcode) и
  ## payload до 125 байт: нужен, чтобы отправлять фрагментированные
  ## сообщения (FIN = 0 и opcode 0x0 у продолжения).
  doAssert len(payload) <= 125
  await send(client, $char(firstByte) & $char(len(payload)) & payload)

proc recvExact(sock: AsyncSocket, n: int): Future[string] {.async.} =
  ## Читает из sock ровно n байт, накапливая их из нескольких recv()
  ## при необходимости; исключение, если соединение закрылось раньше.
  result = ""
  while len(result) < n:
    let chunk = await recv(sock, n - len(result))
    if len(chunk) == 0:
      raise newException(IOError, "peer closed")
    add(result, chunk)

proc recvClientFrame(client: AsyncSocket): Future[string] {.async.} =
  ## Принимает один клиентский WebSocket-фрейм и возвращает его
  ## демаскированный payload. Клиентские фреймы по RFC 6455 всегда
  ## маскированы 4-байтовым ключом — сервер обязан снять маску.
  let
    head = await recvExact(client, 2)
    b1 = byte(head[1])
  var length = int(b1 and 0x7F)
  if length == 126:
    let ext = await recvExact(client, 2)
    length = (int(byte(ext[0])) shl 8) or int(byte(ext[1]))
  var maskKey: array[4, byte]
  let m = await recvExact(client, 4)
  for i in 0 ..< 4:
    maskKey[i] = byte(m[i])
  var payload = await recvExact(client, length)
  for i in 0 ..< len(payload):
    payload[i] = char(byte(payload[i]) xor maskKey[i mod 4])
  result = payload

proc handleClient(client: AsyncSocket) {.async.} =
  ## Обслуживает одно клиентское соединение целиком: проводит HTTP
  ## Upgrade-рукопожатие, затем в цикле отвечает на CDP-команды —
  ## Page.navigate обрабатывается предметно (см. ниже), остальные
  ## методы просто эхо-отражаются обратно вызывающему.
  # --- HTTP Upgrade handshake ---
  var clientKey = ""
  # См. подробный комментарий в cdp/wsclient.nim: recvLine() отдаёт
  # пустую строку-разделитель заголовков как буквальное "\r\n", а не
  # как "", поэтому проверка `len(line) > 0` без нормализации никогда
  # не срабатывает и цикл виснет навсегда.
  proc readHeaderLine(): Future[string] {.async.} =
    let raw = await recvLine(client)
    result = strip(raw, leading = false, trailing = true, chars = {'\r', '\L'})

  var line = await readHeaderLine()
  while len(line) > 0:
    if startsWith(toLowerAscii(line), "sec-websocket-key:"):
      clientKey = strip(split(line, ':', 1)[1])
    line = await readHeaderLine()

  let
    accept = acceptKeyFor(clientKey)
    response = "HTTP/1.1 101 Switching Protocols\r\n" &
               "Upgrade: websocket\r\n" &
               "Connection: Upgrade\r\n" &
               "Sec-WebSocket-Accept: " & accept & "\r\n\r\n"
  await send(client, response)

  # --- Простейшая протокольная логика для теста ---
  while true:
    let raw = await recvClientFrame(client)
    if len(raw) == 0:
      break # клиент закрыл соединение (пустой close-фрейм)
    let
      msg = parseJson(raw)
      id = getInt(msg["id"])
      meth = getStr(msg["method"])

    # Сценарии, включаемые именем метода. Всё, что здесь не перечислено,
    # эхо-отражается обратно вызывающему.
    case meth
    of "Page.navigate":
      # Сначала отвечаем на саму команду...
      let resultEnvelope = %*{"id": id, "result": {"frameId": "F1"}}
      await sendServerFrame(client, 0x1, $resultEnvelope)
      # ...затем шлём событие, как это делает настоящий Chromium.
      let event = %*{"method": "Page.loadEventFired", "params": {"timestamp": 123.45}}
      await sendServerFrame(client, 0x1, $event)
    of "Test.fragmented":
      # Ответ, разрезанный на два фрейма: text (FIN = 0) + continuation.
      let full = $(%*{"id": id, "result": {"echo": meth}})
      let cut = len(full) div 2
      await sendRawFrame(client, 0x01, full[0 ..< cut])
      await sendRawFrame(client, 0x80, full[cut .. ^1])
    of "Test.pingFirst":
      # Ping от сервера перед ответом: клиент обязан его пропустить.
      await sendServerFrame(client, 0x9, "keepalive")
      await sendServerFrame(client, 0x1, $(%*{"id": id, "result": {"echo": meth}}))
    of "Test.hugeFrame":
      # Заголовок с заведомо недопустимой длиной (2^62) и без payload.
      await send(client, "\x81\x7f\x40\x00\x00\x00\x00\x00\x00\x00")
    of "Test.closeFrame":
      await sendServerFrame(client, 0x8, "")
    of "Test.drop":
      # Обрыв соединения без ответа на команду.
      close(client)
      return
    else:
      let resultEnvelope = %*{"id": id, "result": {"echo": meth}}
      await sendServerFrame(client, 0x1, $resultEnvelope)

proc serve*(port: int) {.async.} =
  ## Запускает мок-сервер на localhost:port и бесконечно принимает
  ## подключения, обрабатывая каждое в отдельной асинхронной задаче.
  var server = newAsyncSocket()
  setSockOpt(server, OptReuseAddr, true)
  bindAddr(server, Port(port))
  listen(server)
  while true:
    let client = await accept(server)
    proc runClient(c: AsyncSocket) {.async.} =
      ## Обрыв соединения клиентом — штатная ситуация для тестов, поэтому
      ## ошибки чтения/записи не должны ронять сервер.
      try:
        await handleClient(c)
      except CatchableError:
        discard
      try:
        close(c)
      except CatchableError:
        discard
    asyncCheck runClient(client)
