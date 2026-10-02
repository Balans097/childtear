# cdp — справочник низкоуровневого слоя

> **Импорт:** `import cdp/transport` (сессии/команды/события), `import cdp/browser` (HTTP `/json/*`), `import cdp/wsclient` (сырой WebSocket), `import cdp/domains/<domain>` (обёртки над доменами CDP — `page`, `dom`, `runtime`, `input`, `network`, `fetch`, `emulation`, `target`, `browserdomain`, `storage`, `log`).

> **Область применения:** прямой доступ к командам Chrome DevTools Protocol из Nim — для случаев, не покрытых высокоуровневым API `childtear.nim` (см. [`childtear_reference_ru.md`](./childtear_reference_ru.md)), либо когда нужен полный контроль над конкретной командой протокола.

Этот слой не пытается быть удобным — он пытается быть честным: каждая функция здесь соответствует ровно одной команде CDP (или, в `transport.nim`/`wsclient.nim`, одному шагу протокола WebSocket/JSON-RPC), без дополнительной логики поверх. Общая конвенция для всех доменных модулей — первым параметром они принимают `session: CDPSession`, полученный через `newCDPSession()` (раздел II); почти все процедуры асинхронны (`{.async.}`) и требуют `await` внутри `proc ... {.async.}` или запуска через `waitFor` на верхнем уровне.

Во всех примерах ниже, кроме раздела II, предполагается уже открытая сессия `session: CDPSession` (получена так, как показано в примере `newCDPSession()`) — открывать её заново в примере каждой отдельной функции было бы избыточно. Также предполагаются доступными импорты `std/asyncdispatch`, `std/json` и соответствующий `cdp/...` модуль раздела.


---

## Оглавление
I. [Типы и общие соглашения](#типы-и-общие-соглашения)
   1. [`CDPSession` — transport.nim](#cdpsession-transportnim)
   2. [`CDPError` — transport.nim](#cdperror-transportnim)
   3. [`EventHandler` — transport.nim](#eventhandler-transportnim)
   4. [`WebSocket` — wsclient.nim](#websocket-wsclientnim)
   5. [`WebSocketError` — wsclient.nim](#websocketerror-wsclientnim)
   6. [`BrowserConnection` — browser.nim](#browserconnection-browsernim)
II. [Транспорт: сессии, команды, события](#транспорт-сессии-команды-события)
   1. [`newCDPSession` — transport.nim](#newcdpsession-transportnim)
   2. [`call` — transport.nim](#call-transportnim)
   3. [`on` — transport.nim](#on-transportnim)
   4. [`onSession` — transport.nim](#onsession-transportnim)
   5. [`waitForEvent` — transport.nim](#waitforevent-transportnim)
   6. [`close` — transport.nim](#close-transportnim)
III. [WebSocket-клиент](#websocket-клиент)
   1. [`newWebSocket` — wsclient.nim](#newwebsocket-wsclientnim)
   2. [`send` — wsclient.nim](#send-wsclientnim)
   3. [`receiveMessage` — wsclient.nim](#receivemessage-wsclientnim)
   4. [`close` — wsclient.nim](#close-wsclientnim)
IV. [Browser-level HTTP API](#browser-level-http-api)
   1. [`newBrowserConnection` — browser.nim](#newbrowserconnection-browsernim)
   2. [`listTargets` — browser.nim](#listtargets-browsernim)
   3. [`newTarget` — browser.nim](#newtarget-browsernim)
   4. [`closeTarget` — browser.nim](#closetarget-browsernim)
   5. [`activateTarget` — browser.nim](#activatetarget-browsernim)
   6. [`browserVersion` — browser.nim](#browserversion-browsernim)
V. [Домен Page — навигация и жизненный цикл вкладки](#домен-page-навигация-и-жизненный-цикл-вкладки)
   1. [`enable` — page.nim](#enable-pagenim)
   2. [`disable` — page.nim](#disable-pagenim)
   3. [`navigate` — page.nim](#navigate-pagenim)
   4. [`reload` — page.nim](#reload-pagenim)
   5. [`stopLoading` — page.nim](#stoploading-pagenim)
   6. [`close` — page.nim](#close-pagenim)
   7. [`bringToFront` — page.nim](#bringtofront-pagenim)
   8. [`getFrameTree` — page.nim](#getframetree-pagenim)
   9. [`setDocumentContent` — page.nim](#setdocumentcontent-pagenim)
   10. [`getNavigationHistory` — page.nim](#getnavigationhistory-pagenim)
   11. [`navigateToHistoryEntry` — page.nim](#navigatetohistoryentry-pagenim)
   12. [`resetNavigationHistory` — page.nim](#resetnavigationhistory-pagenim)
   13. [`setLifecycleEventsEnabled` — page.nim](#setlifecycleeventsenabled-pagenim)
   14. [`setBypassCSP` — page.nim](#setbypasscsp-pagenim)
   15. [`addScriptToEvaluateOnNewDocument` — page.nim](#addscripttoevaluateonnewdocument-pagenim)
   16. [`removeScriptToEvaluateOnNewDocument` — page.nim](#removescripttoevaluateonnewdocument-pagenim)
   17. [`createIsolatedWorld` — page.nim](#createisolatedworld-pagenim)
   18. [`handleJavaScriptDialog` — page.nim](#handlejavascriptdialog-pagenim)
   19. [`setInterceptFileChooserDialog` — page.nim](#setinterceptfilechooserdialog-pagenim)
   20. [`setDownloadBehavior` — page.nim](#setdownloadbehavior-pagenim)
   21. [`getLayoutMetrics` — page.nim](#getlayoutmetrics-pagenim)
   22. [`captureScreenshot` — page.nim](#capturescreenshot-pagenim)
   23. [`printToPDF` — page.nim](#printtopdf-pagenim)
VI. [Домен DOM — дерево элементов](#домен-dom-дерево-элементов)
   1. [`enable` — dom.nim](#enable-domnim)
   2. [`disable` — dom.nim](#disable-domnim)
   3. [`getDocument` — dom.nim](#getdocument-domnim)
   4. [`querySelector` — dom.nim](#queryselector-domnim)
   5. [`querySelectorAll` — dom.nim](#queryselectorall-domnim)
   6. [`getBoxModel` — dom.nim](#getboxmodel-domnim)
   7. [`getContentQuads` — dom.nim](#getcontentquads-domnim)
   8. [`focus` — dom.nim](#focus-domnim)
   9. [`setAttributeValue` — dom.nim](#setattributevalue-domnim)
   10. [`removeAttribute` — dom.nim](#removeattribute-domnim)
   11. [`getAttributes` — dom.nim](#getattributes-domnim)
   12. [`resolveNode` — dom.nim](#resolvenode-domnim)
   13. [`requestNode` — dom.nim](#requestnode-domnim)
   14. [`describeNode` — dom.nim](#describenode-domnim)
   15. [`getOuterHTML` — dom.nim](#getouterhtml-domnim)
   16. [`setOuterHTML` — dom.nim](#setouterhtml-domnim)
   17. [`setNodeValue` — dom.nim](#setnodevalue-domnim)
   18. [`removeNode` — dom.nim](#removenode-domnim)
   19. [`requestChildNodes` — dom.nim](#requestchildnodes-domnim)
   20. [`scrollIntoViewIfNeeded` — dom.nim](#scrollintoviewifneeded-domnim)
   21. [`setFileInputFiles` — dom.nim](#setfileinputfiles-domnim)
   22. [`getNodeForLocation` — dom.nim](#getnodeforlocation-domnim)
VII. [Домен Runtime — выполнение JS](#домен-runtime-выполнение-js)
   1. [`enable` — runtime.nim](#enable-runtimenim)
   2. [`disable` — runtime.nim](#disable-runtimenim)
   3. [`evaluate` — runtime.nim](#evaluate-runtimenim)
   4. [`evaluateValue` — runtime.nim](#evaluatevalue-runtimenim)
   5. [`callFunctionOn` — runtime.nim](#callfunctionon-runtimenim)
   6. [`getProperties` — runtime.nim](#getproperties-runtimenim)
   7. [`releaseObject` — runtime.nim](#releaseobject-runtimenim)
   8. [`releaseObjectGroup` — runtime.nim](#releaseobjectgroup-runtimenim)
   9. [`discardConsoleEntries` — runtime.nim](#discardconsoleentries-runtimenim)
   10. [`awaitPromise` — runtime.nim](#awaitpromise-runtimenim)
   11. [`addBinding` — runtime.nim](#addbinding-runtimenim)
   12. [`removeBinding` — runtime.nim](#removebinding-runtimenim)
VIII. [Домен Input — мышь, клавиатура, тач](#домен-input-мышь-клавиатура-тач)
   1. [`dispatchMouseEvent` — input.nim](#dispatchmouseevent-inputnim)
   2. [`click` — input.nim](#click-inputnim)
   3. [`moveMouse` — input.nim](#movemouse-inputnim)
   4. [`scroll` — input.nim](#scroll-inputnim)
   5. [`insertText` — input.nim](#inserttext-inputnim)
   6. [`dispatchKeyEvent` — input.nim](#dispatchkeyevent-inputnim)
   7. [`pressKey` — input.nim](#presskey-inputnim)
   8. [`typeChar` — input.nim](#typechar-inputnim)
   9. [`dispatchTouchEvent` — input.nim](#dispatchtouchevent-inputnim)
   10. [`setIgnoreInputEvents` — input.nim](#setignoreinputevents-inputnim)
   11. [`cancelDragging` — input.nim](#canceldragging-inputnim)
IX. [Домен Network — сеть, куки, кэш](#домен-network-сеть-куки-кэш)
   1. [`enable` — network.nim](#enable-networknim)
   2. [`disable` — network.nim](#disable-networknim)
   3. [`setExtraHTTPHeaders` — network.nim](#setextrahttpheaders-networknim)
   4. [`setUserAgentOverride` — network.nim](#setuseragentoverride-networknim)
   5. [`setCacheDisabled` — network.nim](#setcachedisabled-networknim)
   6. [`clearBrowserCache` — network.nim](#clearbrowsercache-networknim)
   7. [`clearBrowserCookies` — network.nim](#clearbrowsercookies-networknim)
   8. [`getCookies` — network.nim](#getcookies-networknim)
   9. [`setCookie` — network.nim](#setcookie-networknim)
   10. [`setCookies` — network.nim](#setcookies-networknim)
   11. [`deleteCookies` — network.nim](#deletecookies-networknim)
   12. [`getResponseBody` — network.nim](#getresponsebody-networknim)
   13. [`getRequestPostData` — network.nim](#getrequestpostdata-networknim)
   14. [`setBlockedURLs` — network.nim](#setblockedurls-networknim)
   15. [`setBypassServiceWorker` — network.nim](#setbypassserviceworker-networknim)
   16. [`emulateNetworkConditions` — network.nim](#emulatenetworkconditions-networknim)
X. [Домен Fetch — перехват запросов](#домен-fetch-перехват-запросов)
   1. [`enable` — fetch.nim](#enable-fetchnim)
   2. [`disable` — fetch.nim](#disable-fetchnim)
   3. [`continueRequest` — fetch.nim](#continuerequest-fetchnim)
   4. [`failRequest` — fetch.nim](#failrequest-fetchnim)
   5. [`fulfillRequest` — fetch.nim](#fulfillrequest-fetchnim)
   6. [`getResponseBody` — fetch.nim](#getresponsebody-fetchnim)
   7. [`takeResponseBodyAsStream` — fetch.nim](#takeresponsebodyasstream-fetchnim)
   8. [`continueWithAuth` — fetch.nim](#continuewithauth-fetchnim)
XI. [Домен Emulation — подмена окружения](#домен-emulation-подмена-окружения)
   1. [`setDeviceMetricsOverride` — emulation.nim](#setdevicemetricsoverride-emulationnim)
   2. [`clearDeviceMetricsOverride` — emulation.nim](#cleardevicemetricsoverride-emulationnim)
   3. [`setUserAgentOverride` — emulation.nim](#setuseragentoverride-emulationnim)
   4. [`setGeolocationOverride` — emulation.nim](#setgeolocationoverride-emulationnim)
   5. [`clearGeolocationOverride` — emulation.nim](#cleargeolocationoverride-emulationnim)
   6. [`setTimezoneOverride` — emulation.nim](#settimezoneoverride-emulationnim)
   7. [`setLocaleOverride` — emulation.nim](#setlocaleoverride-emulationnim)
   8. [`setScriptExecutionDisabled` — emulation.nim](#setscriptexecutiondisabled-emulationnim)
   9. [`setEmulatedMedia` — emulation.nim](#setemulatedmedia-emulationnim)
   10. [`setCPUThrottlingRate` — emulation.nim](#setcputhrottlingrate-emulationnim)
   11. [`setDefaultBackgroundColorOverride` — emulation.nim](#setdefaultbackgroundcoloroverride-emulationnim)
   12. [`clearDefaultBackgroundColorOverride` — emulation.nim](#cleardefaultbackgroundcoloroverride-emulationnim)
   13. [`setTouchEmulationEnabled` — emulation.nim](#settouchemulationenabled-emulationnim)
XII. [Домен Target — вкладки и профили](#домен-target-вкладки-и-профили)
   1. [`getTargets` — target.nim](#gettargets-targetnim)
   2. [`getTargetInfo` — target.nim](#gettargetinfo-targetnim)
   3. [`setDiscoverTargets` — target.nim](#setdiscovertargets-targetnim)
   4. [`activateTarget` — target.nim](#activatetarget-targetnim)
   5. [`createTarget` — target.nim](#createtarget-targetnim)
   6. [`closeTarget` — target.nim](#closetarget-targetnim)
   7. [`createBrowserContext` — target.nim](#createbrowsercontext-targetnim)
   8. [`getBrowserContexts` — target.nim](#getbrowsercontexts-targetnim)
   9. [`disposeBrowserContext` — target.nim](#disposebrowsercontext-targetnim)
   10. [`attachToTarget` — target.nim](#attachtotarget-targetnim)
   11. [`detachFromTarget` — target.nim](#detachfromtarget-targetnim)
   12. [`setAutoAttach` — target.nim](#setautoattach-targetnim)
   13. [`callWithSession` — target.nim](#callwithsession-targetnim)
XIII. [Домен Browser — окно и разрешения](#домен-browser-окно-и-разрешения)
   1. [`getVersion` — browserdomain.nim](#getversion-browserdomainnim)
   2. [`close` — browserdomain.nim](#close-browserdomainnim)
   3. [`setDownloadBehavior` — browserdomain.nim](#setdownloadbehavior-browserdomainnim)
   4. [`getWindowForTarget` — browserdomain.nim](#getwindowfortarget-browserdomainnim)
   5. [`setWindowBounds` — browserdomain.nim](#setwindowbounds-browserdomainnim)
   6. [`resetPermissions` — browserdomain.nim](#resetpermissions-browserdomainnim)
   7. [`grantPermissions` — browserdomain.nim](#grantpermissions-browserdomainnim)
XIV. [Домен Storage — данные конкретного origin'а](#домен-storage-данные-конкретного-originа)
   1. [`clearDataForOrigin` — storage.nim](#cleardatafororigin-storagenim)
   2. [`getCookies` — storage.nim](#getcookies-storagenim)
   3. [`clearCookies` — storage.nim](#clearcookies-storagenim)
XV. [Домен Log — консольные записи браузера](#домен-log-консольные-записи-браузера)
   1. [`enable` — log.nim](#enable-lognim)
   2. [`disable` — log.nim](#disable-lognim)
   3. [`clear` — log.nim](#clear-lognim)
XVI. [Практические рецепты](#практические-рецепты)
XVII. [Краткая таблица](#краткая-таблица)
XVIII. [Сводка: какую функцию выбрать](#сводка-какую-функцию-выбрать)


---

## Типы и общие соглашения

### `CDPSession` — transport.nim

Активная сессия протокола поверх одного WebSocket-соединения: хранит открытый `WebSocket`, счётчики id команд/обработчиков, таблицу ожидающих ответов (`pending`) и таблицу подписчиков на события (`handlers`). Единственный тип, который реально передаётся почти во все низкоуровневые функции. Получается через `newCDPSession()`.

### `CDPError` — transport.nim

Исключение, поднимаемое `call()`, когда браузер вернул `{"error": {...}}` вместо `{"result": {...}}` — например, неизвестный метод, невалидные параметры, узел не найден и т.п.

### `EventHandler` — transport.nim

Тип обработчика событий: `proc(params: JsonNode) {.gcsafe.}`. Регистрируется через `on()`/`onSession()`/`waitForEvent()` и вызывается с полем `"params"` входящего события.

### `WebSocket` — wsclient.nim

Открытое WebSocket-соединение на уровне сырых кадров (фреймов) протокола — ниже, чем `CDPSession`: ничего не знает про JSON-конверт CDP, только про фреймы RFC 6455. Получается через `newWebSocket()`.

### `WebSocketError` — wsclient.nim

Исключение уровня WebSocket-клиента: ошибка handshake (несовпадение `Sec-WebSocket-Accept`), обрыв соединения при чтении фрейма и т.п.

### `BrowserConnection` — browser.nim

Параметры подключения к HTTP-эндпоинтам браузера (`host`, `port`) — не открывает соединение сама по себе, каждый вызов `listTargets()`/`newTarget()`/... делает отдельный HTTP-запрos. Получается через `newBrowserConnection()`.


---

## Транспорт: сессии, команды, события

Протокольная документация домена: Сердце низкоуровневого слоя — превращает сырой WebSocket в объект `CDPSession`, умеющий (1) отправлять команды и сопоставлять ответы по числовому id, и (2) рассылать входящие события подписчикам.


### `newCDPSession` — transport.nim


```nim
proc newCDPSession*(wsUrl: string): Future[CDPSession] {.async.}
```


**Что делает.** Открывает WebSocket к конкретной вкладке (webSocketDebuggerUrl, полученный через HTTP /json/new или /json/list) и запускает фоновый цикл чтения.


**Разбор реализации.** Функция не просто открывает сокет, а разворачивает вокруг него инфраструктуру сопоставления запрос/ответ: `nextId` — счётчик для генерации уникальных id исходящих команд, `pending` — таблица "id команды → Future её результата". Когда `listenLoop()` (запускается тут же через `asyncCheck`) получает сообщение с полем `"id"`, он находит в `pending` соответствующий Future и завершает его — так асинхронный запрос-ответ поверх одного WebSocket-соединения превращается в обычный `await`. Сообщения без `"id"`, но с `"method"` — это события, а не ответы; они уходят не в `pending`, а в `handlers` (см. `on()`/`waitForEvent()`).


**Параметры:**

- `wsUrl` (`string`) — адрес WebSocket-эндпоинта (`ws://...`) — из ответа `/json/list` или `/json/version`.


**Возвращает:** `Future[CDPSession]`


**Пример:**

```nim
let session = await newCDPSession("ws://127.0.0.1:9222/devtools/page/ABCD1234")
echo session != nil # выводит true
```


### `call` — transport.nim


```nim
proc call*(session: CDPSession, meth: string, params: JsonNode = newJObject(), sessionId = ""): Future[JsonNode] {.async.}
```


**Что делает.** Отправляет команду CDP (например "Page.navigate") и дожидается ответа с тем же id. Это основной низкоуровневый примитив, поверх которого построены все cdp/domains/*.nim обёртки. sessionId нужен только в "плоском" (flattened) режиме мультиплексирования нескольких вкладок через одно browser-level соединение (см. cdp/domains/target.nim -> attachToTarget) — в обычном режиме "один WebSocket на вкладку" его передавать не нужно.


**Разбор реализации.** Три шага: (1) взять текущий `nextId` и увеличить счётчик — гарантия уникальности id в пределах сессии; (2) создать пустой `Future[JsonNode]`, положить в `pending[id]` и отправить в сокет JSON вида `{"id", "method", "params"}` (плюс `"sessionId"`, если он не пуст — для мультиплексирования нескольких вкладок через одно browser-level соединение); (3) дождаться этого Future — его завершит `listenLoop()`, когда придёт ответ с тем же id. Если сервер вернул `{"error": ...}` вместо `{"result": ...}`, `call()` поднимает `CDPError`, а не отдаёт вызывающему коду ошибку под видом результата.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `meth` (`string`) — имя команды протокола, например "Page.navigate".
- `params` (`JsonNode`), по умолчанию `newJObject()`
- `sessionId`, по умолчанию `""` — идентификатор сессии в "плоском" (flattened) режиме мультиплексирования — из ответа `attachToTarget()`.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
discard await call(session, "Page.enable")
let res = await call(session, "Runtime.evaluate", %*{"expression": "1 + 1"})
echo res["result"]["value"] # выводит 2
```


### `on` — transport.nim


```nim
proc on*(session: CDPSession, event: string, handler: EventHandler)
```


**Что делает.** Регистрирует обработчик события основной ("корневой") сессии, например: session.on("Page.loadEventFired", proc (p: JsonNode) = ...). Подписка постоянна — живёт, пока жива сессия. Для событий вкладки, присоединённой через Target.attachToTarget в flatten-режиме, используйте onSession() — иначе события чужих вкладок на том же browser-level соединении будут неотличимы друг от друга.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `event` (`string`) — имя события протокола, например "Page.loadEventFired".
- `handler` (`EventHandler`) — функция, вызываемая с params каждый раз, когда приходит событие event.


**Пример:**

```nim
proc onLoad(params: JsonNode) {.gcsafe.} =
  echo "страница загрузилась" # выводит при каждом Page.loadEventFired
on(session, "Page.loadEventFired", onLoad)
```


### `onSession` — transport.nim


```nim
proc onSession*(session: CDPSession, sessionId, event: string, handler: EventHandler)
```


**Что делает.** Как on(), но только для событий конкретной присоединённой вкладки (sessionId, полученный из Target.attachToTarget) — нужно при мультиплексировании нескольких вкладок через одно browser-level соединение.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `sessionId` (`string`) — идентификатор сессии в "плоском" (flattened) режиме мультиплексирования — из ответа `attachToTarget()`.
- `event` (`string`) — имя события протокола, например "Page.loadEventFired".
- `handler` (`EventHandler`) — функция, вызываемая с params каждый раз, когда приходит событие event от конкретной присоединённой сессии.


**Пример:**

```nim
proc onEntry(params: JsonNode) {.gcsafe.} =
  echo "запись лога от конкретной вкладки" # выводит только для этой вкладки
onSession(browserSession, attachedSessionId, "Log.entryAdded", onEntry)
```


### `waitForEvent` — transport.nim


```nim
proc waitForEvent*(session: CDPSession, event: string, timeoutMs = 30_000, sessionId = ""): Future[JsonNode] {.async.}
```


**Что делает.** Однократно дожидается указанного события (например "Page.loadEventFired") с таймаутом. Удобно для последовательных сценариев вида "перейти по ссылке и дождаться загрузки". Передайте sessionId, чтобы ждать событие конкретной присоединённой вкладки в flatten-режиме (см. onSession). В отличие от on()/onSession(), обработчик всегда снимается сам — и при успешном срабатывании, и по таймауту, — чтобы повторные ожидания одного и того же события не копились в таблице подписчиков сессии.


**Разбор реализации.** По сути — одноразовая подписка: регистрирует обработчик через внутренний `addHandler()`, который при первом же срабатывании завершает `Future[JsonNode]` и сам себя отписывает — то есть после одного события обработчик не остаётся висеть в таблице подписчиков сессии. Гонка с таймаутом разрешена через параллельный `sleepAsync(timeoutMs)`: какая future завершится первой — событие или таймер — та и определяет результат. Если сработал таймер, обработчик всё равно снимается вручную.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `event` (`string`) — имя ожидаемого события протокола, например "Page.loadEventFired".
- `timeoutMs`, по умолчанию `30_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута.
- `sessionId`, по умолчанию `""` — идентификатор сессии в "плоском" (flattened) режиме мультиплексирования — из ответа `attachToTarget()`.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
discard await call(session, "Page.navigate", %*{"url": "https://example.com"})
discard await waitForEvent(session, "Page.loadEventFired", timeoutMs = 10_000)
echo "дождались загрузки" # выводит "дождались загрузки"
```


### `isAlive` — transport.nim


```nim
proc isAlive*(session: CDPSession): bool
```


**Что делает.** `true`, пока соединение открыто и фоновый цикл чтения работает. После обрыва или `close()` возвращает `false`; `call()` и `waitForEvent()` на такой сессии сразу бросают `CDPError`.


### `close` — transport.nim


```nim
proc close*(session: CDPSession) {.async.}
```


**Что делает.** Закрывает WebSocket и дожидается штатного завершения фонового listenLoop, чтобы после return из close() в системе не оставалось "подвешенных" detached-futures с этим соединением.


**Разбор реализации.** Отменяет все ещё не завершённые команды через внутренний `failAllPending()` (иначе `await call(...)`, уже ожидающие ответа, зависли бы навсегда — сервер, с которым разорвали связь, ответа не пришлёт), затем останавливает фоновый `listenLoop()` и закрывает сам WebSocket. Порядок важен: сначала оборвать ожидающие Future понятной ошибкой, потом уже рвать сокет.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await close(session) # обрывает ожидающие call() и закрывает WebSocket
echo "сессия закрыта" # выводит "сессия закрыта"
```


---

## WebSocket-клиент

Протокольная документация домена: Самый нижний слой — handshake, чтение/запись WebSocket-фреймов по RFC 6455, без внешних зависимостей. `transport.nim` использует этот модуль, но обычно вызывающему коду он не нужен напрямую.


### `newWebSocket` — wsclient.nim


```nim
proc newWebSocket*(url: string): Future[WebSocket] {.async.}
```


**Что делает.** Подключается по адресу вида ws://host:port/path и выполняет handshake. Возвращает готовый к работе WebSocket.


**Разбор реализации.** Реализует клиентский handshake WebSocket (RFC 6455) вручную: генерирует случайный 16-байтовый ключ, кодирует в base64 и шлёт как заголовок `Sec-WebSocket-Key`; сервер обязан ответить заголовком `Sec-WebSocket-Accept`, равным base64(SHA1(ключ + магическая GUID-строка из спецификации)). Функция независимо считает то же значение и сверяет с ответом — если не совпало, соединение считается недоверенным и обрывается.


**Параметры:**

- `url` (`string`) — адрес страницы или ресурса, к которому относится команда.


**Возвращает:** `Future[WebSocket]`


**Пример:**

```nim
let ws = await newWebSocket("ws://127.0.0.1:9222/devtools/page/ABCD1234")
echo ws != nil # выводит true
```


### `send` — wsclient.nim


```nim
proc send*(ws: WebSocket, text: string) {.async.}
```


**Что делает.** Отправляет текстовый (JSON) фрейм — основной способ общения с CDP.


**Параметры:**

- `ws` (`WebSocket`) — открытое соединение, полученное через newWebSocket().
- `text` (`string`) — содержимое текстового (JSON) фрейма для отправки.


**Пример:**

```nim
await send(ws, """{"id": 1, "method": "Page.enable"}""")
echo "команда отправлена" # выводит "команда отправлена"
```


### `receiveMessage` — wsclient.nim


```nim
proc receiveMessage*(ws: WebSocket): Future[string] {.async.}
```


**Что делает.** Читает одно логическое сообщение, прозрачно склеивая фрагментированные фреймы и автоматически отвечая на ping. Возвращает пустую строку, если сервер закрыл соединение.


**Разбор реализации.** WebSocket-сообщение не обязано укладываться в один TCP-фрейм: большие сообщения (например, JSON с полным деревом DOM большой страницы) браузер режет на несколько фреймов, из которых только последний помечен битом FIN. Функция читает фреймы в цикле, склеивая их payload, пока не встретит FIN = true — снаружи это выглядит как один вызов, хотя внутри может быть сделано произвольное число чтений из сокета.


**Параметры:**

- `ws` (`WebSocket`) — открытое соединение, полученное через newWebSocket().


**Возвращает:** `Future[string]`


**Пример:**

```nim
let raw = await receiveMessage(ws)
echo len(raw) > 0 # выводит true — получено непустое JSON-сообщение
```


### `close` — wsclient.nim


```nim
proc close*(ws: WebSocket) {.async.}
```


**Что делает.** Штатно закрывает соединение: посылает close-фрейм (если сокет ещё не помечен закрытым — например, receiveMessage() уже не получила close от сервера) и в любом случае закрывает сам TCP-сокет. Ошибка при отправке close-фрейма на уже оборванном соединении гасится — цель этого вызова — гарантированно освободить сокет, а не сообщить об ошибке в уже ненужном прощальном рукопожатии.


**Параметры:**

- `ws` (`WebSocket`) — соединение, которое нужно закрыть.


**Пример:**

```nim
await close(ws)
echo "сокет закрыт" # выводит "сокет закрыт"
```


---

## Browser-level HTTP API

Протокольная документация домена: Служебные HTTP-эндпоинты `/json/*`, которые отдаёт сам Chromium (не через WebSocket) — список вкладок, открыть/закрыть/активировать вкладку, версия браузера.


### `newBrowserConnection` — browser.nim


```nim
proc newBrowserConnection*(host = "127.0.0.1", port = 9222): BrowserConnection
```


**Что делает.** Описывает, куда стучаться: обычно это тот же адрес и порт, что указан в `--remote-debugging-port` при запуске `chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox`. Значение порта здесь — самостоятельный дефолт этого низкоуровневого модуля (на случай прямого использования cdp/browser.nim в обход childtear.nim); высокоуровневый newBrowser() в childtear.nim передаёт сюда свою именованную константу DefaultDebuggingPort, а не полагается на этот литерал.


**Параметры:**

- `host`, по умолчанию `"127.0.0.1"`
- `port`, по умолчанию `9222`


**Возвращает:** `BrowserConnection`


**Пример:**

```nim
let bc = newBrowserConnection("127.0.0.1", 9222)
echo bc != nil # выводит true
```


### `listTargets` — browser.nim


```nim
proc listTargets*(bc: BrowserConnection): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Возвращает список всех открытых вкладок/целей (как в chrome://inspect).


**Параметры:**

- `bc` (`BrowserConnection`) — описание подключения к браузеру, полученное через newBrowserConnection().


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let targets = await listTargets(bc)
echo len(targets) # выводит количество открытых вкладок/воркеров
```


### `newTarget` — browser.nim


```nim
proc newTarget*(bc: BrowserConnection, url = "about:blank"): Future[JsonNode] {.async.}
```


**Что делает.** Открывает новую вкладку с указанным URL и возвращает её описание (включая "id" и "webSocketDebuggerUrl").


**Параметры:**

- `bc` (`BrowserConnection`) — описание подключения к браузеру, полученное через newBrowserConnection().
- `url = "about` (`blank"`)


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let info = await newTarget(bc, "https://example.com")
echo info["id"] # выводит идентификатор новой вкладки, например "ABCD1234..."
```


### `closeTarget` — browser.nim


```nim
proc closeTarget*(bc: BrowserConnection, targetId: string) {.async.}
```


**Что делает.** Закрывает вкладку по её id.


**Параметры:**

- `bc` (`BrowserConnection`) — описание подключения к браузеру, полученное через newBrowserConnection().
- `targetId` (`string`) — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.


**Пример:**

```nim
let info = await newTarget(bc)
await closeTarget(bc, getStr(info["id"]))
echo "вкладка закрыта" # выводит "вкладка закрыта"
```


### `activateTarget` — browser.nim


```nim
proc activateTarget*(bc: BrowserConnection, targetId: string) {.async.}
```


**Что делает.** Делает вкладку "активной" (аналог переключения фокуса на неё).


**Параметры:**

- `bc` (`BrowserConnection`) — описание подключения к браузеру, полученное через newBrowserConnection().
- `targetId` (`string`) — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.


**Пример:**

```nim
let targets = await listTargets(bc)
await activateTarget(bc, getStr(targets[0]["id"]))
echo "вкладка на переднем плане" # выводит "вкладка на переднем плане"
```


### `browserVersion` — browser.nim


```nim
proc browserVersion*(bc: BrowserConnection): Future[JsonNode] {.async.}
```


**Что делает.** /json/version — метаданные браузера и адрес browser-level WebSocket (полезно, если понадобится управлять браузером в целом, а не отдельной вкладкой).


**Параметры:**

- `bc` (`BrowserConnection`) — описание подключения к браузеру, полученное через newBrowserConnection().


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let ver = await browserVersion(bc)
echo ver["product"] # выводит что-то вроде "HeadlessChrome/120.0.0.0"
```


---

## Домен Page — навигация и жизненный цикл вкладки

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Page/ — переходы по URL, история, диалоги, скриншоты, печать в PDF, изолированные JS-миры.


### `enable` — page.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**Что делает.** Включает домен Page — обязательно перед подпиской на его события (loadEventFired, frameNavigated и т.д.).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await enable(session)
echo "домен Page включён" # выводит "домен Page включён"
```


### `disable` — page.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**Что делает.** Отключает домен Page — подписки на его события (loadEventFired и т.п.) перестают срабатывать.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await disable(session)
echo "домен Page выключен" # выводит "домен Page выключен"
```


### `navigate` — page.nim


```nim
proc navigate*(session: CDPSession, url: string, referrer = "", transitionType = ""): Future[JsonNode] {.async.}
```


**Что делает.** Открывает URL в текущей вкладке. Возвращает {"frameId", "loaderId", ...}, а при неудачной навигации (например, DNS не резолвится) — ещё и "errorText" с причиной, которую проверяет вызывающий код в childtear.nim, не дожидаясь полного таймаута Page.loadEventFired.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `url` (`string`) — адрес страницы или ресурса, к которому относится команда.
- `referrer`, по умолчанию `""`
- `transitionType`, по умолчанию `""`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let navResult = await navigate(session, "https://example.com")
echo hasKey(navResult, "errorText") # выводит false при успешном старте навигации
```


### `reload` — page.nim


```nim
proc reload*(session: CDPSession, ignoreCache = false, scriptToEvaluateOnLoad = "") {.async.}
```


**Что делает.** Перезагружает текущую страницу. ignoreCache = true — то же самое, что Ctrl+Shift+R (жёсткая перезагрузка мимо HTTP-кэша). scriptToEvaluateOnLoad — однократный JS, выполняемый сразу после создания нового документа, до остальных скриптов страницы.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `ignoreCache`, по умолчанию `false`
- `scriptToEvaluateOnLoad`, по умолчанию `""`


**Пример:**

```nim
await reload(session, ignoreCache = true)
echo "страница перезагружается мимо кэша" # выводит "страница перезагружается мимо кэша"
```


### `stopLoading` — page.nim


```nim
proc stopLoading*(session: CDPSession) {.async.}
```


**Что делает.** Останавливает текущую загрузку страницы (аналог кнопки "стоп" в браузере). Уже загруженная часть DOM остаётся как есть.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await stopLoading(session)
echo "загрузка остановлена" # выводит "загрузка остановлена"
```


### `close` — page.nim


```nim
proc close*(session: CDPSession) {.async.}
```


**Что делает.** Закрывает вкладку так же, как это делает пользователь (кнопкой "закрыть таб"), в отличие от HTTP /json/close — может, например, запустить beforeunload-диалог.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await close(session)
echo "вкладка закрыта" # выводит "вкладка закрыта"
```


### `bringToFront` — page.nim


```nim
proc bringToFront*(session: CDPSession) {.async.}
```


**Что делает.** Делает вкладку активной (аналог Puppeteer page.bringToFront()).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await bringToFront(session)
echo "вкладка выведена на передний план" # выводит "вкладка выведена на передний план"
```


### `getFrameTree` — page.nim


```nim
proc getFrameTree*(session: CDPSession): Future[JsonNode] {.async.}
```


**Что делает.** Дерево фреймов страницы: {"frame": {...}, "childFrames": [...]} — каждый узел содержит "frame": {"id", "url", "name", ...} и рекурсивно "childFrames" для вложенных iframe.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let tree = await getFrameTree(session)
echo tree["frame"]["url"] # выводит URL главного фрейма страницы
```


### `setDocumentContent` — page.nim


```nim
proc setDocumentContent*(session: CDPSession, frameId, html: string) {.async.}
```


**Что делает.** Заменяет содержимое документа фрейма целиком, без навигации по URL (frameId — из getFrameTree()) — основа page.setContent() в Puppeteer.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `frameId` (`string`) — id фрейма, полученный из getFrameTree().
- `html` (`string`) — HTML-разметка, которой заменяется содержимое документа.


**Пример:**

```nim
let tree = await getFrameTree(session)
await setDocumentContent(session, getStr(tree["frame"]["id"]), "<h1>Заменено</h1>")
echo "документ заменён" # выводит "документ заменён"
```


### `getNavigationHistory` — page.nim


```nim
proc getNavigationHistory*(session: CDPSession): Future[JsonNode] {.async.}
```


**Что делает.** Возвращает {"currentIndex", "entries": [...]}.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let hist = await getNavigationHistory(session)
echo hist["currentIndex"] # выводит индекс текущей записи истории
```


### `navigateToHistoryEntry` — page.nim


```nim
proc navigateToHistoryEntry*(session: CDPSession, entryId: int) {.async.}
```


**Что делает.** Переходит к конкретной записи истории по её id (см. getNavigationHistory()) — основа goBack()/goForward() в childtear.nim.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `entryId` (`int`) — id записи истории, полученный из getNavigationHistory().


**Пример:**

```nim
let hist = await getNavigationHistory(session)
await navigateToHistoryEntry(session, hist["entries"][0]["id"].getInt)
echo "переход к первой записи истории" # выводит "переход к первой записи истории"
```


### `resetNavigationHistory` — page.nim


```nim
proc resetNavigationHistory*(session: CDPSession) {.async.}
```


**Что делает.** Очищает всю историю навигации вкладки, оставляя только текущую запись — после этого goBack()/goForward() возвращают false, пока не появятся новые записи.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await resetNavigationHistory(session)
echo "история очищена" # выводит "история очищена"
```


### `setLifecycleEventsEnabled` — page.nim


```nim
proc setLifecycleEventsEnabled*(session: CDPSession, enabled = true) {.async.}
```


**Что делает.** Включает более гранулярные события "Page.lifecycleEvent" (networkIdle, DOMContentLoaded и т.п.) — полезно для более точного waitForNavigation, чем просто loadEventFired.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `enabled`, по умолчанию `true`


**Пример:**

```nim
await setLifecycleEventsEnabled(session, true)
echo "события жизненного цикла включены" # выводит "события жизненного цикла включены" — придут Page.lifecycleEvent
```


### `setBypassCSP` — page.nim


```nim
proc setBypassCSP*(session: CDPSession, enabled = true) {.async.}
```


**Что делает.** Отключает Content-Security-Policy страницы — нужно, например, чтобы addScriptTag() мог инжектить произвольные скрипты на сайтах со строгим CSP.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `enabled`, по умолчанию `true`


**Пример:**

```nim
await setBypassCSP(session, true)
echo "Content-Security-Policy обходится" # выводит "Content-Security-Policy обходится"
```


### `addScriptToEvaluateOnNewDocument` — page.nim


```nim
proc addScriptToEvaluateOnNewDocument*(session: CDPSession, source: string, worldName = ""): Future[string] {.async.}
```


**Что делает.** Скрипт будет выполняться при создании *каждого* нового документа этой вкладки (до того, как выполнится любой другой JS страницы) — основа page.evaluateOnNewDocument() в Puppeteer. Возвращает identifier для последующего removeScriptToEvaluateOnNewDocument.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `source` (`string`) — исходный код JS, который будет выполняться при создании каждого нового документа вкладки.
- `worldName`, по умолчанию `""`


**Возвращает:** `Future[string]`


**Пример:**

```nim
let scriptId = await addScriptToEvaluateOnNewDocument(session, "window.__marker = 42;")
echo len(scriptId) > 0 # выводит true — получен идентификатор для removeScriptToEvaluateOnNewDocument
```


### `removeScriptToEvaluateOnNewDocument` — page.nim


```nim
proc removeScriptToEvaluateOnNewDocument*(session: CDPSession, identifier: string) {.async.}
```


**Что делает.** Отменяет скрипт, добавленный addScriptToEvaluateOnNewDocument(), по его identifier — на уже загруженные документы не влияет, только на следующие навигации.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `identifier` (`string`) — идентификатор, возвращённый addScriptToEvaluateOnNewDocument().


**Пример:**

```nim
await removeScriptToEvaluateOnNewDocument(session, scriptId)
echo "скрипт отменён" # выводит "скрипт отменён"
```


### `createIsolatedWorld` — page.nim


```nim
proc createIsolatedWorld*(session: CDPSession, frameId: string, worldName = "", grantUniversalAccess = false): Future[int] {.async.}
```


**Что делает.** Возвращает executionContextId изолированного JS-контекста для указанного фрейма — контекст не виден скриптам самой страницы (полезно для расширений/инструментов автоматизации, которым не стоит "светиться" в window).


**Разбор реализации.** "Изолированный" значит недоступный обычному JS страницы: скрипты страницы не видят глобальные переменные, объявленные в этом контексте, и наоборот. DOM у изолированного контекста тот же самый — `document` внутри него указывает на тот же документ фрейма, отдельно только JS-окружение (window, глобальные объекты). Это позволяет инструментам автоматизации не "светиться" в window страницы.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `frameId` (`string`) — id фрейма (из getFrameTree()/describeNode()), для которого создаётся изолированный контекст.
- `worldName`, по умолчанию `""`
- `grantUniversalAccess`, по умолчанию `false`


**Возвращает:** `Future[int]`


**Пример:**

```nim
let
  tree = await getFrameTree(session)
  ctxId = await createIsolatedWorld(session, getStr(tree["frame"]["id"]), "myWorld", grantUniversalAccess = true)
echo ctxId > 0 # выводит true
```


### `handleJavaScriptDialog` — page.nim


```nim
proc handleJavaScriptDialog*(session: CDPSession, accept: bool, promptText = "") {.async.}
```


**Что делает.** Отвечает на alert()/confirm()/prompt()/beforeunload, приостановивший страницу — см. событие "Page.javascriptDialogOpening".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `accept` (`bool`) — true — подтвердить диалог (OK/Enter), false — отклонить (Cancel).
- `promptText`, по умолчанию `""`


**Пример:**

```nim
await handleJavaScriptDialog(session, true, promptText = "мой ответ")
echo "диалог подтверждён" # выводит "диалог подтверждён"
```


### `setInterceptFileChooserDialog` — page.nim


```nim
proc setInterceptFileChooserDialog*(session: CDPSession, enabled = true) {.async.}
```


**Что делает.** После включения системный диалог выбора файла не открывается — вместо этого приходит событие "Page.fileChooserOpened" с backendNodeId инпута, которому затем нужно назначить файлы через DOM.setFileInputFiles.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `enabled`, по умолчанию `true`


**Пример:**

```nim
await setInterceptFileChooserDialog(session, true)
echo "диалог выбора файла перехватывается" # выводит "диалог выбора файла перехватывается" — придёт Page.fileChooserOpened
```


### `setDownloadBehavior` — page.nim


```nim
proc setDownloadBehavior*(session: CDPSession, behavior: string, downloadPath = "") {.async.}
```


**Что делает.** behavior: "deny" | "allow" | "default". Указывать downloadPath нужно только при behavior == "allow".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `behavior` (`string`) — "deny" | "allow" | "default".
- `downloadPath`, по умолчанию `""`


**Пример:**

```nim
await setDownloadBehavior(session, "allow", downloadPath = "/tmp/downloads")
echo "скачивания разрешены" # выводит "скачивания разрешены"
```


### `getLayoutMetrics` — page.nim


```nim
proc getLayoutMetrics*(session: CDPSession): Future[JsonNode] {.async.}
```


**Что делает.** {"layoutViewport", "visualViewport", "contentSize", "cssContentSize"} — реальные размеры страницы, полезно для screenshot(fullPage=true).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let metrics = await getLayoutMetrics(session)
echo metrics["cssContentSize"]["height"] # выводит полную высоту документа в CSS-пикселях
```


### `captureScreenshot` — page.nim


```nim
proc captureScreenshot*(session: CDPSession, format = "png", quality = 100, clip: JsonNode = nil, captureBeyondViewport = false, fromSurface = true): Future[string] {.async.}
```


**Что делает.** Возвращает содержимое скриншота, закодированное в base64 (как оно приходит от браузера, без декодирования). clip — необязательный {"x","y","width","height","scale"} для обрезки конкретной области (см. childtear.screenshot(fullPage=true)).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `format`, по умолчанию `"png"`
- `quality`, по умолчанию `100`
- `clip` (`JsonNode`), по умолчанию `nil`
- `captureBeyondViewport`, по умолчанию `false`
- `fromSurface`, по умолчанию `true`


**Возвращает:** `Future[string]`


**Пример:**

```nim
let base64Png = await captureScreenshot(session, format = "png")
echo len(base64Png) > 0 # выводит true — получена base64-строка PNG
```


### `printToPDF` — page.nim


```nim
proc printToPDF*(session: CDPSession, landscape = false, printBackground = true, paperWidth = 8.5, paperHeight = 11.0, marginTop = 0.4, marginBottom = 0.4, marginLeft = 0.4, marginRight = 0.4, pageRanges = ""): Future[string] {.async.}
```


**Что делает.** Возвращает PDF страницы в base64. Размеры бумаги и поля — в дюймах, как того требует сам протокол.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `landscape`, по умолчанию `false`
- `printBackground`, по умолчанию `true`
- `paperWidth`, по умолчанию `8.5`
- `paperHeight`, по умолчанию `11.0`
- `marginTop`, по умолчанию `0.4`
- `marginBottom`, по умолчанию `0.4`
- `marginLeft`, по умолчанию `0.4`
- `marginRight`, по умолчанию `0.4`
- `pageRanges`, по умолчанию `""`


**Возвращает:** `Future[string]`


**Пример:**

```nim
let base64Pdf = await printToPDF(session, landscape = false)
echo len(base64Pdf) > 0 # выводит true — получена base64-строка PDF
```


---

## Домен DOM — дерево элементов

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/DOM/ — поиск узлов, чтение/изменение атрибутов и разметки, геометрия элементов.


### `enable` — dom.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**Что делает.** Формально требуется спецификацией перед использованием остальных команд домена (в актуальном headless-Chromium многие команды прощают его отсутствие, но полагаться на это не стоит).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await enable(session)
echo "домен DOM включён" # выводит "домен DOM включён"
```


### `disable` — dom.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**Что делает.** Отключает домен DOM — на практике почти никогда не вызывается явно: домен живёт, пока жива сама сессия вкладки.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await disable(session)
echo "домен DOM выключен" # выводит "домен DOM выключен"
```


### `getDocument` — dom.nim


```nim
proc getDocument*(session: CDPSession, depth = 1): Future[JsonNode] {.async.}
```


**Что делает.** Возвращает корневой узел документа (обычно нужен только его "nodeId").


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `depth`, по умолчанию `1` — глубина обхода поддерева; -1 — без ограничения, обойти/вернуть всё поддерево целиком.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let doc = await getDocument(session, depth = 1)
echo doc["root"]["nodeName"] # выводит "#document"
```


### `querySelector` — dom.nim


```nim
proc querySelector*(session: CDPSession, nodeId: int, selector: string): Future[int] {.async.}
```


**Что делает.** Ищет первый узел, соответствующий CSS-селектору, внутри поддерева nodeId. Возвращает 0, если ничего не найдено.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `selector` (`string`) — CSS-селектор искомого элемента.


**Возвращает:** `Future[int]`


**Пример:**

```nim
let
  doc = await getDocument(session)
  nodeId = await querySelector(session, doc["root"]["nodeId"].getInt, "h1")
echo nodeId > 0 # выводит true, если заголовок найден на странице
```


### `querySelectorAll` — dom.nim


```nim
proc querySelectorAll*(session: CDPSession, nodeId: int, selector: string): Future[seq[int]] {.async.}
```


**Что делает.** Как querySelector(), но возвращает nodeId ВСЕХ узлов, подходящих под селектор, внутри поддерева nodeId, а не только первого.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `selector` (`string`) — CSS-селектор искомых элементов.


**Возвращает:** `Future[seq[int]]`


**Пример:**

```nim
let
  doc = await getDocument(session)
  ids = await querySelectorAll(session, doc["root"]["nodeId"].getInt, "a")
echo len(ids) # выводит количество ссылок на странице
```


### `getBoxModel` — dom.nim


```nim
proc getBoxModel*(session: CDPSession, nodeId: int): Future[JsonNode] {.async.}
```


**Что делает.** Геометрия узла на странице (нужна, чтобы навести курсор в его центр).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let box = await getBoxModel(session, nodeId)
echo box["content"] # выводит 8 чисел — координаты 4 углов прямоугольника
```


### `getContentQuads` — dom.nim


```nim
proc getContentQuads*(session: CDPSession, nodeId: int): Future[seq[JsonNode]] {.async.}
```


**Что делает.** В отличие от getBoxModel, работает и для узлов, у которых несколько прямоугольников на экране (например, инлайновые элементы, разбитые переносом строки на несколько строк).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let quads = await getContentQuads(session, nodeId)
echo len(quads) # выводит 1 для обычного блочного элемента, больше — для строчного, разбитого на несколько строк
```


### `focus` — dom.nim


```nim
proc focus*(session: CDPSession, nodeId: int) {.async.}
```


**Что делает.** Программно фокусирует узел (аналог el.focus() из JS, но через DOM, а не Runtime) — узел должен быть фокусируемым (input, [tabindex] и т.п.).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Пример:**

```nim
await focus(session, nodeId)
echo "элемент сфокусирован" # выводит "элемент сфокусирован"
```


### `setAttributeValue` — dom.nim


```nim
proc setAttributeValue*(session: CDPSession, nodeId: int, name, value: string) {.async.}
```


**Что делает.** Устанавливает значение HTML-атрибута узла (Element.setAttribute).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `name` (`string`) — имя HTML-атрибута.
- `value` (`string`) — новое значение атрибута.


**Пример:**

```nim
await setAttributeValue(session, nodeId, "class", "highlighted")
echo "атрибут установлен" # выводит "атрибут установлен"
```


### `removeAttribute` — dom.nim


```nim
proc removeAttribute*(session: CDPSession, nodeId: int, name: string) {.async.}
```


**Что делает.** Удаляет HTML-атрибут узла (Element.removeAttribute); не ошибается, если атрибута и так не было.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `name` (`string`) — имя удаляемого атрибута.


**Пример:**

```nim
await removeAttribute(session, nodeId, "disabled")
echo "атрибут удалён" # выводит "атрибут удалён"
```


### `getAttributes` — dom.nim


```nim
proc getAttributes*(session: CDPSession, nodeId: int): Future[seq[(string, string)]] {.async.}
```


**Что делает.** DOM.getAttributes отдаёт плоский массив ["имя1","значение1","имя2",...] — здесь он уже разложен в пары (имя, значение) для удобства.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int): Future[seq[(string, string`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Пример:**

```nim
let attrs = await getAttributes(session, nodeId)
echo attrs # выводит @[("class", "btn"), ("type", "submit")]
```


### `resolveNode` — dom.nim


```nim
proc resolveNode*(session: CDPSession, nodeId: int): Future[JsonNode] {.async.}
```


**Что делает.** Возвращает Runtime.RemoteObject для узла — используется, когда нужно передать узел в Runtime.callFunctionOn.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let remoteObj = await resolveNode(session, nodeId)
echo remoteObj["objectId"] # выводит идентификатор JS-объекта, пригодный для Runtime.callFunctionOn
```


### `requestNode` — dom.nim


```nim
proc requestNode*(session: CDPSession, objectId: string): Future[int] {.async.}
```


**Что делает.** Обратная операция к resolveNode: получить nodeId по RemoteObject.objectId.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `objectId` (`string`) — идентификатор JS-объекта на стороне браузера (Runtime.RemoteObject.objectId) — из `evaluate()`/`resolveNode()`.


**Возвращает:** `Future[int]`


**Пример:**

```nim
# objectId получен, например, из Runtime.evaluate с returnByValue = false
let nodeId = await requestNode(session, objectId)
echo nodeId > 0 # выводит true
```


### `describeNode` — dom.nim


```nim
proc describeNode*(session: CDPSession, nodeId: int, depth = 1, pierce = false): Future[JsonNode] {.async.}
```


**Что делает.** Возвращает описание узла (Node) — тег, атрибуты, дочерние узлы (на глубину depth; -1 — целиком) и, для `<iframe>`/`<frame>`, поля "frameId" и, при pierce = true, вложенный узел "contentDocument" (корневой документ внутри фрейма). Именно pierce = true и есть тот способ, которым childtear.frame() находит документ внутри iframe, чтобы искать в нём элементы через querySelector().


**Разбор реализации.** Параметр `pierce` определяет, останавливается ли обход дерева на границе iframe. Без него узел `<iframe>` в ответе — просто элемент со своими атрибутами; с `pierce = true` в ответе появляется поле `"contentDocument"` — поддерево документа ВНУТРИ iframe со своим `nodeId`, годным как корень для `querySelector()`. Это единственный штатный мост из "снаружи" в DOM iframe без захода в его собственный JS-контекст.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `depth`, по умолчанию `1` — глубина обхода поддерева; -1 — без ограничения, обойти/вернуть всё поддерево целиком.
- `pierce`, по умолчанию `false` — проходить ли сквозь границы iframe/shadow DOM — без этого обход останавливается на границе фрейма.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let
  iframeNodeId = await querySelector(session, rootId, "iframe")
  described = await describeNode(session, iframeNodeId, depth = 1, pierce = true)
echo described["contentDocument"]["nodeId"] # выводит nodeId документа внутри iframe
```


### `getOuterHTML` — dom.nim


```nim
proc getOuterHTML*(session: CDPSession, nodeId: int): Future[string] {.async.}
```


**Что делает.** HTML-разметка самого узла вместе с ним самим (Element.outerHTML).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let html = await getOuterHTML(session, nodeId)
echo html # выводит "<button class=\"btn\">Войти</button>"
```


### `setOuterHTML` — dom.nim


```nim
proc setOuterHTML*(session: CDPSession, nodeId: int, outerHTML: string) {.async.}
```


**Что делает.** Заменяет узел целиком на разобранный из outerHTML фрагмент разметки (Element.outerHTML =). После вызова исходный nodeId недействителен — узел на его месте нужно искать заново.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `outerHTML` (`string`) — новая HTML-разметка, заменяющая узел целиком.


**Пример:**

```nim
await setOuterHTML(session, nodeId, "<button>Новая кнопка</button>")
echo "разметка заменена" # выводит "разметка заменена" (исходный nodeId после этого недействителен)
```


### `setNodeValue` — dom.nim


```nim
proc setNodeValue*(session: CDPSession, nodeId: int, value: string) {.async.}
```


**Что делает.** Меняет значение текстового узла (Node.nodeValue), а не атрибута.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `value` (`string`) — новое значение текстового узла.


**Пример:**

```nim
# nodeId здесь — текстовый узел (Node.nodeType == 3), не элемент
await setNodeValue(session, textNodeId, "новый текст")
echo "текст изменён" # выводит "текст изменён"
```


### `removeNode` — dom.nim


```nim
proc removeNode*(session: CDPSession, nodeId: int) {.async.}
```


**Что делает.** Удаляет узел из документа (аналог el.remove()).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Пример:**

```nim
await removeNode(session, nodeId)
echo "узел удалён" # выводит "узел удалён"
```


### `requestChildNodes` — dom.nim


```nim
proc requestChildNodes*(session: CDPSession, nodeId: int, depth = 1, pierce = false) {.async.}
```


**Что делает.** "Прогревает" узел на нужную глубину — после этого дочерние узлы доступны в DOM.getDocument/событиях без отдельного getDocument.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `depth`, по умолчанию `1` — глубина обхода поддерева; -1 — без ограничения, обойти/вернуть всё поддерево целиком.
- `pierce`, по умолчанию `false` — проходить ли сквозь границы iframe/shadow DOM — без этого обход останавливается на границе фрейма.


**Пример:**

```nim
await requestChildNodes(session, nodeId, depth = -1)
echo "дочерние узлы подгружены" # выводит "дочерние узлы подгружены" (сами узлы придут события DOM.setChildNodes)
```


### `scrollIntoViewIfNeeded` — dom.nim


```nim
proc scrollIntoViewIfNeeded*(session: CDPSession, nodeId: int) {.async.}
```


**Что делает.** Прокручивает страницу так, чтобы узел оказался в видимой области — настоящий пользователь не может кликнуть на то, что вне экрана, поэтому click()/hover() в childtear.nim вызывают это перед кликом.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.


**Пример:**

```nim
await scrollIntoViewIfNeeded(session, nodeId)
echo "элемент в зоне видимости" # выводит "элемент в зоне видимости"
```


### `setFileInputFiles` — dom.nim


```nim
proc setFileInputFiles*(session: CDPSession, nodeId: int, files: seq[string]) {.async.}
```


**Что делает.** Назначает файлы элементу <input type="file"> напрямую, без системного диалога выбора файла — files: полные пути на диске, где выполняется сам браузер.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `nodeId` (`int`) — идентификатор DOM-узла, полученный от `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; действителен, пока не изменилось дерево документа.
- `files` (`seq[string]`) — полные пути к файлам на диске, где выполняется сам браузер.


**Пример:**

```nim
await setFileInputFiles(session, inputNodeId, @["/tmp/photo.jpg"])
echo "файл выбран" # выводит "файл выбран"
```


### `getNodeForLocation` — dom.nim


```nim
proc getNodeForLocation*(session: CDPSession, x, y: int): Future[JsonNode] {.async.}
```


**Что делает.** Возвращает узел под указанной точкой экрана (аналог document.elementFromPoint).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `x` (`int`) — координата по горизонтали в системе координат страницы (CSS-пиксели от левого края вьюпорта).
- `y` (`int`) — координата по вертикали в системе координат страницы (CSS-пиксели от верхнего края вьюпорта).


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let res = await getNodeForLocation(session, 100, 200)
echo res["nodeId"] # выводит nodeId элемента в точке (100, 200) вьюпорта
```


---

## Домен Runtime — выполнение JS

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Runtime/ — исполнение произвольных выражений, работа с промисами, мост window -> Nim.


### `enable` — runtime.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**Что делает.** Включает домен Runtime — обязательно перед evaluate() и подпиской на "Runtime.consoleAPICalled"/"Runtime.exceptionThrown"/ "Runtime.executionContextCreated" и т.п.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await enable(session)
echo "домен Runtime включён" # выводит "домен Runtime включён"
```


### `disable` — runtime.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**Что делает.** Отключает домен Runtime.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await disable(session)
echo "домен Runtime выключен" # выводит "домен Runtime выключен"
```


### `evaluate` — runtime.nim


```nim
proc evaluate*(session: CDPSession, expression: string, awaitPromise = false, returnByValue = true, contextId = 0): Future[JsonNode] {.async.}
```


**Что делает.** Исполняет выражение JS в контексте страницы и возвращает Runtime.RemoteObject (result). При ошибке в самом JS-выражении поле "exceptionDetails" будет присутствовать в ответе. contextId выбирает, В КАКОМ execution context выполнить выражение — 0 (по умолчанию) означает "основной контекст главного фрейма страницы"; отличный от 0 id нужен, чтобы выполнить JS внутри конкретного iframe (см. Page.createIsolatedWorld в page.nim и childtear.frame()/Frame.evalJS(), которые как раз и получают такой id для содержимого iframe).


**Разбор реализации.** `contextId = 0` — служебное значение "не передавать это поле вовсе", а не настоящий id контекста (id исполняемых контекстов CDP всегда положительные). По умолчанию выражение выполняется в основном контексте главного фрейма страницы. Ненулевой `contextId` (например, из `Page.createIsolatedWorld()`) переопределяет это и запускает выражение в конкретном изолированном контексте — так `childtear.Frame` выполняет JS внутри iframe, а не в контексте главной страницы.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `expression` (`string`) — исполняемое JS-выражение.
- `awaitPromise`, по умолчанию `false`
- `returnByValue`, по умолчанию `true`
- `contextId`, по умолчанию `0`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let res = await evaluate(session, "document.title")
echo res["result"]["value"] # выводит заголовок страницы, например "Example Domain"
```


### `evaluateValue` — runtime.nim


```nim
proc evaluateValue*(session: CDPSession, expression: string, awaitPromise = false, contextId = 0): Future[JsonNode] {.async.}
```


**Что делает.** Удобный вариант evaluate(), сразу возвращающий JSON-значение результата (result.value), а не весь конверт RemoteObject. contextId — см. evaluate().


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `expression` (`string`) — исполняемое JS-выражение.
- `awaitPromise`, по умолчанию `false`
- `contextId`, по умолчанию `0`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let value = await evaluateValue(session, "2 + 2")
echo value # выводит 4
```


### `callFunctionOn` — runtime.nim


```nim
proc callFunctionOn*(session: CDPSession, objectId: string, functionDeclaration: string, arguments: seq[JsonNode] = @[], awaitPromise = false): Future[JsonNode] {.async.}
```


**Что делает.** Вызывает функцию в контексте конкретного объекта (например, DOM-узла, полученного через DOM.resolveNode) — используется для click()/focus()/value= и т.п. без глобального querySelector.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `objectId` (`string`) — идентификатор JS-объекта на стороне браузера (Runtime.RemoteObject.objectId) — из `evaluate()`/`resolveNode()`.
- `functionDeclaration` (`string`) — исходный код функции (например, "function() { ... }"), вызываемой в контексте объекта objectId.
- `arguments` (`seq[JsonNode]`), по умолчанию `@[]`
- `awaitPromise`, по умолчанию `false`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let
  remoteObj = await resolveNode(session, nodeId)
  res = await callFunctionOn(session, getStr(remoteObj["objectId"]), "function() { return this.tagName; }")
echo res["result"]["value"] # выводит "BUTTON"
```


### `getProperties` — runtime.nim


```nim
proc getProperties*(session: CDPSession, objectId: string, ownProperties = true): Future[JsonNode] {.async.}
```


**Что делает.** Список свойств объекта (аналог Object.getOwnPropertyNames + доступ к значениям) — используется, когда нужно инспектировать произвольный RemoteObject, не сериализуя его целиком в JSON.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `objectId` (`string`) — идентификатор JS-объекта на стороне браузера (Runtime.RemoteObject.objectId) — из `evaluate()`/`resolveNode()`.
- `ownProperties`, по умолчанию `true`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let props = await getProperties(session, objectId)
echo len(props["result"]) # выводит количество собственных свойств объекта
```


### `releaseObject` — runtime.nim


```nim
proc releaseObject*(session: CDPSession, objectId: string) {.async.}
```


**Что делает.** Освобождает RemoteObject на стороне браузера. RemoteObject'ы, полученные без returnByValue (например, из resolveNode), держат ссылку на живой JS-объект, пока их явно не отпустить — на долгоживущей сессии с большим числом evaluate() их стоит убирать.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `objectId` (`string`) — идентификатор JS-объекта на стороне браузера (Runtime.RemoteObject.objectId) — из `evaluate()`/`resolveNode()`.


**Пример:**

```nim
await releaseObject(session, objectId)
echo "объект освобождён" # выводит "объект освобождён"
```


### `releaseObjectGroup` — runtime.nim


```nim
proc releaseObjectGroup*(session: CDPSession, objectGroup: string) {.async.}
```


**Что делает.** Как releaseObject(), но разом для всех объектов, полученных с общим "objectGroup" (см. параметр objectGroup у Runtime.evaluate — здесь не обёрнутый, так как childtear.nim им не пользуется).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `objectGroup` (`string`) — имя группы объектов, переданное в параметре objectGroup при их получении (например, у Runtime.evaluate).


**Пример:**

```nim
await releaseObjectGroup(session, "childtear-temp")
echo "группа объектов освобождена" # выводит "группа объектов освобождена"
```


### `discardConsoleEntries` — runtime.nim


```nim
proc discardConsoleEntries*(session: CDPSession) {.async.}
```


**Что делает.** Очищает буфер уже накопленных сообщений консоли на стороне браузера (аналог кнопки "Clear console" в DevTools).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await discardConsoleEntries(session)
echo "буфер консоли очищен" # выводит "буфер консоли очищен"
```


### `awaitPromise` — runtime.nim


```nim
proc awaitPromise*(session: CDPSession, promiseObjectId: string, returnByValue = true): Future[JsonNode] {.async.}
```


**Что делает.** Дожидается разрешения промиса (RemoteObject которого уже получен, например, через evaluate(expr, awaitPromise=false)) и возвращает его итоговое значение.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `promiseObjectId` (`string`) — objectId промиса, уже полученный ранее (например, из evaluate() без awaitPromise).
- `returnByValue`, по умолчанию `true`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let
  promiseRes = await evaluate(session, "fetch('/api/data').then(r => r.json())", awaitPromise = false, returnByValue = false)
  resolved = await awaitPromise(session, getStr(promiseRes["result"]["objectId"]))
echo resolved["result"]["value"] # выводит распакованное значение промиса, например {"ok": true}
```


### `addBinding` — runtime.nim


```nim
proc addBinding*(session: CDPSession, name: string, executionContextName = ""): Future[void] {.async.}
```


**Что делает.** Добавляет глобальную функцию `name` в window каждого контекста — её вызов из JS страницы приходит сюда событием "Runtime.bindingCalled". Это низкоуровневая основа для Tab.exposeFunction() в childtear.nim (аналог page.exposeFunction() в Puppeteer).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `name` (`string`) — имя глобальной функции, добавляемой в window каждого execution context.
- `executionContextName`, по умолчанию `""`


**Возвращает:** `Future[void]`


**Пример:**

```nim
await addBinding(session, "nimCallback")
echo "мост создан" # выводит "мост создан" — теперь window.nimCallback(x) в JS шлёт событие Runtime.bindingCalled
```


### `removeBinding` — runtime.nim


```nim
proc removeBinding*(session: CDPSession, name: string) {.async.}
```


**Что делает.** Убирает функцию, добавленную addBinding() — сам JS-шим в window (если он уже был инжектирован в childtear.exposeFunction()) при этом не удаляется, только низкоуровневый мост перестаёт работать.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `name` (`string`) — имя функции, ранее добавленной addBinding().


**Пример:**

```nim
await removeBinding(session, "nimCallback")
echo "мост убран" # выводит "мост убран"
```


---

## Домен Input — мышь, клавиатура, тач

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Input/ — низкоуровневая генерация событий ввода, из которых собраны click()/fill() и т.п. в childtear.nim.


### `dispatchMouseEvent` — input.nim


```nim
proc dispatchMouseEvent*(session: CDPSession, kind: string, x, y: float, button = "left", clickCount = 1, deltaX = 0.0, deltaY = 0.0, buttons = 0) {.async.}
```


**Что делает.** kind: "mousePressed" | "mouseReleased" | "mouseMoved" | "mouseWheel". deltaX/deltaY используются только для "mouseWheel".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `kind` (`string`) — "mousePressed" | "mouseReleased" | "mouseMoved" | "mouseWheel".
- `x` (`float`) — координата по горизонтали в системе координат страницы (CSS-пиксели от левого края вьюпорта).
- `y` (`float`) — координата по вертикали в системе координат страницы (CSS-пиксели от верхнего края вьюпорта).
- `button`, по умолчанию `"left"`
- `clickCount`, по умолчанию `1`
- `deltaX`, по умолчанию `0.0`
- `deltaY`, по умолчанию `0.0`
- `buttons`, по умолчанию `0` — битовая маска удерживаемых кнопок (левая = 1, правая = 2, средняя = 4). Для перетаскивания передавайте `buttons = 1` в каждом `mouseMoved` между нажатием и отпусканием: обработчики `pointermove`/`mousemove` проверяют `event.buttons`.


**Пример:**

```nim
await dispatchMouseEvent(session, "mousePressed", 100.0, 200.0, button = "left", clickCount = 1)
await dispatchMouseEvent(session, "mouseReleased", 100.0, 200.0, button = "left", clickCount = 1)
echo "клик отправлен" # выводит "клик отправлен"
```


### `click` — input.nim


```nim
proc click*(session: CDPSession, x, y: float, holdMs = 70) {.async.}
```


**Что делает.** Полный клик = перемещение курсора + нажатие + отпускание кнопки, в тех же координатах, что видит сама страница (viewport-относительные).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `x` (`float`) — координата по горизонтали в системе координат страницы (CSS-пиксели от левого края вьюпорта).
- `y` (`float`) — координата по вертикали в системе координат страницы (CSS-пиксели от верхнего края вьюпорта).
- `holdMs` (`int`, по умолчанию `70`) — пауза между `mousePressed` и `mouseReleased`: некоторые страницы фильтруют клики с нулевой задержкой между press/release как "не настоящие" (защита от кликджекинга/скликивания), поэтому задержка проставлена безусловно, а не только под конкретный сайт.


**Пример:**

```nim
await click(session, 150.0, 250.0)
echo "клик по точке (150, 250)" # выводит "клик по точке (150, 250)"
```


### `moveMouse` — input.nim


```nim
proc moveMouse*(session: CDPSession, x, y: float) {.async.}
```


**Что делает.** Только перемещение курсора, без клика — основа hover().


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `x` (`float`) — координата по горизонтали в системе координат страницы (CSS-пиксели от левого края вьюпорта).
- `y` (`float`) — координата по вертикали в системе координат страницы (CSS-пиксели от верхнего края вьюпорта).


**Пример:**

```nim
await moveMouse(session, 400.0, 300.0)
echo "курсор перемещён" # выводит "курсор перемещён" — сработают обработчики mouseover/mouseenter
```


### `scroll` — input.nim


```nim
proc scroll*(session: CDPSession, x, y, deltaX, deltaY: float) {.async.}
```


**Что делает.** Эмулирует прокрутку колесом мыши в точке (x, y).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `x` (`float`) — координата по горизонтали в системе координат страницы (CSS-пиксели от левого края вьюпорта).
- `y` (`float`) — координата по вертикали в системе координат страницы (CSS-пиксели от верхнего края вьюпорта).
- `deltaX` (`float`) — горизонтальное смещение колеса мыши.
- `deltaY` (`float`) — вертикальное смещение колеса мыши.


**Пример:**

```nim
await scroll(session, 200.0, 200.0, 0.0, 400.0)
echo "прокрутка выполнена" # выводит "прокрутка выполнена" — страница прокручена на 400px вниз
```


### `insertText` — input.nim


```nim
proc insertText*(session: CDPSession, text: string) {.async.}
```


**Что делает.** Вставляет текст в текущий сфокусированный элемент одним куском — быстрее и надёжнее посимвольной эмуляции нажатий клавиш.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `text` (`string`) — текст, вставляемый в текущий сфокусированный элемент одним куском.


**Пример:**

```nim
await insertText(session, "hello@example.com")
echo "текст вставлен" # выводит "текст вставлен" — в текущий фокус, без посимвольных keydown/keyup
```


### `dispatchKeyEvent` — input.nim


```nim
proc dispatchKeyEvent*(session: CDPSession, kind: string, key: string, code = "", text = "", modifiers = 0) {.async.}
```


**Что делает.** kind: "keyDown" | "keyUp" | "rawKeyDown" | "char". modifiers — битовая маска по спецификации CDP: Alt=1, Ctrl=2, Meta=4, Shift=8. text — символ, который должен быть напечатан (для kind == "char"), иначе Chromium может не сгенерировать реальный input-событие.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `kind` (`string`) — "keyDown" | "keyUp" | "rawKeyDown" | "char".
- `key` (`string`) — имя клавиши по номенклатуре CDP, например "Enter", "Tab", "a".
- `code`, по умолчанию `""`
- `text`, по умолчанию `""`
- `modifiers`, по умолчанию `0`


**Пример:**

```nim
await dispatchKeyEvent(session, "keyDown", "Enter", code = "Enter")
await dispatchKeyEvent(session, "keyUp", "Enter", code = "Enter")
echo "клавиша Enter нажата" # выводит "клавиша Enter нажата"
```


### `pressKey` — input.nim


```nim
proc pressKey*(session: CDPSession, key: string, code = "", modifiers = 0) {.async.}
```


**Что делает.** Нажатие и отпускание одной клавиши (например, "Enter", "Tab").


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `key` (`string`) — имя клавиши по номенклатуре CDP, например "Enter", "Tab", "ArrowDown".
- `code`, по умолчанию `""`
- `modifiers`, по умолчанию `0`


**Пример:**

```nim
await pressKey(session, "Tab")
echo "фокус переведён на следующее поле" # выводит "фокус переведён на следующее поле"
```


### `typeChar` — input.nim


```nim
proc typeChar*(session: CDPSession, ch: string) {.async.}
```


**Что делает.** Печатает один символ через настоящее событие клавиатуры "char" — в отличие от insertText(), это то, что видят обработчики keydown/keypress/input страницы по отдельности, а не одним куском. Используется в Tab.type() для эмуляции живого набора текста.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `ch` (`string`) — один символ, печатаемый настоящим событием клавиатуры "char".


**Пример:**

```nim
await typeChar(session, "A")
echo "символ введён" # выводит "символ введён" — полный цикл keydown -> char -> keyup
```


### `dispatchTouchEvent` — input.nim


```nim
proc dispatchTouchEvent*(session: CDPSession, kind: string, touchPoints: seq[JsonNode]) {.async.}
```


**Что делает.** kind: "touchStart" | "touchEnd" | "touchMove" | "touchCancel". touchPoints — например @[%*{"x": 10.0, "y": 20.0}].


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `kind` (`string`) — "touchStart" | "touchEnd" | "touchMove" | "touchCancel".
- `touchPoints` (`seq[JsonNode]`) — точки касания, например @[%*{"x": 10.0, "y": 20.0}].


**Пример:**

```nim
let point = %*{"x": 100, "y": 200}
await dispatchTouchEvent(session, "touchStart", @[point])
await dispatchTouchEvent(session, "touchEnd", @[])
echo "тач-событие отправлено" # выводит "тач-событие отправлено"
```


### `setIgnoreInputEvents` — input.nim


```nim
proc setIgnoreInputEvents*(session: CDPSession, ignore = true) {.async.}
```


**Что делает.** Заставляет браузер игнорировать весь пользовательский ввод — полезно, чтобы фоновая автоматизация не смешивалась с реальными событиями мыши/клавиатуры на этой же машине.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `ignore`, по умолчанию `true`


**Пример:**

```nim
await setIgnoreInputEvents(session, true)
echo "ввод игнорируется" # выводит "ввод игнорируется" — клики/клавиатура больше не доходят до страницы
```


### `cancelDragging` — input.nim


```nim
proc cancelDragging*(session: CDPSession) {.async.}
```


**Что делает.** Отменяет драг, начатый через Input.dispatchDragEvent (низкоуровневый API нативного HTML5 drag-and-drop через сам Input-домен, здесь не обёрнутый — childtear.nim эмулирует HTML5 DnD не им, а прямой JS-симуляцией DragEvent/DataTransfer, см. dragAndDrop(native=true) в childtear.nim). Полезно как аварийный сброс "зависшего" состояния перетаскивания страницы.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await cancelDragging(session)
echo "перетаскивание отменено" # выводит "перетаскивание отменено"
```


---

## Домен Network — сеть, куки, кэш

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Network/ — заголовки, куки, чтение тел ответов, эмуляция условий сети.


### `enable` — network.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**Что делает.** Включает отслеживание сети — обязательно перед подпиской на "Network.responseReceived"/"Network.requestWillBeSent" и т.п., и перед getResponseBody() (без enable() тела ответов не сохраняются).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await enable(session)
echo "домен Network включён" # выводит "домен Network включён"
```


### `disable` — network.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**Что делает.** Отключает отслеживание сети — экономит трафик/память сессии, если сетевые события больше не нужны.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await disable(session)
echo "домен Network выключен" # выводит "домен Network выключен"
```


### `setExtraHTTPHeaders` — network.nim


```nim
proc setExtraHTTPHeaders*(session: CDPSession, headers: JsonNode) {.async.}
```


**Что делает.** headers — плоский JSON-объект вида {"X-My-Header": "value", ...}.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `headers` (`JsonNode`) — плоский JSON-объект вида {"X-My-Header": "value", ...}.


**Пример:**

```nim
await setExtraHTTPHeaders(session, %*{"X-Debug": "1"})
echo "заголовок будет добавляться ко всем запросам" # выводит "заголовок будет добавляться ко всем запросам"
```


### `setUserAgentOverride` — network.nim


```nim
proc setUserAgentOverride*(session: CDPSession, userAgent: string) {.async.}
```


**Что делает.** Deprecated в пользу Emulation.setUserAgentOverride, но всё ещё работает и не требует домена Emulation — оставлено для простых случаев, когда нужен только UA без остальных полей.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `userAgent` (`string`) — строка User-Agent.


**Пример:**

```nim
await setUserAgentOverride(session, "Mozilla/5.0 (compatible; childtear-bot)")
echo "User-Agent подменён" # выводит "User-Agent подменён"
```


### `setCacheDisabled` — network.nim


```nim
proc setCacheDisabled*(session: CDPSession, disabled = true) {.async.}
```


**Что делает.** disabled = true заставляет браузер игнорировать HTTP-кэш при запросах этой вкладки (аналог DevTools -> Network -> "Disable cache") — не путать с clearBrowserCache() (та чистит уже накопленный кэш, эта — не даёт им пользоваться дальше).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `disabled`, по умолчанию `true`


**Пример:**

```nim
await setCacheDisabled(session, true)
echo "HTTP-кэш отключён для вкладки" # выводит "HTTP-кэш отключён для вкладки"
```


### `clearBrowserCache` — network.nim


```nim
proc clearBrowserCache*(session: CDPSession) {.async.}
```


**Что делает.** Полностью очищает HTTP-дисковый кэш браузера. ВНИМАНИЕ: сам CDP не даёт способа ограничить эту команду одной вкладкой или origin'ом — это ограничение протокола, а не childtear.nim; см. Storage.clearDataForOrigin (cdp/domains/storage.nim) для по-настоящему изолированной альтернативы для Cache Storage (кэша service worker'ов — не то же самое, что HTTP-кэш).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await clearBrowserCache(session)
echo "HTTP-кэш браузера очищен" # выводит "HTTP-кэш браузера очищен" — целиком, не только для этой вкладки
```


### `clearBrowserCookies` — network.nim


```nim
proc clearBrowserCookies*(session: CDPSession) {.async.}
```


**Что делает.** Полностью очищает куки браузера — всех вкладок, всех сайтов, всех открытых профилей разом. ВНИМАНИЕ: CDP не даёт отдельной команды "очистить куки одной вкладки/origin'а"; чтобы ограничиться текущим origin'ом, получите список кук через getCookies(urls) и удалите их по одной через deleteCookies() — так и устроен childtear.clearCookiesForOrigin().


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await clearBrowserCookies(session)
echo "куки браузера очищены" # выводит "куки браузера очищены" — целиком, все сайты и вкладки
```


### `getCookies` — network.nim


```nim
proc getCookies*(session: CDPSession, urls: seq[string] = @[]): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Без urls возвращает куки для всех фреймов текущей страницы.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `urls` (`seq[string]`), по умолчанию `@[]`


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let cookies = await getCookies(session, @["https://example.com"])
echo len(cookies) # выводит количество кук, видимых этому URL
```


### `setCookie` — network.nim


```nim
proc setCookie*(session: CDPSession, name, value: string, url = "", domain = "", path = "/", secure = false, httpOnly = false, sameSite = ""): Future[bool] {.async.}
```


**Что делает.** Нужно указать либо url, либо domain — так требует сам протокол.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `name` (`string`) — имя куки.
- `value` (`string`) — значение куки.
- `url`, по умолчанию `""` — адрес страницы или ресурса, к которому относится команда.
- `domain`, по умолчанию `""`
- `path`, по умолчанию `"/"`
- `secure`, по умолчанию `false`
- `httpOnly`, по умолчанию `false`
- `sameSite`, по умолчанию `""`


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let ok = await setCookie(session, "session_id", "abc123", domain = "example.com", secure = true)
echo ok # выводит true, если кука успешно установлена
```


### `setCookies` — network.nim


```nim
proc setCookies*(session: CDPSession, cookies: seq[JsonNode]) {.async.}
```


**Что делает.** Пакетная версия setCookie — каждый элемент это объект вида {"name", "value", "url"/"domain", ...}.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `cookies` (`seq[JsonNode]`) — список объектов вида {"name", "value", "url"/"domain", ...}.


**Пример:**

```nim
let batch = @[%*{"name": "a", "value": "1", "domain": "example.com"},
              %*{"name": "b", "value": "2", "domain": "example.com"}]
await setCookies(session, batch)
echo "куки установлены пакетом" # выводит "куки установлены пакетом"
```


### `deleteCookies` — network.nim


```nim
proc deleteCookies*(session: CDPSession, name: string, url = "", domain = "", path = "") {.async.}
```


**Что делает.** Удаляет куки с именем name, дополнительно отфильтрованные по url/domain/path (нужен хотя бы url либо domain, иначе браузер не знает, к какому сайту относится кука). В отличие от clearBrowserCookies(), это единственный способ удалить куки выборочно, а не все сразу.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `name` (`string`) — имя удаляемой куки.
- `url`, по умолчанию `""` — адрес страницы или ресурса, к которому относится команда.
- `domain`, по умолчанию `""`
- `path`, по умолчанию `""`


**Пример:**

```nim
await deleteCookies(session, "session_id", url = "https://example.com")
echo "кука удалена" # выводит "кука удалена"
```


### `getResponseBody` — network.nim


```nim
proc getResponseBody*(session: CDPSession, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.}
```


**Что делает.** Доступно только для запросов, чьи данные ещё не были "вытолкнуты" из памяти браузера (обычно — пока обработчик Network.loadingFinished ещё не отработал слишком давно).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.


**Возвращает:** `bool]]`


**Пример:**

```nim
let (body, isBase64) = await getResponseBody(session, requestId)
echo isBase64 # выводит false для текстовых ответов (HTML/JSON/текст), true для бинарных
```


### `getRequestPostData` — network.nim


```nim
proc getRequestPostData*(session: CDPSession, requestId: string): Future[string] {.async.}
```


**Что делает.** Тело POST-запроса (например, JSON или form-data), как оно было реально отправлено страницей — доступно только пока Chromium не вытолкнул данные запроса из памяти (тот же принцип, что и у getResponseBody()).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let postData = await getRequestPostData(session, requestId)
echo postData # выводит тело запроса, например "username=andy&password=secret"
```


### `setBlockedURLs` — network.nim


```nim
proc setBlockedURLs*(session: CDPSession, urls: seq[string]) {.async.}
```


**Что делает.** Простая блокировка по маскам ("*ads*", "*.png" и т.п.) — если нужна более гибкая логика (например, решение на лету по каждому запросу), см. cdp/domains/fetch.nim.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `urls` (`seq[string]`) — список масок URL для блокировки, например ["*ads*", "*.png"].


**Пример:**

```nim
await setBlockedURLs(session, @["*.png", "*doubleclick.net*"])
echo "паттерны заблокированы" # выводит "паттерны заблокированы"
```


### `setBypassServiceWorker` — network.nim


```nim
proc setBypassServiceWorker*(session: CDPSession, bypass = true) {.async.}
```


**Что делает.** bypass = true заставляет запросы идти напрямую в сеть, минуя service worker страницы (если он есть), — полезно, когда важно видеть настоящие сетевые ответы, а не то, чем их подменяет кэш service worker'а.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `bypass`, по умолчанию `true`


**Пример:**

```nim
await setBypassServiceWorker(session, true)
echo "service worker обходится" # выводит "service worker обходится" — запросы идут напрямую в сеть
```


### `emulateNetworkConditions` — network.nim


```nim
proc emulateNetworkConditions*(session: CDPSession, offline = false, latencyMs = 0.0, downloadThroughput = -1.0, uploadThroughput = -1.0, connectionType = "") {.async.}
```


**Что делает.** throughput в байтах/сек, -1 — без ограничения. connectionType, например, "cellular3g" — влияет только на navigator.connection.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `offline`, по умолчанию `false`
- `latencyMs`, по умолчанию `0.0`
- `downloadThroughput`, по умолчанию `-1.0`
- `uploadThroughput`, по умолчанию `-1.0`
- `connectionType`, по умолчанию `""`


**Пример:**

```nim
await emulateNetworkConditions(session, offline = false, latencyMs = 300.0,
                                downloadThroughput = 50_000.0, uploadThroughput = 20_000.0)
echo "эмуляция медленной сети включена" # выводит "эмуляция медленной сети включена"
```


---

## Домен Fetch — перехват запросов

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Fetch/ — приостановка запросов на лету с возможностью подменить/заблокировать/продолжить их.


### `enable` — fetch.nim


```nim
proc enable*(session: CDPSession, patterns: seq[string] = @["*"], handleAuthRequests = false) {.async.}
```


**Что делает.** patterns — список URL-масок для перехвата (по умолчанию — все запросы). handleAuthRequests — также перехватывать HTTP Basic/Digest auth-запросы событием "Fetch.authRequired" (см. continueWithAuth).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `patterns` (`seq[string]`), по умолчанию `@["*"]`
- `handleAuthRequests`, по умолчанию `false`


**Пример:**

```nim
await enable(session, @["*"], handleAuthRequests = false)
echo "перехват запросов включён" # выводит "перехват запросов включён"
```


### `disable` — fetch.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**Что делает.** Отключает перехват — все дальнейшие запросы страницы уходят в сеть как обычно, без остановки на "Fetch.requestPaused".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await disable(session)
echo "перехват запросов выключен" # выводит "перехват запросов выключен"
```


### `continueRequest` — fetch.nim


```nim
proc continueRequest*(session: CDPSession, requestId: string, url = "", methodOverride = "", postData = "", headers: JsonNode = nil) {.async.}
```


**Что делает.** Пропускает запрос дальше, при желании подменив URL/метод/тело/заголовки перед тем, как он реально уйдёт в сеть (все параметры необязательны).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.
- `url`, по умолчанию `""` — адрес страницы или ресурса, к которому относится команда.
- `methodOverride`, по умолчанию `""`
- `postData`, по умолчанию `""`
- `headers` (`JsonNode`), по умолчанию `nil`


**Пример:**

```nim
await continueRequest(session, requestId, url = "https://example.com/mocked")
echo "запрос продолжен с изменённым URL" # выводит "запрос продолжен с изменённым URL"
```


### `failRequest` — fetch.nim


```nim
proc failRequest*(session: CDPSession, requestId: string, errorReason = "BlockedByClient") {.async.}
```


**Что делает.** Обрывает запрос с указанной причиной (например, для блокировки рекламы).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.
- `errorReason`, по умолчанию `"BlockedByClient"`


**Пример:**

```nim
await failRequest(session, requestId, "BlockedByClient")
echo "запрос заблокирован" # выводит "запрос заблокирован" — страница увидит сетевую ошибку
```


### `fulfillRequest` — fetch.nim


```nim
proc fulfillRequest*(session: CDPSession, requestId: string, responseCode = 200, body = "", mimeType = "text/plain", extraHeaders: JsonNode = nil) {.async.}
```


**Что делает.** Отвечает на запрос заранее заготовленным содержимым, не обращаясь к сети вовсе — удобно для мокирования API в тестах.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.
- `responseCode`, по умолчанию `200`
- `body`, по умолчанию `""`
- `mimeType`, по умолчанию `"text/plain"`
- `extraHeaders` (`JsonNode`), по умолчанию `nil`


**Пример:**

```nim
await fulfillRequest(session, requestId, responseCode = 200,
                      body = """{"ok": true}""", mimeType = "application/json")
echo "ответ подменён" # выводит "ответ подменён" — страница получит наш JSON вместо настоящего сервера
```


### `getResponseBody` — fetch.nim


```nim
proc getResponseBody*(session: CDPSession, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.}
```


**Что делает.** Тело оригинального ответа сервера для запроса, приостановленного Fetch.requestPaused *после* стадии Response (т.е. когда ответ уже получен, но ещё не отдан странице) — полезно, чтобы прочитать и затем, например, переписать fulfillRequest'ом.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.


**Возвращает:** `bool]]`


**Пример:**

```nim
let (body, isBase64) = await getResponseBody(session, requestId)
echo isBase64 # выводит false/true в зависимости от типа содержимого
```


### `takeResponseBodyAsStream` — fetch.nim


```nim
proc takeResponseBodyAsStream*(session: CDPSession, requestId: string): Future[string] {.async.}
```


**Что делает.** Возвращает handle потока (для больших ответов) — читать его нужно через IO.read с полученным handle.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let streamHandle = await takeResponseBodyAsStream(session, requestId)
echo len(streamHandle) > 0 # выводит true — получен идентификатор потока для IO.read
```


### `continueWithAuth` — fetch.nim


```nim
proc continueWithAuth*(session: CDPSession, requestId: string, response: string, username = "", password = "") {.async.}
```


**Что делает.** response: "Default" | "CancelAuth" | "ProvideCredentials" — ответ на событие "Fetch.authRequired" (требует enable(handleAuthRequests=true)).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `requestId` (`string`) — идентификатор конкретного сетевого запроса — приходит в событиях домена Network/Fetch.
- `response` (`string`) — "Default" | "CancelAuth" | "ProvideCredentials".
- `username`, по умолчанию `""`
- `password`, по умолчанию `""`


**Пример:**

```nim
await continueWithAuth(session, requestId, "ProvideCredentials", "andy", "secret")
echo "учётные данные отправлены" # выводит "учётные данные отправлены"
```


---

## Домен Emulation — подмена окружения

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Emulation/ — вьюпорт, User-Agent, геолокация, часовой пояс, CPU-throttling и т.п.


### `setDeviceMetricsOverride` — emulation.nim


```nim
proc setDeviceMetricsOverride*(session: CDPSession, width, height: int, deviceScaleFactor = 1.0, mobile = false) {.async.}
```


**Что делает.** Подделывает размеры вьюпорта и плотность пикселей — основа page.setViewport() в Puppeteer. width/height = 0 сбрасывает override на реальный размер окна.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `width` (`int`) — ширина вьюпорта; 0 сбрасывает override.
- `height` (`int`) — высота вьюпорта; 0 сбрасывает override.
- `deviceScaleFactor`, по умолчанию `1.0`
- `mobile`, по умолчанию `false`


**Пример:**

```nim
await setDeviceMetricsOverride(session, 390, 844, deviceScaleFactor = 3.0, mobile = true)
echo "вьюпорт подменён под iPhone" # выводит "вьюпорт подменён под iPhone"
```


### `clearDeviceMetricsOverride` — emulation.nim


```nim
proc clearDeviceMetricsOverride*(session: CDPSession) {.async.}
```


**Что делает.** Сбрасывает override, сделанный setDeviceMetricsOverride(), — размер вьюпорта и deviceScaleFactor снова определяются реальным окном браузера.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await clearDeviceMetricsOverride(session)
echo "override вьюпорта снят" # выводит "override вьюпорта снят"
```


### `setUserAgentOverride` — emulation.nim


```nim
proc setUserAgentOverride*(session: CDPSession, userAgent: string, acceptLanguage = "", platform = "") {.async.}
```


**Что делает.** Актуальный (не-deprecated) способ подменить User-Agent — в отличие от Network.setUserAgentOverride, также умеет acceptLanguage/platform (влияет на navigator.language и navigator.platform).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `userAgent` (`string`) — строка User-Agent.
- `acceptLanguage`, по умолчанию `""`
- `platform`, по умолчанию `""`


**Пример:**

```nim
await setUserAgentOverride(session, "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", platform = "iPhone")
echo "User-Agent и platform подменены" # выводит "User-Agent и platform подменены"
```


### `setGeolocationOverride` — emulation.nim


```nim
proc setGeolocationOverride*(session: CDPSession, latitude, longitude: float, accuracy = 1.0) {.async.}
```


**Что делает.** Подделывает координаты navigator.geolocation — страница получает их как настоящий ответ геолокации, без системного диалога разрешения (в headless-режиме такого диалога и так нет).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `latitude` (`float`) — широта в градусах.
- `longitude` (`float`) — долгота в градусах.
- `accuracy`, по умолчанию `1.0`


**Пример:**

```nim
await setGeolocationOverride(session, 55.7558, 37.6173, accuracy = 10.0)
echo "координаты подменены на Москву" # выводит "координаты подменены на Москву"
```


### `clearGeolocationOverride` — emulation.nim


```nim
proc clearGeolocationOverride*(session: CDPSession) {.async.}
```


**Что делает.** Сбрасывает override, сделанный setGeolocationOverride() — geolocation после этого либо недоступна, либо использует реальное окружение браузера.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await clearGeolocationOverride(session)
echo "override геолокации снят" # выводит "override геолокации снят"
```


### `setTimezoneOverride` — emulation.nim


```nim
proc setTimezoneOverride*(session: CDPSession, timezoneId: string) {.async.}
```


**Что делает.** timezoneId — IANA-имя, например "Europe/Amsterdam".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `timezoneId` (`string`) — имя часового пояса IANA, например "Europe/Amsterdam".


**Пример:**

```nim
await setTimezoneOverride(session, "Europe/Amsterdam")
echo "часовой пояс подменён" # выводит "часовой пояс подменён"
```


### `setLocaleOverride` — emulation.nim


```nim
proc setLocaleOverride*(session: CDPSession, locale = "") {.async.}
```


**Что делает.** Пустая строка сбрасывает override на системную локаль.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `locale`, по умолчанию `""`


**Пример:**

```nim
await setLocaleOverride(session, "nl-NL")
echo "локаль подменена" # выводит "локаль подменена"
```


### `setScriptExecutionDisabled` — emulation.nim


```nim
proc setScriptExecutionDisabled*(session: CDPSession, disabled = true) {.async.}
```


**Что делает.** Полностью включает/выключает выполнение JS на странице (аналог настройки браузера "разрешить JavaScript"); полезно, чтобы проверить, как выглядит/работает страница без скриптов (progressive enhancement).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `disabled`, по умолчанию `true`


**Пример:**

```nim
await setScriptExecutionDisabled(session, true)
echo "выполнение JS отключено" # выводит "выполнение JS отключено"
```


### `setEmulatedMedia` — emulation.nim


```nim
proc setEmulatedMedia*(session: CDPSession, media = "", features: JsonNode = newJArray()) {.async.}
```


**Что делает.** media: "screen"/"print"/"" (сбросить). features — массив вида [{"name": "prefers-color-scheme", "value": "dark"}].


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `media`, по умолчанию `""`
- `features` (`JsonNode`), по умолчанию `newJArray()`


**Пример:**

```nim
await setEmulatedMedia(session, media = "print")
echo "эмуляция медиа-типа print включена" # выводит "эмуляция медиа-типа print включена"
```


### `setCPUThrottlingRate` — emulation.nim


```nim
proc setCPUThrottlingRate*(session: CDPSession, rate: float) {.async.}
```


**Что делает.** rate = 1 — без замедления, rate = 4 — CPU в 4 раза "медленнее".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `rate` (`float`) — коэффициент замедления CPU: 1 — без изменений, 4 — в 4 раза медленнее.


**Пример:**

```nim
await setCPUThrottlingRate(session, 4.0)
echo "CPU замедлен в 4 раза" # выводит "CPU замедлен в 4 раза"
```


### `setDefaultBackgroundColorOverride` — emulation.nim


```nim
proc setDefaultBackgroundColorOverride*(session: CDPSession, r, g, b: int, a = 1.0) {.async.}
```


**Что делает.** Полезно для скриншотов с прозрачным фоном: a = 0.


**Разбор реализации.** У CDP нет отдельной команды "снять override фона" — по спецификации протокола, вызов `Emulation.setDefaultBackgroundColorOverride` вовсе без параметра `color` как раз и означает "убрать override". `clearDefaultBackgroundColorOverride()` дёргает ровно ту же команду, просто без параметров, а не какой-то другой протокольный метод.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `r` (`int`) — компонента red, 0–255.
- `g` (`int`) — компонента green, 0–255.
- `b` (`int`) — компонента blue, 0–255.
- `a`, по умолчанию `1.0`


**Пример:**

```nim
await setDefaultBackgroundColorOverride(session, 0, 0, 0, a = 0.0)
echo "фон страницы стал прозрачным" # выводит "фон страницы стал прозрачным"
```


### `clearDefaultBackgroundColorOverride` — emulation.nim


```nim
proc clearDefaultBackgroundColorOverride*(session: CDPSession) {.async.}
```


**Что делает.** Сбрасывает override фона, сделанный setDefaultBackgroundColorOverride(). У CDP нет отдельной команды "clear" для этого override — по спецификации протокола, вызов Emulation.setDefaultBackgroundColorOverride вовсе без параметра "color" как раз и означает "снять override", поэтому здесь сознательно вызывается та же самая команда, но без параметров, а не другой метод.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await clearDefaultBackgroundColorOverride(session)
echo "override фона снят" # выводит "override фона снят"
```


### `setTouchEmulationEnabled` — emulation.nim


```nim
proc setTouchEmulationEnabled*(session: CDPSession, enabled = true, maxTouchPoints = 1) {.async.}
```


**Что делает.** Подделывает поддержку сенсорного ввода (navigator.maxTouchPoints, 'ontouchstart' in window и т.п.) — не эмулирует сами тач-события, только признаки их поддержки; сами события шлются через Input.dispatchTouchEvent (см. input.nim).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `enabled`, по умолчанию `true`
- `maxTouchPoints`, по умолчанию `1`


**Пример:**

```nim
await setTouchEmulationEnabled(session, true, maxTouchPoints = 5)
echo "признаки touch-устройства включены" # выводит "признаки touch-устройства включены"
```


---

## Домен Target — вкладки и профили

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Target/ — протокольный аналог HTTP /json/*, плюс изолированные профили и мультиплексирование сессий.


### `getTargets` — target.nim


```nim
proc getTargets*(session: CDPSession): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Список всех целей (вкладок, воркеров и т.д.), видимых браузеру — аналог HTTP /json/list, но по протоколу.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let targets = await getTargets(session)
echo len(targets) # выводит количество видимых браузеру целей
```


### `getTargetInfo` — target.nim


```nim
proc getTargetInfo*(session: CDPSession, targetId = ""): Future[JsonNode] {.async.}
```


**Что делает.** Без targetId возвращает информацию о цели, к которой относится сама сессия (актуально при вызове на attached-сессии).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `targetId`, по умолчанию `""` — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let info = await getTargetInfo(session)
echo info["type"] # выводит "page" для обычной вкладки
```


### `setDiscoverTargets` — target.nim


```nim
proc setDiscoverTargets*(session: CDPSession, discover = true) {.async.}
```


**Что делает.** Включает уведомления Target.targetCreated/targetInfoChanged/targetDestroyed обо всех целях браузера, даже тех, к которым мы не присоединены.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `discover`, по умолчанию `true`


**Пример:**

```nim
await setDiscoverTargets(session, true)
echo "уведомления о новых целях включены" # выводит "уведомления о новых целях включены" — придут Target.targetCreated
```


### `activateTarget` — target.nim


```nim
proc activateTarget*(session: CDPSession, targetId: string) {.async.}
```


**Что делает.** Делает вкладку активной на экране (аналог Page.bringToFront, но вызывается с browser-level сессии по targetId, без attach).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `targetId` (`string`) — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.


**Пример:**

```nim
await activateTarget(session, targetId)
echo "цель активирована" # выводит "цель активирована"
```


### `createTarget` — target.nim


```nim
proc createTarget*(session: CDPSession, url: string, width = 0, height = 0, browserContextId = "", newWindow = false, background = false): Future[string] {.async.}
```


**Что делает.** Создаёт новую вкладку и возвращает её targetId. browserContextId позволяет открыть вкладку в изолированном (инкогнито-подобном) профиле, созданном через createBrowserContext().


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `url` (`string`) — адрес страницы или ресурса, к которому относится команда.
- `width`, по умолчанию `0`
- `height`, по умолчанию `0`
- `browserContextId`, по умолчанию `""` — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.
- `newWindow`, по умолчанию `false`
- `background`, по умолчанию `false`


**Возвращает:** `Future[string]`


**Пример:**

```nim
let newTargetId = await createTarget(session, "https://example.com", width = 1280, height = 800)
echo len(newTargetId) > 0 # выводит true
```


### `closeTarget` — target.nim


```nim
proc closeTarget*(session: CDPSession, targetId: string) {.async.}
```


**Что делает.** Закрывает вкладку/цель по её id — протокольный аналог HTTP /json/close/`<id>` (см. cdp/browser.nim -> closeTarget()); childtear.nim по умолчанию использует именно HTTP-вариант (см. заголовок модуля), этот остаётся для тех, кто явно работает через домен Target.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `targetId` (`string`) — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.


**Пример:**

```nim
await closeTarget(session, targetId)
echo "цель закрыта" # выводит "цель закрыта"
```


### `createBrowserContext` — target.nim


```nim
proc createBrowserContext*(session: CDPSession): Future[string] {.async.}
```


**Что делает.** Создаёт изолированный профиль (свои куки/localStorage/кэш, отдельно от основного и других контекстов) — аналог browser.createIncognitoBrowserContext() в Puppeteer. Возвращает browserContextId для передачи в createTarget().


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[string]`


**Пример:**

```nim
let ctxId = await createBrowserContext(session)
echo len(ctxId) > 0 # выводит true — создан изолированный профиль (инкогнито-подобный)
```


### `getBrowserContexts` — target.nim


```nim
proc getBrowserContexts*(session: CDPSession): Future[seq[string]] {.async.}
```


**Что делает.** Список id всех изолированных профилей (см. createBrowserContext()), созданных за время жизни браузера и ещё не уничтоженных.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[seq[string]]`


**Пример:**

```nim
let contexts = await getBrowserContexts(session)
echo len(contexts) # выводит количество созданных ранее изолированных профилей
```


### `disposeBrowserContext` — target.nim


```nim
proc disposeBrowserContext*(session: CDPSession, browserContextId: string) {.async.}
```


**Что делает.** Уничтожает профиль и закрывает все его вкладки.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `browserContextId` (`string`) — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.


**Пример:**

```nim
await disposeBrowserContext(session, ctxId)
echo "профиль уничтожен" # выводит "профиль уничтожен" — вместе со всеми его вкладками, куками и т.п.
```


### `attachToTarget` — target.nim


```nim
proc attachToTarget*(session: CDPSession, targetId: string, flatten = true): Future[string] {.async.}
```


**Что делает.** Присоединяется к цели и возвращает sessionId — в "плоском" (flatten) режиме этот sessionId нужно прикладывать к каждой последующей команде (см. callWithSession ниже), что позволяет мультиплексировать несколько вкладок через одно browser-level WebSocket-соединение.


**Разбор реализации.** При `flatten = true` (значение по умолчанию и единственный режим, которым пользуется `childtear.nim`) все дальнейшие команды к присоединённой вкладке шлются через ТУ ЖЕ browser-level сессию, но с полем `"sessionId"`, равным возвращённому значению (см. `callWithSession()`), а входящие события этой вкладки помечаются тем же `"sessionId"` в конверте — так несколько вкладок мультиплексируются через одно WebSocket-соединение вместо отдельного сокета на каждую.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `targetId` (`string`) — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.
- `flatten`, по умолчанию `true`


**Возвращает:** `Future[string]`


**Пример:**

```nim
let attachedSessionId = await attachToTarget(session, targetId, flatten = true)
echo len(attachedSessionId) > 0 # выводит true
```


### `detachFromTarget` — target.nim


```nim
proc detachFromTarget*(session: CDPSession, sessionId: string) {.async.}
```


**Что делает.** Отсоединяется от цели, к которой ранее присоединились через attachToTarget() — сама вкладка при этом не закрывается, только прекращается мультиплексирование её команд/событий через sessionId.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `sessionId` (`string`) — идентификатор сессии в "плоском" (flattened) режиме мультиплексирования — из ответа `attachToTarget()`.


**Пример:**

```nim
await detachFromTarget(session, attachedSessionId)
echo "отсоединено от цели" # выводит "отсоединено от цели"
```


### `setAutoAttach` — target.nim


```nim
proc setAutoAttach*(session: CDPSession, autoAttach = true, waitForDebuggerOnStart = false) {.async.}
```


**Что делает.** Подписывает на автоматическое присоединение ко всем новым целям — удобно, чтобы ловить всплывающие окна (window.open, target=_blank).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `autoAttach`, по умолчанию `true`
- `waitForDebuggerOnStart`, по умолчанию `false`


**Пример:**

```nim
await setAutoAttach(session, true, waitForDebuggerOnStart = false)
echo "автоприсоединение включено" # выводит "автоприсоединение включено" — новые вкладки/воркеры авто-attach
```


### `callWithSession` — target.nim


```nim
proc callWithSession*(session: CDPSession, sessionId: string, meth: string, params: JsonNode = newJObject()): Future[JsonNode] {.async.}
```


**Что делает.** Отправляет команду конкретной присоединённой (attachToTarget) вкладке через общее browser-level соединение, в "плоском" режиме (см. https://chromedevtools.github.io/devtools-protocol/#flattened). Домены page/dom/runtime/... рассчитаны на отдельный WebSocket на вкладку, поэтому это — самостоятельный низкоуровневый примитив для тех, кто явно выбирает мультиплексирование одним соединением.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `sessionId` (`string`) — идентификатор сессии в "плоском" (flattened) режиме мультиплексирования — из ответа `attachToTarget()`.
- `meth` (`string`) — имя команды протокола, например "Page.navigate".
- `params` (`JsonNode`), по умолчанию `newJObject()`


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let res = await callWithSession(browserSession, attachedSessionId, "Page.navigate", %*{"url": "https://example.com"})
echo hasKey(res, "frameId") # выводит true
```


---

## Домен Browser — окно и разрешения

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Browser/ — размер/состояние окна ОС, разрешения (геолокация, уведомления и т.п.) на уровне браузера.


### `getVersion` — browserdomain.nim


```nim
proc getVersion*(session: CDPSession): Future[JsonNode] {.async.}
```


**Что делает.** Дублирует то же самое, что отдаёт HTTP /json/version, но по протоколу (полезно, если уже есть открытая browser-level сессия).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let ver = await getVersion(session)
echo ver["product"] # выводит что-то вроде "HeadlessChrome/120.0.0.0"
```


### `close` — browserdomain.nim


```nim
proc close*(session: CDPSession) {.async.}
```


**Что делает.** Завершает процесс браузера целиком (все вкладки, все контексты).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await close(session)
echo "браузер закрыт" # выводит "браузер закрыт" — целиком, все вкладки
```


### `setDownloadBehavior` — browserdomain.nim


```nim
proc setDownloadBehavior*(session: CDPSession, behavior: string, downloadPath = "", browserContextId = "") {.async.}
```


**Что делает.** behavior: "deny" | "allow" | "allowAndName" | "default".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `behavior` (`string`) — "deny" | "allow" | "allowAndName" | "default".
- `downloadPath`, по умолчанию `""`
- `browserContextId`, по умолчанию `""` — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.


**Пример:**

```nim
await setDownloadBehavior(session, "allow", downloadPath = "/tmp/downloads")
echo "поведение скачивания настроено на уровне браузера" # выводит "поведение скачивания настроено на уровне браузера"
```


### `getWindowForTarget` — browserdomain.nim


```nim
proc getWindowForTarget*(session: CDPSession, targetId = ""): Future[JsonNode] {.async.}
```


**Что делает.** Возвращает {"windowId", "bounds"} — нужно для setWindowBounds.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `targetId`, по умолчанию `""` — идентификатор цели (вкладки/воркера) — из `listTargets()`/`getTargets()`/события `Target.targetCreated`.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let win = await getWindowForTarget(session, targetId)
echo win["windowId"] # выводит числовой id окна, которому принадлежит вкладка
```


### `setWindowBounds` — browserdomain.nim


```nim
proc setWindowBounds*(session: CDPSession, windowId: int, bounds: JsonNode) {.async.}
```


**Что делает.** bounds — например {"width": 1280, "height": 800} или {"windowState": "maximized"}.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `windowId` (`int`) — id окна, полученный из getWindowForTarget().
- `bounds` (`JsonNode`) — например {"width": 1280, "height": 800} или {"windowState": "maximized"}.


**Пример:**

```nim
let win = await getWindowForTarget(session, targetId)
await setWindowBounds(session, win["windowId"].getInt, %*{"width": 1280, "height": 800})
echo "размер окна изменён" # выводит "размер окна изменён"
```


### `resetPermissions` — browserdomain.nim


```nim
proc resetPermissions*(session: CDPSession, browserContextId = "") {.async.}
```


**Что делает.** Сбрасывает все разрешения, выданные через grantPermissions(), назад к дефолтному поведению браузера (обычно — "спрашивать"/"отказывать", в headless-режиме без UI разрешения без явного grant обычно просто недоступны сайту).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `browserContextId`, по умолчанию `""` — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.


**Пример:**

```nim
await resetPermissions(session)
echo "разрешения сброшены" # выводит "разрешения сброшены"
```


### `grantPermissions` — browserdomain.nim


```nim
proc grantPermissions*(session: CDPSession, permissions: seq[string], origin = "", browserContextId = "") {.async.}
```


**Что делает.** permissions — например @["geolocation", "notifications"].


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `permissions` (`seq[string]`) — имена разрешений, например @["geolocation", "notifications"].
- `origin`, по умолчанию `""` — origin в формате "схема://хост[:порт]", например "https://example.com".
- `browserContextId`, по умолчанию `""` — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.


**Пример:**

```nim
await grantPermissions(session, @["geolocation", "notifications"], origin = "https://example.com")
echo "разрешения выданы" # выводит "разрешения выданы"
```


---

## Домен Storage — данные конкретного origin'а

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Storage/ — точечная, per-origin очистка данных, в отличие от Network.clearBrowserCache()/clearBrowserCookies().


### `clearDataForOrigin` — storage.nim


```nim
proc clearDataForOrigin*(session: CDPSession, origin: string, storageTypes = AllStorageTypes) {.async.}
```


**Что делает.** Очищает перечисленные в storageTypes виды данных (через запятую), но только для указанного origin'а (схема+хост+порт, например "https://example.com") — в отличие от Network.clearBrowserCookies()/ clearBrowserCache(), не трогает остальные сайты и вкладки браузера. ВАЖНО: "cache_storage" здесь — это Cache API (кэш service worker'ов), а не HTTP-дисковый кэш браузера; сам CDP не даёт способа очистить именно HTTP-кэш в границах одного origin'а — это ограничение протокола (см. Network.clearBrowserCache()), а не childtear.nim.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `origin` (`string`) — origin в формате "схема://хост[:порт]", например "https://example.com".
- `storageTypes`, по умолчанию `AllStorageTypes`


**Пример:**

```nim
await clearDataForOrigin(session, "https://example.com", "cookies,cache_storage")
echo "данные origin'а очищены" # выводит "данные origin'а очищены"
```


### `getCookies` — storage.nim


```nim
proc getCookies*(session: CDPSession, browserContextId = ""): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Куки всего изолированного профиля browserContextId (или основного профиля, если не указан) — в отличие от Network.getCookies(), не привязан к конкретной вкладке/её фреймам.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `browserContextId`, по умолчанию `""` — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let cookies = await storageApi.getCookies(session)
echo len(cookies) # выводит количество кук во всём профиле браузера
```


### `clearCookies` — storage.nim


```nim
proc clearCookies*(session: CDPSession, browserContextId = "") {.async.}
```


**Что делает.** Очищает куки всего изолированного профиля browserContextId (или основного профиля) — как и Network.clearBrowserCookies(), это операция на уровне профиля целиком, а не одного origin'а; для очистки конкретного origin'а используйте clearDataForOrigin() с storageTypes = "cookies".


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).
- `browserContextId`, по умолчанию `""` — идентификатор изолированного профиля, полученный из `createBrowserContext()`; пустая строка — основной профиль.


**Пример:**

```nim
await storageApi.clearCookies(session)
echo "куки профиля очищены" # выводит "куки профиля очищены"
```


---

## Домен Log — консольные записи браузера

Протокольная документация домена: https://chromedevtools.github.io/devtools-protocol/tot/Log/ — единый поток записей лога браузера, включая сетевые/security-предупреждения.


### `enable` — log.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**Что делает.** Включает домен Log — обязательно перед подпиской на "Log.entryAdded" (без него события не приходят).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await enable(session)
echo "домен Log включён" # выводит "домен Log включён"
```


### `disable` — log.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**Что делает.** Отключает домен Log — подписка на "Log.entryAdded" перестаёт получать новые записи.


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await disable(session)
echo "домен Log выключен" # выводит "домен Log выключен"
```


### `clear` — log.nim


```nim
proc clear*(session: CDPSession) {.async.}
```


**Что делает.** Очищает буфер уже накопленных записей лога на стороне браузера (на уже отправленные через "Log.entryAdded" события не влияет — только на то, что браузер хранит внутри себя).


**Параметры:**

- `session` (`CDPSession`) — CDP-сессия, полученная через `newCDPSession()` — обычной вкладочной или browser-level (см. раздел II).


**Пример:**

```nim
await clear(session)
echo "буфер лога браузера очищен" # выводит "буфер лога браузера очищен"
```


---
## Практические рецепты

### Открыть вкладку и дождаться загрузки "вручную"

Без высокоуровневого `childtear.goto()` — то, что происходит у него под капотом:

```nim
import std/[asyncdispatch, json]
import cdp/browser, cdp/transport
import cdp/domains/page as pageApi

proc main() {.async.} =
  let
    bc = newBrowserConnection()
    info = await newTarget(bc, "about:blank")
    tabs = await listTargets(bc)
  var wsUrl = ""
  for t in tabs:
    if getStr(t["id"]) == getStr(info["id"]):
      wsUrl = getStr(t["webSocketDebuggerUrl"])
  let session = await newCDPSession(wsUrl)
  await pageApi.enable(session)
  discard await pageApi.navigate(session, "https://example.com")
  discard await waitForEvent(session, "Page.loadEventFired", timeoutMs = 10_000)
  echo "страница загружена" # выводит "страница загружена"
  await close(session)

waitFor main()
```

---

### Достать текст элемента через Runtime, а не готовый getText()

```nim
import std/[asyncdispatch, json]
import cdp/domains/runtime as runtimeApi

proc rawGetText(session: CDPSession, selector: string): Future[string] {.async.} =
  let
    sel = %selector
    js = "document.querySelector(" & $sel & ").innerText"
    value = await runtimeApi.evaluateValue(session, js)
  result = getStr(value)

proc main() {.async.} =
  let text = await rawGetText(session, "h1")
  echo text # выводит текст первого заголовка на странице
```

---

### Найти узел через DOM и кликнуть по нему через Input

```nim
import std/asyncdispatch
import cdp/domains/[dom, input]

proc main() {.async.} =
  let
    doc = await dom.getDocument(session)
    nodeId = await dom.querySelector(session, doc["root"]["nodeId"].getInt, "button.submit")
    box = await dom.getBoxModel(session, nodeId)
    quad = box["content"]
    centerX = (quad[0].getFloat + quad[4].getFloat) / 2.0
    centerY = (quad[1].getFloat + quad[5].getFloat) / 2.0
  await input.click(session, centerX, centerY)
  echo "клик выполнен по центру кнопки" # выводит "клик выполнен по центру кнопки"
```

---

### Перехватить и подменить ответ конкретного API-запроса

```nim
import std/[asyncdispatch, json]
import cdp/transport
import cdp/domains/fetch as fetchApi

proc main() {.async.} =
  await fetchApi.enable(session, @["*api/config*"])
  proc onPaused(params: JsonNode) {.gcsafe.} =
    let requestId = getStr(params["requestId"])
    asyncCheck fetchApi.fulfillRequest(session, requestId, responseCode = 200,
      body = \"\"\"{"featureFlag": true}\"\"\", mimeType = "application/json")
  on(session, "Fetch.requestPaused", onPaused)
  echo "перехват настроен" # выводит "перехват настроен"
```

---

### Присоединиться ко всем новым вкладкам браузера автоматически

```nim
import std/[asyncdispatch, json]
import cdp/browser, cdp/transport
import cdp/domains/target as targetApi

proc main() {.async.} =
  let
    bc = newBrowserConnection()
    ver = await browserVersion(bc)
    browserSession = await newCDPSession(getStr(ver["webSocketDebuggerUrl"]))
  await targetApi.setAutoAttach(browserSession, true, waitForDebuggerOnStart = false)
  proc onAttached(params: JsonNode) {.gcsafe.} =
    echo "автоприсоединились к новой вкладке" # выводит при каждой новой вкладке
  on(browserSession, "Target.attachedToTarget", onAttached)
```

---

### Очистить данные конкретного сайта, не трогая остальной браузер

```nim
import std/asyncdispatch
import cdp/domains/storage as storageApi

proc main() {.async.} =
  await storageApi.clearDataForOrigin(session, "https://example.com", "cookies,cache_storage,local_storage")
  echo "данные example.com очищены" # выводит "данные example.com очищены"
```

---

## Краткая таблица

| Задача | Модуль | Функция |
|---|---|---|
| Открыть CDP-сессию по WebSocket URL | `transport.nim` | `newCDPSession` |
| Отправить произвольную команду протокола | `transport.nim` | `call` |
| Подписаться на событие | `transport.nim` | `on` / `onSession` |
| Дождаться одного конкретного события | `transport.nim` | `waitForEvent` |
| Список вкладок браузера (без WebSocket) | `browser.nim` | `listTargets` |
| Открыть/закрыть вкладку (HTTP) | `browser.nim` | `newTarget` / `closeTarget` |
| Перейти по URL | `page.nim` | `navigate` |
| Скриншот / PDF | `page.nim` | `captureScreenshot` / `printToPDF` |
| Изолированный JS-мир (для iframe) | `page.nim` | `createIsolatedWorld` |
| Найти узел по CSS-селектору | `dom.nim` | `querySelector` / `querySelectorAll` |
| Геометрия/координаты элемента | `dom.nim` | `getBoxModel` |
| Заглянуть внутрь iframe | `dom.nim` | `describeNode(pierce = true)` |
| Выполнить произвольный JS | `runtime.nim` | `evaluate` / `evaluateValue` |
| Вызвать функцию на уже полученном объекте | `runtime.nim` | `callFunctionOn` |
| Клик/движение мыши по координатам | `input.nim` | `click` / `moveMouse` |
| Ввод текста | `input.nim` | `insertText` |
| Клавиша с модификаторами | `input.nim` | `dispatchKeyEvent` |
| Куки конкретного URL | `network.nim` | `getCookies` / `setCookie` |
| Очистить браузер целиком (куки/кэш) | `network.nim` | `clearBrowserCookies` / `clearBrowserCache` |
| Подменить/заблокировать сетевой ответ | `fetch.nim` | `fulfillRequest` / `failRequest` |
| Подделать вьюпорт/устройство | `emulation.nim` | `setDeviceMetricsOverride` |
| Подделать геолокацию | `emulation.nim` | `setGeolocationOverride` |
| Список/создание/закрытие целей по протоколу | `target.nim` | `getTargets` / `createTarget` / `closeTarget` |
| Изолированный профиль (инкогнито) | `target.nim` | `createBrowserContext` |
| Мультиплексирование нескольких вкладок | `target.nim` | `attachToTarget` + `callWithSession` |
| Размер/состояние окна ОС | `browserdomain.nim` | `setWindowBounds` |
| Разрешения (геолокация, уведомления) | `browserdomain.nim` | `grantPermissions` / `resetPermissions` |
| Очистить данные ОДНОГО origin'а | `storage.nim` | `clearDataForOrigin` |
| Записи консоли браузера | `log.nim` | `enable` + событие `Log.entryAdded` |

---

## Сводка: какую функцию выбрать

- Нужно просто открыть страницу и подождать загрузки → `page.navigate` + `waitForEvent(session, "Page.loadEventFired")` (или, что почти всегда лучше, готовый `childtear.goto()`).
- Нужно найти элемент → `dom.querySelector`/`querySelectorAll`, координаты для клика — `dom.getBoxModel`.
- Нужно прочитать/изменить текст, вычислить что-то на странице → `runtime.evaluate`/`evaluateValue`, а не разбирать DOM вручную через `dom.nim`.
- Нужно кликнуть/напечатать текст максимально похоже на настоящего пользователя → `input.dispatchMouseEvent`/`dispatchKeyEvent`, а не `runtime.evaluate("el.click()")` — последнее не триггерит обработчики, ждущие именно события мыши/клавиатуры.
- Нужно поработать с содержимым iframe → `dom.describeNode(pierce = true)` за `contentDocument.nodeId` + `page.createIsolatedWorld(frameId)` за execution context.
- Нужно посмотреть/изменить сетевой трафик без его блокировки → `network.nim` (пассивное наблюдение, чтение уже случившихся ответов).
- Нужно перехватить запрос ДО того, как он ушёл в сеть, и подменить/заблокировать его → `fetch.nim`, а не `network.nim`.
- Нужно подделать окружение (устройство, геолокация, часовой пояс, сеть) → `emulation.nim`.
- Нужно управлять несколькими вкладками из одного соединения или создать изолированный профиль → `target.nim`.
- Нужно раздвинуть/свернуть окно браузера или выдать сайту разрешение → `browserdomain.nim`.
- Нужно почистить данные ровно одного сайта, не трогая остальной браузер → `storage.clearDataForOrigin`, а не `network.clearBrowserCache`/`clearBrowserCookies` (те — весь браузер, ограничение самого протокола).
- Всё вышеперечисленное уже собрано в удобные команды → используйте высокоуровневый API, [`childtear_reference_ru.md`](./childtear_reference_ru.md), и опускайтесь на этот уровень только когда готовой функции не нашлось.
