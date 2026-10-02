## cdp/domains/network.nim
##
## Обёртка над доменом Network:
## https://chromedevtools.github.io/devtools-protocol/tot/Network/
##
## Из всего домена (а он огромный) вынесено только то, что реально
## нужно для базовой автоматизации: включение отслеживания сети,
## простановка своих заголовков и извлечение финального статуса ответа.

import std/[asyncdispatch, json]
import ../transport

proc enable*(session: CDPSession) {.async.} =
  ## Включает отслеживание сети — обязательно перед подпиской на
  ## "Network.responseReceived"/"Network.requestWillBeSent" и т.п., и
  ## перед getResponseBody() (без enable() тела ответов не сохраняются).
  discard await call(session, "Network.enable")

proc disable*(session: CDPSession) {.async.} =
  ## Отключает отслеживание сети — экономит трафик/память сессии, если
  ## сетевые события больше не нужны.
  discard await call(session, "Network.disable")

proc setExtraHTTPHeaders*(session: CDPSession, headers: JsonNode) {.async.} =
  ## headers — плоский JSON-объект вида {"X-My-Header": "value", ...}.
  discard await call(session, "Network.setExtraHTTPHeaders", %*{"headers": headers})

proc setUserAgentOverride*(session: CDPSession, userAgent: string) {.async.} =
  ## Deprecated в пользу Emulation.setUserAgentOverride, но всё ещё
  ## работает и не требует домена Emulation — оставлено для простых
  ## случаев, когда нужен только UA без остальных полей.
  discard await call(session, "Network.setUserAgentOverride", %*{"userAgent": userAgent})

proc setCacheDisabled*(session: CDPSession, disabled = true) {.async.} =
  ## disabled = true заставляет браузер игнорировать HTTP-кэш при
  ## запросах этой вкладки (аналог DevTools -> Network -> "Disable
  ## cache") — не путать с clearBrowserCache() (та чистит уже
  ## накопленный кэш, эта — не даёт им пользоваться дальше).
  discard await call(session, "Network.setCacheDisabled", %*{"cacheDisabled": disabled})

proc clearBrowserCache*(session: CDPSession) {.async.} =
  ## Полностью очищает HTTP-дисковый кэш браузера. ВНИМАНИЕ: сам CDP не
  ## даёт способа ограничить эту команду одной вкладкой или origin'ом —
  ## это ограничение протокола, а не childtear.nim; см.
  ## Storage.clearDataForOrigin (cdp/domains/storage.nim) для
  ## по-настоящему изолированной альтернативы для Cache Storage
  ## (кэша service worker'ов — не то же самое, что HTTP-кэш).
  discard await call(session, "Network.clearBrowserCache")

proc clearBrowserCookies*(session: CDPSession) {.async.} =
  ## Полностью очищает куки браузера — всех вкладок, всех сайтов, всех
  ## открытых профилей разом. ВНИМАНИЕ: CDP не даёт отдельной команды
  ## "очистить куки одной вкладки/origin'а"; чтобы ограничиться текущим
  ## origin'ом, получите список кук через getCookies(urls) и удалите их
  ## по одной через deleteCookies() — так и устроен
  ## childtear.clearCookiesForOrigin().
  discard await call(session, "Network.clearBrowserCookies")

proc getCookies*(session: CDPSession, urls: seq[string] = @[]): Future[seq[JsonNode]] {.async.} =
  ## Без urls возвращает куки для всех фреймов текущей страницы.
  var params = newJObject()
  if len(urls) > 0:
    var arr = newJArray()
    for u in urls:
      add(arr, %u)
    params["urls"] = arr
  let res = await call(session, "Network.getCookies", params)
  result = getElems(res["cookies"])

proc setCookie*(session: CDPSession, name, value: string, url = "", domain = "",
                 path = "/", secure = false, httpOnly = false, sameSite = "",
                 expires = 0.0): Future[bool] {.async.} =
  ## Нужно указать либо url, либо domain — так требует сам протокол.
  ## expires > 0 — время истечения (секунды с эпохи Unix): кука становится
  ## постоянной и сохраняется на диск профиля. Без expires — сессионная
  ## кука, которую Chromium не записывает в базу cookies и теряет при
  ## закрытии процесса.
  var params = %*{
    "name": name,
    "value": value,
    "path": path,
    "secure": secure,
    "httpOnly": httpOnly,
  }
  if len(url) > 0:
    params["url"] = %url
  if len(domain) > 0:
    params["domain"] = %domain
  if len(sameSite) > 0:
    params["sameSite"] = %sameSite
  if expires > 0.0:
    params["expires"] = %expires
  let res = await call(session, "Network.setCookie", params)
  result = getBool(getOrDefault(res, "success"), true)

proc setCookies*(session: CDPSession, cookies: seq[JsonNode]) {.async.} =
  ## Пакетная версия setCookie — каждый элемент это объект вида
  ## {"name", "value", "url"/"domain", ...}.
  var arr = newJArray()
  for c in cookies:
    add(arr, c)
  discard await call(session, "Network.setCookies", %*{"cookies": arr})

proc deleteCookies*(session: CDPSession, name: string, url = "", domain = "", path = "") {.async.} =
  ## Удаляет куки с именем name, дополнительно отфильтрованные по
  ## url/domain/path (нужен хотя бы url либо domain, иначе браузер не
  ## знает, к какому сайту относится кука). В отличие от
  ## clearBrowserCookies(), это единственный способ удалить куки
  ## выборочно, а не все сразу.
  var params = %*{"name": name}
  if len(url) > 0:
    params["url"] = %url
  if len(domain) > 0:
    params["domain"] = %domain
  if len(path) > 0:
    params["path"] = %path
  discard await call(session, "Network.deleteCookies", params)

proc getResponseBody*(session: CDPSession, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.} =
  ## Доступно только для запросов, чьи данные ещё не были "вытолкнуты"
  ## из памяти браузера (обычно — пока обработчик Network.loadingFinished
  ## ещё не отработал слишком давно).
  let res = await call(session, "Network.getResponseBody", %*{"requestId": requestId})
  result = (getStr(res["body"]), getBool(getOrDefault(res, "base64Encoded"), false))

proc getRequestPostData*(session: CDPSession, requestId: string): Future[string] {.async.} =
  ## Тело POST-запроса (например, JSON или form-data), как оно было
  ## реально отправлено страницей — доступно только пока Chromium не
  ## вытолкнул данные запроса из памяти (тот же принцип, что и у
  ## getResponseBody()).
  let res = await call(session, "Network.getRequestPostData", %*{"requestId": requestId})
  result = getStr(getOrDefault(res, "postData"))

proc setBlockedURLs*(session: CDPSession, urls: seq[string]) {.async.} =
  ## Простая блокировка по маскам ("*ads*", "*.png" и т.п.) — если
  ## нужна более гибкая логика (например, решение на лету по каждому
  ## запросу), см. cdp/domains/fetch.nim.
  var arr = newJArray()
  for u in urls:
    add(arr, %u)
  discard await call(session, "Network.setBlockedURLs", %*{"urls": arr})

proc setBypassServiceWorker*(session: CDPSession, bypass = true) {.async.} =
  ## bypass = true заставляет запросы идти напрямую в сеть, минуя
  ## service worker страницы (если он есть), — полезно, когда важно
  ## видеть настоящие сетевые ответы, а не то, чем их подменяет кэш
  ## service worker'а.
  discard await call(session, "Network.setBypassServiceWorker", %*{"bypass": bypass})

proc emulateNetworkConditions*(session: CDPSession, offline = false, latencyMs = 0.0,
                                downloadThroughput = -1.0, uploadThroughput = -1.0,
                                connectionType = "") {.async.} =
  ## throughput в байтах/сек, -1 — без ограничения. connectionType,
  ## например, "cellular3g" — влияет только на navigator.connection.
  var params = %*{
    "offline": offline,
    "latency": latencyMs,
    "downloadThroughput": downloadThroughput,
    "uploadThroughput": uploadThroughput,
  }
  if len(connectionType) > 0:
    params["connectionType"] = %connectionType
  discard await call(session, "Network.emulateNetworkConditions", params)
