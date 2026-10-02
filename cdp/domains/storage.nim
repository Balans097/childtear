## cdp/domains/storage.nim
##
## Обёртка над доменом Storage:
## https://chromedevtools.github.io/devtools-protocol/tot/Storage/
##
## В отличие от Network.clearBrowserCache()/clearBrowserCookies()
## (cdp/domains/network.nim), действующих на весь браузер,
## Storage.clearDataForOrigin чистит данные ровно одного origin — штатное
## средство изолированной очистки без побочных эффектов для других вкладок.

import std/[asyncdispatch, json]
import ../transport

const AllStorageTypes* = "cookies,local_storage,session_storage,indexeddb," &
  "websql,cache_storage,service_workers,shader_cache,file_systems," &
  "appcache,interest_groups"
  ## Полный список типов данных, которые понимает clearDataForOrigin,
  ## через запятую (именно так их и ожидает сам протокол в поле
  ## "storageTypes"). Полезно как готовый аргумент "вычистить всё для
  ## этого сайта", когда не нужно перечислять типы вручную.

proc clearDataForOrigin*(session: CDPSession, origin: string, storageTypes = AllStorageTypes) {.async.} =
  ## Очищает перечисленные через запятую виды данных (storageTypes) только
  ## для origin (схема+хост+порт, например "https://example.com"), не
  ## затрагивая остальные сайты и вкладки. "cache_storage" — это Cache API
  ## service worker'ов, а не HTTP-дисковый кэш: очистить его по origin CDP
  ## не позволяет (ограничение протокола, см. Network.clearBrowserCache()).
  discard await call(session, "Storage.clearDataForOrigin", %*{
    "origin": origin,
    "storageTypes": storageTypes,
  })

proc getCookies*(session: CDPSession, browserContextId = ""): Future[seq[JsonNode]] {.async.} =
  ## Куки всего изолированного профиля browserContextId (или основного
  ## профиля, если не указан) — в отличие от Network.getCookies(),
  ## не привязан к конкретной вкладке/её фреймам.
  var params = newJObject()
  if len(browserContextId) > 0:
    params["browserContextId"] = %browserContextId
  let res = await call(session, "Storage.getCookies", params)
  result = getElems(res["cookies"])

proc clearCookies*(session: CDPSession, browserContextId = "") {.async.} =
  ## Очищает куки всего изолированного профиля browserContextId (или
  ## основного профиля) — как и Network.clearBrowserCookies(), это
  ## операция на уровне профиля целиком, а не одного origin'а; для
  ## очистки конкретного origin'а используйте clearDataForOrigin()
  ## с storageTypes = "cookies".
  var params = newJObject()
  if len(browserContextId) > 0:
    params["browserContextId"] = %browserContextId
  discard await call(session, "Storage.clearCookies", params)
