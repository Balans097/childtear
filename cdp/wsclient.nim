## cdp/wsclient.nim
##
## Минимальный асинхронный WebSocket-клиент на стандартной библиотеке Nim
## (asyncnet, asyncdispatch, base64, uri) и checksums/sha1: CDP общается с
## браузером по WebSocket. Реализован минимум RFC 6455: клиентское
## рукопожатие (HTTP Upgrade), отправка маскированных текстовых фреймов,
## приём фрагментированных текстовых и управляющих фреймов (ping/close).



import std/[asyncdispatch, asyncnet, uri, strutils, strformat, base64, random]
import checksums/sha1



type
  WebSocketError* = object of CatchableError
    ## Поднимается при ошибках хендшейка или протокола.

  WebSocket* = ref object
    socket: AsyncSocket
    closed*: bool

# -----------------------------------------------------------------
# Вспомогательные процедуры
# -----------------------------------------------------------------

var rngSeeded = false
  ## См. ensureRngSeeded() ниже.

proc ensureRngSeeded() =
  ## std/random без randomize() стартует с фиксированным сидом. Маскирующий
  ## ключ фреймов (maskPayload()/sendFrame()) и nonce Sec-WebSocket-Key
  ## (randomWebSocketKey()) по RFC 6455 должны быть непредсказуемыми.
  ## Вызывается лениво из newWebSocket(), а не при импорте модуля, чтобы не
  ## засевать глобальный RNG программы без реального подключения.
  if not rngSeeded:
    randomize()
    rngSeeded = true

proc randomWebSocketKey(): string =
  ## Генерирует случайный 16-байтовый ключ и кодирует его в base64,
  ## как того требует заголовок Sec-WebSocket-Key.
  var raw = newString(16)
  for i in 0 ..< len(raw):
    raw[i] = char(rand(255))
  result = base64.encode(raw)

proc computeAcceptKey(key: string): string =
  ## Считает ожидаемое значение Sec-WebSocket-Accept согласно RFC 6455:
  ## base64(SHA1(key + magicGUID)).
  const magicGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  let digest = secureHash(key & magicGuid)
  result = base64.encode(parseHexStr($digest))

proc maskPayload(data: string, maskKey: array[4, byte]): string =
  ## Клиентские фреймы обязаны маскироваться (RFC 6455, п. 5.3).
  result = newString(len(data))
  for i in 0 ..< len(data):
    result[i] = char(byte(data[i]) xor maskKey[i mod 4])

# -----------------------------------------------------------------
# Установление соединения (HTTP Upgrade handshake)
# -----------------------------------------------------------------

proc newWebSocket*(url: string): Future[WebSocket] {.async.} =
  ## Подключается по адресу вида ws://host:port/path и выполняет
  ## handshake. Возвращает готовый к работе WebSocket.
  let parsed = parseUri(url)
  if parsed.scheme == "wss":
    raise newException(WebSocketError, "wss:// не поддерживается — CDP отдаёт незашифрованный ws://")
  if parsed.scheme != "ws":
    raise newException(WebSocketError, "поддерживается только схема ws:// (получено: " & url & ")")

  ensureRngSeeded()

  let
    port = if len(parsed.port) > 0: parseInt(parsed.port) else: 80
    path = if len(parsed.path) > 0: parsed.path else: "/"
    fullPath = if len(parsed.query) > 0: path & "?" & parsed.query else: path

  var sock = newAsyncSocket()
  await connect(sock, parsed.hostname, Port(port))

  let
    wsKey = randomWebSocketKey()
    request = &"""GET {fullPath} HTTP/1.1
Host: {parsed.hostname}:{port}
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: {wsKey}
Sec-WebSocket-Version: 13

"""
  await send(sock, replace(request, "\n", "\r\n"))

  # Читаем строку статуса и заголовки до пустой строки.
  var statusLine = await recvLine(sock)
  if not startsWith(statusLine, "HTTP/1.1 101"):
    raise newException(WebSocketError, "рукопожатие не удалось, ответ сервера: " & statusLine)

  var acceptValue = ""
  while true:
    # asyncnet.recvLine() возвращает пустую строку "" только когда сокет
    # закрылся; пустая строка-разделитель заголовков ("\r\n" в сыром
    # HTTP-ответе) приходит от неё как буквальное "\r\n", а не как "".
    # Поэтому конец заголовков определяем по line (после срезания
    # "\r\n"-хвоста), а закрытие сокета — отдельно, по rawLine.
    let
      rawLine = await recvLine(sock)
      line = strip(rawLine, leading = false, trailing = true, chars = {'\r', '\L'})
    if len(rawLine) == 0 or len(line) == 0:
      break
    let idx = find(line, ':')
    if idx >= 0:
      let
        name = toLowerAscii(strip(line[0 ..< idx]))
        value = strip(line[idx + 1 .. ^1])
      if name == "sec-websocket-accept":
        acceptValue = value

  if acceptValue != computeAcceptKey(wsKey):
    raise newException(WebSocketError, "сервер вернул неверный Sec-WebSocket-Accept")

  result = WebSocket(socket: sock, closed: false)

# -----------------------------------------------------------------
# Отправка фреймов
# -----------------------------------------------------------------

proc sendFrame(ws: WebSocket, opcode: int, payload: string) {.async.} =
  ## Отправляет один (нефрагментированный) маскированный фрейм.
  var header: seq[byte] = @[]
  add(header, byte(0x80 or opcode)) # FIN=1, opcode
  let length = len(payload)

  if length <= 125:
    add(header, byte(0x80 or length)) # MASK=1
  elif length <= 0xFFFF:
    add(header, byte(0x80 or 126))
    add(header, byte((length shr 8) and 0xFF))
    add(header, byte(length and 0xFF))
  else:
    add(header, byte(0x80 or 127))
    for shift in countdown(56, 0, 8):
      add(header, byte((length.int64 shr shift) and 0xFF))

  var maskKey: array[4, byte]
  for i in 0 ..< 4:
    maskKey[i] = byte(rand(255))
  for b in maskKey:
    add(header, b)

  var headerStr = newString(len(header))
  for i, b in header:
    headerStr[i] = char(b)

  await send(ws.socket, headerStr & maskPayload(payload, maskKey))

proc send*(ws: WebSocket, text: string) {.async.} =
  ## Отправляет текстовый (JSON) фрейм — основной способ общения с CDP.
  await sendFrame(ws, 0x1, text)

proc sendPong(ws: WebSocket, payload: string) {.async.} =
  ## Отвечает на ping тем же самым payload'ом, как того требует RFC 6455 —
  ## вызывается автоматически из receiveMessage() при получении фрейма
  ## с opcode 0x9, вручную дёргать эту процедуру не нужно.
  await sendFrame(ws, 0xA, payload)

proc sendClose(ws: WebSocket) {.async.} =
  ## Посылает close-фрейм (opcode 0x8) с пустым payload'ом — часть
  ## штатного закрытия соединения из close(ws), инициирующая handshake
  ## закрытия по RFC 6455 (ответного close-фрейма от сервера здесь не
  ## ждут: сокет закрывается сразу после отправки).
  await sendFrame(ws, 0x8, "")

# -----------------------------------------------------------------
# Приём фреймов
# -----------------------------------------------------------------

proc recvExact(sock: AsyncSocket, n: int): Future[string] {.async.} =
  ## recv из asyncnet не гарантирует получение ровно n байт за один
  ## вызов, поэтому дочитываем в цикле.
  result = ""
  while len(result) < n:
    let chunk = await recv(sock, n - len(result))
    if len(chunk) == 0:
      raise newException(WebSocketError, "соединение закрыто удалённой стороной")
    add(result, chunk)

const MaxFramePayload = 256 * 1024 * 1024
  ## Верхняя граница длины одного фрейма (256 МиБ): защита от
  ## отрицательной или заведомо неадекватной длины в заголовке.

proc recvOneFrame(ws: WebSocket): Future[tuple[opcode: int, fin: bool, payload: string]] {.async.} =
  ## Читает и разбирает ровно один WebSocket-фрейм по заголовку (opcode,
  ## FIN-бит, длина payload'а в одном из трёх форматов — 7/16/64 бита —
  ## и, если сервер вдруг замаскировал фрейм, маску) — низкоуровневый
  ## строительный блок для receiveMessage(), которая уже склеивает
  ## фрагментированные сообщения из нескольких таких фреймов.
  let head = await recvExact(ws.socket, 2)
  let
    b0 = byte(head[0])
    b1 = byte(head[1])
    fin = (b0 and 0x80) != 0
    opcode = int(b0 and 0x0F)
    masked = (b1 and 0x80) != 0
  var length = int(b1 and 0x7F)

  if length == 126:
    let ext = await recvExact(ws.socket, 2)
    length = (int(byte(ext[0])) shl 8) or int(byte(ext[1]))
  elif length == 127:
    let ext = await recvExact(ws.socket, 8)
    length = 0
    for i in 0 ..< 8:
      length = (length shl 8) or int(byte(ext[i]))

  var maskKey: array[4, byte]
  if masked:
    let m = await recvExact(ws.socket, 4)
    for i in 0 ..< 4:
      maskKey[i] = byte(m[i])

  if length < 0 or length > MaxFramePayload:
    raise newException(WebSocketError, "недопустимая длина фрейма: " & $length)

  var payload = await recvExact(ws.socket, length)
  if masked:
    payload = maskPayload(payload, maskKey)

  result = (opcode, fin, payload)

proc receiveMessage*(ws: WebSocket): Future[string] {.async.} =
  ## Читает одно логическое сообщение, прозрачно склеивая
  ## фрагментированные фреймы и автоматически отвечая на ping.
  ## Возвращает пустую строку, если сервер закрыл соединение.
  var assembled = ""
  while true:
    let frame = await recvOneFrame(ws)
    case frame.opcode
    of 0x8: # close: по RFC 6455 отвечаем встречным close и закрываем
      if not ws.closed:
        ws.closed = true
        try:
          await sendClose(ws)
        except CatchableError:
          discard
      return ""
    of 0x9: # ping -> отвечаем pong тем же payload'ом
      await sendPong(ws, frame.payload)
      continue
    of 0xA: # pong — игнорируем
      continue
    of 0x0: # continuation
      add(assembled, frame.payload)
    else: # text/binary — начало (возможно, единственного) сообщения
      # 0x1 text / 0x2 binary: CDP шлёт только текст, различать не нужно.
      add(assembled, frame.payload)

    if frame.fin:
      break
  result = assembled

proc close*(ws: WebSocket) {.async.} =
  ## Штатно закрывает соединение: посылает close-фрейм (если сокет ещё
  ## не помечен закрытым — например, receiveMessage() уже не получила
  ## close от сервера) и в любом случае закрывает сам TCP-сокет.
  ## Ошибка при отправке close-фрейма на уже оборванном соединении
  ## гасится — цель этого вызова — гарантированно освободить сокет,
  ## а не сообщить об ошибке в уже ненужном прощальном рукопожатии.
  if not ws.closed:
    try:
      await sendClose(ws)
    except CatchableError:
      discard
    ws.closed = true
  close(ws.socket)
