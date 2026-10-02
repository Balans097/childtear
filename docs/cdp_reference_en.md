# cdp — Low-Level Layer Reference

> **Import:** `import cdp/transport` (sessions/commands/events), `import cdp/browser` (HTTP `/json/*`), `import cdp/wsclient` (raw WebSocket), `import cdp/domains/<domain>` (wrappers over CDP domains — `page`, `dom`, `runtime`, `input`, `network`, `fetch`, `emulation`, `target`, `browserdomain`, `storage`, `log`).

> **Scope:** direct access to Chrome DevTools Protocol commands from Nim — for cases not covered by the high-level `childtear.nim` API (see [`childtear_reference_ru.md`](./childtear_reference_ru.md)), or when you need full control over a specific protocol command.

This layer does not try to be convenient — it tries to be honest: every function here corresponds to exactly one CDP command (or, in `transport.nim`/`wsclient.nim`, to one step of the WebSocket/JSON-RPC protocol), with no extra logic on top. A convention common to all domain modules: the first parameter is `session: CDPSession`, obtained via `newCDPSession()` (section II); almost all procedures are asynchronous (`{.async.}`) and require `await` inside a `proc ... {.async.}` or a top-level `waitFor`.

In all the examples below, except section II, an already open session `session: CDPSession` is assumed (obtained as shown in the `newCDPSession()` example) — reopening it in the example for every single function would be redundant. The imports `std/asyncdispatch`, `std/json`, and the corresponding `cdp/...` module of the section are also assumed to be available.


---

## Table of Contents
I. [Types and General Conventions](#types-and-general-conventions)
   1. [`CDPSession` — transport.nim](#cdpsession-transportnim)
   2. [`CDPError` — transport.nim](#cdperror-transportnim)
   3. [`EventHandler` — transport.nim](#eventhandler-transportnim)
   4. [`WebSocket` — wsclient.nim](#websocket-wsclientnim)
   5. [`WebSocketError` — wsclient.nim](#websocketerror-wsclientnim)
   6. [`BrowserConnection` — browser.nim](#browserconnection-browsernim)
II. [Transport: Sessions, Commands, Events](#transport-sessions-commands-events)
   1. [`newCDPSession` — transport.nim](#newcdpsession-transportnim)
   2. [`call` — transport.nim](#call-transportnim)
   3. [`on` — transport.nim](#on-transportnim)
   4. [`onSession` — transport.nim](#onsession-transportnim)
   5. [`waitForEvent` — transport.nim](#waitforevent-transportnim)
   6. [`close` — transport.nim](#close-transportnim)
III. [WebSocket Client](#websocket-client)
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
V. [Page Domain — Navigation and Tab Lifecycle](#page-domain-navigation-and-tab-lifecycle)
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
VI. [DOM Domain — Element Tree](#dom-domain-element-tree)
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
VII. [Runtime Domain — JS Execution](#runtime-domain-js-execution)
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
VIII. [Input Domain — Mouse, Keyboard, Touch](#input-domain-mouse-keyboard-touch)
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
IX. [Network Domain — Network, Cookies, Cache](#network-domain-network-cookies-cache)
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
X. [Fetch Domain — Request Interception](#fetch-domain-request-interception)
   1. [`enable` — fetch.nim](#enable-fetchnim)
   2. [`disable` — fetch.nim](#disable-fetchnim)
   3. [`continueRequest` — fetch.nim](#continuerequest-fetchnim)
   4. [`failRequest` — fetch.nim](#failrequest-fetchnim)
   5. [`fulfillRequest` — fetch.nim](#fulfillrequest-fetchnim)
   6. [`getResponseBody` — fetch.nim](#getresponsebody-fetchnim)
   7. [`takeResponseBodyAsStream` — fetch.nim](#takeresponsebodyasstream-fetchnim)
   8. [`continueWithAuth` — fetch.nim](#continuewithauth-fetchnim)
XI. [Emulation Domain — Environment Overrides](#emulation-domain-environment-overrides)
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
XII. [Target Domain — Tabs and Profiles](#target-domain-tabs-and-profiles)
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
XIII. [Browser Domain — Window and Permissions](#browser-domain-window-and-permissions)
   1. [`getVersion` — browserdomain.nim](#getversion-browserdomainnim)
   2. [`close` — browserdomain.nim](#close-browserdomainnim)
   3. [`setDownloadBehavior` — browserdomain.nim](#setdownloadbehavior-browserdomainnim)
   4. [`getWindowForTarget` — browserdomain.nim](#getwindowfortarget-browserdomainnim)
   5. [`setWindowBounds` — browserdomain.nim](#setwindowbounds-browserdomainnim)
   6. [`resetPermissions` — browserdomain.nim](#resetpermissions-browserdomainnim)
   7. [`grantPermissions` — browserdomain.nim](#grantpermissions-browserdomainnim)
XIV. [Storage Domain — Data for a Specific Origin](#storage-domain-data-for-a-specific-origin)
   1. [`clearDataForOrigin` — storage.nim](#cleardatafororigin-storagenim)
   2. [`getCookies` — storage.nim](#getcookies-storagenim)
   3. [`clearCookies` — storage.nim](#clearcookies-storagenim)
XV. [Log Domain — Browser Console Entries](#log-domain-browser-console-entries)
   1. [`enable` — log.nim](#enable-lognim)
   2. [`disable` — log.nim](#disable-lognim)
   3. [`clear` — log.nim](#clear-lognim)
XVI. [Practical Recipes](#practical-recipes)
XVII. [Quick Reference Table](#quick-reference-table)
XVIII. [Summary: Which Function to Choose](#summary-which-function-to-choose)


---

## Types and General Conventions

### `CDPSession` — transport.nim

An active protocol session on top of a single WebSocket connection: it holds the open `WebSocket`, the counters for command/handler ids, the table of pending responses (`pending`), and the table of event subscribers (`handlers`). It is the only type that is actually passed to almost all low-level functions. Obtained via `newCDPSession()`.

### `CDPError` — transport.nim

The exception raised by `call()` when the browser returned `{"error": {...}}` instead of `{"result": {...}}` — for example, an unknown method, invalid parameters, a node that was not found, and so on.

### `EventHandler` — transport.nim

The event handler type: `proc(params: JsonNode) {.gcsafe.}`. It is registered via `on()`/`onSession()`/`waitForEvent()` and is called with the `"params"` field of the incoming event.

### `WebSocket` — wsclient.nim

An open WebSocket connection at the level of raw protocol frames — lower than `CDPSession`: it knows nothing about the CDP JSON envelope, only about RFC 6455 frames. Obtained via `newWebSocket()`.

### `WebSocketError` — wsclient.nim

An exception at the WebSocket client level: a handshake error (`Sec-WebSocket-Accept` mismatch), a connection drop while reading a frame, and so on.

### `BrowserConnection` — browser.nim

The parameters for connecting to the browser's HTTP endpoints (`host`, `port`) — it does not open a connection by itself; each call to `listTargets()`/`newTarget()`/... makes a separate HTTP request. Obtained via `newBrowserConnection()`.


---

## Transport: Sessions, Commands, Events

Protocol documentation for the domain: The heart of the low-level layer — it turns a raw WebSocket into a `CDPSession` object that can (1) send commands and match responses by numeric id, and (2) dispatch incoming events to subscribers.


### `newCDPSession` — transport.nim


```nim
proc newCDPSession*(wsUrl: string): Future[CDPSession] {.async.}
```


**What it does.** Opens a WebSocket to a specific tab (the webSocketDebuggerUrl obtained via HTTP /json/new or /json/list) and starts a background read loop.


**Implementation notes.** The function does not merely open a socket; it builds request/response matching infrastructure around it: `nextId` is a counter for generating unique ids for outgoing commands, and `pending` is a table "command id → Future of its result". When `listenLoop()` (started right here via `asyncCheck`) receives a message with an `"id"` field, it finds the corresponding Future in `pending` and completes it — this is how asynchronous request/response over a single WebSocket connection becomes an ordinary `await`. Messages without an `"id"` but with a `"method"` are events, not responses; they go not to `pending` but to `handlers` (see `on()`/`waitForEvent()`).


**Parameters:**

- `wsUrl` (`string`) — the address of the WebSocket endpoint (`ws://...`) — from the response of `/json/list` or `/json/version`.


**Returns:** `Future[CDPSession]`


**Example:**

```nim
let session = await newCDPSession("ws://127.0.0.1:9222/devtools/page/ABCD1234")
echo session != nil # prints true
```


### `call` — transport.nim


```nim
proc call*(session: CDPSession, meth: string, params: JsonNode = newJObject(), sessionId = ""): Future[JsonNode] {.async.}
```


**What it does.** Sends a CDP command (for example "Page.navigate") and waits for the response with the same id. This is the main low-level primitive on top of which all the cdp/domains/*.nim wrappers are built. sessionId is needed only in the "flat" (flattened) mode of multiplexing several tabs over a single browser-level connection (see cdp/domains/target.nim -> attachToTarget) — in the regular "one WebSocket per tab" mode you do not need to pass it.


**Implementation notes.** Three steps: (1) take the current `nextId` and increment the counter — this guarantees id uniqueness within the session; (2) create an empty `Future[JsonNode]`, put it into `pending[id]`, and send JSON of the form `{"id", "method", "params"}` to the socket (plus `"sessionId"` if it is not empty — for multiplexing several tabs over a single browser-level connection); (3) wait for that Future — it will be completed by `listenLoop()` when the response with the same id arrives. If the server returned `{"error": ...}` instead of `{"result": ...}`, `call()` raises `CDPError` rather than handing the error to the caller disguised as a result.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `meth` (`string`) — the protocol command name, for example "Page.navigate".
- `params` (`JsonNode`), default `newJObject()`
- `sessionId`, default `""` — the session identifier in the "flat" (flattened) multiplexing mode — from the response of `attachToTarget()`.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
discard await call(session, "Page.enable")
let res = await call(session, "Runtime.evaluate", %*{"expression": "1 + 1"})
echo res["result"]["value"] # prints 2
```


### `on` — transport.nim


```nim
proc on*(session: CDPSession, event: string, handler: EventHandler)
```


**What it does.** Registers an event handler for the main ("root") session, for example: session.on("Page.loadEventFired", proc (p: JsonNode) = ...). The subscription is permanent — it lives as long as the session does. For events of a tab attached via Target.attachToTarget in flatten mode, use onSession() — otherwise events from different tabs on the same browser-level connection will be indistinguishable from one another.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `event` (`string`) — the protocol event name, for example "Page.loadEventFired".
- `handler` (`EventHandler`) — the function called with params every time the event `event` arrives.


**Example:**

```nim
proc onLoad(params: JsonNode) {.gcsafe.} =
  echo "page loaded" # prints on every Page.loadEventFired
on(session, "Page.loadEventFired", onLoad)
```


### `onSession` — transport.nim


```nim
proc onSession*(session: CDPSession, sessionId, event: string, handler: EventHandler)
```


**What it does.** Like on(), but only for events of a specific attached tab (the sessionId obtained from Target.attachToTarget) — needed when multiplexing several tabs over a single browser-level connection.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `sessionId` (`string`) — the session identifier in the "flat" (flattened) multiplexing mode — from the response of `attachToTarget()`.
- `event` (`string`) — the protocol event name, for example "Page.loadEventFired".
- `handler` (`EventHandler`) — the function called with params every time the event `event` arrives from the specific attached session.


**Example:**

```nim
proc onEntry(params: JsonNode) {.gcsafe.} =
  echo "log entry from a specific tab" # prints only for this tab
onSession(browserSession, attachedSessionId, "Log.entryAdded", onEntry)
```


### `waitForEvent` — transport.nim


```nim
proc waitForEvent*(session: CDPSession, event: string, timeoutMs = 30_000, sessionId = ""): Future[JsonNode] {.async.}
```


**What it does.** Waits once for the specified event (for example "Page.loadEventFired") with a timeout. Convenient for sequential scenarios like "follow a link and wait for it to load". Pass sessionId to wait for an event from a specific attached tab in flatten mode (see onSession). Unlike on()/onSession(), the handler is always removed automatically — both on successful firing and on timeout — so that repeated waits for the same event do not accumulate in the session's subscriber table.


**Implementation notes.** Essentially a one-shot subscription: it registers a handler via the internal `addHandler()`, which on its first firing completes the `Future[JsonNode]` and unsubscribes itself — that is, after a single event the handler does not remain hanging in the session's subscriber table. The race with the timeout is resolved via a parallel `sleepAsync(timeoutMs)`: whichever future completes first — the event or the timer — determines the result. If the timer fires, the handler is still removed manually.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `event` (`string`) — the name of the protocol event to wait for, for example "Page.loadEventFired".
- `timeoutMs`, default `30_000` — how many milliseconds to wait before raising a timeout exception.
- `sessionId`, default `""` — the session identifier in the "flat" (flattened) multiplexing mode — from the response of `attachToTarget()`.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
discard await call(session, "Page.navigate", %*{"url": "https://example.com"})
discard await waitForEvent(session, "Page.loadEventFired", timeoutMs = 10_000)
echo "load completed" # prints "load completed"
```


### `isAlive` — transport.nim


```nim
proc isAlive*(session: CDPSession): bool
```


**What it does.** `true` while the connection is open and the background read loop is running. After a drop or `close()` it returns `false`; `call()` and `waitForEvent()` on such a session immediately throw `CDPError`.


### `close` — transport.nim


```nim
proc close*(session: CDPSession) {.async.}
```


**What it does.** Closes the WebSocket and waits for the background listenLoop to finish normally, so that after `close()` returns there are no "dangling" detached futures left in the system that are tied to this connection.


**Implementation notes.** It cancels all commands that have not yet completed via the internal `failAllPending()` (otherwise `await call(...)` calls that are already waiting for a response would hang forever — the server whose connection was severed will not send one), then stops the background `listenLoop()` and closes the WebSocket itself. The order matters: first interrupt the pending Futures with a clear error, and only then cut the socket.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await close(session) # aborts pending call()s and closes the WebSocket
echo "session closed" # prints "session closed"
```


---

## WebSocket Client

Protocol documentation for the domain: The lowest layer — the handshake and reading/writing WebSocket frames per RFC 6455, with no external dependencies. `transport.nim` uses this module, but calling code usually does not need it directly.


### `newWebSocket` — wsclient.nim


```nim
proc newWebSocket*(url: string): Future[WebSocket] {.async.}
```


**What it does.** Connects to an address of the form ws://host:port/path and performs the handshake. Returns a ready-to-use WebSocket.


**Implementation notes.** Implements the client-side WebSocket handshake (RFC 6455) by hand: it generates a random 16-byte key, encodes it in base64, and sends it as the `Sec-WebSocket-Key` header; the server must reply with a `Sec-WebSocket-Accept` header equal to base64(SHA1(key + the magic GUID string from the specification)). The function independently computes the same value and compares it with the response — if they do not match, the connection is considered untrusted and is dropped.


**Parameters:**

- `url` (`string`) — the address of the page or resource the command refers to.


**Returns:** `Future[WebSocket]`


**Example:**

```nim
let ws = await newWebSocket("ws://127.0.0.1:9222/devtools/page/ABCD1234")
echo ws != nil # prints true
```


### `send` — wsclient.nim


```nim
proc send*(ws: WebSocket, text: string) {.async.}
```


**What it does.** Sends a text (JSON) frame — the primary way of communicating with CDP.


**Parameters:**

- `ws` (`WebSocket`) — an open connection obtained via newWebSocket().
- `text` (`string`) — the contents of the text (JSON) frame to send.


**Example:**

```nim
await send(ws, """{"id": 1, "method": "Page.enable"}""")
echo "command sent" # prints "command sent"
```


### `receiveMessage` — wsclient.nim


```nim
proc receiveMessage*(ws: WebSocket): Future[string] {.async.}
```


**What it does.** Reads one logical message, transparently stitching together fragmented frames and automatically replying to pings. Returns an empty string if the server closed the connection.


**Implementation notes.** A WebSocket message is not required to fit into a single TCP frame: large messages (for example, JSON with the full DOM tree of a large page) are split by the browser into several frames, of which only the last one is marked with the FIN bit. The function reads frames in a loop, concatenating their payloads, until it meets FIN = true — from the outside this looks like a single call, although internally an arbitrary number of socket reads may be performed.


**Parameters:**

- `ws` (`WebSocket`) — an open connection obtained via newWebSocket().


**Returns:** `Future[string]`


**Example:**

```nim
let raw = await receiveMessage(ws)
echo len(raw) > 0 # prints true — a non-empty JSON message was received
```


### `close` — wsclient.nim


```nim
proc close*(ws: WebSocket) {.async.}
```


**What it does.** Closes the connection gracefully: sends a close frame (if the socket is not yet marked as closed — for example, receiveMessage() has not yet received a close from the server) and in any case closes the TCP socket itself. An error when sending the close frame on an already broken connection is swallowed — the purpose of this call is to guarantee that the socket is released, not to report an error in a farewell handshake that is no longer needed.


**Parameters:**

- `ws` (`WebSocket`) — the connection to close.


**Example:**

```nim
await close(ws)
echo "socket closed" # prints "socket closed"
```


---

## Browser-level HTTP API

Protocol documentation for the domain: Service HTTP endpoints `/json/*` served by Chromium itself (not over WebSocket) — the list of tabs, opening/closing/activating a tab, and the browser version.


### `newBrowserConnection` — browser.nim


```nim
proc newBrowserConnection*(host = "127.0.0.1", port = 9222): BrowserConnection
```


**What it does.** Describes where to knock: usually this is the same address and port that were specified in `--remote-debugging-port` when launching `chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox`. The port value here is an independent default of this low-level module (for the case of using cdp/browser.nim directly, bypassing childtear.nim); the high-level newBrowser() in childtear.nim passes its own named constant DefaultDebuggingPort here rather than relying on this literal.


**Parameters:**

- `host`, default `"127.0.0.1"`
- `port`, default `9222`


**Returns:** `BrowserConnection`


**Example:**

```nim
let bc = newBrowserConnection("127.0.0.1", 9222)
echo bc != nil # prints true
```


### `listTargets` — browser.nim


```nim
proc listTargets*(bc: BrowserConnection): Future[seq[JsonNode]] {.async.}
```


**What it does.** Returns the list of all open tabs/targets (as in chrome://inspect).


**Parameters:**

- `bc` (`BrowserConnection`) — the description of the connection to the browser, obtained via newBrowserConnection().


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let targets = await listTargets(bc)
echo len(targets) # prints the number of open tabs/workers
```


### `newTarget` — browser.nim


```nim
proc newTarget*(bc: BrowserConnection, url = "about:blank"): Future[JsonNode] {.async.}
```


**What it does.** Opens a new tab with the specified URL and returns its description (including "id" and "webSocketDebuggerUrl").


**Parameters:**

- `bc` (`BrowserConnection`) — the description of the connection to the browser, obtained via newBrowserConnection().
- `url = "about` (`blank"`)


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let info = await newTarget(bc, "https://example.com")
echo info["id"] # prints the identifier of the new tab, for example "ABCD1234..."
```


### `closeTarget` — browser.nim


```nim
proc closeTarget*(bc: BrowserConnection, targetId: string) {.async.}
```


**What it does.** Closes a tab by its id.


**Parameters:**

- `bc` (`BrowserConnection`) — the description of the connection to the browser, obtained via newBrowserConnection().
- `targetId` (`string`) — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.


**Example:**

```nim
let info = await newTarget(bc)
await closeTarget(bc, getStr(info["id"]))
echo "tab closed" # prints "tab closed"
```


### `activateTarget` — browser.nim


```nim
proc activateTarget*(bc: BrowserConnection, targetId: string) {.async.}
```


**What it does.** Makes a tab "active" (the equivalent of switching focus to it).


**Parameters:**

- `bc` (`BrowserConnection`) — the description of the connection to the browser, obtained via newBrowserConnection().
- `targetId` (`string`) — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.


**Example:**

```nim
let targets = await listTargets(bc)
await activateTarget(bc, getStr(targets[0]["id"]))
echo "tab in the foreground" # prints "tab in the foreground"
```


### `browserVersion` — browser.nim


```nim
proc browserVersion*(bc: BrowserConnection): Future[JsonNode] {.async.}
```


**What it does.** /json/version — browser metadata and the address of the browser-level WebSocket (useful if you need to control the browser as a whole rather than an individual tab).


**Parameters:**

- `bc` (`BrowserConnection`) — the description of the connection to the browser, obtained via newBrowserConnection().


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let ver = await browserVersion(bc)
echo ver["product"] # prints something like "HeadlessChrome/120.0.0.0"
```


---

## Page Domain — Navigation and Tab Lifecycle

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Page/ — URL navigation, history, dialogs, screenshots, printing to PDF, isolated JS worlds.


### `enable` — page.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**What it does.** Enables the Page domain — required before subscribing to its events (loadEventFired, frameNavigated, etc.).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await enable(session)
echo "Page domain enabled" # prints "Page domain enabled"
```


### `disable` — page.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**What it does.** Disables the Page domain — subscriptions to its events (loadEventFired, etc.) stop firing.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await disable(session)
echo "Page domain disabled" # prints "Page domain disabled"
```


### `navigate` — page.nim


```nim
proc navigate*(session: CDPSession, url: string, referrer = "", transitionType = ""): Future[JsonNode] {.async.}
```


**What it does.** Opens a URL in the current tab. Returns {"frameId", "loaderId", ...}, and on a failed navigation (for example, DNS does not resolve) also an "errorText" with the reason, which the calling code in childtear.nim checks without waiting for the full Page.loadEventFired timeout.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `url` (`string`) — the address of the page or resource the command refers to.
- `referrer`, default `""`
- `transitionType`, default `""`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let navResult = await navigate(session, "https://example.com")
echo hasKey(navResult, "errorText") # prints false if the navigation started successfully
```


### `reload` — page.nim


```nim
proc reload*(session: CDPSession, ignoreCache = false, scriptToEvaluateOnLoad = "") {.async.}
```


**What it does.** Reloads the current page. ignoreCache = true is the same as Ctrl+Shift+R (a hard reload bypassing the HTTP cache). scriptToEvaluateOnLoad is a one-time JS snippet executed right after the new document is created, before the page's other scripts.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `ignoreCache`, default `false`
- `scriptToEvaluateOnLoad`, default `""`


**Example:**

```nim
await reload(session, ignoreCache = true)
echo "page is reloading, bypassing the cache" # prints "page is reloading, bypassing the cache"
```


### `stopLoading` — page.nim


```nim
proc stopLoading*(session: CDPSession) {.async.}
```


**What it does.** Stops the current page load (the equivalent of the browser's "stop" button). The part of the DOM that has already loaded stays as it is.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await stopLoading(session)
echo "loading stopped" # prints "loading stopped"
```


### `close` — page.nim


```nim
proc close*(session: CDPSession) {.async.}
```


**What it does.** Closes the tab the same way a user does (with the "close tab" button); unlike HTTP /json/close, it may, for example, trigger a beforeunload dialog.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await close(session)
echo "tab closed" # prints "tab closed"
```


### `bringToFront` — page.nim


```nim
proc bringToFront*(session: CDPSession) {.async.}
```


**What it does.** Makes the tab active (the equivalent of Puppeteer's page.bringToFront()).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await bringToFront(session)
echo "tab brought to the foreground" # prints "tab brought to the foreground"
```


### `getFrameTree` — page.nim


```nim
proc getFrameTree*(session: CDPSession): Future[JsonNode] {.async.}
```


**What it does.** The page's frame tree: {"frame": {...}, "childFrames": [...]} — each node contains "frame": {"id", "url", "name", ...} and, recursively, "childFrames" for nested iframes.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let tree = await getFrameTree(session)
echo tree["frame"]["url"] # prints the URL of the page's main frame
```


### `setDocumentContent` — page.nim


```nim
proc setDocumentContent*(session: CDPSession, frameId, html: string) {.async.}
```


**What it does.** Replaces the frame's entire document content without navigating to a URL (frameId — from getFrameTree()) — the basis of page.setContent() in Puppeteer.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `frameId` (`string`) — the frame id obtained from getFrameTree().
- `html` (`string`) — the HTML markup that replaces the document content.


**Example:**

```nim
let tree = await getFrameTree(session)
await setDocumentContent(session, getStr(tree["frame"]["id"]), "<h1>Replaced</h1>")
echo "document replaced" # prints "document replaced"
```


### `getNavigationHistory` — page.nim


```nim
proc getNavigationHistory*(session: CDPSession): Future[JsonNode] {.async.}
```


**What it does.** Returns {"currentIndex", "entries": [...]}.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let hist = await getNavigationHistory(session)
echo hist["currentIndex"] # prints the index of the current history entry
```


### `navigateToHistoryEntry` — page.nim


```nim
proc navigateToHistoryEntry*(session: CDPSession, entryId: int) {.async.}
```


**What it does.** Navigates to a specific history entry by its id (see getNavigationHistory()) — the basis of goBack()/goForward() in childtear.nim.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `entryId` (`int`) — the history entry id obtained from getNavigationHistory().


**Example:**

```nim
let hist = await getNavigationHistory(session)
await navigateToHistoryEntry(session, hist["entries"][0]["id"].getInt)
echo "navigated to the first history entry" # prints "navigated to the first history entry"
```


### `resetNavigationHistory` — page.nim


```nim
proc resetNavigationHistory*(session: CDPSession) {.async.}
```


**What it does.** Clears the tab's entire navigation history, leaving only the current entry — after that goBack()/goForward() return false until new entries appear.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await resetNavigationHistory(session)
echo "history cleared" # prints "history cleared"
```


### `setLifecycleEventsEnabled` — page.nim


```nim
proc setLifecycleEventsEnabled*(session: CDPSession, enabled = true) {.async.}
```


**What it does.** Enables the more granular "Page.lifecycleEvent" events (networkIdle, DOMContentLoaded, etc.) — useful for a more precise waitForNavigation than just loadEventFired.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `enabled`, default `true`


**Example:**

```nim
await setLifecycleEventsEnabled(session, true)
echo "lifecycle events enabled" # prints "lifecycle events enabled" — Page.lifecycleEvent events will start arriving
```


### `setBypassCSP` — page.nim


```nim
proc setBypassCSP*(session: CDPSession, enabled = true) {.async.}
```


**What it does.** Disables the page's Content-Security-Policy — needed, for example, so that addScriptTag() can inject arbitrary scripts on sites with a strict CSP.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `enabled`, default `true`


**Example:**

```nim
await setBypassCSP(session, true)
echo "Content-Security-Policy is bypassed" # prints "Content-Security-Policy is bypassed"
```


### `addScriptToEvaluateOnNewDocument` — page.nim


```nim
proc addScriptToEvaluateOnNewDocument*(session: CDPSession, source: string, worldName = ""): Future[string] {.async.}
```


**What it does.** The script will be executed whenever *each* new document of this tab is created (before any other page JS runs) — the basis of page.evaluateOnNewDocument() in Puppeteer. Returns an identifier for the subsequent removeScriptToEvaluateOnNewDocument.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `source` (`string`) — the JS source code that will be executed whenever each new document of the tab is created.
- `worldName`, default `""`


**Returns:** `Future[string]`


**Example:**

```nim
let scriptId = await addScriptToEvaluateOnNewDocument(session, "window.__marker = 42;")
echo len(scriptId) > 0 # prints true — an identifier for removeScriptToEvaluateOnNewDocument was obtained
```


### `removeScriptToEvaluateOnNewDocument` — page.nim


```nim
proc removeScriptToEvaluateOnNewDocument*(session: CDPSession, identifier: string) {.async.}
```


**What it does.** Cancels a script added by addScriptToEvaluateOnNewDocument(), by its identifier — it does not affect documents that are already loaded, only subsequent navigations.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `identifier` (`string`) — the identifier returned by addScriptToEvaluateOnNewDocument().


**Example:**

```nim
await removeScriptToEvaluateOnNewDocument(session, scriptId)
echo "script cancelled" # prints "script cancelled"
```


### `createIsolatedWorld` — page.nim


```nim
proc createIsolatedWorld*(session: CDPSession, frameId: string, worldName = "", grantUniversalAccess = false): Future[int] {.async.}
```


**What it does.** Returns the executionContextId of an isolated JS context for the specified frame — the context is not visible to the page's own scripts (useful for extensions/automation tools that should not "show up" in window).


**Implementation notes.** "Isolated" means inaccessible to the page's ordinary JS: the page's scripts do not see global variables declared in this context, and vice versa. The isolated context has the same DOM — `document` inside it points to the same frame document; only the JS environment (window, global objects) is separate. This allows automation tools not to "show up" in the page's window.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `frameId` (`string`) — the id of the frame (from getFrameTree()/describeNode()) for which the isolated context is created.
- `worldName`, default `""`
- `grantUniversalAccess`, default `false`


**Returns:** `Future[int]`


**Example:**

```nim
let
  tree = await getFrameTree(session)
  ctxId = await createIsolatedWorld(session, getStr(tree["frame"]["id"]), "myWorld", grantUniversalAccess = true)
echo ctxId > 0 # prints true
```


### `handleJavaScriptDialog` — page.nim


```nim
proc handleJavaScriptDialog*(session: CDPSession, accept: bool, promptText = "") {.async.}
```


**What it does.** Responds to an alert()/confirm()/prompt()/beforeunload that has paused the page — see the "Page.javascriptDialogOpening" event.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `accept` (`bool`) — true — accept the dialog (OK/Enter), false — dismiss it (Cancel).
- `promptText`, default `""`


**Example:**

```nim
await handleJavaScriptDialog(session, true, promptText = "my answer")
echo "dialog accepted" # prints "dialog accepted"
```


### `setInterceptFileChooserDialog` — page.nim


```nim
proc setInterceptFileChooserDialog*(session: CDPSession, enabled = true) {.async.}
```


**What it does.** Once enabled, the system file-selection dialog does not open — instead, a "Page.fileChooserOpened" event arrives with the backendNodeId of the input, to which files must then be assigned via DOM.setFileInputFiles.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `enabled`, default `true`


**Example:**

```nim
await setInterceptFileChooserDialog(session, true)
echo "file chooser dialog is being intercepted" # prints "file chooser dialog is being intercepted" — Page.fileChooserOpened will arrive
```


### `setDownloadBehavior` — page.nim


```nim
proc setDownloadBehavior*(session: CDPSession, behavior: string, downloadPath = "") {.async.}
```


**What it does.** behavior: "deny" | "allow" | "default". downloadPath needs to be specified only when behavior == "allow".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `behavior` (`string`) — "deny" | "allow" | "default".
- `downloadPath`, default `""`


**Example:**

```nim
await setDownloadBehavior(session, "allow", downloadPath = "/tmp/downloads")
echo "downloads allowed" # prints "downloads allowed"
```


### `getLayoutMetrics` — page.nim


```nim
proc getLayoutMetrics*(session: CDPSession): Future[JsonNode] {.async.}
```


**What it does.** {"layoutViewport", "visualViewport", "contentSize", "cssContentSize"} — the real dimensions of the page, useful for screenshot(fullPage=true).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let metrics = await getLayoutMetrics(session)
echo metrics["cssContentSize"]["height"] # prints the full height of the document in CSS pixels
```


### `captureScreenshot` — page.nim


```nim
proc captureScreenshot*(session: CDPSession, format = "png", quality = 100, clip: JsonNode = nil, captureBeyondViewport = false, fromSurface = true): Future[string] {.async.}
```


**What it does.** Returns the screenshot contents encoded in base64 (as it arrives from the browser, without decoding). clip is an optional {"x","y","width","height","scale"} for cropping a specific area (see childtear.screenshot(fullPage=true)).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `format`, default `"png"`
- `quality`, default `100`
- `clip` (`JsonNode`), default `nil`
- `captureBeyondViewport`, default `false`
- `fromSurface`, default `true`


**Returns:** `Future[string]`


**Example:**

```nim
let base64Png = await captureScreenshot(session, format = "png")
echo len(base64Png) > 0 # prints true — a base64 PNG string was obtained
```


### `printToPDF` — page.nim


```nim
proc printToPDF*(session: CDPSession, landscape = false, printBackground = true, paperWidth = 8.5, paperHeight = 11.0, marginTop = 0.4, marginBottom = 0.4, marginLeft = 0.4, marginRight = 0.4, pageRanges = ""): Future[string] {.async.}
```


**What it does.** Returns the page's PDF in base64. Paper dimensions and margins are in inches, as the protocol itself requires.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `landscape`, default `false`
- `printBackground`, default `true`
- `paperWidth`, default `8.5`
- `paperHeight`, default `11.0`
- `marginTop`, default `0.4`
- `marginBottom`, default `0.4`
- `marginLeft`, default `0.4`
- `marginRight`, default `0.4`
- `pageRanges`, default `""`


**Returns:** `Future[string]`


**Example:**

```nim
let base64Pdf = await printToPDF(session, landscape = false)
echo len(base64Pdf) > 0 # prints true — a base64 PDF string was obtained
```


---

## DOM Domain — Element Tree

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/DOM/ — finding nodes, reading/modifying attributes and markup, element geometry.


### `enable` — dom.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**What it does.** Formally required by the specification before using the domain's other commands (in current headless Chromium many commands tolerate its absence, but you should not rely on that).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await enable(session)
echo "DOM domain enabled" # prints "DOM domain enabled"
```


### `disable` — dom.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**What it does.** Disables the DOM domain — in practice it is almost never called explicitly: the domain lives as long as the tab's session itself does.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await disable(session)
echo "DOM domain disabled" # prints "DOM domain disabled"
```


### `getDocument` — dom.nim


```nim
proc getDocument*(session: CDPSession, depth = 1): Future[JsonNode] {.async.}
```


**What it does.** Returns the document's root node (usually only its "nodeId" is needed).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `depth`, default `1` — the subtree traversal depth; -1 — unlimited, traverse/return the entire subtree.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let doc = await getDocument(session, depth = 1)
echo doc["root"]["nodeName"] # prints "#document"
```


### `querySelector` — dom.nim


```nim
proc querySelector*(session: CDPSession, nodeId: int, selector: string): Future[int] {.async.}
```


**What it does.** Finds the first node matching a CSS selector within the nodeId subtree. Returns 0 if nothing is found.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `selector` (`string`) — the CSS selector of the element being searched for.


**Returns:** `Future[int]`


**Example:**

```nim
let
  doc = await getDocument(session)
  nodeId = await querySelector(session, doc["root"]["nodeId"].getInt, "h1")
echo nodeId > 0 # prints true if the heading is found on the page
```


### `querySelectorAll` — dom.nim


```nim
proc querySelectorAll*(session: CDPSession, nodeId: int, selector: string): Future[seq[int]] {.async.}
```


**What it does.** Like querySelector(), but returns the nodeId of ALL nodes matching the selector within the nodeId subtree, not just the first one.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `selector` (`string`) — the CSS selector of the elements being searched for.


**Returns:** `Future[seq[int]]`


**Example:**

```nim
let
  doc = await getDocument(session)
  ids = await querySelectorAll(session, doc["root"]["nodeId"].getInt, "a")
echo len(ids) # prints the number of links on the page
```


### `getBoxModel` — dom.nim


```nim
proc getBoxModel*(session: CDPSession, nodeId: int): Future[JsonNode] {.async.}
```


**What it does.** The node's geometry on the page (needed to move the cursor to its center).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let box = await getBoxModel(session, nodeId)
echo box["content"] # prints 8 numbers — the coordinates of the 4 corners of the rectangle
```


### `getContentQuads` — dom.nim


```nim
proc getContentQuads*(session: CDPSession, nodeId: int): Future[seq[JsonNode]] {.async.}
```


**What it does.** Unlike getBoxModel, it also works for nodes that have several rectangles on the screen (for example, inline elements broken by a line wrap across several lines).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let quads = await getContentQuads(session, nodeId)
echo len(quads) # prints 1 for an ordinary block element, more for an inline element broken across several lines
```


### `focus` — dom.nim


```nim
proc focus*(session: CDPSession, nodeId: int) {.async.}
```


**What it does.** Programmatically focuses a node (the equivalent of el.focus() in JS, but through the DOM rather than Runtime) — the node must be focusable (input, [tabindex], etc.).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Example:**

```nim
await focus(session, nodeId)
echo "element focused" # prints "element focused"
```


### `setAttributeValue` — dom.nim


```nim
proc setAttributeValue*(session: CDPSession, nodeId: int, name, value: string) {.async.}
```


**What it does.** Sets the value of a node's HTML attribute (Element.setAttribute).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `name` (`string`) — the name of the HTML attribute.
- `value` (`string`) — the new value of the attribute.


**Example:**

```nim
await setAttributeValue(session, nodeId, "class", "highlighted")
echo "attribute set" # prints "attribute set"
```


### `removeAttribute` — dom.nim


```nim
proc removeAttribute*(session: CDPSession, nodeId: int, name: string) {.async.}
```


**What it does.** Removes an HTML attribute from a node (Element.removeAttribute); it does not raise an error if the attribute was not there in the first place.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `name` (`string`) — the name of the attribute to remove.


**Example:**

```nim
await removeAttribute(session, nodeId, "disabled")
echo "attribute removed" # prints "attribute removed"
```


### `getAttributes` — dom.nim


```nim
proc getAttributes*(session: CDPSession, nodeId: int): Future[seq[(string, string)]] {.async.}
```


**What it does.** DOM.getAttributes returns a flat array ["name1","value1","name2",...] — here it is already unpacked into (name, value) pairs for convenience.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int): Future[seq[(string, string`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Example:**

```nim
let attrs = await getAttributes(session, nodeId)
echo attrs # prints @[("class", "btn"), ("type", "submit")]
```


### `resolveNode` — dom.nim


```nim
proc resolveNode*(session: CDPSession, nodeId: int): Future[JsonNode] {.async.}
```


**What it does.** Returns a Runtime.RemoteObject for the node — used when you need to pass a node to Runtime.callFunctionOn.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let remoteObj = await resolveNode(session, nodeId)
echo remoteObj["objectId"] # prints the identifier of a JS object suitable for Runtime.callFunctionOn
```


### `requestNode` — dom.nim


```nim
proc requestNode*(session: CDPSession, objectId: string): Future[int] {.async.}
```


**What it does.** The inverse operation of resolveNode: obtain a nodeId from a RemoteObject.objectId.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `objectId` (`string`) — the identifier of a JS object on the browser side (Runtime.RemoteObject.objectId) — from `evaluate()`/`resolveNode()`.


**Returns:** `Future[int]`


**Example:**

```nim
# objectId was obtained, for example, from Runtime.evaluate with returnByValue = false
let nodeId = await requestNode(session, objectId)
echo nodeId > 0 # prints true
```


### `describeNode` — dom.nim


```nim
proc describeNode*(session: CDPSession, nodeId: int, depth = 1, pierce = false): Future[JsonNode] {.async.}
```


**What it does.** Returns a description of a node (Node) — the tag, attributes, child nodes (to depth `depth`; -1 — the entire subtree) and, for `<iframe>`/`<frame>`, the "frameId" field and, with pierce = true, a nested "contentDocument" node (the root document inside the frame). It is precisely pierce = true that is the way childtear.frame() finds the document inside an iframe in order to search for elements in it via querySelector().


**Implementation notes.** The `pierce` parameter determines whether the tree traversal stops at the iframe boundary. Without it, an `<iframe>` node in the response is just an element with its own attributes; with `pierce = true`, the response gains a `"contentDocument"` field — the document subtree INSIDE the iframe with its own `nodeId`, usable as a root for `querySelector()`. This is the only supported bridge from the "outside" into an iframe's DOM without entering its own JS context.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `depth`, default `1` — the subtree traversal depth; -1 — unlimited, traverse/return the entire subtree.
- `pierce`, default `false` — whether to pass through iframe/shadow DOM boundaries — without this, the traversal stops at the frame boundary.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let
  iframeNodeId = await querySelector(session, rootId, "iframe")
  described = await describeNode(session, iframeNodeId, depth = 1, pierce = true)
echo described["contentDocument"]["nodeId"] # prints the nodeId of the document inside the iframe
```


### `getOuterHTML` — dom.nim


```nim
proc getOuterHTML*(session: CDPSession, nodeId: int): Future[string] {.async.}
```


**What it does.** The HTML markup of the node itself together with the node (Element.outerHTML).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Returns:** `Future[string]`


**Example:**

```nim
let html = await getOuterHTML(session, nodeId)
echo html # prints "<button class=\"btn\">Log in</button>"
```


### `setOuterHTML` — dom.nim


```nim
proc setOuterHTML*(session: CDPSession, nodeId: int, outerHTML: string) {.async.}
```


**What it does.** Replaces the node entirely with a markup fragment parsed from outerHTML (Element.outerHTML =). After the call the original nodeId is invalid — the node in its place has to be looked up again.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `outerHTML` (`string`) — the new HTML markup that replaces the node entirely.


**Example:**

```nim
await setOuterHTML(session, nodeId, "<button>New button</button>")
echo "markup replaced" # prints "markup replaced" (the original nodeId is invalid after this)
```


### `setNodeValue` — dom.nim


```nim
proc setNodeValue*(session: CDPSession, nodeId: int, value: string) {.async.}
```


**What it does.** Changes the value of a text node (Node.nodeValue), not of an attribute.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `value` (`string`) — the new value of the text node.


**Example:**

```nim
# nodeId here is a text node (Node.nodeType == 3), not an element
await setNodeValue(session, textNodeId, "new text")
echo "text changed" # prints "text changed"
```


### `removeNode` — dom.nim


```nim
proc removeNode*(session: CDPSession, nodeId: int) {.async.}
```


**What it does.** Removes a node from the document (the equivalent of el.remove()).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Example:**

```nim
await removeNode(session, nodeId)
echo "node removed" # prints "node removed"
```


### `requestChildNodes` — dom.nim


```nim
proc requestChildNodes*(session: CDPSession, nodeId: int, depth = 1, pierce = false) {.async.}
```


**What it does.** "Warms up" a node to the required depth — after that the child nodes are available in DOM.getDocument/events without a separate getDocument.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `depth`, default `1` — the subtree traversal depth; -1 — unlimited, traverse/return the entire subtree.
- `pierce`, default `false` — whether to pass through iframe/shadow DOM boundaries — without this, the traversal stops at the frame boundary.


**Example:**

```nim
await requestChildNodes(session, nodeId, depth = -1)
echo "child nodes loaded" # prints "child nodes loaded" (the nodes themselves will arrive as DOM.setChildNodes events)
```


### `scrollIntoViewIfNeeded` — dom.nim


```nim
proc scrollIntoViewIfNeeded*(session: CDPSession, nodeId: int) {.async.}
```


**What it does.** Scrolls the page so that the node ends up in the visible area — a real user cannot click on something that is off-screen, so click()/hover() in childtear.nim call this before clicking.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.


**Example:**

```nim
await scrollIntoViewIfNeeded(session, nodeId)
echo "element in the visible area" # prints "element in the visible area"
```


### `setFileInputFiles` — dom.nim


```nim
proc setFileInputFiles*(session: CDPSession, nodeId: int, files: seq[string]) {.async.}
```


**What it does.** Assigns files to an <input type="file"> element directly, without the system file-selection dialog — files: full paths on the disk where the browser itself runs.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `nodeId` (`int`) — the identifier of a DOM node obtained from `querySelector()`/`querySelectorAll()`/`requestNode()`/`describeNode()`; valid as long as the document tree has not changed.
- `files` (`seq[string]`) — full paths to files on the disk where the browser itself runs.


**Example:**

```nim
await setFileInputFiles(session, inputNodeId, @["/tmp/photo.jpg"])
echo "file selected" # prints "file selected"
```


### `getNodeForLocation` — dom.nim


```nim
proc getNodeForLocation*(session: CDPSession, x, y: int): Future[JsonNode] {.async.}
```


**What it does.** Returns the node under the specified point on the screen (the equivalent of document.elementFromPoint).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `x` (`int`) — the horizontal coordinate in the page coordinate system (CSS pixels from the left edge of the viewport).
- `y` (`int`) — the vertical coordinate in the page coordinate system (CSS pixels from the top edge of the viewport).


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let res = await getNodeForLocation(session, 100, 200)
echo res["nodeId"] # prints the nodeId of the element at point (100, 200) of the viewport
```


---

## Runtime Domain — JS Execution

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Runtime/ — executing arbitrary expressions, working with promises, the window -> Nim bridge.



### `enable` — runtime.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**What it does.** Enables the Runtime domain — required before evaluate() and before subscribing to "Runtime.consoleAPICalled"/"Runtime.exceptionThrown"/"Runtime.executionContextCreated", etc.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await enable(session)
echo "Runtime domain enabled" # prints "Runtime domain enabled"
```


### `disable` — runtime.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**What it does.** Disables the Runtime domain.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await disable(session)
echo "Runtime domain disabled" # prints "Runtime domain disabled"
```


### `evaluate` — runtime.nim


```nim
proc evaluate*(session: CDPSession, expression: string, awaitPromise = false, returnByValue = true, contextId = 0): Future[JsonNode] {.async.}
```


**What it does.** Executes a JS expression in the page context and returns a Runtime.RemoteObject (result). If there is an error in the JS expression itself, the "exceptionDetails" field will be present in the response. contextId selects IN WHICH execution context to run the expression — 0 (the default) means "the main context of the page's main frame"; a non-zero id is needed to run JS inside a specific iframe (see Page.createIsolatedWorld in page.nim and childtear.frame()/Frame.evalJS(), which are exactly what obtain such an id for iframe content).


**Implementation notes.** `contextId = 0` is a service value meaning "do not pass this field at all", not a real context id (CDP execution context ids are always positive). By default the expression is executed in the main context of the page's main frame. A non-zero `contextId` (for example, from `Page.createIsolatedWorld()`) overrides this and runs the expression in a specific isolated context — this is how `childtear.Frame` runs JS inside an iframe rather than in the main page's context.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `expression` (`string`) — the JS expression to execute.
- `awaitPromise`, default `false`
- `returnByValue`, default `true`
- `contextId`, default `0`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let res = await evaluate(session, "document.title")
echo res["result"]["value"] # prints the page title, for example "Example Domain"
```


### `evaluateValue` — runtime.nim


```nim
proc evaluateValue*(session: CDPSession, expression: string, awaitPromise = false, contextId = 0): Future[JsonNode] {.async.}
```


**What it does.** A convenient variant of evaluate() that immediately returns the JSON value of the result (result.value) rather than the whole RemoteObject envelope. For contextId, see evaluate().


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `expression` (`string`) — the JS expression to execute.
- `awaitPromise`, default `false`
- `contextId`, default `0`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let value = await evaluateValue(session, "2 + 2")
echo value # prints 4
```


### `callFunctionOn` — runtime.nim


```nim
proc callFunctionOn*(session: CDPSession, objectId: string, functionDeclaration: string, arguments: seq[JsonNode] = @[], awaitPromise = false): Future[JsonNode] {.async.}
```


**What it does.** Calls a function in the context of a specific object (for example, a DOM node obtained via DOM.resolveNode) — used for click()/focus()/value= and the like without a global querySelector.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `objectId` (`string`) — the identifier of a JS object on the browser side (Runtime.RemoteObject.objectId) — from `evaluate()`/`resolveNode()`.
- `functionDeclaration` (`string`) — the source code of the function (for example, "function() { ... }") called in the context of the object objectId.
- `arguments` (`seq[JsonNode]`), default `@[]`
- `awaitPromise`, default `false`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let
  remoteObj = await resolveNode(session, nodeId)
  res = await callFunctionOn(session, getStr(remoteObj["objectId"]), "function() { return this.tagName; }")
echo res["result"]["value"] # prints "BUTTON"
```


### `getProperties` — runtime.nim


```nim
proc getProperties*(session: CDPSession, objectId: string, ownProperties = true): Future[JsonNode] {.async.}
```


**What it does.** The list of an object's properties (the equivalent of Object.getOwnPropertyNames + access to the values) — used when you need to inspect an arbitrary RemoteObject without serializing it entirely to JSON.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `objectId` (`string`) — the identifier of a JS object on the browser side (Runtime.RemoteObject.objectId) — from `evaluate()`/`resolveNode()`.
- `ownProperties`, default `true`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let props = await getProperties(session, objectId)
echo len(props["result"]) # prints the number of the object's own properties
```


### `releaseObject` — runtime.nim


```nim
proc releaseObject*(session: CDPSession, objectId: string) {.async.}
```


**What it does.** Releases a RemoteObject on the browser side. RemoteObjects obtained without returnByValue (for example, from resolveNode) hold a reference to a live JS object until they are explicitly released — in a long-lived session with a large number of evaluate() calls they should be cleaned up.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `objectId` (`string`) — the identifier of a JS object on the browser side (Runtime.RemoteObject.objectId) — from `evaluate()`/`resolveNode()`.


**Example:**

```nim
await releaseObject(session, objectId)
echo "object released" # prints "object released"
```


### `releaseObjectGroup` — runtime.nim


```nim
proc releaseObjectGroup*(session: CDPSession, objectGroup: string) {.async.}
```


**What it does.** Like releaseObject(), but at once for all objects obtained with a shared "objectGroup" (see the objectGroup parameter of Runtime.evaluate — not wrapped here, since childtear.nim does not use it).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `objectGroup` (`string`) — the name of the object group passed in the objectGroup parameter when the objects were obtained (for example, in Runtime.evaluate).


**Example:**

```nim
await releaseObjectGroup(session, "childtear-temp")
echo "object group released" # prints "object group released"
```


### `discardConsoleEntries` — runtime.nim


```nim
proc discardConsoleEntries*(session: CDPSession) {.async.}
```


**What it does.** Clears the buffer of already accumulated console messages on the browser side (the equivalent of the "Clear console" button in DevTools).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await discardConsoleEntries(session)
echo "console buffer cleared" # prints "console buffer cleared"
```


### `awaitPromise` — runtime.nim


```nim
proc awaitPromise*(session: CDPSession, promiseObjectId: string, returnByValue = true): Future[JsonNode] {.async.}
```


**What it does.** Waits for a promise to resolve (whose RemoteObject has already been obtained, for example, via evaluate(expr, awaitPromise=false)) and returns its final value.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `promiseObjectId` (`string`) — the objectId of a promise, already obtained earlier (for example, from evaluate() without awaitPromise).
- `returnByValue`, default `true`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let
  promiseRes = await evaluate(session, "fetch('/api/data').then(r => r.json())", awaitPromise = false, returnByValue = false)
  resolved = await awaitPromise(session, getStr(promiseRes["result"]["objectId"]))
echo resolved["result"]["value"] # prints the unwrapped value of the promise, for example {"ok": true}
```


### `addBinding` — runtime.nim


```nim
proc addBinding*(session: CDPSession, name: string, executionContextName = ""): Future[void] {.async.}
```


**What it does.** Adds a global function `name` to the window of every context — a call to it from the page's JS arrives here as a "Runtime.bindingCalled" event. This is the low-level basis for Tab.exposeFunction() in childtear.nim (the equivalent of page.exposeFunction() in Puppeteer).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `name` (`string`) — the name of the global function added to the window of every execution context.
- `executionContextName`, default `""`


**Returns:** `Future[void]`


**Example:**

```nim
await addBinding(session, "nimCallback")
echo "bridge created" # prints "bridge created" — now window.nimCallback(x) in JS sends a Runtime.bindingCalled event
```


### `removeBinding` — runtime.nim


```nim
proc removeBinding*(session: CDPSession, name: string) {.async.}
```


**What it does.** Removes a function added by addBinding() — the JS shim in window itself (if it has already been injected in childtear.exposeFunction()) is not removed by this; only the low-level bridge stops working.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `name` (`string`) — the name of a function previously added by addBinding().


**Example:**

```nim
await removeBinding(session, "nimCallback")
echo "bridge removed" # prints "bridge removed"
```


---

## Input Domain — Mouse, Keyboard, Touch

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Input/ — low-level generation of input events, from which click()/fill() and the like in childtear.nim are assembled.



### `dispatchMouseEvent` — input.nim


```nim
proc dispatchMouseEvent*(session: CDPSession, kind: string, x, y: float, button = "left", clickCount = 1, deltaX = 0.0, deltaY = 0.0, buttons = 0) {.async.}
```


**What it does.** kind: "mousePressed" | "mouseReleased" | "mouseMoved" | "mouseWheel". deltaX/deltaY are used only for "mouseWheel".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `kind` (`string`) — "mousePressed" | "mouseReleased" | "mouseMoved" | "mouseWheel".
- `x` (`float`) — the horizontal coordinate in the page coordinate system (CSS pixels from the left edge of the viewport).
- `y` (`float`) — the vertical coordinate in the page coordinate system (CSS pixels from the top edge of the viewport).
- `button`, default `"left"`
- `clickCount`, default `1`
- `deltaX`, default `0.0`
- `deltaY`, default `0.0`
- `buttons`, default `0` — a bitmask of the buttons being held (left = 1, right = 2, middle = 4). For dragging, pass `buttons = 1` in every `mouseMoved` between the press and the release: the `pointermove`/`mousemove` handlers check `event.buttons`.


**Example:**

```nim
await dispatchMouseEvent(session, "mousePressed", 100.0, 200.0, button = "left", clickCount = 1)
await dispatchMouseEvent(session, "mouseReleased", 100.0, 200.0, button = "left", clickCount = 1)
echo "click sent" # prints "click sent"
```


### `click` — input.nim


```nim
proc click*(session: CDPSession, x, y: float, holdMs = 70) {.async.}
```


**What it does.** A full click = cursor movement + button press + button release, in the same coordinates the page itself sees (viewport-relative).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `x` (`float`) — the horizontal coordinate in the page coordinate system (CSS pixels from the left edge of the viewport).
- `y` (`float`) — the vertical coordinate in the page coordinate system (CSS pixels from the top edge of the viewport).
- `holdMs` (`int`, default `70`) — the pause between `mousePressed` and `mouseReleased`: some pages filter out clicks with zero delay between press/release as "not genuine" (protection against clickjacking/click automation), so the delay is applied unconditionally rather than only for a particular site.


**Example:**

```nim
await click(session, 150.0, 250.0)
echo "click at point (150, 250)" # prints "click at point (150, 250)"
```


### `moveMouse` — input.nim


```nim
proc moveMouse*(session: CDPSession, x, y: float) {.async.}
```


**What it does.** Cursor movement only, without a click — the basis of hover().


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `x` (`float`) — the horizontal coordinate in the page coordinate system (CSS pixels from the left edge of the viewport).
- `y` (`float`) — the vertical coordinate in the page coordinate system (CSS pixels from the top edge of the viewport).


**Example:**

```nim
await moveMouse(session, 400.0, 300.0)
echo "cursor moved" # prints "cursor moved" — mouseover/mouseenter handlers will fire
```


### `scroll` — input.nim


```nim
proc scroll*(session: CDPSession, x, y, deltaX, deltaY: float) {.async.}
```


**What it does.** Emulates mouse-wheel scrolling at the point (x, y).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `x` (`float`) — the horizontal coordinate in the page coordinate system (CSS pixels from the left edge of the viewport).
- `y` (`float`) — the vertical coordinate in the page coordinate system (CSS pixels from the top edge of the viewport).
- `deltaX` (`float`) — the horizontal mouse-wheel offset.
- `deltaY` (`float`) — the vertical mouse-wheel offset.


**Example:**

```nim
await scroll(session, 200.0, 200.0, 0.0, 400.0)
echo "scroll performed" # prints "scroll performed" — the page is scrolled down by 400px
```


### `insertText` — input.nim


```nim
proc insertText*(session: CDPSession, text: string) {.async.}
```


**What it does.** Inserts text into the currently focused element in one piece — faster and more reliable than character-by-character emulation of key presses.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `text` (`string`) — the text inserted into the currently focused element in one piece.


**Example:**

```nim
await insertText(session, "hello@example.com")
echo "text inserted" # prints "text inserted" — into the current focus, without per-character keydown/keyup
```


### `dispatchKeyEvent` — input.nim


```nim
proc dispatchKeyEvent*(session: CDPSession, kind: string, key: string, code = "", text = "", modifiers = 0) {.async.}
```


**What it does.** kind: "keyDown" | "keyUp" | "rawKeyDown" | "char". modifiers is a bitmask per the CDP specification: Alt=1, Ctrl=2, Meta=4, Shift=8. text is the character that should be typed (for kind == "char"); otherwise Chromium may not generate a real input event.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `kind` (`string`) — "keyDown" | "keyUp" | "rawKeyDown" | "char".
- `key` (`string`) — the key name per CDP nomenclature, for example "Enter", "Tab", "a".
- `code`, default `""`
- `text`, default `""`
- `modifiers`, default `0`


**Example:**

```nim
await dispatchKeyEvent(session, "keyDown", "Enter", code = "Enter")
await dispatchKeyEvent(session, "keyUp", "Enter", code = "Enter")
echo "Enter key pressed" # prints "Enter key pressed"
```


### `pressKey` — input.nim


```nim
proc pressKey*(session: CDPSession, key: string, code = "", modifiers = 0) {.async.}
```


**What it does.** Pressing and releasing a single key (for example, "Enter", "Tab").


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `key` (`string`) — the key name per CDP nomenclature, for example "Enter", "Tab", "ArrowDown".
- `code`, default `""`
- `modifiers`, default `0`


**Example:**

```nim
await pressKey(session, "Tab")
echo "focus moved to the next field" # prints "focus moved to the next field"
```


### `typeChar` — input.nim


```nim
proc typeChar*(session: CDPSession, ch: string) {.async.}
```


**What it does.** Types a single character via a genuine "char" keyboard event — unlike insertText(), this is what the page's keydown/keypress/input handlers see individually, rather than in one piece. Used in Tab.type() to emulate live typing.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `ch` (`string`) — a single character typed via a genuine "char" keyboard event.


**Example:**

```nim
await typeChar(session, "A")
echo "character entered" # prints "character entered" — a full keydown -> char -> keyup cycle
```


### `dispatchTouchEvent` — input.nim


```nim
proc dispatchTouchEvent*(session: CDPSession, kind: string, touchPoints: seq[JsonNode]) {.async.}
```


**What it does.** kind: "touchStart" | "touchEnd" | "touchMove" | "touchCancel". touchPoints — for example @[%*{"x": 10.0, "y": 20.0}].


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `kind` (`string`) — "touchStart" | "touchEnd" | "touchMove" | "touchCancel".
- `touchPoints` (`seq[JsonNode]`) — the touch points, for example @[%*{"x": 10.0, "y": 20.0}].


**Example:**

```nim
let point = %*{"x": 100, "y": 200}
await dispatchTouchEvent(session, "touchStart", @[point])
await dispatchTouchEvent(session, "touchEnd", @[])
echo "touch event sent" # prints "touch event sent"
```


### `setIgnoreInputEvents` — input.nim


```nim
proc setIgnoreInputEvents*(session: CDPSession, ignore = true) {.async.}
```


**What it does.** Makes the browser ignore all user input — useful so that background automation does not get mixed up with real mouse/keyboard events on the same machine.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `ignore`, default `true`


**Example:**

```nim
await setIgnoreInputEvents(session, true)
echo "input is ignored" # prints "input is ignored" — clicks/keyboard no longer reach the page
```


### `cancelDragging` — input.nim


```nim
proc cancelDragging*(session: CDPSession) {.async.}
```


**What it does.** Cancels a drag started via Input.dispatchDragEvent (the low-level API for native HTML5 drag-and-drop through the Input domain itself, not wrapped here — childtear.nim emulates HTML5 DnD not with it but with a direct JS simulation of DragEvent/DataTransfer; see dragAndDrop(native=true) in childtear.nim). Useful as an emergency reset of a "stuck" page drag state.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await cancelDragging(session)
echo "drag cancelled" # prints "drag cancelled"
```


---

## Network Domain — Network, Cookies, Cache

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Network/ — headers, cookies, reading response bodies, network condition emulation.


### `enable` — network.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**What it does.** Enables network tracking — required before subscribing to "Network.responseReceived"/"Network.requestWillBeSent", etc., and before getResponseBody() (without enable(), response bodies are not retained).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await enable(session)
echo "Network domain enabled" # prints "Network domain enabled"
```


### `disable` — network.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**What it does.** Disables network tracking — saves session traffic/memory if network events are no longer needed.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await disable(session)
echo "Network domain disabled" # prints "Network domain disabled"
```


### `setExtraHTTPHeaders` — network.nim


```nim
proc setExtraHTTPHeaders*(session: CDPSession, headers: JsonNode) {.async.}
```


**What it does.** headers — a flat JSON object of the form {"X-My-Header": "value", ...}.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `headers` (`JsonNode`) — a flat JSON object of the form {"X-My-Header": "value", ...}.


**Example:**

```nim
await setExtraHTTPHeaders(session, %*{"X-Debug": "1"})
echo "the header will be added to all requests" # prints "the header will be added to all requests"
```


### `setUserAgentOverride` — network.nim


```nim
proc setUserAgentOverride*(session: CDPSession, userAgent: string) {.async.}
```


**What it does.** Deprecated in favor of Emulation.setUserAgentOverride, but still works and does not require the Emulation domain — kept for simple cases where only the UA is needed, without the other fields.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `userAgent` (`string`) — the User-Agent string.


**Example:**

```nim
await setUserAgentOverride(session, "Mozilla/5.0 (compatible; childtear-bot)")
echo "User-Agent overridden" # prints "User-Agent overridden"
```


### `setCacheDisabled` — network.nim


```nim
proc setCacheDisabled*(session: CDPSession, disabled = true) {.async.}
```


**What it does.** disabled = true makes the browser ignore the HTTP cache for this tab's requests (the equivalent of DevTools -> Network -> "Disable cache") — not to be confused with clearBrowserCache() (that one clears the cache that has already accumulated, whereas this one prevents it from being used going forward).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `disabled`, default `true`


**Example:**

```nim
await setCacheDisabled(session, true)
echo "HTTP cache disabled for the tab" # prints "HTTP cache disabled for the tab"
```


### `clearBrowserCache` — network.nim


```nim
proc clearBrowserCache*(session: CDPSession) {.async.}
```


**What it does.** Completely clears the browser's HTTP disk cache. WARNING: CDP itself provides no way to restrict this command to a single tab or origin — this is a protocol limitation, not a childtear.nim one; see Storage.clearDataForOrigin (cdp/domains/storage.nim) for a genuinely isolated alternative for Cache Storage (the service workers' cache — not the same thing as the HTTP cache).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await clearBrowserCache(session)
echo "browser HTTP cache cleared" # prints "browser HTTP cache cleared" — entirely, not just for this tab
```


### `clearBrowserCookies` — network.nim


```nim
proc clearBrowserCookies*(session: CDPSession) {.async.}
```


**What it does.** Completely clears the browser's cookies — for all tabs, all sites, all open profiles at once. WARNING: CDP does not provide a separate command to "clear the cookies of a single tab/origin"; to restrict it to the current origin, obtain the list of cookies via getCookies(urls) and delete them one at a time via deleteCookies() — this is exactly how childtear.clearCookiesForOrigin() is built.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await clearBrowserCookies(session)
echo "browser cookies cleared" # prints "browser cookies cleared" — entirely, all sites and tabs
```


### `getCookies` — network.nim


```nim
proc getCookies*(session: CDPSession, urls: seq[string] = @[]): Future[seq[JsonNode]] {.async.}
```


**What it does.** Without urls, returns the cookies for all frames of the current page.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `urls` (`seq[string]`), default `@[]`


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let cookies = await getCookies(session, @["https://example.com"])
echo len(cookies) # prints the number of cookies visible to this URL
```


### `setCookie` — network.nim


```nim
proc setCookie*(session: CDPSession, name, value: string, url = "", domain = "", path = "/", secure = false, httpOnly = false, sameSite = ""): Future[bool] {.async.}
```


**What it does.** Either url or domain must be specified — the protocol itself requires this.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `name` (`string`) — the cookie name.
- `value` (`string`) — the cookie value.
- `url`, default `""` — the address of the page or resource the command refers to.
- `domain`, default `""`
- `path`, default `"/"`
- `secure`, default `false`
- `httpOnly`, default `false`
- `sameSite`, default `""`


**Returns:** `Future[bool]`


**Example:**

```nim
let ok = await setCookie(session, "session_id", "abc123", domain = "example.com", secure = true)
echo ok # prints true if the cookie was set successfully
```


### `setCookies` — network.nim


```nim
proc setCookies*(session: CDPSession, cookies: seq[JsonNode]) {.async.}
```


**What it does.** The batch version of setCookie — each element is an object of the form {"name", "value", "url"/"domain", ...}.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `cookies` (`seq[JsonNode]`) — a list of objects of the form {"name", "value", "url"/"domain", ...}.


**Example:**

```nim
let batch = @[%*{"name": "a", "value": "1", "domain": "example.com"},
              %*{"name": "b", "value": "2", "domain": "example.com"}]
await setCookies(session, batch)
echo "cookies set as a batch" # prints "cookies set as a batch"
```


### `deleteCookies` — network.nim


```nim
proc deleteCookies*(session: CDPSession, name: string, url = "", domain = "", path = "") {.async.}
```


**What it does.** Deletes cookies named name, additionally filtered by url/domain/path (at least url or domain is required, otherwise the browser does not know which site the cookie belongs to). Unlike clearBrowserCookies(), this is the only way to delete cookies selectively rather than all at once.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `name` (`string`) — the name of the cookie to delete.
- `url`, default `""` — the address of the page or resource the command refers to.
- `domain`, default `""`
- `path`, default `""`


**Example:**

```nim
await deleteCookies(session, "session_id", url = "https://example.com")
echo "cookie deleted" # prints "cookie deleted"
```


### `getResponseBody` — network.nim


```nim
proc getResponseBody*(session: CDPSession, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.}
```


**What it does.** Available only for requests whose data has not yet been "evicted" from the browser's memory (usually — as long as the Network.loadingFinished handler has not run too long ago).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.


**Returns:** `bool]]`


**Example:**

```nim
let (body, isBase64) = await getResponseBody(session, requestId)
echo isBase64 # prints false for text responses (HTML/JSON/text), true for binary ones
```


### `getRequestPostData` — network.nim


```nim
proc getRequestPostData*(session: CDPSession, requestId: string): Future[string] {.async.}
```


**What it does.** The body of a POST request (for example, JSON or form-data) exactly as it was actually sent by the page — available only until Chromium evicts the request data from memory (the same principle as for getResponseBody()).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.


**Returns:** `Future[string]`


**Example:**

```nim
let postData = await getRequestPostData(session, requestId)
echo postData # prints the request body, for example "username=andy&password=secret"
```


### `setBlockedURLs` — network.nim


```nim
proc setBlockedURLs*(session: CDPSession, urls: seq[string]) {.async.}
```


**What it does.** Simple blocking by patterns ("*ads*", "*.png", etc.) — if more flexible logic is needed (for example, deciding on the fly for each request), see cdp/domains/fetch.nim.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `urls` (`seq[string]`) — a list of URL patterns to block, for example ["*ads*", "*.png"].


**Example:**

```nim
await setBlockedURLs(session, @["*.png", "*doubleclick.net*"])
echo "patterns blocked" # prints "patterns blocked"
```


### `setBypassServiceWorker` — network.nim


```nim
proc setBypassServiceWorker*(session: CDPSession, bypass = true) {.async.}
```


**What it does.** bypass = true makes requests go directly to the network, bypassing the page's service worker (if there is one) — useful when it is important to see the real network responses rather than whatever the service worker's cache substitutes for them.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `bypass`, default `true`


**Example:**

```nim
await setBypassServiceWorker(session, true)
echo "service worker is bypassed" # prints "service worker is bypassed" — requests go directly to the network
```


### `emulateNetworkConditions` — network.nim


```nim
proc emulateNetworkConditions*(session: CDPSession, offline = false, latencyMs = 0.0, downloadThroughput = -1.0, uploadThroughput = -1.0, connectionType = "") {.async.}
```


**What it does.** throughput is in bytes/sec, -1 — unlimited. connectionType, for example, "cellular3g" — affects only navigator.connection.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `offline`, default `false`
- `latencyMs`, default `0.0`
- `downloadThroughput`, default `-1.0`
- `uploadThroughput`, default `-1.0`
- `connectionType`, default `""`


**Example:**

```nim
await emulateNetworkConditions(session, offline = false, latencyMs = 300.0,
                                downloadThroughput = 50_000.0, uploadThroughput = 20_000.0)
echo "slow network emulation enabled" # prints "slow network emulation enabled"
```


---

## Fetch Domain — Request Interception

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Fetch/ — pausing requests on the fly with the ability to substitute/block/continue them.


### `enable` — fetch.nim


```nim
proc enable*(session: CDPSession, patterns: seq[string] = @["*"], handleAuthRequests = false) {.async.}
```


**What it does.** patterns — a list of URL patterns to intercept (by default — all requests). handleAuthRequests — also intercept HTTP Basic/Digest auth requests with the "Fetch.authRequired" event (see continueWithAuth).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `patterns` (`seq[string]`), default `@["*"]`
- `handleAuthRequests`, default `false`


**Example:**

```nim
await enable(session, @["*"], handleAuthRequests = false)
echo "request interception enabled" # prints "request interception enabled"
```


### `disable` — fetch.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**What it does.** Disables interception — all subsequent page requests go to the network as usual, without stopping at "Fetch.requestPaused".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await disable(session)
echo "request interception disabled" # prints "request interception disabled"
```


### `continueRequest` — fetch.nim


```nim
proc continueRequest*(session: CDPSession, requestId: string, url = "", methodOverride = "", postData = "", headers: JsonNode = nil) {.async.}
```


**What it does.** Lets the request proceed, optionally substituting the URL/method/body/headers before it actually goes out to the network (all parameters are optional).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.
- `url`, default `""` — the address of the page or resource the command refers to.
- `methodOverride`, default `""`
- `postData`, default `""`
- `headers` (`JsonNode`), default `nil`


**Example:**

```nim
await continueRequest(session, requestId, url = "https://example.com/mocked")
echo "request continued with a modified URL" # prints "request continued with a modified URL"
```


### `failRequest` — fetch.nim


```nim
proc failRequest*(session: CDPSession, requestId: string, errorReason = "BlockedByClient") {.async.}
```


**What it does.** Aborts the request with the specified reason (for example, to block ads).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.
- `errorReason`, default `"BlockedByClient"`


**Example:**

```nim
await failRequest(session, requestId, "BlockedByClient")
echo "request blocked" # prints "request blocked" — the page will see a network error
```


### `fulfillRequest` — fetch.nim


```nim
proc fulfillRequest*(session: CDPSession, requestId: string, responseCode = 200, body = "", mimeType = "text/plain", extraHeaders: JsonNode = nil) {.async.}
```


**What it does.** Responds to the request with pre-prepared content without contacting the network at all — convenient for mocking an API in tests.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.
- `responseCode`, default `200`
- `body`, default `""`
- `mimeType`, default `"text/plain"`
- `extraHeaders` (`JsonNode`), default `nil`


**Example:**

```nim
await fulfillRequest(session, requestId, responseCode = 200,
                      body = """{"ok": true}""", mimeType = "application/json")
echo "response substituted" # prints "response substituted" — the page will receive our JSON instead of the real server's
```


### `getResponseBody` — fetch.nim


```nim
proc getResponseBody*(session: CDPSession, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.}
```


**What it does.** The body of the server's original response for a request paused by Fetch.requestPaused *after* the Response stage (that is, when the response has already been received but not yet handed to the page) — useful for reading it and then, for example, rewriting it with fulfillRequest.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.


**Returns:** `bool]]`


**Example:**

```nim
let (body, isBase64) = await getResponseBody(session, requestId)
echo isBase64 # prints false/true depending on the content type
```


### `takeResponseBodyAsStream` — fetch.nim


```nim
proc takeResponseBodyAsStream*(session: CDPSession, requestId: string): Future[string] {.async.}
```


**What it does.** Returns a stream handle (for large responses) — it must be read via IO.read with the obtained handle.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.


**Returns:** `Future[string]`


**Example:**

```nim
let streamHandle = await takeResponseBodyAsStream(session, requestId)
echo len(streamHandle) > 0 # prints true — a stream identifier for IO.read was obtained
```


### `continueWithAuth` — fetch.nim


```nim
proc continueWithAuth*(session: CDPSession, requestId: string, response: string, username = "", password = "") {.async.}
```


**What it does.** response: "Default" | "CancelAuth" | "ProvideCredentials" — the reply to the "Fetch.authRequired" event (requires enable(handleAuthRequests=true)).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `requestId` (`string`) — the identifier of a specific network request — arrives in Network/Fetch domain events.
- `response` (`string`) — "Default" | "CancelAuth" | "ProvideCredentials".
- `username`, default `""`
- `password`, default `""`


**Example:**

```nim
await continueWithAuth(session, requestId, "ProvideCredentials", "andy", "secret")
echo "credentials sent" # prints "credentials sent"
```


---

## Emulation Domain — Environment Overrides

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Emulation/ — viewport, User-Agent, geolocation, time zone, CPU throttling, etc.


### `setDeviceMetricsOverride` — emulation.nim

```nim
proc setDeviceMetricsOverride*(session: CDPSession, width, height: int, deviceScaleFactor = 1.0, mobile = false) {.async.}
```


**What it does.** Spoofs the viewport dimensions and pixel density — the basis of page.setViewport() in Puppeteer. width/height = 0 resets the override to the real window size.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `width` (`int`) — the viewport width; 0 resets the override.
- `height` (`int`) — the viewport height; 0 resets the override.
- `deviceScaleFactor`, default `1.0`
- `mobile`, default `false`


**Example:**

```nim
await setDeviceMetricsOverride(session, 390, 844, deviceScaleFactor = 3.0, mobile = true)
echo "viewport overridden to match an iPhone" # prints "viewport overridden to match an iPhone"
```


### `clearDeviceMetricsOverride` — emulation.nim


```nim
proc clearDeviceMetricsOverride*(session: CDPSession) {.async.}
```


**What it does.** Resets the override made by setDeviceMetricsOverride() — the viewport size and deviceScaleFactor are once again determined by the real browser window.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await clearDeviceMetricsOverride(session)
echo "viewport override removed" # prints "viewport override removed"
```


### `setUserAgentOverride` — emulation.nim


```nim
proc setUserAgentOverride*(session: CDPSession, userAgent: string, acceptLanguage = "", platform = "") {.async.}
```


**What it does.** The current (non-deprecated) way to override the User-Agent — unlike Network.setUserAgentOverride, it also supports acceptLanguage/platform (which affect navigator.language and navigator.platform).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `userAgent` (`string`) — the User-Agent string.
- `acceptLanguage`, default `""`
- `platform`, default `""`


**Example:**

```nim
await setUserAgentOverride(session, "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", platform = "iPhone")
echo "User-Agent and platform overridden" # prints "User-Agent and platform overridden"
```


### `setGeolocationOverride` — emulation.nim


```nim
proc setGeolocationOverride*(session: CDPSession, latitude, longitude: float, accuracy = 1.0) {.async.}
```


**What it does.** Spoofs the coordinates of navigator.geolocation — the page receives them as a genuine geolocation response, without a system permission dialog (in headless mode there is no such dialog anyway).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `latitude` (`float`) — the latitude in degrees.
- `longitude` (`float`) — the longitude in degrees.
- `accuracy`, default `1.0`


**Example:**

```nim
await setGeolocationOverride(session, 55.7558, 37.6173, accuracy = 10.0)
echo "coordinates overridden to Moscow" # prints "coordinates overridden to Moscow"
```


### `clearGeolocationOverride` — emulation.nim


```nim
proc clearGeolocationOverride*(session: CDPSession) {.async.}
```


**What it does.** Resets the override made by setGeolocationOverride() — afterwards geolocation is either unavailable or uses the browser's real environment.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await clearGeolocationOverride(session)
echo "geolocation override removed" # prints "geolocation override removed"
```


### `setTimezoneOverride` — emulation.nim


```nim
proc setTimezoneOverride*(session: CDPSession, timezoneId: string) {.async.}
```


**What it does.** timezoneId — an IANA name, for example "Europe/Amsterdam".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `timezoneId` (`string`) — an IANA time zone name, for example "Europe/Amsterdam".


**Example:**

```nim
await setTimezoneOverride(session, "Europe/Amsterdam")
echo "time zone overridden" # prints "time zone overridden"
```


### `setLocaleOverride` — emulation.nim


```nim
proc setLocaleOverride*(session: CDPSession, locale = "") {.async.}
```


**What it does.** An empty string resets the override to the system locale.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `locale`, default `""`


**Example:**

```nim
await setLocaleOverride(session, "nl-NL")
echo "locale overridden" # prints "locale overridden"
```


### `setScriptExecutionDisabled` — emulation.nim


```nim
proc setScriptExecutionDisabled*(session: CDPSession, disabled = true) {.async.}
```


**What it does.** Completely enables/disables JS execution on the page (the equivalent of the browser's "allow JavaScript" setting); useful for checking how the page looks/works without scripts (progressive enhancement).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `disabled`, default `true`


**Example:**

```nim
await setScriptExecutionDisabled(session, true)
echo "JS execution disabled" # prints "JS execution disabled"
```


### `setEmulatedMedia` — emulation.nim


```nim
proc setEmulatedMedia*(session: CDPSession, media = "", features: JsonNode = newJArray()) {.async.}
```


**What it does.** media: "screen"/"print"/"" (reset). features — an array of the form [{"name": "prefers-color-scheme", "value": "dark"}].


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `media`, default `""`
- `features` (`JsonNode`), default `newJArray()`


**Example:**

```nim
await setEmulatedMedia(session, media = "print")
echo "print media type emulation enabled" # prints "print media type emulation enabled"
```


### `setCPUThrottlingRate` — emulation.nim


```nim
proc setCPUThrottlingRate*(session: CDPSession, rate: float) {.async.}
```


**What it does.** rate = 1 — no slowdown, rate = 4 — the CPU is 4 times "slower".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `rate` (`float`) — the CPU slowdown factor: 1 — unchanged, 4 — 4 times slower.


**Example:**

```nim
await setCPUThrottlingRate(session, 4.0)
echo "CPU slowed down 4x" # prints "CPU slowed down 4x"
```


### `setDefaultBackgroundColorOverride` — emulation.nim


```nim
proc setDefaultBackgroundColorOverride*(session: CDPSession, r, g, b: int, a = 1.0) {.async.}
```


**What it does.** Useful for screenshots with a transparent background: a = 0.


**Implementation notes.** CDP has no separate command to "remove the background override" — per the protocol specification, calling `Emulation.setDefaultBackgroundColorOverride` with no `color` parameter at all is precisely what means "remove the override". `clearDefaultBackgroundColorOverride()` invokes exactly the same command, simply without parameters, rather than some other protocol method.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `r` (`int`) — the red component, 0–255.
- `g` (`int`) — the green component, 0–255.
- `b` (`int`) — the blue component, 0–255.
- `a`, default `1.0`


**Example:**

```nim
await setDefaultBackgroundColorOverride(session, 0, 0, 0, a = 0.0)
echo "page background became transparent" # prints "page background became transparent"
```


### `clearDefaultBackgroundColorOverride` — emulation.nim


```nim
proc clearDefaultBackgroundColorOverride*(session: CDPSession) {.async.}
```


**What it does.** Resets the background override made by setDefaultBackgroundColorOverride(). CDP has no separate "clear" command for this override — per the protocol specification, calling Emulation.setDefaultBackgroundColorOverride with no "color" parameter at all is precisely what means "remove the override", so the very same command is deliberately called here, but without parameters, rather than a different method.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await clearDefaultBackgroundColorOverride(session)
echo "background override removed" # prints "background override removed"
```


### `setTouchEmulationEnabled` — emulation.nim


```nim
proc setTouchEmulationEnabled*(session: CDPSession, enabled = true, maxTouchPoints = 1) {.async.}
```


**What it does.** Spoofs touch input support (navigator.maxTouchPoints, 'ontouchstart' in window, etc.) — it does not emulate the touch events themselves, only the indicators that they are supported; the events themselves are sent via Input.dispatchTouchEvent (see input.nim).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `enabled`, default `true`
- `maxTouchPoints`, default `1`


**Example:**

```nim
await setTouchEmulationEnabled(session, true, maxTouchPoints = 5)
echo "touch-device indicators enabled" # prints "touch-device indicators enabled"
```


---

## Target Domain — Tabs and Profiles

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Target/ — the protocol analogue of HTTP /json/*, plus isolated profiles and session multiplexing.


### `getTargets` — target.nim


```nim
proc getTargets*(session: CDPSession): Future[seq[JsonNode]] {.async.}
```


**What it does.** The list of all targets (tabs, workers, etc.) visible to the browser — the analogue of HTTP /json/list, but over the protocol.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let targets = await getTargets(session)
echo len(targets) # prints the number of targets visible to the browser
```


### `getTargetInfo` — target.nim


```nim
proc getTargetInfo*(session: CDPSession, targetId = ""): Future[JsonNode] {.async.}
```


**What it does.** Without targetId, returns information about the target the session itself belongs to (relevant when called on an attached session).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `targetId`, default `""` — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let info = await getTargetInfo(session)
echo info["type"] # prints "page" for an ordinary tab
```


### `setDiscoverTargets` — target.nim


```nim
proc setDiscoverTargets*(session: CDPSession, discover = true) {.async.}
```


**What it does.** Enables Target.targetCreated/targetInfoChanged/targetDestroyed notifications about all of the browser's targets, even those we are not attached to.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `discover`, default `true`


**Example:**

```nim
await setDiscoverTargets(session, true)
echo "new-target notifications enabled" # prints "new-target notifications enabled" — Target.targetCreated events will arrive
```


### `activateTarget` — target.nim


```nim
proc activateTarget*(session: CDPSession, targetId: string) {.async.}
```


**What it does.** Makes a tab active on screen (the analogue of Page.bringToFront, but called from a browser-level session by targetId, without attaching).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `targetId` (`string`) — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.


**Example:**

```nim
await activateTarget(session, targetId)
echo "target activated" # prints "target activated"
```


### `createTarget` — target.nim


```nim
proc createTarget*(session: CDPSession, url: string, width = 0, height = 0, browserContextId = "", newWindow = false, background = false): Future[string] {.async.}
```


**What it does.** Creates a new tab and returns its targetId. browserContextId allows opening the tab in an isolated (incognito-like) profile created via createBrowserContext().


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `url` (`string`) — the address of the page or resource the command refers to.
- `width`, default `0`
- `height`, default `0`
- `browserContextId`, default `""` — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.
- `newWindow`, default `false`
- `background`, default `false`


**Returns:** `Future[string]`


**Example:**

```nim
let newTargetId = await createTarget(session, "https://example.com", width = 1280, height = 800)
echo len(newTargetId) > 0 # prints true
```


### `closeTarget` — target.nim


```nim
proc closeTarget*(session: CDPSession, targetId: string) {.async.}
```


**What it does.** Closes a tab/target by its id — the protocol analogue of HTTP /json/close/`<id>` (see cdp/browser.nim -> closeTarget()); childtear.nim uses the HTTP variant by default (see the module header), while this one remains for those who work explicitly through the Target domain.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `targetId` (`string`) — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.


**Example:**

```nim
await closeTarget(session, targetId)
echo "target closed" # prints "target closed"
```


### `createBrowserContext` — target.nim


```nim
proc createBrowserContext*(session: CDPSession): Future[string] {.async.}
```


**What it does.** Creates an isolated profile (with its own cookies/localStorage/cache, separate from the main one and from other contexts) — the analogue of browser.createIncognitoBrowserContext() in Puppeteer. Returns a browserContextId to pass to createTarget().


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[string]`


**Example:**

```nim
let ctxId = await createBrowserContext(session)
echo len(ctxId) > 0 # prints true — an isolated (incognito-like) profile was created
```


### `getBrowserContexts` — target.nim


```nim
proc getBrowserContexts*(session: CDPSession): Future[seq[string]] {.async.}
```


**What it does.** The list of ids of all isolated profiles (see createBrowserContext()) created during the browser's lifetime and not yet destroyed.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[seq[string]]`


**Example:**

```nim
let contexts = await getBrowserContexts(session)
echo len(contexts) # prints the number of previously created isolated profiles
```


### `disposeBrowserContext` — target.nim


```nim
proc disposeBrowserContext*(session: CDPSession, browserContextId: string) {.async.}
```


**What it does.** Destroys a profile and closes all of its tabs.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `browserContextId` (`string`) — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.


**Example:**

```nim
await disposeBrowserContext(session, ctxId)
echo "profile destroyed" # prints "profile destroyed" — together with all its tabs, cookies, etc.
```


### `attachToTarget` — target.nim


```nim
proc attachToTarget*(session: CDPSession, targetId: string, flatten = true): Future[string] {.async.}
```


**What it does.** Attaches to a target and returns a sessionId — in the "flat" (flatten) mode this sessionId must be attached to every subsequent command (see callWithSession below), which allows multiplexing several tabs over a single browser-level WebSocket connection.


**Implementation notes.** With `flatten = true` (the default and the only mode `childtear.nim` uses), all further commands to the attached tab are sent through THE SAME browser-level session, but with a `"sessionId"` field equal to the returned value (see `callWithSession()`), and the incoming events of this tab are marked with the same `"sessionId"` in the envelope — this is how several tabs are multiplexed over a single WebSocket connection instead of a separate socket for each.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `targetId` (`string`) — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.
- `flatten`, default `true`


**Returns:** `Future[string]`


**Example:**

```nim
let attachedSessionId = await attachToTarget(session, targetId, flatten = true)
echo len(attachedSessionId) > 0 # prints true
```


### `detachFromTarget` — target.nim


```nim
proc detachFromTarget*(session: CDPSession, sessionId: string) {.async.}
```


**What it does.** Detaches from a target to which we previously attached via attachToTarget() — the tab itself is not closed; only the multiplexing of its commands/events via sessionId stops.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `sessionId` (`string`) — the session identifier in the "flat" (flattened) multiplexing mode — from the response of `attachToTarget()`.


**Example:**

```nim
await detachFromTarget(session, attachedSessionId)
echo "detached from the target" # prints "detached from the target"
```


### `setAutoAttach` — target.nim


```nim
proc setAutoAttach*(session: CDPSession, autoAttach = true, waitForDebuggerOnStart = false) {.async.}
```


**What it does.** Subscribes to automatic attachment to all new targets — convenient for catching pop-up windows (window.open, target=_blank).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `autoAttach`, default `true`
- `waitForDebuggerOnStart`, default `false`


**Example:**

```nim
await setAutoAttach(session, true, waitForDebuggerOnStart = false)
echo "auto-attach enabled" # prints "auto-attach enabled" — new tabs/workers are auto-attached
```


### `callWithSession` — target.nim


```nim
proc callWithSession*(session: CDPSession, sessionId: string, meth: string, params: JsonNode = newJObject()): Future[JsonNode] {.async.}
```


**What it does.** Sends a command to a specific attached (attachToTarget) tab through the shared browser-level connection, in "flat" mode (see https://chromedevtools.github.io/devtools-protocol/#flattened). The page/dom/runtime/... domains are designed around a separate WebSocket per tab, so this is a standalone low-level primitive for those who explicitly choose to multiplex over a single connection.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `sessionId` (`string`) — the session identifier in the "flat" (flattened) multiplexing mode — from the response of `attachToTarget()`.
- `meth` (`string`) — the protocol command name, for example "Page.navigate".
- `params` (`JsonNode`), default `newJObject()`


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let res = await callWithSession(browserSession, attachedSessionId, "Page.navigate", %*{"url": "https://example.com"})
echo hasKey(res, "frameId") # prints true
```


---

## Browser Domain — Window and Permissions

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Browser/ — OS window size/state, permissions (geolocation, notifications, etc.) at the browser level.


### `getVersion` — browserdomain.nim


```nim
proc getVersion*(session: CDPSession): Future[JsonNode] {.async.}
```


**What it does.** Duplicates what HTTP /json/version returns, but over the protocol (useful if a browser-level session is already open).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let ver = await getVersion(session)
echo ver["product"] # prints something like "HeadlessChrome/120.0.0.0"
```


### `close` — browserdomain.nim


```nim
proc close*(session: CDPSession) {.async.}
```


**What it does.** Terminates the entire browser process (all tabs, all contexts).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await close(session)
echo "browser closed" # prints "browser closed" — entirely, all tabs
```


### `setDownloadBehavior` — browserdomain.nim


```nim
proc setDownloadBehavior*(session: CDPSession, behavior: string, downloadPath = "", browserContextId = "") {.async.}
```


**What it does.** behavior: "deny" | "allow" | "allowAndName" | "default".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `behavior` (`string`) — "deny" | "allow" | "allowAndName" | "default".
- `downloadPath`, default `""`
- `browserContextId`, default `""` — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.


**Example:**

```nim
await setDownloadBehavior(session, "allow", downloadPath = "/tmp/downloads")
echo "download behavior configured at the browser level" # prints "download behavior configured at the browser level"
```


### `getWindowForTarget` — browserdomain.nim


```nim
proc getWindowForTarget*(session: CDPSession, targetId = ""): Future[JsonNode] {.async.}
```


**What it does.** Returns {"windowId", "bounds"} — needed for setWindowBounds.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `targetId`, default `""` — the identifier of the target (tab/worker) — from `listTargets()`/`getTargets()`/the `Target.targetCreated` event.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let win = await getWindowForTarget(session, targetId)
echo win["windowId"] # prints the numeric id of the window the tab belongs to
```


### `setWindowBounds` — browserdomain.nim


```nim
proc setWindowBounds*(session: CDPSession, windowId: int, bounds: JsonNode) {.async.}
```


**What it does.** bounds — for example {"width": 1280, "height": 800} or {"windowState": "maximized"}.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `windowId` (`int`) — the window id obtained from getWindowForTarget().
- `bounds` (`JsonNode`) — for example {"width": 1280, "height": 800} or {"windowState": "maximized"}.


**Example:**

```nim
let win = await getWindowForTarget(session, targetId)
await setWindowBounds(session, win["windowId"].getInt, %*{"width": 1280, "height": 800})
echo "window size changed" # prints "window size changed"
```


### `resetPermissions` — browserdomain.nim


```nim
proc resetPermissions*(session: CDPSession, browserContextId = "") {.async.}
```


**What it does.** Resets all permissions granted via grantPermissions() back to the browser's default behavior (usually "ask"/"deny"; in headless mode, without a UI, permissions without an explicit grant are usually simply unavailable to the site).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `browserContextId`, default `""` — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.


**Example:**

```nim
await resetPermissions(session)
echo "permissions reset" # prints "permissions reset"
```


### `grantPermissions` — browserdomain.nim


```nim
proc grantPermissions*(session: CDPSession, permissions: seq[string], origin = "", browserContextId = "") {.async.}
```


**What it does.** permissions — for example @["geolocation", "notifications"].


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `permissions` (`seq[string]`) — the permission names, for example @["geolocation", "notifications"].
- `origin`, default `""` — an origin in the format "scheme://host[:port]", for example "https://example.com".
- `browserContextId`, default `""` — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.


**Example:**

```nim
await grantPermissions(session, @["geolocation", "notifications"], origin = "https://example.com")
echo "permissions granted" # prints "permissions granted"
```


---

## Storage Domain — Data for a Specific Origin

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Storage/ — targeted, per-origin data clearing, unlike Network.clearBrowserCache()/clearBrowserCookies().


### `clearDataForOrigin` — storage.nim


```nim
proc clearDataForOrigin*(session: CDPSession, origin: string, storageTypes = AllStorageTypes) {.async.}
```


**What it does.** Clears the kinds of data listed in storageTypes (comma-separated), but only for the specified origin (scheme+host+port, for example "https://example.com") — unlike Network.clearBrowserCookies()/clearBrowserCache(), it does not touch the browser's other sites and tabs. IMPORTANT: "cache_storage" here is the Cache API (the service workers' cache), not the browser's HTTP disk cache; CDP itself provides no way to clear specifically the HTTP cache within the bounds of a single origin — this is a protocol limitation (see Network.clearBrowserCache()), not a childtear.nim one.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `origin` (`string`) — an origin in the format "scheme://host[:port]", for example "https://example.com".
- `storageTypes`, default `AllStorageTypes`


**Example:**

```nim
await clearDataForOrigin(session, "https://example.com", "cookies,cache_storage")
echo "origin data cleared" # prints "origin data cleared"
```


### `getCookies` — storage.nim


```nim
proc getCookies*(session: CDPSession, browserContextId = ""): Future[seq[JsonNode]] {.async.}
```


**What it does.** The cookies of the entire isolated profile browserContextId (or of the main profile, if not specified) — unlike Network.getCookies(), it is not tied to a specific tab/its frames.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `browserContextId`, default `""` — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let cookies = await storageApi.getCookies(session)
echo len(cookies) # prints the number of cookies in the entire browser profile
```


### `clearCookies` — storage.nim


```nim
proc clearCookies*(session: CDPSession, browserContextId = "") {.async.}
```


**What it does.** Clears the cookies of the entire isolated profile browserContextId (or of the main profile) — like Network.clearBrowserCookies(), this is a whole-profile operation rather than one for a single origin; to clear a specific origin, use clearDataForOrigin() with storageTypes = "cookies".


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).
- `browserContextId`, default `""` — the identifier of an isolated profile obtained from `createBrowserContext()`; an empty string means the main profile.


**Example:**

```nim
await storageApi.clearCookies(session)
echo "profile cookies cleared" # prints "profile cookies cleared"
```


---

## Log Domain — Browser Console Entries

Protocol documentation for the domain: https://chromedevtools.github.io/devtools-protocol/tot/Log/ — a single stream of browser log entries, including network/security warnings.


### `enable` — log.nim


```nim
proc enable*(session: CDPSession) {.async.}
```


**What it does.** Enables the Log domain — required before subscribing to "Log.entryAdded" (without it the events do not arrive).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await enable(session)
echo "Log domain enabled" # prints "Log domain enabled"
```


### `disable` — log.nim


```nim
proc disable*(session: CDPSession) {.async.}
```


**What it does.** Disables the Log domain — a subscription to "Log.entryAdded" stops receiving new entries.


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await disable(session)
echo "Log domain disabled" # prints "Log domain disabled"
```


### `clear` — log.nim


```nim
proc clear*(session: CDPSession) {.async.}
```


**What it does.** Clears the buffer of already accumulated log entries on the browser side (it does not affect events already sent via "Log.entryAdded" — only what the browser keeps internally).


**Parameters:**

- `session` (`CDPSession`) — a CDP session obtained via `newCDPSession()` — either a regular per-tab one or a browser-level one (see section II).


**Example:**

```nim
await clear(session)
echo "browser log buffer cleared" # prints "browser log buffer cleared"
```


---
## Practical Recipes

### Open a tab and wait for the load "manually"

Without the high-level `childtear.goto()` — what happens under its hood:

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
  echo "page loaded" # prints "page loaded"
  await close(session)

waitFor main()
```

---

### Get an element's text via Runtime instead of the ready-made getText()

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
  echo text # prints the text of the first heading on the page
```

---

### Find a node via the DOM and click it via Input

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
  echo "clicked the center of the button" # prints "clicked the center of the button"
```

---

### Intercept and replace the response of a specific API request

```nim
import std/[asyncdispatch, json]
import cdp/transport
import cdp/domains/fetch as fetchApi

proc main() {.async.} =
  await fetchApi.enable(session, @["*api/config*"])
  proc onPaused(params: JsonNode) {.gcsafe.} =
    let requestId = getStr(params["requestId"])
    asyncCheck fetchApi.fulfillRequest(session, requestId, responseCode = 200,
      body = """{"featureFlag": true}""", mimeType = "application/json")
  on(session, "Fetch.requestPaused", onPaused)
  echo "interception configured" # prints "interception configured"
```

---

### Automatically attach to all new browser tabs

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
    echo "auto-attached to a new tab" # prints for every new tab
  on(browserSession, "Target.attachedToTarget", onAttached)
```

---

### Clear a specific site's data without touching the rest of the browser

```nim
import std/asyncdispatch
import cdp/domains/storage as storageApi

proc main() {.async.} =
  await storageApi.clearDataForOrigin(session, "https://example.com", "cookies,cache_storage,local_storage")
  echo "example.com data cleared" # prints "example.com data cleared"
```

---

## Quick Reference Table

| Task | Module | Function |
|---|---|---|
| Open a CDP session over a WebSocket URL | `transport.nim` | `newCDPSession` |
| Send an arbitrary protocol command | `transport.nim` | `call` |
| Subscribe to an event | `transport.nim` | `on` / `onSession` |
| Wait for one specific event | `transport.nim` | `waitForEvent` |
| List the browser's tabs (without a WebSocket) | `browser.nim` | `listTargets` |
| Open/close a tab (HTTP) | `browser.nim` | `newTarget` / `closeTarget` |
| Navigate to a URL | `page.nim` | `navigate` |
| Screenshot / PDF | `page.nim` | `captureScreenshot` / `printToPDF` |
| Isolated JS world (for an iframe) | `page.nim` | `createIsolatedWorld` |
| Find a node by CSS selector | `dom.nim` | `querySelector` / `querySelectorAll` |
| Element geometry/coordinates | `dom.nim` | `getBoxModel` |
| Look inside an iframe | `dom.nim` | `describeNode(pierce = true)` |
| Execute arbitrary JS | `runtime.nim` | `evaluate` / `evaluateValue` |
| Call a function on an already obtained object | `runtime.nim` | `callFunctionOn` |
| Mouse click/movement by coordinates | `input.nim` | `click` / `moveMouse` |
| Text input | `input.nim` | `insertText` |
| A key with modifiers | `input.nim` | `dispatchKeyEvent` |
| Cookies for a specific URL | `network.nim` | `getCookies` / `setCookie` |
| Clear the entire browser (cookies/cache) | `network.nim` | `clearBrowserCookies` / `clearBrowserCache` |
| Substitute/block a network response | `fetch.nim` | `fulfillRequest` / `failRequest` |
| Spoof the viewport/device | `emulation.nim` | `setDeviceMetricsOverride` |
| Spoof geolocation | `emulation.nim` | `setGeolocationOverride` |
| List/create/close targets over the protocol | `target.nim` | `getTargets` / `createTarget` / `closeTarget` |
| Isolated profile (incognito) | `target.nim` | `createBrowserContext` |
| Multiplexing several tabs | `target.nim` | `attachToTarget` + `callWithSession` |
| OS window size/state | `browserdomain.nim` | `setWindowBounds` |
| Permissions (geolocation, notifications) | `browserdomain.nim` | `grantPermissions` / `resetPermissions` |
| Clear the data of ONE origin | `storage.nim` | `clearDataForOrigin` |
| Browser console entries | `log.nim` | `enable` + the `Log.entryAdded` event |

---

## Summary: Which Function to Choose

- You just need to open a page and wait for it to load → `page.navigate` + `waitForEvent(session, "Page.loadEventFired")` (or, which is almost always better, the ready-made `childtear.goto()`).
- You need to find an element → `dom.querySelector`/`querySelectorAll`; for click coordinates — `dom.getBoxModel`.
- You need to read/change text or compute something on the page → `runtime.evaluate`/`evaluateValue`, rather than parsing the DOM manually through `dom.nim`.
- You need to click/type text as much like a real user as possible → `input.dispatchMouseEvent`/`dispatchKeyEvent`, rather than `runtime.evaluate("el.click()")` — the latter does not trigger handlers that are waiting specifically for a mouse/keyboard event.
- You need to work with the contents of an iframe → `dom.describeNode(pierce = true)` for the `contentDocument.nodeId` + `page.createIsolatedWorld(frameId)` for the execution context.
- You need to observe/modify network traffic without blocking it → `network.nim` (passive observation, reading responses that have already happened).
- You need to intercept a request BEFORE it goes out to the network and substitute/block it → `fetch.nim`, not `network.nim`.
- You need to spoof the environment (device, geolocation, time zone, network) → `emulation.nim`.
- You need to control several tabs from a single connection or create an isolated profile → `target.nim`.
- You need to resize/minimize the browser window or grant a site a permission → `browserdomain.nim`.
- You need to clean up the data of exactly one site without touching the rest of the browser → `storage.clearDataForOrigin`, not `network.clearBrowserCache`/`clearBrowserCookies` (those affect the whole browser — a limitation of the protocol itself).
- Everything listed above is already packaged into convenient commands → use the high-level API, [`childtear_reference_ru.md`](./childtear_reference_ru.md), and drop down to this level only when no ready-made function was found.
