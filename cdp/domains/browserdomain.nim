## cdp/domains/browserdomain.nim
##
## Обёртка над протокольным доменом Browser:
## https://chromedevtools.github.io/devtools-protocol/tot/Browser/
##
## Не путать с cdp/browser.nim — тот работает через обычный HTTP
## (/json/new, /json/list, ...), а это домен CDP, команды которого
## нужно слать в *browser-level* сессию (WebSocket из
## /json/version -> "webSocketDebuggerUrl"), а не в сессию вкладки.
## Именно здесь живёт Browser.close — единственный штатный способ
## закрыть headless-Chromium целиком через протокол.

import std/[asyncdispatch, json]
import ../transport

proc getVersion*(session: CDPSession): Future[JsonNode] {.async.} =
  ## Дублирует то же самое, что отдаёт HTTP /json/version, но по
  ## протоколу (полезно, если уже есть открытая browser-level сессия).
  result = await call(session, "Browser.getVersion")

proc close*(session: CDPSession) {.async.} =
  ## Завершает процесс браузера целиком (все вкладки, все контексты).
  discard await call(session, "Browser.close")

proc setDownloadBehavior*(session: CDPSession, behavior: string, downloadPath = "",
                           browserContextId = "") {.async.} =
  ## behavior: "deny" | "allow" | "allowAndName" | "default".
  var params = %*{"behavior": behavior}
  if len(downloadPath) > 0:
    params["downloadPath"] = %downloadPath
  if len(browserContextId) > 0:
    params["browserContextId"] = %browserContextId
  discard await call(session, "Browser.setDownloadBehavior", params)

proc getWindowForTarget*(session: CDPSession, targetId = ""): Future[JsonNode] {.async.} =
  ## Возвращает {"windowId", "bounds"} — нужно для setWindowBounds.
  var params = newJObject()
  if len(targetId) > 0:
    params["targetId"] = %targetId
  result = await call(session, "Browser.getWindowForTarget", params)

proc setWindowBounds*(session: CDPSession, windowId: int, bounds: JsonNode) {.async.} =
  ## bounds — например {"width": 1280, "height": 800} или
  ## {"windowState": "maximized"}.
  discard await call(session, "Browser.setWindowBounds", %*{"windowId": windowId, "bounds": bounds})

proc resetPermissions*(session: CDPSession, browserContextId = "") {.async.} =
  ## Сбрасывает все разрешения, выданные через grantPermissions(), назад
  ## к дефолтному поведению браузера (обычно — "спрашивать"/"отказывать",
  ## в headless-режиме без UI разрешения без явного grant обычно просто
  ## недоступны сайту).
  var params = newJObject()
  if len(browserContextId) > 0:
    params["browserContextId"] = %browserContextId
  discard await call(session, "Browser.resetPermissions", params)

proc grantPermissions*(session: CDPSession, permissions: seq[string], origin = "",
                        browserContextId = "") {.async.} =
  ## permissions — например @["geolocation", "notifications"].
  var permArr = newJArray()
  for p in permissions:
    add(permArr, %p)
  var params = %*{"permissions": permArr}
  if len(origin) > 0:
    params["origin"] = %origin
  if len(browserContextId) > 0:
    params["browserContextId"] = %browserContextId
  discard await call(session, "Browser.grantPermissions", params)
