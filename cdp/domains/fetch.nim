## cdp/domains/fetch.nim
##
## Обёртка над доменом Fetch:
## https://chromedevtools.github.io/devtools-protocol/tot/Fetch/
##
## Позволяет перехватывать сетевые запросы страницы до того, как они
## реально уйдут в сеть: заблокировать (например, рекламу/трекеры),
## подменить ответ или пропустить как есть. В отличие от Network
## (только наблюдение), Fetch даёт управление.
##
## Типичный сценарий: enable() -> подписка на "Fetch.requestPaused" ->
## по каждому запросу решить continueRequest / failRequest / fulfillRequest.

import std/[asyncdispatch, json, base64]
import ../transport

proc enable*(session: CDPSession, patterns: seq[string] = @["*"], handleAuthRequests = false) {.async.} =
  ## patterns — список URL-масок для перехвата (по умолчанию — все запросы).
  ## handleAuthRequests — также перехватывать HTTP Basic/Digest auth-запросы
  ## событием "Fetch.authRequired" (см. continueWithAuth).
  var patternArr = newJArray()
  for p in patterns:
    add(patternArr, %*{"urlPattern": p})
  discard await call(session, "Fetch.enable", %*{
    "patterns": patternArr,
    "handleAuthRequests": handleAuthRequests,
  })

proc disable*(session: CDPSession) {.async.} =
  ## Отключает перехват — все дальнейшие запросы страницы уходят в сеть
  ## как обычно, без остановки на "Fetch.requestPaused".
  discard await call(session, "Fetch.disable")

proc continueRequest*(session: CDPSession, requestId: string, url = "", methodOverride = "",
                       postData = "", headers: JsonNode = nil) {.async.} =
  ## Пропускает запрос дальше, при желании подменив URL/метод/тело/заголовки
  ## перед тем, как он реально уйдёт в сеть (все параметры необязательны).
  var params = %*{"requestId": requestId}
  if len(url) > 0:
    params["url"] = %url
  if len(methodOverride) > 0:
    params["method"] = %methodOverride
  if len(postData) > 0:
    params["postData"] = %base64.encode(postData)
  if headers != nil:
    params["headers"] = headers
  discard await call(session, "Fetch.continueRequest", params)

proc failRequest*(session: CDPSession, requestId: string, errorReason = "BlockedByClient") {.async.} =
  ## Обрывает запрос с указанной причиной (например, для блокировки рекламы).
  discard await call(session, "Fetch.failRequest", %*{"requestId": requestId, "errorReason": errorReason})

proc fulfillRequest*(session: CDPSession, requestId: string, responseCode = 200,
                      body = "", mimeType = "text/plain", extraHeaders: JsonNode = nil) {.async.} =
  ## Отвечает на запрос заранее заготовленным содержимым, не обращаясь
  ## к сети вовсе — удобно для мокирования API в тестах.
  var headers = %*[{"name": "Content-Type", "value": mimeType}]
  if extraHeaders != nil:
    for h in getElems(extraHeaders):
      add(headers, h)
  let params = %*{
    "requestId": requestId,
    "responseCode": responseCode,
    "responseHeaders": headers,
    "body": base64.encode(body),
  }
  discard await call(session, "Fetch.fulfillRequest", params)

proc getResponseBody*(session: CDPSession, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.} =
  ## Тело оригинального ответа сервера для запроса, приостановленного
  ## Fetch.requestPaused *после* стадии Response (т.е. когда ответ уже
  ## получен, но ещё не отдан странице) — полезно, чтобы прочитать и
  ## затем, например, переписать fulfillRequest'ом.
  let res = await call(session, "Fetch.getResponseBody", %*{"requestId": requestId})
  result = (getStr(res["body"]), getBool(getOrDefault(res, "base64Encoded"), false))

proc takeResponseBodyAsStream*(session: CDPSession, requestId: string): Future[string] {.async.} =
  ## Возвращает handle потока (для больших ответов) — читать его нужно
  ## через IO.read с полученным handle.
  let res = await call(session, "Fetch.takeResponseBodyAsStream", %*{"requestId": requestId})
  result = getStr(res["stream"])

proc continueWithAuth*(session: CDPSession, requestId: string, response: string,
                        username = "", password = "") {.async.} =
  ## response: "Default" | "CancelAuth" | "ProvideCredentials" —
  ## ответ на событие "Fetch.authRequired" (требует enable(handleAuthRequests=true)).
  var authResponse = %*{"response": response}
  if len(username) > 0:
    authResponse["username"] = %username
  if len(password) > 0:
    authResponse["password"] = %password
  discard await call(session, "Fetch.continueWithAuth", %*{
    "requestId": requestId,
    "authChallengeResponse": authResponse,
  })
