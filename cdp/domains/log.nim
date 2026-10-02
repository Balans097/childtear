## cdp/domains/log.nim
##
## Обёртка над доменом Log:
## https://chromedevtools.github.io/devtools-protocol/tot/Log/
##
## Отдаёт записи из "браузерного" консольного лога (в том числе
## сетевые и security-предупреждения, а не только console.log —
## для чистого console.* удобнее событие Runtime.consoleAPICalled).
## Типичный сценарий: enable() -> session.on("Log.entryAdded", ...).

import std/asyncdispatch
import ../transport

proc enable*(session: CDPSession) {.async.} =
  ## Включает домен Log — обязательно перед подпиской на
  ## "Log.entryAdded" (без него события не приходят).
  discard await call(session, "Log.enable")

proc disable*(session: CDPSession) {.async.} =
  ## Отключает домен Log — подписка на "Log.entryAdded" перестаёт
  ## получать новые записи.
  discard await call(session, "Log.disable")

proc clear*(session: CDPSession) {.async.} =
  ## Очищает буфер уже накопленных записей лога на стороне браузера
  ## (на уже отправленные через "Log.entryAdded" события не влияет —
  ## только на то, что браузер хранит внутри себя).
  discard await call(session, "Log.clear")
