## cdp/browser.nim
##
## Chromium с --remote-debugging-port поднимает HTTP-сервер со служебными
## эндпоинтами (/json/list, /json/new, /json/close, ...), через который
## создаются и закрываются вкладки и выясняется адрес WebSocket вкладки.
## Это единственное место библиотеки с обычным HTTP вместо CDP. Домен
## Target не используется: управление вкладками через HTTP проще, не
## требует sessionId и официально поддерживается Chromium.

import std/[asyncdispatch, httpclient, json, uri, strformat]

type
  BrowserConnection* = ref object
    host*: string
    port*: int

proc newBrowserConnection*(host = "127.0.0.1", port = 9222): BrowserConnection =
  ## Описывает, куда стучаться: обычно это тот же адрес и порт, что
  ## указан в `--remote-debugging-port` при запуске
  ## `chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox`.
  BrowserConnection(host: host, port: port)

proc httpBase(bc: BrowserConnection): string =
  ## Собирает базовый "http://host:port" для служебных эндпоинтов
  ## /json/* — используется всеми процедурами этого модуля.
  &"http://{bc.host}:{bc.port}"

proc httpGetJson(url: string): Future[JsonNode] {.async.} =
  ## GET-запрос, разобранный как JSON, — для читающих эндпоинтов
  ## (/json/list, /json/version).
  var client = newAsyncHttpClient()
  try:
    let body = await getContent(client, url)
    result = parseJson(body)
  finally:
    close(client)

proc httpPut(url: string): Future[string] {.async.} =
  ## PUT-запрос к «действующим» эндпоинтам DevTools (/json/new,
  ## /json/close, /json/activate): с Chrome 111 GET к ним отвечает 405
  ## (защита от XSRF). Возвращает тело ответа; статус не 2xx — ошибка.
  var client = newAsyncHttpClient()
  try:
    let response = await request(client, url, httpMethod = HttpPut)
    let raw = await body(response)
    if not is2xx(code(response)):
      raise newException(HttpRequestError, "DevTools вернул " & $response.status & ": " & raw)
    result = raw
  finally:
    close(client)

proc httpPutJson(url: string): Future[JsonNode] {.async.} =
  ## httpPut() с разбором тела ответа как JSON (для /json/new).
  result = parseJson(await httpPut(url))

proc listTargets*(bc: BrowserConnection): Future[seq[JsonNode]] {.async.} =
  ## Возвращает список всех открытых вкладок/целей (как в chrome://inspect).
  let raw = await httpGetJson(httpBase(bc) & "/json/list")
  result = getElems(raw)

proc newTarget*(bc: BrowserConnection, url = "about:blank"): Future[JsonNode] {.async.} =
  ## Открывает новую вкладку с указанным URL и возвращает её описание
  ## (включая "id" и "webSocketDebuggerUrl").
  ## usePlus = false: /json/new ожидает обычное percent-encoding, а не
  ## application/x-www-form-urlencoded (пробел должен быть %20, не '+').
  let encoded = encodeUrl(url, usePlus = false)
  result = await httpPutJson(httpBase(bc) & "/json/new?" & encoded)

proc closeTarget*(bc: BrowserConnection, targetId: string) {.async.} =
  ## Закрывает вкладку по её id.
  discard await httpPut(httpBase(bc) & "/json/close/" & targetId)

proc activateTarget*(bc: BrowserConnection, targetId: string) {.async.} =
  ## Делает вкладку "активной" (аналог переключения фокуса на неё).
  discard await httpPut(httpBase(bc) & "/json/activate/" & targetId)

proc browserVersion*(bc: BrowserConnection): Future[JsonNode] {.async.} =
  ## /json/version — метаданные браузера и адрес browser-level WebSocket
  ## (полезно, если понадобится управлять браузером в целом, а не
  ## отдельной вкладкой).
  result = await httpGetJson(httpBase(bc) & "/json/version")
