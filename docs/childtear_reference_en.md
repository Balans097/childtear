# childtear — High-Level API Reference

> **Import:** `import childtear`

> **Scope:** the library's main interface for controlling headless Chromium — open a tab, click, fill in a form, read text, take a screenshot, and so on, each with a single command. For cases this API does not cover, there is a low-level CDP layer — see [`cdp_reference_ru.md`](./cdp_reference_ru.md).

This API works with three types: `Browser` — a connection to a running browser (`newBrowser()`), `Tab` — an open tab (`openTab()`/`newPage()`), and `Frame` — the contents of a single iframe (`tab.frame(cssSelector)`). Most functions take a `Tab` as their first parameter; where this is not the case (for example, `Frame` or `Browser`), it is stated separately in the signature. On error (element not found, timeout expired, etc.) functions raise `ChildTearError` rather than silently returning an empty value.

All the examples below assume that `browser: Browser` and `tab: Tab` are already open (see the `openTab()` example at the beginning of section I) — reopening them in the example for every individual function would be redundant. It is also assumed that the code runs inside `proc main() {.async.} = ...` with `import childtear` and `import std/asyncdispatch`.


---

## Table of Contents
I. [Types](#types)
   1. [`Browser`](#browser)
   2. [`Tab`](#tab)
   3. [`Frame`](#frame)
   4. [`ChildTearError`](#childtearerror)
II. [Browser and Tabs](#browser-and-tabs)
   1. [`newBrowser`](#newbrowser)
   2. [`openTab` (Browser)](#opentab-browser)
   3. [`listTabs` (Browser)](#listtabs-browser)
   4. [`attachTab` (Browser)](#attachtab-browser)
   5. [`close` (Tab)](#close-tab)
   6. [`newPage` (Browser)](#newpage-browser)
   7. [`pages` (Browser)](#pages-browser)
   8. [`version` (Browser)](#version-browser)
   9. [`close` (Browser)](#close-browser)
   10. [`createIncognitoContext` (Browser)](#createincognitocontext-browser)
   11. [`newPageInContext` (Browser)](#newpageincontext-browser)
   12. [`closeContext` (Browser)](#closecontext-browser)
   13. [`enableNetwork` (Tab)](#enablenetwork-tab)
   14. [`setExtraHeaders` (Tab)](#setextraheaders-tab)
   15. [`blockUrls` (Tab)](#blockurls-tab)
   16. [`setViewport` (Tab)](#setviewport-tab)
   17. [`setUserAgent` (Tab)](#setuseragent-tab)
   18. [`cookies` (Tab)](#cookies-tab)
   19. [`setCookie` (Tab)](#setcookie-tab)
   20. [`deleteCookie` (Tab)](#deletecookie-tab)
   21. [`clearCookies` (Tab)](#clearcookies-tab)
   22. [`clearCookiesForOrigin` (Tab)](#clearcookiesfororigin-tab)
   23. [`content` (Tab)](#content-tab)
   24. [`setContent` (Tab)](#setcontent-tab)
III. [Navigation](#navigation)
   1. [`goto` (Tab)](#goto-tab)
   2. [`reload` (Tab)](#reload-tab)
IV. [Interacting with Elements](#interacting-with-elements)
   1. [`click` (Tab)](#click-tab)
   2. [`hover` (Tab)](#hover-tab)
   3. [`fill` (Tab)](#fill-tab)
   4. [`fillForm` (Tab)](#fillform-tab)
   5. [`typeText` (Tab)](#typetext-tab)
   6. [`selectOption` (Tab)](#selectoption-tab)
   7. [`uploadFile` (Tab)](#uploadfile-tab)
   8. [`submitForm` (Tab)](#submitform-tab)
   9. [`getText` (Tab)](#gettext-tab)
   10. [`getAllText` (Tab)](#getalltext-tab)
   11. [`count` (Tab)](#count-tab)
   12. [`saveText` (Tab)](#savetext-tab)
   13. [`getAttribute` (Tab)](#getattribute-tab)
   14. [`exists` (Tab)](#exists-tab)
   15. [`waitForSelector` (Tab)](#waitforselector-tab)
   16. [`waitForNavigation` (Tab)](#waitfornavigation-tab)
   17. [`waitForFunction` (Tab)](#waitforfunction-tab)
   18. [`pressEnter` (Tab)](#pressenter-tab)
   19. [`onDialog` (Tab)](#ondialog-tab)
   20. [`acceptDialog` (Tab)](#acceptdialog-tab)
   21. [`dismissDialog` (Tab)](#dismissdialog-tab)
   22. [`autoDismissDialogs` (Tab)](#autodismissdialogs-tab)
V. [JS "Escape Hatch" and Page Snapshots](#js-escape-hatch-and-page-snapshots)
   1. [`evalJS` (Tab)](#evaljs-tab)
   2. [`screenshot` (Tab)](#screenshot-tab)
   3. [`savePDF` (Tab)](#savepdf-tab)
   4. [`title` (Tab)](#title-tab)
   5. [`currentUrl` (Tab)](#currenturl-tab)
VI. [Injectable Scripts and the JS -> Nim Bridge](#injectable-scripts-and-the-js---nim-bridge)
   1. [`addScriptTag` (Tab)](#addscripttag-tab)
   2. [`evaluateOnNewDocument` (Tab)](#evaluateonnewdocument-tab)
   3. [`removeEvaluateOnNewDocument` (Tab)](#removeevaluateonnewdocument-tab)
   4. [`exposeFunction` (Tab)](#exposefunction-tab)
VII. [Navigation: History, Stopping a Load, Tab Focus](#navigation-history-stopping-a-load-tab-focus)
   1. [`goBack` (Tab)](#goback-tab)
   2. [`goForward` (Tab)](#goforward-tab)
   3. [`stop` (Tab)](#stop-tab)
   4. [`bringToFront` (Tab)](#bringtofront-tab)
   5. [`waitForURL` (Tab)](#waitforurl-tab)
VIII. [Mouse and Keyboard: Advanced Gestures](#mouse-and-keyboard-advanced-gestures)
   1. [`doubleClick` (Tab)](#doubleclick-tab)
   2. [`rightClick` (Tab)](#rightclick-tab)
   3. [`clickAt` (Tab)](#clickat-tab)
   4. [`scrollBy` (Tab)](#scrollby-tab)
   5. [`scrollIntoView` (Tab)](#scrollintoview-tab)
   6. [`dragAndDrop` (Tab)](#draganddrop-tab)
   7. [`dragBy` (Tab, Frame)](#dragby-tab-frame)
   8. [`dragToEnd` (Tab, Frame)](#dragtoend-tab-frame)
   9. [`pressKey` (Tab)](#presskey-tab)
   10. [`pressKeyCombo` (Tab)](#presskeycombo-tab)
   11. [`selectAllText` (Tab)](#selectalltext-tab)
   12. [`clearValue` (Tab)](#clearvalue-tab)
IX. [Forms: Checkboxes, Values, Field State](#forms-checkboxes-values-field-state)
   1. [`setChecked` (Tab)](#setchecked-tab)
   2. [`check` (Tab)](#check-tab)
   3. [`uncheck` (Tab)](#uncheck-tab)
   4. [`getValue` (Tab)](#getvalue-tab)
   5. [`isChecked` (Tab)](#ischecked-tab)
   6. [`isDisabled` (Tab)](#isdisabled-tab)
   7. [`isVisible` (Tab)](#isvisible-tab)
   8. [`focus` (Tab)](#focus-tab)
   9. [`blur` (Tab)](#blur-tab)
X. [Reading Element State and Content](#reading-element-state-and-content)
   1. [`boundingBox` (Tab)](#boundingbox-tab)
   2. [`innerHTML` (Tab)](#innerhtml-tab)
   3. [`outerHTML` (Tab)](#outerhtml-tab)
   4. [`getLinks` (Tab)](#getlinks-tab)
   5. [`getAllAttributes` (Tab)](#getallattributes-tab)
   6. [`getViewportSize` (Tab)](#getviewportsize-tab)
XI. [Additional Waits](#additional-waits)
   1. [`waitForSelectorGone` (Tab)](#waitforselectorgone-tab)
   2. [`waitForText` (Tab)](#waitfortext-tab)
   3. [`waitUntilTrue`](#waituntiltrue)
   4. [`waitUntilCleared` (Tab)](#waituntilcleared-tab)
XII. [localStorage and sessionStorage](#localstorage-and-sessionstorage)
   1. [`localStorageGet` (Tab)](#localstorageget-tab)
   2. [`localStorageSet` (Tab)](#localstorageset-tab)
   3. [`localStorageRemove` (Tab)](#localstorageremove-tab)
   4. [`localStorageClear` (Tab)](#localstorageclear-tab)
   5. [`sessionStorageGet` (Tab)](#sessionstorageget-tab)
   6. [`sessionStorageSet` (Tab)](#sessionstorageset-tab)
   7. [`sessionStorageRemove` (Tab)](#sessionstorageremove-tab)
   8. [`sessionStorageClear` (Tab)](#sessionstorageclear-tab)
XIII. [Environment Emulation](#environment-emulation)
   1. [`setGeolocation` (Tab)](#setgeolocation-tab)
   2. [`clearGeolocation` (Tab)](#cleargeolocation-tab)
   3. [`setTimezone` (Tab)](#settimezone-tab)
   4. [`setLocale` (Tab)](#setlocale-tab)
   5. [`emulateMedia` (Tab)](#emulatemedia-tab)
   6. [`setCPUThrottle` (Tab)](#setcputhrottle-tab)
   7. [`setBackgroundColor` (Tab)](#setbackgroundcolor-tab)
   8. [`clearBackgroundColor` (Tab)](#clearbackgroundcolor-tab)
   9. [`enableTouchEmulation` (Tab)](#enabletouchemulation-tab)
   10. [`setJavaScriptEnabled` (Tab)](#setjavascriptenabled-tab)
   11. [`setBypassCSP` (Tab)](#setbypasscsp-tab)
   12. [`setCacheEnabled` (Tab)](#setcacheenabled-tab)
   13. [`clearBrowserCache` (Tab)](#clearbrowsercache-tab)
   14. [`clearCacheForOrigin` (Tab)](#clearcachefororigin-tab)
   15. [`setOffline` (Tab)](#setoffline-tab)
   16. [`throttleNetwork` (Tab)](#throttlenetwork-tab)
XIV. [Permissions and the Browser Window](#permissions-and-the-browser-window)
   1. [`grantPermissions` (Browser)](#grantpermissions-browser)
   2. [`resetPermissions` (Browser)](#resetpermissions-browser)
   3. [`setWindowSize` (Tab)](#setwindowsize-tab)
   4. [`maximizeWindow` (Tab)](#maximizewindow-tab)
XV. [File Downloads and Uploads](#file-downloads-and-uploads)
   1. [`setDownloadPath` (Tab)](#setdownloadpath-tab)
   2. [`interceptFileChooser` (Tab)](#interceptfilechooser-tab)
XVI. [Console and Page Errors](#console-and-page-errors)
   1. [`onConsole` (Tab)](#onconsole-tab)
   2. [`onPageError` (Tab)](#onpageerror-tab)
XVII. [Network: Waiting for Specific Responses](#network-waiting-for-specific-responses)
   1. [`waitForResponse` (Tab)](#waitforresponse-tab)
   2. [`responseBody` (Tab)](#responsebody-tab)
XVIII. [Frames](#frames)
   1. [`frames` (Tab)](#frames-tab)
   2. [`frame` (Tab)](#frame-tab)
   3. [`click` (Frame)](#click-frame)
   4. [`hover` (Frame)](#hover-frame)
   5. [`evalJS` (Frame)](#evaljs-frame)
   6. [`getText` (Frame)](#gettext-frame)
   7. [`getAllText` (Frame)](#getalltext-frame)
   8. [`fill` (Frame)](#fill-frame)
   9. [`exists` (Frame)](#exists-frame)
XIX. [Screenshot of a Single Element](#screenshot-of-a-single-element)
   1. [`screenshotElement` (Tab)](#screenshotelement-tab)
XX. [Other Core Functions](#other-core-functions)
   1. [`insertTextAtCursor`](#inserttextatcursortab-text)
   2. [`setControlledValue`](#setcontrolledvaluetab-selector-value)
   3. [`installNetworkFailureLog`](#installnetworkfailurelogtab)
XXI. [Practical Recipes](#practical-recipes)
XXII. [Brief Table](#brief-table)
XXIII. [Summary: Which Function to Choose](#summary-which-function-to-choose)


Infrastructure that is specific to the site-automation scenario
(`siteworkers/*.nim`) but not to any one particular site lives in
separate modules with their own references:
[`siteworker_common_reference_ru.md`](./siteworker_common_reference_ru.md)
(the `AskResult`/`SiteWorkerPref`/`ImageFormat` types, finding and marking
elements by visible text, `vecho`/`warnLoggedOut`),
[`browser_lifecycle_reference_ru.md`](./browser_lifecycle_reference_ru.md)
(`ensureBrowser`/`stopBrowser`/`gotoWithRetry`/`dumpDebugInfoVerbose`) and
[`clipboard_reference_ru.md`](./clipboard_reference_ru.md)
(`captureAnswerScreenshot` and working with the clipboard).




---

## Types

### `Browser`

A connection to an already running browser (host:port from `newBrowser()`). By itself it does not open any tabs — it is the entry point for `openTab()`/`pages()`/`listTabs()` and for browser-level settings (`grantPermissions()`, `resetPermissions()`).

### `Tab`

An open browser tab with an active CDP WebSocket session. The main object that almost the entire API works with — `goto`/`click`/`fill`/`getText`/`screenshot`, etc. take a `Tab` as their first parameter.

### `Frame`

The contents of a single iframe on the page — obtained via `tab.frame(cssSelector)`. Unlike `Tab`, all high-level work with elements inside a `Frame` goes not against the tab's main document but against the document of that specific iframe — it has its own DOM sub-document and its own JS execution context, created lazily on the first call to `evalJS()`/`getText()`/`fill()`, etc.

### `ChildTearError`

A high-level exception: element not found, navigation failed, wait timeout expired, etc. — it is raised instead of quietly returning an empty/false value.


---

## Browser and Tabs


### `newBrowser`


```nim
proc newBrowser*(host = "127.0.0.1", port = DefaultDebuggingPort): Browser
```


**What it does.** Describes a connection to an already running headless Chromium (see the launch command in the file header). By itself it opens nothing — the connection is established in openTab().


**Parameters:**

- `host`, default `"127.0.0.1"`
- `port`, default `DefaultDebuggingPort`


**Returns:** `Browser`


**Example:**

```nim
let browser = newBrowser("127.0.0.1", 9222)
echo browser != nil # prints true
```


### `openTab` (Browser)


```nim
proc openTab*(browser: Browser, url = ""): Future[Tab] {.async.}
```


**What it does.** "Open a tab". Creates a new tab in the browser, connects to it over WebSocket, and enables the Page/DOM/Runtime domains. If url is given, it navigates there immediately and waits for the load to finish.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `url`, default `""` — the address — of the page to navigate to, of a script, of a resource, etc., depending on the function.


**Returns:** `Future[Tab]`


**Example:**

```nim
let
  browser = newBrowser() # 127.0.0.1:9222 by default
  tab = await openTab(browser, "https://example.com")
echo await title(tab) # prints "Example Domain"
```


### `listTabs` (Browser)


```nim
proc listTabs*(browser: Browser): Future[seq[JsonNode]] {.async.}
```


**What it does.** Returns a list of all tabs already open in the browser (as in chrome://inspect) — each element contains "id", "title", "url".


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let tabs = await listTabs(browser)
echo len(tabs) # prints the number of open tabs
```


### `attachTab` (Browser)


```nim
proc attachTab*(browser: Browser, targetId: string): Future[Tab] {.async.}
```


**What it does.** Attaches to an already existing tab by its id (for example, one obtained from listTabs()), without creating a new one.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `targetId` (`string`) — the id of the tab/target, usually taken from listTabs() or chrome://inspect.


**Returns:** `Future[Tab]`


**Exceptions:**

- `ChildTearError` — if no tab with the given `targetId` exists (for example, it has already been closed).

**Example:**

```nim
let
  tabs = await listTabs(browser)
  tab = await attachTab(browser, getStr(tabs[0]["id"]))
echo await currentUrl(tab) # prints the current URL of the already open tab
```


### `close` (Tab)


```nim
proc close*(tab: Tab) {.async.}
```


**What it does.** Closes the tab: first the WebSocket session, then the tab itself in the browser (via HTTP /json/close). If a browser-level session was already lazily created for this tab (see tabBrowserSession(), used by setWindowSize()/maximizeWindow()), it closes that too — otherwise it would linger until the end of the browser process's lifetime.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await close(tab)
echo "tab closed" # prints "tab closed"
```


### `newPage` (Browser)


```nim
proc newPage*(browser: Browser, url = ""): Future[Tab] {.async.}
```


**What it does.** A synonym for openTab() — this is what the method is called in Puppeteer (browser.newPage()).


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `url`, default `""` — the address — of the page to navigate to, of a script, of a resource, etc., depending on the function.


**Returns:** `Future[Tab]`


**Example:**

```nim
let tab = await newPage(browser, "https://example.com")
echo await title(tab) # prints "Example Domain"
```


### `newPageWithRetry` (Browser)


```nim
proc newPageWithRetry*(browser: Browser, url: string, attempts = 3, delayMs = 2_000,
                        onRetry: RetryCallback = nil): Future[Tab] {.async.}
```


**What it does.** Like `newPage()`, but if the first navigation fails it retries up to `attempts` times with a `delayMs` pause between them. Useful on the cold start of a freshly launched Chromium: `waitForReady()` only waits for the CDP port to be ready, not for the browser to have already resolved its network/proxy settings (WPAD/PAC, etc.) — at that moment the first navigation to a URL occasionally fails with a network error (for example, `net::ERR_TUNNEL_CONNECTION_FAILED`) even though the network as a whole works.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `url` (`string`) — the address of the page to navigate to (unlike `newPage()`, this parameter is required here — without a URL, retries would make no sense).
- `attempts`, default `3` — how many times in total to try navigating to `url` before letting the error propagate.
- `delayMs`, default `2_000` — the pause in milliseconds between failed attempts.
- `onRetry` (`RetryCallback`), default `nil` — `proc(attempt, attempts: int, msg: string)`, called before each retry (the number of the failed attempt, the total number of attempts, the error text)


**Returns:** `Future[Tab]`


**Exceptions:**

- `ChildTearError` — if the navigation failed all `attempts` times in a row; the same exception as that of the last `newPage()` attempt is raised.


**Example:**

```nim
discard startProcess("chromium", args = @["--remote-debugging-port=9222", "--headless=new"])
let browser = newBrowser("localhost", 9222)
await waitForReady(browser)
let tab = await newPageWithRetry(browser, "https://example.com") # survives a temporary network glitch right after startup
```


### `pages` (Browser)


```nim
proc pages*(browser: Browser): Future[seq[Tab]] {.async.}
```


**What it does.** Attaches to all tabs already open in the browser (the equivalent of browser.pages() in Puppeteer) — workers/service workers and the like are skipped in the target list, leaving only real tabs.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.


**Returns:** `Future[seq[Tab]]`


**Example:**

```nim
let tabs = await pages(browser)
echo len(tabs) # prints the number of open tabs as Tab objects
```


### `version` (Browser)


```nim
proc version*(browser: Browser): Future[JsonNode]
```


**What it does.** Browser metadata: the Chromium version, the default User-Agent, the protocol version, etc.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let ver = await version(browser)
echo ver["product"] # prints something like "HeadlessChrome/120.0.0.0"
```


### `waitForReady` (Browser)


```nim
proc waitForReady*(browser: Browser, timeoutMs = 15_000) {.async.}
```


**What it does.** Waits until Chromium brings up the debugging HTTP/CDP endpoint, polling `/json/version` in 200 ms steps. Useful right after the calling code has just started the browser process itself (childtear does not launch it — the browser process has to be started independently, for example via `osproc.startProcess` with the `--remote-debugging-port` flag): there is a small delay between the process starting and the port being ready, and the very first `openTab()`/`newPage()` without this wait may fail with a connection refusal.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()` (the `Browser` object itself can be created even before the port actually opens — the HTTP/WS connection only happens on the first real call).
- `timeoutMs`, default `15_000` — how many milliseconds in total to wait before giving up.


**Returns:** `Future[void]`


**Exceptions:**

- `ChildTearError` — if Chromium did not bring up the debugging port within `timeoutMs`.


**Example:**

```nim
discard startProcess("chromium", args = @["--remote-debugging-port=9222", "--headless=new"])
let browser = newBrowser("localhost", 9222)
await waitForReady(browser) # wait until the port actually opens
let tab = await newPage(browser)
```


### `close` (Browser)


```nim
proc close*(browser: Browser) {.async.}
```


**What it does.** Closes the entire browser (all tabs, the whole process) — unlike Tab.close(), which closes only a single tab.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.


**Example:**

```nim
await close(browser)
echo "browser closed entirely" # prints "browser closed entirely"
```


### `createIncognitoContext` (Browser)


```nim
proc createIncognitoContext*(browser: Browser): Future[string] {.async.}
```


**What it does.** Creates an isolated profile (its own cookies/cache/localStorage) — the equivalent of browser.createIncognitoBrowserContext() in Puppeteer. Returns a browserContextId for newPageInContext()/closeContext().


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.


**Returns:** `Future[string]`


**Example:**

```nim
let ctxId = await createIncognitoContext(browser)
echo len(ctxId) > 0 # prints true — an isolated profile has been created, with no cookies shared with ordinary tabs
```


### `newPageInContext` (Browser)


```nim
proc newPageInContext*(browser: Browser, browserContextId: string, url = ""): Future[Tab] {.async.}
```


**What it does.** Opens a tab inside the isolated profile created by createIncognitoContext().


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `browserContextId` (`string`) — the id of the isolated profile, obtained from createIncognitoContext().
- `url`, default `""` — the address — of the page to navigate to, of a script, of a resource, etc., depending on the function.


**Returns:** `Future[Tab]`


**Example:**

```nim
let
  ctxId = await createIncognitoContext(browser)
  tab = await newPageInContext(browser, ctxId, "https://example.com")
echo await title(tab) # prints "Example Domain", but with this profile's clean cookies
```


### `closeContext` (Browser)


```nim
proc closeContext*(browser: Browser, browserContextId: string) {.async.}
```


**What it does.** Destroys the isolated profile and closes all of its tabs.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `browserContextId` (`string`) — the id of the isolated profile, obtained from createIncognitoContext(); it is destroyed together with all of its tabs.


**Example:**

```nim
let ctxId = await createIncognitoContext(browser)
await closeContext(browser, ctxId)
echo "profile and all its tabs closed" # prints "profile and all its tabs closed"
```


### `enableNetwork` (Tab)


```nim
proc enableNetwork*(tab: Tab) {.async.}
```


**What it does.** Enables the Network domain — it is not done by default, so as not to waste extra traffic on events when they are not needed.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await enableNetwork(tab)
echo "network tracking enabled" # prints "network tracking enabled"
```


### `setExtraHeaders` (Tab)


```nim
proc setExtraHeaders*(tab: Tab, headers: openArray[(string, string)]) {.async.}
```


**What it does.** Adds the given headers to all subsequent HTTP requests of this tab (for example, authorization or a custom User-Agent-like header) — it stays in effect until it is called again with a different set. Requires the Network domain to be enabled (see enableNetwork()).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `headers` (`openArray[(string, string)]`) — (name, value) pairs of headers, for example `{("X-My-Header", "value")}`.


**Example:**

```nim
await setExtraHeaders(tab, {"X-Debug": "1"})
echo "the header will be added to all of the tab's requests" # prints "the header will be added to all of the tab's requests"
```


### `blockUrls` (Tab)


```nim
proc blockUrls*(tab: Tab, urlSubstrings: seq[string]) {.async.}
```


**What it does.** Blocks requests whose URL contains any of the substrings in urlSubstrings (for example, ad/tracker domains), letting the rest through unchanged. Built on the Fetch domain.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `urlSubstrings` (`seq[string]`) — a list of substrings — a request is blocked if its URL contains any of them (for example, ad/tracker domains).


**Example:**

```nim
await blockUrls(tab, @["*.png", "*doubleclick.net*"])
echo "patterns blocked" # prints "patterns blocked"
```


### `setViewport` (Tab)


```nim
proc setViewport*(tab: Tab, width, height: int, deviceScaleFactor = 1.0, mobile = false) {.async.}
```


**What it does.** Fakes the viewport size and pixel density (the equivalent of page.setViewport() in Puppeteer). It stays in effect until it is called again with different values — it does not affect the size of the browser window itself (which, in headless mode, has no screen).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `width` (`int`) — the viewport width in CSS pixels.
- `height` (`int`) — the viewport height in CSS pixels.
- `deviceScaleFactor`, default `1.0`
- `mobile`, default `false`


**Example:**

```nim
await setViewport(tab, 1280, 800)
echo "viewport set to 1280x800" # prints "viewport set to 1280x800"
```


### `setUserAgent` (Tab)


```nim
proc setUserAgent*(tab: Tab, userAgent: string, acceptLanguage = "", platform = "") {.async.}
```


**What it does.** Fakes navigator.userAgent (and, optionally, Accept-Language and navigator.platform) for all subsequent requests and scripts of this tab — it stays in effect until the next call with different values.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `userAgent` (`string`) — the User-Agent string that the page's navigator.userAgent and the HTTP User-Agent header will see.
- `acceptLanguage`, default `""`
- `platform`, default `""`


**Example:**

```nim
await setUserAgent(tab, "Mozilla/5.0 (compatible; childtear-bot)")
echo "User-Agent overridden" # prints "User-Agent overridden"
```


### `cookies` (Tab)


```nim
proc cookies*(tab: Tab, urls: seq[string] = @[]): Future[seq[JsonNode]] {.async.}
```


**What it does.** Without urls, returns the cookies visible to the current page.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `urls` (`seq[string]`), default `@[]`


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let cks = await cookies(tab, @["https://example.com"])
echo len(cks) # prints the number of cookies visible to this URL
```


### `setCookie` (Tab)


```nim
proc setCookie*(tab: Tab, name, value: string, domain = "", path = "/", secure = false, httpOnly = false, sameSite = ""): Future[bool] {.async.}
```


**What it does.** You need to specify domain, otherwise the cookie will be bound to the tab's current URL (which is requested automatically if domain is not passed).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `name` (`string`) — the name — of a cookie, an attribute, a storage key, or a JS function, depending on the function's context.
- `value` (`string`) — the value to set — of a cookie, a storage key, etc.
- `domain`, default `""`
- `path`, default `"/"` — the path to a file on disk — where to save (a screenshot, PDF, text) or where to load from.
- `secure`, default `false`
- `httpOnly`, default `false`
- `sameSite`, default `""`


**Returns:** `Future[bool]`


**Example:**

```nim
let ok = await setCookie(tab, "session_id", "abc123", domain = "example.com", secure = true)
echo ok # prints true if the cookie was set successfully
```


### `deleteCookie` (Tab)


```nim
proc deleteCookie*(tab: Tab, name: string, url = "") {.async.}
```


**What it does.** Deletes a single cookie by name (and, optionally, url — if not passed, the tab's current URL is used). Unlike clearCookies(), it affects only this one cookie, not the entire browser.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `name` (`string`) — the name — of a cookie, an attribute, a storage key, or a JS function, depending on the function's context.
- `url`, default `""` — the address — of the page to navigate to, of a script, of a resource, etc., depending on the function.


**Example:**

```nim
await deleteCookie(tab, "session_id")
echo "cookie deleted" # prints "cookie deleted"
```


### `clearCookies` (Tab)


```nim
proc clearCookies*(tab: Tab) {.async.}
```


**What it does.** WARNING: Chromium has no way to clear the cookies of just one tab — this command clears the cookies of the entire browser (all tabs, all sites, all open profiles). If you only need to clear the cookies of the current site, see clearCookiesForOrigin().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await clearCookies(tab)
echo "browser cookies cleared" # prints "browser cookies cleared" — the whole browser, all sites and tabs
```


### `clearCookiesForOrigin` (Tab)


```nim
proc clearCookiesForOrigin*(tab: Tab) {.async.}
```


**What it does.** Unlike clearCookies() (which clears the whole browser at once — this is how the CDP protocol itself works; it has no separate "cookies of one tab" command), it deletes only the cookies visible to the current page: first it gets their list via cookies() (Network.getCookies), then deletes each one individually via Network.deleteCookies, already bound to a specific URL. Other sites and tabs are not affected.


**Implementation breakdown.** CDP has no separate "clear the cookies of one tab" command — `Network.clearBrowserCookies` always acts on the entire browser at once. The function works around this limitation manually: it gets the list of cookies visible to the current URL via `cookies()` (`Network.getCookies`) and deletes each one individually via `Network.deleteCookies`, already bound to a specific URL — other sites and tabs are not affected.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await clearCookiesForOrigin(tab)
echo "current site's cookies cleared" # prints "current site's cookies cleared" — only the current origin
```


### `content` (Tab)


```nim
proc content*(tab: Tab): Future[string] {.async.}
```


**What it does.** The full HTML of the document (document.documentElement.outerHTML) — the equivalent of page.content() in Puppeteer.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[string]`


**Example:**

```nim
let html = await content(tab)
echo len(html) > 0 # prints true — the page's full HTML markup has been obtained
```


### `setContent` (Tab)


```nim
proc setContent*(tab: Tab, html: string) {.async.}
```


**What it does.** Replaces the page's content with arbitrary HTML without navigating to a URL (the equivalent of page.setContent() in Puppeteer) — convenient for tests when you need a page with exactly specified markup.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `html` (`string`) — the HTML markup that will replace the content of the current document.


**Example:**

```nim
await setContent(tab, "<h1>Replaced manually</h1>")
echo await getText(tab, "h1") # prints "Replaced manually"
```


---

## Navigation


### `goto` (Tab)


```nim
proc goto*(tab: Tab, url: string, timeoutMs = 30_000) {.async.}
```


**What it does.** "Go to a link" (load an arbitrary URL in the current tab). Waits for the Page.loadEventFired event, i.e. it returns control only after the page has fully loaded. If the navigation could not even start (for example, the DNS name does not resolve or the URL is invalid), Page.navigate returns an "errorText" field in its response — in that case Page.loadEventFired will never arrive, so errorText is checked immediately, before waiting for the event, and is turned into a clear error stating the reason and the URL, instead of an opaque timeout after timeoutMs.


**Implementation breakdown.** If the navigation could not even start (for example, the DNS name does not resolve or the URL is invalid), `Page.navigate` returns an `"errorText"` field in its response — in that case the `Page.loadEventFired` event will never arrive. `goto()` checks `errorText` immediately, before waiting for the event, and raises a clear error with the reason and the URL, instead of an opaque timeout after `timeoutMs`.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `url` (`string`) — the address — of the page to navigate to, of a script, of a resource, etc., depending on the function.
- `timeoutMs`, default `30_000` — how many milliseconds to wait before raising a timeout exception/returning false.


**Exceptions:**

- `ChildTearError` — if the navigation could not start (DNS does not resolve, invalid URL, etc. — CDP returned `errorText`); the message states the reason and the URL itself. If `Page.loadEventFired` did not arrive within `timeoutMs` for any other reason — an event-wait timeout (also a `ChildTearError`).

**Example:**

```nim
await goto(tab, "https://example.com")
echo await title(tab) # prints "Example Domain"
```


### `reload` (Tab)


```nim
proc reload*(tab: Tab, ignoreCache = false) {.async.}
```


**What it does.** Reloads the current page and waits for Page.loadEventFired (like goto()). ignoreCache = true — the same as Ctrl+Shift+R, a hard reload bypassing the HTTP cache.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `ignoreCache`, default `false`


**Example:**

```nim
await reload(tab, ignoreCache = true)
echo "page reloaded, bypassing the cache" # prints "page reloaded, bypassing the cache"
```


---

## Interacting with Elements


### `click` (Tab)


```nim
proc click*(tab: Tab, selector: string) {.async.}
```


**What it does.** "Press a button" (or any other element, by CSS selector). Computes the element's center on the screen and emulates a real mouse click via the Input domain — the same way a user does.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await click(tab, "button[type=submit]")
echo "click performed" # prints "click performed"
```


### `hover` (Tab)


```nim
proc hover*(tab: Tab, selector: string) {.async.}
```


**What it does.** Moves the cursor over an element without clicking — emulates mouseover (useful for dropdown menus/tooltips that appear on hover).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await hover(tab, ".dropdown-trigger")
echo "cursor hovered" # prints "cursor hovered" — the mouseover/mouseenter handlers will fire
```


### `fill` (Tab)


```nim
proc fill*(tab: Tab, selector: string, text: string) {.async.}
```


**What it does.** "Fill a field with data". Focuses the element, selects its current content (so that the new text replaces the old rather than being appended to it), and inserts the text via Input.insertText.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `text` (`string`) — the text that will be inserted into the field in place of its current content.


**Exceptions:**

- `ChildTearError` — if the element to fill is not found by `selector`.

**Example:**

```nim
await fill(tab, "#username", "andy")
echo await getValue(tab, "#username") # prints "andy"
```


### `syncControlledValue` (Tab)


```nim
proc syncControlledValue*(tab: Tab, selector: string): Future[bool] {.async.}
```


**What it does.** Fixes fields controlled by a React/Vue-like framework (a "controlled" input component): such a framework overrides the native setter of the `value` property on `<input>`/`<textarea>` with its own — so `fill()`/`type()` (keyboard events/`Input.insertText`) change `.value` bypassing that override, the component itself remains unaware of the change, and on the next re-render it rolls the field back to its own (usually empty) internal state. It fetches the NATIVE setter via the prototype descriptor of `HTMLInputElement`/`HTMLTextAreaElement` (rather than the current one overridden by the framework) and explicitly calls it with the same value that is already in the field, then dispatches an `input` event with `bubbles: true` — after which the framework recomputes the component's state and sees the entered text. Call it AFTER `fill()`/`type()` if you suspect the framework did not notice the change (a typical symptom: the field visually shows the text, but a button that depends on it stays inactive, or the value disappears on the next action on the page).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[bool]` — `false` if the element is not found (this is not considered an error), otherwise `true`.


**Example:**

```nim
await fill(tab, "#react-input", "andy")
discard await syncControlledValue(tab, "#react-input") # make the React component notice the new value
```


### `fillForm` (Tab)


```nim
proc fillForm*(tab: Tab, fields: seq[(string, string)]) {.async.}
```


**What it does.** "Fill a form with data". Takes a list of (selector, value) pairs and fills each field in turn, for example: await fillForm(tab, @[("#login", "andy"), ("#password", "secret")])


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `fields` (`seq[(string, string)]`) — (CSS selector, value) pairs; each field is filled in turn in the same way as with `fill()`. Specifically a `seq`, not an `openArray`: see the explanation under `pressKeyCombo()` — an `openArray` parameter cannot be captured in the closure of an async procedure.


**Example:**

```nim
await fillForm(tab, @{"#username": "andy", "#password": "secret"})
echo "form filled" # prints "form filled"
```


### `typeText` (Tab)


```nim
proc typeText*(tab: Tab, selector: string, text: string, delayMs = 0) {.async.}
```


**What it does.** Unlike fill() (which inserts the text in one piece via insertText), it types one character at a time using real keyboard events — so the page sees keydown/keypress/input for each character separately (needed for fields with input masks, autocomplete, etc., like page.type() in Puppeteer). delayMs is the pause between characters in milliseconds, for more "human-like" typing.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `text` (`string`) — the text typed character by character using real keyboard events.
- `delayMs`, default `0`


**Example:**

```nim
await typeText(tab, "#search", "childtear nim", delayMs = 50)
echo await getValue(tab, "#search") # prints "childtear nim"
```


### `selectOption` (Tab)


```nim
proc selectOption*(tab: Tab, selector: string, value: string) {.async.}
```


**What it does.** Selects the option with the given value in a `<select>` element and fires a "change" event, the way the browser does on a real selection.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `value` (`string`) — the value to set — of a cookie, a storage key, etc.


**Exceptions:**

- `ChildTearError` — if the `<select>` element is not found by `selector`.

**Example:**

```nim
await selectOption(tab, "#country", "NL")
echo await getValue(tab, "#country") # prints "NL"
```


### `uploadFile` (Tab)


```nim
proc uploadFile*(tab: Tab, selector: string, paths: seq[string]) {.async.}
```


**What it does.** Assigns files to an <input type="file"> element directly, without the system file-selection dialog. paths are absolute paths on the disk where the browser itself runs (not necessarily the machine where childtear runs, if Chromium is launched remotely).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `paths` (`seq[string]`) — absolute paths to files on the disk where the browser itself runs (not necessarily the machine where childtear runs).


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await uploadFile(tab, "input[type=file]", @["/tmp/photo.jpg"])
echo "file selected" # prints "file selected"
```


### `submitForm` (Tab)


```nim
proc submitForm*(tab: Tab, selector: string) {.async.}
```


**What it does.** Submits a form programmatically (the equivalent of form.submit()) — useful when the form has no explicit "Submit" button under the cursor.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Example:**

```nim
await submitForm(tab, "#login-form")
echo "form submitted" # prints "form submitted"
```


### `getText` (Tab)


```nim
proc getText*(tab: Tab, selector: string): Future[string] {.async.}
```


**What it does.** Returns the visible text of an element (innerText, or textContent if innerText is unavailable, as is the case with SVG nodes).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[string]`


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
let heading = await getText(tab, "h1")
echo heading # prints "Example Domain"
```


### `getAllText` (Tab)


```nim
proc getAllText*(tab: Tab, selector: string): Future[seq[string]] {.async.}
```


**What it does.** Like getText(), but for ALL elements matching the selector — for example, to collect in a single call the text of all news headlines on a page (a selector like "h3.headline"). The order of the result matches the order of the elements in the document.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[seq[string]]`


**Example:**

```nim
let items = await getAllText(tab, "li.product-name")
echo len(items) # prints the number of list items found
```


### `getLastText` (Tab)


```nim
proc getLastText*(tab: Tab, selector: string): Future[string] {.async.}
```


**What it does.** Like `getText()`, but takes the LAST document node matching `selector` (via `document.querySelectorAll()`), rather than the first (`getText()` uses `document.querySelector()`, which always returns the first match). Useful on pages with a list of identically marked-up repeating elements (chat message history, a feed, etc.) when you need specifically the most recent one. Unlike `getText()`, the absence of matches is NOT considered an error — `""` is returned (on dynamic pages the needed node may not yet be in the DOM at the time of the call). It is used as a building block inside `waitForStableText()` (see below).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the elements being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[string]` — the text of the last match, or `""` if there are no matches.


**Example:**

```nim
let lastMessage = await getLastText(tab, ".chat-message")
echo lastMessage # prints the text of the most recent chat message
```


### `count` (Tab)


```nim
proc count*(tab: Tab, selector: string): Future[int] {.async.}
```


**What it does.** Counts the number of elements matching a CSS selector — convenient as a quick check of the form "there are at least N product cards on the page", without reading the elements' text.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[int]`


**Example:**

```nim
let n = await count(tab, "a")
echo n # prints the number of links on the page
```


### `saveText` (Tab)


```nim
proc saveText*(tab: Tab, selector: string, path: string) {.async.}
```


**What it does.** A convenient combination of getText() + writing to a file: gets the visible text of an element (for example, an entire article, if the selector points to its container — the browser will already insert line breaks between paragraphs in innerText itself) and saves it to the text file path.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `path` (`string`) — the path to a file on disk — where to save (a screenshot, PDF, text) or where to load from.


**Example:**

```nim
await saveText(tab, "article", "/tmp/article.txt")
echo "article text saved to file" # prints "article text saved to file"
```


### `getAttribute` (Tab)


```nim
proc getAttribute*(tab: Tab, selector, name: string): Future[string] {.async.}
```


**What it does.** An element's HTML attribute (Element.getAttribute) — for example, "href" on a link or "data-id" on an arbitrary data attribute. Returns an empty string if the attribute is absent (indistinguishable from an attribute with an empty value — if that matters, check via exists()/evalJS() with hasAttribute()).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `name` (`string`) — the name — of a cookie, an attribute, a storage key, or a JS function, depending on the function's context.


**Returns:** `Future[string]`


**Example:**

```nim
let href = await getAttribute(tab, "a.main-link", "href")
echo href # prints the value of the href attribute, e.g. "https://example.com/more"
```


### `exists` (Tab)


```nim
proc exists*(tab: Tab, selector: string): Future[bool] {.async.}
```


**What it does.** Checks whether an element is present on the page right now, without waiting.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[bool]`


**Example:**

```nim
let found = await exists(tab, "#cookie-banner")
echo found # prints true/false depending on whether the element is present
```


### `existsWithText` (Tab)


```nim
proc existsWithText*(tab: Tab, tag: string, textSubstring: string): Future[bool] {.async.}
```


**What it does.** Looks for an element by HTML tag (for example "button") that contains the given substring in its visible text (the comparison is case-insensitive) — a replacement for Playwright's `:has-text(...)` pseudo-selector, which is absent from ordinary CSS. Useful when the only reliable marker of the needed element is its text, not a class/id/attribute (for example, checking "is there no button with the text 'Log in' on the page", meaning the session is not authorized).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `tag` (`string`) — the name of an HTML tag without CSS decorations, for example "button", "a", "div".
- `textSubstring` (`string`) — the substring of visible text that we look for inside elements with the tag `tag` (case does not matter).


**Returns:** `Future[bool]`


**Example:**

```nim
let loggedOut = await existsWithText(tab, "button", "Log in")
echo loggedOut # prints true if there is a button with the text "Log in" on the page
```


### `waitForSelector` (Tab)


```nim
proc waitForSelector*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**What it does.** Waits for an element to appear on the page (for example, after an AJAX request or an animation), polling the DOM at the given interval. Returns true if the element appeared before timeoutMs expired, otherwise false.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `timeoutMs`, default `5_000` — how many milliseconds to wait before raising a timeout exception/returning false.
- `pollIntervalMs`, default `100` — how often (in milliseconds) to recheck the condition while waiting — a compromise between responsiveness and load on the CDP connection.


**Returns:** `Future[bool]`


**Example:**

```nim
let appeared = await waitForSelector(tab, "#result", timeoutMs = 5_000)
echo appeared # prints true if the element appeared before the timeout expired
```


### `waitForNavigation` (Tab)


```nim
proc waitForNavigation*(tab: Tab, timeoutMs = 30_000): Future[JsonNode]
```


**What it does.** Unlike goto(), it does not start a navigation itself, but merely waits for the next page load — the wait is registered synchronously at the moment of the call, so the typical Puppeteer scenario "click a link and wait for the navigation" works without a race: let navigated = waitForNavigation(tab) await click(tab, "a.some-link") discard await navigated


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `timeoutMs`, default `30_000` — how many milliseconds to wait before raising a timeout exception/returning false.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
await click(tab, "a.next-page")
discard await waitForNavigation(tab, timeoutMs = 10_000)
echo "navigation to the new page complete" # prints "navigation to the new page complete"
```


### `waitForFunction` (Tab)


```nim
proc waitForFunction*(tab: Tab, expression: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[JsonNode] {.async.}
```


**What it does.** Polls a JS expression until it returns a "truthy" (in the JS sense) value — the equivalent of page.waitForFunction() in Puppeteer. Returns the final value of the expression.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `expression` (`string`) — the JS expression polled until it returns a "truthy" (in the JS sense) value.
- `timeoutMs`, default `5_000` — how many milliseconds to wait before raising a timeout exception/returning false.
- `pollIntervalMs`, default `100` — how often (in milliseconds) to recheck the condition while waiting — a compromise between responsiveness and load on the CDP connection.


**Returns:** `Future[JsonNode]`


**Exceptions:**

- `ChildTearError` — if `expression` did not become truthy (in the JS sense) within `timeoutMs`.

**Example:**

```nim
discard await waitForFunction(tab, "document.readyState === 'complete'")
echo "document fully loaded" # prints "document fully loaded"
```


### `pressEnter` (Tab)


```nim
proc pressEnter*(tab: Tab, selector = "") {.async.}
```


**What it does.** Presses Enter — either in the currently focused element or (if selector is passed) after clicking on it first.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector`, default `""` — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Example:**

```nim
await fill(tab, "#search", "childtear")
await pressEnter(tab, "#search")
echo "search submitted via Enter" # prints "search submitted via Enter"
```


### `onDialog` (Tab)


```nim
proc onDialog*(tab: Tab, handler: DialogHandler)
```


**What it does.** Subscribes to the opening of JS dialogs (alert/confirm/prompt/ beforeunload). IMPORTANT: while a dialog is open, the tab is "frozen" — navigation and most commands do not execute until the dialog is closed via acceptDialog()/dismissDialog(). Unlike interactive mode, Chromium does NOT close dialogs by itself — if you do not subscribe (or use autoDismissDialogs()), the tab may hang on the very first alert().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `handler` (`DialogHandler`) — a callback function that receives the dialog's text, its type ("alert"/"confirm"/"prompt"/"beforeunload"), and the default text for prompt().


**Example:**

```nim
proc handler(kind, message: string): bool =
  echo message # prints the dialog's text, e.g. "Are you sure?"
  result = true # true — accept (OK), false — dismiss (Cancel)
onDialog(tab, handler)
```


### `acceptDialog` (Tab)


```nim
proc acceptDialog*(tab: Tab, promptText = "") {.async.}
```


**What it does.** Accepts an open JS dialog (OK for alert/confirm, Enter for prompt). promptText is what to "type" into a prompt() dialog before accepting; it is ignored for alert()/confirm().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `promptText`, default `""`


**Example:**

```nim
await acceptDialog(tab, promptText = "my answer")
echo "dialog accepted" # prints "dialog accepted"
```


### `dismissDialog` (Tab)


```nim
proc dismissDialog*(tab: Tab) {.async.}
```


**What it does.** Dismisses an open JS dialog (Cancel for confirm/prompt; for alert() it is equivalent to acceptDialog(), since it has no "cancel" option).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await dismissDialog(tab)
echo "dialog dismissed" # prints "dialog dismissed"
```


### `autoDismissDialogs` (Tab)


```nim
proc autoDismissDialogs*(tab: Tab)
```


**What it does.** A convenient default: all dialogs are dismissed automatically so that the page does not hang, if explicit handling is not needed.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
autoDismissDialogs(tab)
echo "all further dialogs will be closed automatically" # prints "all further dialogs will be closed automatically"
```


---

## JS "Escape Hatch" and Page Snapshots


### `evalJS` (Tab)


```nim
proc evalJS*(tab: Tab, expression: string): Future[JsonNode] {.async.}
```


**What it does.** Executes arbitrary JS code and returns the result as JSON — for cases not covered by the ready-made commands above.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `expression` (`string`) — arbitrary JS code, executed in the context of the page's main document.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let res = await evalJS(tab, "document.querySelectorAll('a').length")
echo res["result"]["value"] # prints the number of links on the page
```


### `screenshot` (Tab)


```nim
proc screenshot*(tab: Tab, path: string, format = "png", fullPage = false, quality = 100) {.async.}
```


**What it does.** Saves a screenshot of the tab's current state to a file at path. format: "png" or "jpeg". fullPage = true captures the entire page (including what is outside the current viewport), not just the visible area.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `path` (`string`) — the path to a file on disk — where to save (a screenshot, PDF, text) or where to load from.
- `format`, default `"png"`
- `fullPage`, default `false`
- `quality`, default `100`


**Example:**

```nim
await screenshot(tab, "/tmp/page.png", fullPage = true)
echo "screenshot saved" # prints "screenshot saved"
```


### `savePDF` (Tab)


```nim
proc savePDF*(tab: Tab, path: string, landscape = false, printBackground = true) {.async.}
```


**What it does.** Saves the current page as a PDF (the equivalent of the browser's "print to PDF").


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `path` (`string`) — the path to a file on disk — where to save (a screenshot, PDF, text) or where to load from.
- `landscape`, default `false`
- `printBackground`, default `true`


**Example:**

```nim
await savePDF(tab, "/tmp/page.pdf", landscape = false)
echo "PDF saved" # prints "PDF saved"
```


### `title` (Tab)


```nim
proc title*(tab: Tab): Future[string] {.async.}
```


**What it does.** The current page title (document.title).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[string]`


**Example:**

```nim
let pageTitle = await title(tab)
echo pageTitle # prints "Example Domain"
```


### `currentUrl` (Tab)


```nim
proc currentUrl*(tab: Tab): Future[string] {.async.}
```


**What it does.** The page's current URL (location.href) — taking redirects and client-side navigation into account (unlike the URL that was passed to the last goto()).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[string]`


**Example:**

```nim
let url = await currentUrl(tab)
echo url # prints "https://example.com/", taking redirects into account
```


---

## Injectable Scripts and the JS -> Nim Bridge


### `addScriptTag` (Tab)


```nim
proc addScriptTag*(tab: Tab, url = "", content = "") {.async.}
```


**What it does.** Adds a `<script>` to the current page — either by url (waits for it to load), or with ready-made content (exactly one of the two options must be specified). The equivalent of page.addScriptTag() in Puppeteer.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `url`, default `""` — the address — of the page to navigate to, of a script, of a resource, etc., depending on the function.
- `content`, default `""`


**Exceptions:**

- `ChildTearError` — if exactly one of `url`/`content` is not specified (neither or both at once).

**Example:**

```nim
await addScriptTag(tab, content = "window.__marker = 42;")
echo "script added and executed" # prints "script added and executed"
```


### `evaluateOnNewDocument` (Tab)


```nim
proc evaluateOnNewDocument*(tab: Tab, script: string): Future[string] {.async.}
```


**What it does.** The script will be executed before any of the page's own JS on every subsequent document load (the equivalent of page.evaluateOnNewDocument() in Puppeteer). Returns an identifier for removeEvaluateOnNewDocument().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `script` (`string`) — JS code that will be executed before any of the page's own scripts on every subsequent document load.


**Returns:** `Future[string]`


**Example:**

```nim
let scriptId = await evaluateOnNewDocument(tab, "window.__injected = true;")
echo len(scriptId) > 0 # prints true — the script will now run on every new navigation
```


### `removeEvaluateOnNewDocument` (Tab)


```nim
proc removeEvaluateOnNewDocument*(tab: Tab, identifier: string) {.async.}
```


**What it does.** Cancels a script added by evaluateOnNewDocument(), by the identifier it returned — it does not affect an already loaded document, only subsequent navigations.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `identifier` (`string`) — the identifier returned by evaluateOnNewDocument().


**Example:**

```nim
await removeEvaluateOnNewDocument(tab, scriptId)
echo "script auto-run cancelled" # prints "script auto-run cancelled"
```


### `exposeFunction` (Tab)


```nim
proc exposeFunction*(tab: Tab, name: string, callback: ExposedCallback) {.async.}
```


**What it does.** Adds a function `name` to the page's window: JS code can call it like an ordinary (asynchronous) function, while it will actually be executed here, on the Nim side — the equivalent of page.exposeFunction() in Puppeteer. callback receives the array of call arguments as a JsonNode and must return a JSON-serializable result. Technically this is Runtime.addBinding (a low-level bridge that can only "fire and forget" from the page's side) plus an injected JS shim that wraps it in a real Promise, and a "Runtime.bindingCalled" event handler that calls the callback and resolves the corresponding Promise via Runtime.evaluate.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `name` (`string`) — the name — of a cookie, an attribute, a storage key, or a JS function, depending on the function's context.
- `callback` (`ExposedCallback`) — a Nim-side function called on every invocation of name from the page's JS; it receives the call arguments as a JsonNode and must return a JSON-serializable result.


**Example:**

```nim
proc onNimSide(args: seq[JsonNode]): JsonNode =
  echo "called from JS on the page: ", args # prints the passed arguments
  result = %*{"ok": true}
await exposeFunction(tab, "nimCallback", onNimSide)
discard await evalJS(tab, "window.nimCallback('hello')")
```


---

## Navigation: History, Stopping a Load, Tab Focus


### `goBack` (Tab)


```nim
proc goBack*(tab: Tab): Future[bool] {.async.}
```


**What it does.** The equivalent of the browser's "back" button. Returns false (and navigates nowhere) if the tab's history has no previous entry.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[bool]`


**Example:**

```nim
let moved = await goBack(tab)
echo moved # prints true if there was a previous entry in the history
```


### `goForward` (Tab)


```nim
proc goForward*(tab: Tab): Future[bool] {.async.}
```


**What it does.** The equivalent of the "forward" button. Returns false if the tab's history has no next entry (for example, if no one has gone back yet).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[bool]`


**Example:**

```nim
let moved = await goForward(tab)
echo moved # prints true if there was a next entry in the history
```


### `stop` (Tab)


```nim
proc stop*(tab: Tab) {.async.}
```


**What it does.** Stops the current page load (the equivalent of the browser's "stop" button/Escape during loading).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await stop(tab)
echo "load stopped" # prints "load stopped"
```


### `bringToFront` (Tab)


```nim
proc bringToFront*(tab: Tab) {.async.}
```


**What it does.** Makes the tab active among the other tabs of the same browser.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await bringToFront(tab)
echo "tab brought to the foreground" # prints "tab brought to the foreground"
```


### `waitForURL` (Tab)


```nim
proc waitForURL*(tab: Tab, substring: string, timeoutMs = 10_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**What it does.** Waits until location.href contains substring — for example, after clicking a link that leads through several intermediate redirects, when a single Page.loadEventFired is not enough.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `substring` (`string`) — the substring that location.href must contain for the wait to succeed.
- `timeoutMs`, default `10_000` — how many milliseconds to wait before raising a timeout exception/returning false.
- `pollIntervalMs`, default `100` — how often (in milliseconds) to recheck the condition while waiting — a compromise between responsiveness and load on the CDP connection.


**Returns:** `Future[bool]`


**Example:**

```nim
await click(tab, "a.checkout")
let arrived = await waitForURL(tab, "/checkout", timeoutMs = 10_000)
echo arrived # prints true if the URL came to contain "/checkout" before the timeout expired
```


---

## Mouse and Keyboard: Advanced Gestures


### `doubleClick` (Tab)


```nim
proc doubleClick*(tab: Tab, selector: string) {.async.}
```


**What it does.** A double click — like click(), but with two consecutive presses and the correct clickCount, so that the page sees a genuine dblclick rather than two independent single clicks.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await doubleClick(tab, ".editable-cell")
echo "double click performed" # prints "double click performed"
```


### `rightClick` (Tab)


```nim
proc rightClick*(tab: Tab, selector: string) {.async.}
```


**What it does.** Opens the context menu (emulates a right mouse click). The system menu itself is not rendered in headless Chromium, but the page receives a genuine "contextmenu" event, as from a live click.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await rightClick(tab, "#file-item")
echo "right click performed" # prints "right click performed" — the page's context menu will open, if it has one
```


### `clickAt` (Tab)


```nim
proc clickAt*(tab: Tab, x, y: float) {.async.}
```


**What it does.** A click at absolute viewport coordinates, bypassing the CSS-selector lookup — for example, when a specific point inside an element matters (a canvas, a map, a custom slider), rather than the element as a whole.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `x` (`float`) — the horizontal coordinate in the page's coordinate system (CSS pixels from the left edge of the viewport).
- `y` (`float`) — the vertical coordinate in the page's coordinate system (CSS pixels from the top edge of the viewport).


**Example:**

```nim
await clickAt(tab, 400.0, 300.0)
echo "click at coordinates (400, 300)" # prints "click at coordinates (400, 300)"
```


### `scrollBy` (Tab)


```nim
proc scrollBy*(tab: Tab, deltaX, deltaY: float) {.async.}
```


**What it does.** Scrolls the page with the mouse wheel (a positive deltaY scrolls down).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `deltaX` (`float`) — the horizontal scroll offset in pixels.
- `deltaY` (`float`) — the vertical scroll offset in pixels (a positive value scrolls down).


**Example:**

```nim
await scrollBy(tab, 0.0, 600.0)
echo "page scrolled down 600px" # prints "page scrolled down 600px"
```


### `scrollIntoView` (Tab)


```nim
proc scrollIntoView*(tab: Tab, selector: string) {.async.}
```


**What it does.** Scrolls the page so that the element ends up in the visible area — without clicking/hovering (click()/hover() do this themselves).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await scrollIntoView(tab, "#footer")
echo "footer in view" # prints "footer in view"
```


### `dragAndDrop` (Tab)


```nim
proc dragAndDrop*(tab: Tab, sourceSelector, targetSelector: string, native = false) {.async.}
```


**What it does.** Drags sourceSelector onto targetSelector. native = false (the default) — an "honest mouse": hovering and pressing the button on the source, moving to the target, releasing, via Input.dispatchMouseEvent. It works for everything that reacts to ordinary mouse events (JS sortable lists such as Sortable.js, custom sliders), but does NOT guarantee that native HTML5 drag-and-drop (dragstart/dragover/drop) fires — some sites wait for exactly those events, which mouse Input.dispatchMouseEvent does not generate at all (that is how the browser itself works: HTML5 DnD is a separate mechanism, not a consequence of ordinary mouse events). native = true — instead of the mouse, it directly dispatches to the source/target a sequence of genuine DragEvents (dragstart, dragenter, dragover, drop, dragend) with a shared DataTransfer object, the way the browser does on a real HTML5 drag. It is needed for elements with draggable="true" and ondrop/ondragover handlers — what the mouse mode does not trigger. Limitation: real files (dragging a file from the OS into an input) cannot be faked this way — DataTransfer.files is read-only and available only from a genuine system drag-and-drop; to upload files use uploadFile().


**Implementation breakdown.** With `native = false` — an "honest mouse": `Input.dispatchMouseEvent` with hovering, pressing, moving, and releasing — it works for sortable lists and sliders built on ordinary mouse events, but does NOT guarantee that native HTML5 drag-and-drop fires, because the browser generates `dragstart`/`dragover`/`drop` separately from ordinary mouse events, not as their consequence. With `native = true`, instead of the mouse, a genuine sequence of `DragEvent`s with a shared `DataTransfer` object is dispatched directly to the source and the target — the way the browser itself does when dragging — which is exactly what elements with `draggable="true"` and `ondrop`/`ondragover` handlers require.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `sourceSelector` (`string`) — the CSS selector of the element being dragged (the source).
- `targetSelector` (`string`) — the CSS selector of the element onto which the drag is performed (the target).
- `native`, default `false` — true — genuine HTML5 drag-and-drop events (dragstart/dragover/drop); false (the default) — mouse emulation.


**Exceptions:**

- `ChildTearError` — if the source or the target is not found by its selector; with `native = true` — a separate message if the synthetic HTML5 drag-and-drop event did not fire.

**Example:**

```nim
# native = true — genuine dragstart/dragover/drop, not mouse emulation
await dragAndDrop(tab, "#drag-item", "#drop-zone", native = true)
echo "drag performed" # prints "drag performed"
```


### `dragBy` (Tab, Frame)


```nim
proc dragBy*(tab: Tab, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.}
proc dragBy*(frame: Frame, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.}
```


**What it does.** Presses the left mouse button at the center of the `selector` element, moves the cursor by `(dx, dy)` pixels (`dx > 0` — to the right, `dy > 0` — down), and releases the button. Intended for sliders without a target element (`input[type=range]`, noUiSlider, "swipe to confirm"). The input is genuine (`isTrusted = true`), the trajectory is smoothed (smoothstep), and every `mouseMoved` carries `buttons = 1`. The `Frame` version works with an element inside an `<iframe>`.

**Parameters:** `steps` — the number of intermediate movements; `stepDelayMs` — the pause between them, in ms; `holdMs` — the pause after pressing before the movement begins, in ms.

**Example:**

```nim
await dragBy(tab, "div.slider-handle", 300.0, 0.0)
```


### `dragToEnd` (Tab, Frame)


```nim
proc dragToEnd*(tab: Tab, handleSelector, trackSelector: string,
                steps = 25, stepDelayMs = 16, holdMs = 80) {.async.}
proc dragToEnd*(frame: Frame, handleSelector, trackSelector: string,
                steps = 25, stepDelayMs = 16, holdMs = 80) {.async.}
```


**What it does.** Drags the handle `handleSelector` to the right edge of the track `trackSelector`; the distance is computed from the geometry of both elements (`boundingBox()`), rather than being given as a number.

**Example:**

```nim
await dragToEnd(tab, ".slider-handle", ".slider-track")
```


### `pressKey` (Tab)


```nim
proc pressKey*(tab: Tab, key: string, modifiers = 0) {.async.}
```


**What it does.** Presses and releases a single named key (for example "Tab", "Escape", "ArrowDown") in the currently focused element.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key name according to CDP's nomenclature, for example "Tab", "Escape", "ArrowDown" (usually the same as KeyboardEvent.key in the browser).
- `modifiers`, default `0`


**Example:**

```nim
await pressKey(tab, "Escape")
echo "Escape key pressed" # prints "Escape key pressed"
```


### `pressKeyCombo` (Tab)


```nim
proc pressKeyCombo*(tab: Tab, keys: seq[string]) {.async.}
```


**What it does.** Presses a key combination, for example @["Control", "a"] for Ctrl+A. All keys except the last are treated as modifiers (Control/ Alt/Shift/Meta) and are held down until the last (main) key is pressed and released — which is how a real keyboard sends combinations.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `keys` (`seq[string]`) — the keys of the combination in order, for example @["Control", "a"]; all keys except the last are treated as modifiers and are held until the last (main) key is pressed and released. Specifically a `seq`, not an `openArray`: an openArray parameter cannot be captured in the closure of a Nim async procedure (the compiler refuses after the first await in the body — "cannot be captured as it would violate memory safety").


**Example:**

```nim
await pressKeyCombo(tab, @["Control", "a"])
echo "Ctrl+A combination pressed" # prints "Ctrl+A combination pressed"
```


### `selectAllText` (Tab)


```nim
proc selectAllText*(tab: Tab, selector = "") {.async.}
```


**What it does.** Selects all text (Ctrl+A) — either in the currently focused element or (if selector is passed) after clicking on it first.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector`, default `""` — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Example:**

```nim
await selectAllText(tab, "#editor")
echo "all of the field's text selected" # prints "all of the field's text selected"
```


### `clearValue` (Tab)


```nim
proc clearValue*(tab: Tab, selector: string) {.async.}
```


**What it does.** Clears the value of an input field directly (el.value = ''), with input/change events — more reliable than select-all + Backspace for fields with text of arbitrary length.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if the element to clear is not found by `selector`.

**Example:**

```nim
await clearValue(tab, "#search")
echo await getValue(tab, "#search") # prints "" (the field is cleared)
```


---

## Forms: Checkboxes, Values, Field State


### `setChecked` (Tab)


```nim
proc setChecked*(tab: Tab, selector: string, checked: bool) {.async.}
```


**What it does.** Sets the state of a checkbox/radio button directly and fires a "change" event, the way the browser does on a real click.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `checked` (`bool`) — true — check the checkbox/radio button, false — uncheck it.


**Exceptions:**

- `ChildTearError` — if the checkbox/radio button is not found by `selector`.

**Example:**

```nim
await setChecked(tab, "#agree", true)
echo await isChecked(tab, "#agree") # prints true
```


### `check` (Tab)


```nim
proc check*(tab: Tab, selector: string) {.async.}
```


**What it does.** Checks a checkbox/radio button (setChecked(tab, selector, true)).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Example:**

```nim
await check(tab, "#subscribe")
echo await isChecked(tab, "#subscribe") # prints true
```


### `uncheck` (Tab)


```nim
proc uncheck*(tab: Tab, selector: string) {.async.}
```


**What it does.** Unchecks a checkbox (setChecked(tab, selector, false)); for a radio button it is usually meaningless — radio buttons are cleared by selecting another radio button in the same group, not by a programmatic reset.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Example:**

```nim
await uncheck(tab, "#subscribe")
echo await isChecked(tab, "#subscribe") # prints false
```


### `getValue` (Tab)


```nim
proc getValue*(tab: Tab, selector: string): Future[string] {.async.}
```


**What it does.** The value of an input/textarea/select (el.value).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[string]`


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
let val = await getValue(tab, "#username")
echo val # prints the field's current value, e.g. "andy"
```


### `isChecked` (Tab)


```nim
proc isChecked*(tab: Tab, selector: string): Future[bool] {.async.}
```


**What it does.** Whether a checkbox/radio button is checked (el.checked). Returns false if the element is not found (see isVisible() regarding this same choice of "not found = false" instead of an exception).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[bool]`


**Example:**

```nim
let checked = await isChecked(tab, "#agree")
echo checked # prints true/false
```


### `isDisabled` (Tab)


```nim
proc isDisabled*(tab: Tab, selector: string): Future[bool] {.async.}
```


**What it does.** Whether a form element is disabled (el.disabled) — unavailable for input and not submitted along with the form. Returns false if the element is not found.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[bool]`


**Example:**

```nim
let disabled = await isDisabled(tab, "button[type=submit]")
echo disabled # prints true if the button is unavailable for pressing
```


### `isVisible` (Tab)


```nim
proc isVisible*(tab: Tab, selector: string): Future[bool] {.async.}
```


**What it does.** "Visibility" in the everyday sense: the element exists, has non-zero dimensions, and is not hidden via display:none/visibility:hidden. Does NOT check for overlap by other elements on top of it.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[bool]`


**Example:**

```nim
let visible = await isVisible(tab, "#modal")
echo visible # prints true/false
```


### `focus` (Tab)


```nim
proc focus*(tab: Tab, selector: string) {.async.}
```


**What it does.** Programmatically focuses an element (el.focus() via the DOM domain — see domApi.focus()); the element must be focusable.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await focus(tab, "#search")
echo "field focused" # prints "field focused"
```


### `blur` (Tab)


```nim
proc blur*(tab: Tab, selector: string) {.async.}
```


**What it does.** Removes focus from an element (el.blur()) — for example, to trigger a "blur" event/field validation without moving focus to anything specific.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
await blur(tab, "#search")
echo "focus removed" # prints "focus removed"
```


---

## Reading Element State and Content


### `boundingBox` (Tab)


```nim
proc boundingBox*(tab: Tab, selector: string): Future[tuple[x, y, width, height: float]] {.async.}
```


**What it does.** The coordinates and dimensions of an element on the page (viewport-relative, after scrolling it into view) — for example, to manually hover the cursor over an arbitrary point inside an element rather than only its center (see nodeCenter()/click()/hover()), or to compute a clip for screenshotElement().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `float]]`


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
let box = await boundingBox(tab, "#header")
echo box.width # prints the element's width in CSS pixels
```


### `innerHTML` (Tab)


```nim
proc innerHTML*(tab: Tab, selector: string): Future[string] {.async.}
```


**What it does.** The HTML markup INSIDE an element, without the element itself (Element.innerHTML) — unlike outerHTML() below.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[string]`


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
let html = await innerHTML(tab, "#card")
echo html # prints the HTML markup inside the element, e.g. "<h2>Heading</h2><p>Text</p>"
```


### `outerHTML` (Tab)


```nim
proc outerHTML*(tab: Tab, selector: string): Future[string] {.async.}
```


**What it does.** Unlike innerHTML() (via JS), it is obtained via the DOM domain (DOM.getOuterHTML) — both approaches are equivalent in result; here the alternative path, no longer tied to eval, is simply shown.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[string]`


**Exceptions:**

- `ChildTearError` — if no element is found by `selector`.

**Example:**

```nim
let html = await outerHTML(tab, "#card")
echo html # prints "<div id=\"card\">...</div>" including the element itself
```


### `getLinks` (Tab)


```nim
proc getLinks*(tab: Tab): Future[seq[tuple[text, href: string]]] {.async.}
```


**What it does.** All links on the page: the visible text and the href value as is (relative paths are not resolved to absolute ones — use getAttribute()/absoluteUrl-like logic on your side if that matters).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `string]]]`


**Example:**

```nim
let links = await getLinks(tab)
echo len(links) # prints the number of links on the page
```


### `getAllAttributes` (Tab)


```nim
proc getAllAttributes*(tab: Tab, selector, name: string): Future[seq[string]] {.async.}
```


**What it does.** The value of the attribute name on ALL elements matching the selector (the analog of getAllText(), but for an attribute rather than text); a missing attribute yields an empty string at the corresponding position.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `name` (`string`) — the name — of a cookie, an attribute, a storage key, or a JS function, depending on the function's context.


**Returns:** `Future[seq[string]]`


**Example:**

```nim
let ids = await getAllAttributes(tab, "li.item", "data-id")
echo ids # prints @["101", "102", "103"]
```


### `getViewportSize` (Tab)


```nim
proc getViewportSize*(tab: Tab): Future[tuple[width, height: int]] {.async.}
```


**What it does.** The current size of the page's visible area (window.innerWidth/Height) — the real one, taking into account what setViewport() faked, if it was called.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `int]]`


**Example:**

```nim
let size = await getViewportSize(tab)
echo size.width # prints the current width of the visible area, e.g. 1280
```


---

## Additional Waits


### `waitForSelectorGone` (Tab)


```nim
proc waitForSelectorGone*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**What it does.** The opposite of waitForSelector() — waits for an element to disappear from the page (for example, a loading spinner or a modal that has closed).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `timeoutMs`, default `5_000` — how many milliseconds to wait before raising a timeout exception/returning false.
- `pollIntervalMs`, default `100` — how often (in milliseconds) to recheck the condition while waiting — a compromise between responsiveness and load on the CDP connection.


**Returns:** `Future[bool]`


**Example:**

```nim
let gone = await waitForSelectorGone(tab, ".spinner", timeoutMs = 5_000)
echo gone # prints true if the spinner disappeared before the timeout expired
```


### `waitForText` (Tab)


```nim
proc waitForText*(tab: Tab, selector, text: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**What it does.** Waits until the element's visible text contains text (for example, the cart counter changes from "0" to "1" after a click).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `text` (`string`) — the substring that the element's visible text must contain for the wait to succeed.
- `timeoutMs`, default `5_000` — how many milliseconds to wait before raising a timeout exception/returning false.
- `pollIntervalMs`, default `100` — how often (in milliseconds) to recheck the condition while waiting — a compromise between responsiveness and load on the CDP connection.


**Returns:** `Future[bool]`


**Example:**

```nim
let appeared = await waitForText(tab, "#status", "Done", timeoutMs = 5_000)
echo appeared # prints true if the element's text came to contain "Done"
```


### `waitForStableText` (Tab)


```nim
proc waitForStableText*(tab: Tab, selector: string, pollMs = 500, stableForMs = 2_000, timeoutMs = 30_000): Future[string] {.async.}
```


**What it does.** Waits until the element's text (see `getLastText()` — the LAST node matching `selector` is taken) stops changing for `stableForMs` in a row, and returns the final text. A typical use case is a chatbot's or another streaming interface's response being written out incrementally, where there is no separate reliable "done" event other than the very fact that the text has stopped growing. Empty text (after `strip()`) is not considered stable — the wait continues until non-empty content appears. If by the time `timeoutMs` expires the text has still not stabilized, but is already non-empty — it returns what has managed to accumulate, instead of throwing an exception out of nowhere; an exception is thrown only if the text never appeared at all during the entire wait.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `pollMs`, default `500` — how often (in milliseconds) to reread the text while waiting.
- `stableForMs`, default `2_000` — how many milliseconds in a row the text must remain unchanged to be considered stable.
- `timeoutMs`, default `30_000` — how many milliseconds in total to wait before giving up (or returning the non-empty text accumulated so far).


**Returns:** `Future[string]` — the final text (stabilized, or accumulated by the time of the timeout).


**Exceptions:**

- `ChildTearError` — if no non-empty text appeared at `selector` within `timeoutMs`.


**Example:**

```nim
await click(tab, "#send-button")
let reply = await waitForStableText(tab, ".assistant-message:last-child")
echo reply # prints the chatbot's full reply once it has stopped being appended to
```


### `waitUntilTrue`


```nim
proc waitUntilTrue*(cond: proc(): Future[bool] {.async.}, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**What it does.** Polls an arbitrary asynchronous condition `cond` at an interval of `pollIntervalMs` until it returns `true` or `timeoutMs` expires. A generalization of the very same wait loop on which `waitForSelector()`/`waitForURL()`/`waitForSelectorGone()`/`waitForText()` above are built (they are themselves implemented via this primitive) — unlike them, `cond` is not tied to a specific `Tab`/selector and can check anything, so it is also suitable for application code on top of childtear (the `askQwen()`/`askKimi()` scenarios from `siteworkers/qwen.nim`/`siteworkers/kimi.nim` are built on it too). Returns `true` if `cond` became true before `timeoutMs` expired, otherwise `false` — the timeout by itself is not considered an error; raising an exception, if needed, is left to the calling code (as `waitForFunction()` does, for example).


**Parameters:**

- `cond` (`proc(): Future[bool] {.async.}`) — an arbitrary asynchronous condition without arguments; as a rule, a closure capturing `tab` and the rest of the context.
- `timeoutMs`, default `5_000` — how many milliseconds to wait before returning `false`.
- `pollIntervalMs`, default `100` — how often (in milliseconds) to recheck the condition while waiting.


**Returns:** `Future[bool]`


**Example:**

```nim
proc noSpinner(): Future[bool] {.async.} = result = not (await exists(tab, ".spinner"))
let ready = await waitUntilTrue(noSpinner, timeoutMs = 5_000, pollIntervalMs = 200)
echo ready # prints true if the spinner disappeared before the timeout expired
```


### `waitUntilCleared` (Tab)


```nim
proc waitUntilCleared*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 250, byValue = false): Future[bool] {.async.}
```


**What it does.** Waits until the text of the `selector` element (see `getText()`), or, with `byValue = true`, the value of the input field (see `getValue()`), becomes empty after `strip()` — a typical sign that a form field cleared itself after submission (text chat interfaces usually clear the input field right after a prompt/message is sent). Like `waitUntilTrue()`, on which it is built, it does not raise an exception on timeout — it returns `false`; the disappearance of the `selector` element itself from the DOM during the wait leads to a `ChildTearError` from `getText()`/`getValue()`, just as with calling them directly.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the input field or another element whose content should become empty.
- `timeoutMs`, default `5_000` — how many milliseconds to wait before returning `false`.
- `pollIntervalMs`, default `250` — how often (in milliseconds) to recheck the condition while waiting.
- `byValue`, default `false` — read the value via `getValue()` (for `<input>`/`<textarea>`) instead of `getText()` (for `contenteditable` elements and other visible text).


**Returns:** `Future[bool]`


**Example:**

```nim
await pressEnter(tab, "#prompt")
let cleared = await waitUntilCleared(tab, "#prompt", timeoutMs = 5_000, byValue = true)
echo cleared # prints true if the input field cleared after submission
```


---

## localStorage and sessionStorage


### `localStorageGet` (Tab)


```nim
proc localStorageGet*(tab: Tab, key: string): Future[string] {.async.}
```


**What it does.** The value of the key `key` in the current page's window.localStorage — storage that is bound to the origin and survives closing the tab. Returns "" both for a missing key and for a key whose value is "" (localStorage stores only strings; these cases can be told apart via evalJS("localStorage.getItem(...) === null")).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key in localStorage/sessionStorage.


**Returns:** `Future[string]`


**Example:**

```nim
let val = await localStorageGet(tab, "theme")
echo val # prints the stored value, e.g. "dark", or "" if there is no such key
```


### `localStorageSet` (Tab)


```nim
proc localStorageSet*(tab: Tab, key, value: string) {.async.}
```


**What it does.** Writes a key/value pair to window.localStorage (creates the key or overwrites an existing one).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key in localStorage/sessionStorage.
- `value` (`string`) — the value to set — of a cookie, a storage key, etc.


**Example:**

```nim
await localStorageSet(tab, "theme", "dark")
echo await localStorageGet(tab, "theme") # prints "dark"
```


### `localStorageRemove` (Tab)


```nim
proc localStorageRemove*(tab: Tab, key: string) {.async.}
```


**What it does.** Removes a single key from window.localStorage; does not fail if the key was not there anyway.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key in localStorage/sessionStorage.


**Example:**

```nim
await localStorageRemove(tab, "theme")
echo await localStorageGet(tab, "theme") # prints ""
```


### `localStorageClear` (Tab)


```nim
proc localStorageClear*(tab: Tab) {.async.}
```


**What it does.** Completely clears the window.localStorage of the current origin.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await localStorageClear(tab)
echo "localStorage cleared" # prints "localStorage cleared"
```


### `sessionStorageGet` (Tab)


```nim
proc sessionStorageGet*(tab: Tab, key: string): Future[string] {.async.}
```


**What it does.** Like localStorageGet(), but for window.sessionStorage — storage that is bound not only to the origin but also to the specific tab (it is closed together with it, unlike localStorage).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key in localStorage/sessionStorage.


**Returns:** `Future[string]`


**Example:**

```nim
let val = await sessionStorageGet(tab, "draftId")
echo val # prints the stored value or "" if there is no such key
```


### `sessionStorageSet` (Tab)


```nim
proc sessionStorageSet*(tab: Tab, key, value: string) {.async.}
```


**What it does.** Like localStorageSet(), but for window.sessionStorage.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key in localStorage/sessionStorage.
- `value` (`string`) — the value to set — of a cookie, a storage key, etc.


**Example:**

```nim
await sessionStorageSet(tab, "draftId", "42")
echo await sessionStorageGet(tab, "draftId") # prints "42"
```


### `sessionStorageRemove` (Tab)


```nim
proc sessionStorageRemove*(tab: Tab, key: string) {.async.}
```


**What it does.** Like localStorageRemove(), but for window.sessionStorage.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — the key in localStorage/sessionStorage.


**Example:**

```nim
await sessionStorageRemove(tab, "draftId")
echo await sessionStorageGet(tab, "draftId") # prints ""
```


### `sessionStorageClear` (Tab)


```nim
proc sessionStorageClear*(tab: Tab) {.async.}
```


**What it does.** Like localStorageClear(), but for window.sessionStorage.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await sessionStorageClear(tab)
echo "sessionStorage cleared" # prints "sessionStorage cleared"
```


---

## Environment Emulation


### `setGeolocation` (Tab)


```nim
proc setGeolocation*(tab: Tab, latitude, longitude: float, accuracy = 1.0) {.async.}
```


**What it does.** Fakes the coordinates of navigator.geolocation — the page receives them as a genuine geolocation response, without a system permission dialog.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `latitude` (`float`) — the latitude in degrees.
- `longitude` (`float`) — the longitude in degrees.
- `accuracy`, default `1.0`


**Example:**

```nim
await setGeolocation(tab, 55.7558, 37.6173, accuracy = 10.0)
echo "coordinates overridden to Moscow" # prints "coordinates overridden to Moscow"
```


### `clearGeolocation` (Tab)


```nim
proc clearGeolocation*(tab: Tab) {.async.}
```


**What it does.** Resets the override made by setGeolocation().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await clearGeolocation(tab)
echo "geolocation override removed" # prints "geolocation override removed"
```


### `setTimezone` (Tab)


```nim
proc setTimezone*(tab: Tab, timezoneId: string) {.async.}
```


**What it does.** timezoneId — an IANA name, for example "Europe/Amsterdam".


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `timezoneId` (`string`) — an IANA time zone name, for example "Europe/Amsterdam".


**Example:**

```nim
await setTimezone(tab, "Europe/Amsterdam")
echo "time zone overridden" # prints "time zone overridden"
```


### `setLocale` (Tab)


```nim
proc setLocale*(tab: Tab, locale = "") {.async.}
```


**What it does.** An empty string resets the override to the system locale.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `locale`, default `""`


**Example:**

```nim
await setLocale(tab, "nl-NL")
echo "locale overridden" # prints "locale overridden"
```


### `emulateMedia` (Tab)


```nim
proc emulateMedia*(tab: Tab, media = "", features: seq[(string, string)] = @[]) {.async.}
```


**What it does.** media: "screen"/"print"/"" (reset). features — pairs of the form ("prefers-color-scheme", "dark"): @[("prefers-color-scheme", "dark")].


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `media`, default `""`
- `features` (`seq[(string, string)]`), default `@[]`


**Example:**

```nim
await emulateMedia(tab, media = "print")
echo "print media type emulation enabled" # prints "print media type emulation enabled"
```


### `setCPUThrottle` (Tab)


```nim
proc setCPUThrottle*(tab: Tab, rate: float) {.async.}
```


**What it does.** rate = 1 — no slowdown, rate = 4 — the CPU is "4 times slower".


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `rate` (`float`) — the CPU slowdown factor: 1 — unchanged, 4 — 4 times slower.


**Example:**

```nim
await setCPUThrottle(tab, 4.0)
echo "CPU slowed down 4 times" # prints "CPU slowed down 4 times"
```


### `setBackgroundColor` (Tab)


```nim
proc setBackgroundColor*(tab: Tab, r, g, b: int, a = 1.0) {.async.}
```


**What it does.** Useful before screenshot(): for example, a = 0 for a transparent background.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `r` (`int`) — the red component of the background, 0–255.
- `g` (`int`) — the green component of the background, 0–255.
- `b` (`int`) — the blue component of the background, 0–255.
- `a`, default `1.0`


**Example:**

```nim
await setBackgroundColor(tab, 0, 0, 0, a = 0.0)
echo "page background became transparent" # prints "page background became transparent"
```


### `clearBackgroundColor` (Tab)


```nim
proc clearBackgroundColor*(tab: Tab) {.async.}
```


**What it does.** Resets the override made by setBackgroundColor() (earlier in the file).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await clearBackgroundColor(tab)
echo "background override removed" # prints "background override removed"
```


### `enableTouchEmulation` (Tab)


```nim
proc enableTouchEmulation*(tab: Tab, enabled = true, maxTouchPoints = 1) {.async.}
```


**What it does.** Fakes the indicators of touch-input support (navigator.maxTouchPoints, 'ontouchstart' in window) — the touch events themselves are emulated separately, via touchTap()/touchSwipe() (see below), which use Input.dispatchTouchEvent directly.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, default `true`
- `maxTouchPoints`, default `1`


**Example:**

```nim
await enableTouchEmulation(tab, true, maxTouchPoints = 5)
echo "touch-device indicators enabled" # prints "touch-device indicators enabled"
```


### `setJavaScriptEnabled` (Tab)


```nim
proc setJavaScriptEnabled*(tab: Tab, enabled: bool) {.async.}
```


**What it does.** Fully enables/disables JS execution on the page — convenient for checking how the page looks and works without scripts (progressive enhancement, accessibility of the markup without JS).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `enabled` (`bool`) — false — completely disable JS execution on the page; true — enable it back.


**Example:**

```nim
await setJavaScriptEnabled(tab, false)
echo "JS execution disabled" # prints "JS execution disabled"
```


### `setBypassCSP` (Tab)


```nim
proc setBypassCSP*(tab: Tab, enabled = true) {.async.}
```


**What it does.** Disables the page's Content-Security-Policy (needed, for example, so that addScriptTag() can inject arbitrary scripts on sites with a strict CSP).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, default `true`


**Example:**

```nim
await setBypassCSP(tab, true)
echo "Content-Security-Policy bypassed" # prints "Content-Security-Policy bypassed"
```


### `setCacheEnabled` (Tab)


```nim
proc setCacheEnabled*(tab: Tab, enabled = true) {.async.}
```


**What it does.** enabled = false — Chromium ignores the HTTP cache for this tab's requests (the equivalent of DevTools -> Network -> "Disable cache"); useful before reload(ignoreCache = false) to guarantee fresh network responses.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, default `true`


**Example:**

```nim
await setCacheEnabled(tab, false)
echo "HTTP cache disabled for the tab" # prints "HTTP cache disabled for the tab"
```


### `clearBrowserCache` (Tab)


```nim
proc clearBrowserCache*(tab: Tab) {.async.}
```


**What it does.** WARNING: like clearCookies(), it clears the HTTP disk cache of the entire browser, not just the current tab — CDP itself provides no way to limit this particular command to a single origin; this is a limitation of the protocol, not a shortcoming of childtear.nim. If you need a truly isolated cleanup (though of Cache Storage — the service workers' cache — rather than the HTTP cache), see clearCacheForOrigin().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await clearBrowserCache(tab)
echo "browser HTTP cache cleared entirely" # prints "browser HTTP cache cleared entirely"
```


### `clearCacheForOrigin` (Tab)


```nim
proc clearCacheForOrigin*(tab: Tab, storageTypes = storageApi.AllStorageTypes) {.async.}
```


**What it does.** Unlike clearBrowserCache() (the whole browser — a limitation of the protocol itself, see its description above), it truly clears the data of ONLY the tab's current origin via Storage.clearDataForOrigin: by default — localStorage/sessionStorage/IndexedDB/Cache Storage/ service workers, etc. (see storageApi.AllStorageTypes); if desired, a narrower storageTypes list can be passed (for example, "cache_storage" — only the Cache API). IMPORTANT: "cache_storage" here is the service workers' Cache API, not the HTTP disk cache, which cannot be cleared per-origin (see clearBrowserCache()).


**Implementation breakdown.** Unlike `clearBrowserCache()` (the whole browser — a limitation of the CDP protocol itself; there is no separate single-origin command for the HTTP cache), this function truly clears the data of ONLY the current origin via `Storage.clearDataForOrigin` — by default localStorage/sessionStorage/IndexedDB/Cache Storage/service workers, etc.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `storageTypes`, default `storageApi.AllStorageTypes`


**Example:**

```nim
await clearCacheForOrigin(tab)
echo "current site's data cleared" # prints "current site's data cleared" — Cache Storage, localStorage, etc.
```


### `setOffline` (Tab)


```nim
proc setOffline*(tab: Tab, offline = true) {.async.}
```


**What it does.** offline = true simulates a complete absence of network (the equivalent of DevTools -> Network -> "Offline") — all of the page's requests start failing, as on a real connection drop.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `offline`, default `true`


**Example:**

```nim
await setOffline(tab, true)
echo "network disabled" # prints "network disabled" — all of the tab's requests will start failing
```


### `throttleNetwork` (Tab)


```nim
proc throttleNetwork*(tab: Tab, latencyMs: float, downloadThroughput = -1.0, uploadThroughput = -1.0) {.async.}
```


**What it does.** throughput — bytes/sec, -1 — unlimited.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `latencyMs` (`float`) — the artificial delay of each request in milliseconds.
- `downloadThroughput`, default `-1.0`
- `uploadThroughput`, default `-1.0`


**Example:**

```nim
await throttleNetwork(tab, latencyMs = 300.0, downloadThroughput = 50_000.0)
echo "slow-network emulation enabled" # prints "slow-network emulation enabled"
```


---

## Permissions and the Browser Window


### `grantPermissions` (Browser)


```nim
proc grantPermissions*(browser: Browser, permissions: seq[string], origin = "", browserContextId = "") {.async.}
```


**What it does.** permissions — for example @["geolocation", "notifications"]. Without browserContextId, it applies to the browser's permissions as a whole, not to a single isolated profile.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `permissions` (`seq[string]`) — permission names, for example @["geolocation", "notifications"].
- `origin`, default `""`
- `browserContextId`, default `""`


**Example:**

```nim
await grantPermissions(browser, @["geolocation", "notifications"], origin = "https://example.com")
echo "permissions granted" # prints "permissions granted"
```


### `resetPermissions` (Browser)


```nim
proc resetPermissions*(browser: Browser, browserContextId = "") {.async.}
```


**What it does.** Resets all permissions granted via grantPermissions(), for the specified isolated profile (or the main one, if none is specified), back to the browser's default behavior.


**Parameters:**

- `browser` (`Browser`) — a connection to the browser (`Browser`), obtained via `newBrowser()`.
- `browserContextId`, default `""`


**Example:**

```nim
await resetPermissions(browser)
echo "permissions reset" # prints "permissions reset"
```


### `setWindowSize` (Tab)


```nim
proc setWindowSize*(tab: Tab, width, height: int) {.async.}
```


**What it does.** Changes the size of the browser window that the tab belongs to (Browser.setWindowBounds) — unlike setViewport(), this is the size of the window itself, not of a faked page viewport; in headless mode the effect depends on the Chromium version. Uses a browser-level session cached on the tab itself (see tabBrowserSession()) — on repeated calls for the same tab no new connection is opened.


**Implementation breakdown.** Window-changing commands belong to the `Browser` domain, not `Page`, and require a browser-level CDP session rather than an ordinary tab session. `Tab` has no persistent reference to `Browser`, so such a session is created lazily on first use and cached on the `Tab` itself (closed along with it in `close()`) — instead of opening a new browser-level connection on every call to `setWindowSize()`/`maximizeWindow()`.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `width` (`int`) — the browser window width in pixels.
- `height` (`int`) — the browser window height in pixels.


**Example:**

```nim
await setWindowSize(tab, 1280, 800)
echo "browser window resized to 1280x800" # prints "browser window resized to 1280x800"
```


### `maximizeWindow` (Tab)


```nim
proc maximizeWindow*(tab: Tab) {.async.}
```


**What it does.** Maximizes the browser window that the tab belongs to to full screen (Browser.setWindowBounds with windowState = "maximized") — like setWindowSize(), it reuses the tab's cached browser-level session instead of opening a new one on each call.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Example:**

```nim
await maximizeWindow(tab)
echo "window maximized to full screen" # prints "window maximized to full screen"
```


---

## File Downloads and Uploads


### `setDownloadPath` (Tab)


```nim
proc setDownloadPath*(tab: Tab, path: string) {.async.}
```


**What it does.** Allows file downloads and saves them to the directory path (which must exist beforehand) — without this, headless Chromium silently blocks all downloads.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `path` (`string`) — the path to a file on disk — where to save (a screenshot, PDF, text) or where to load from.


**Example:**

```nim
await setDownloadPath(tab, "/tmp/downloads")
echo "downloads will be saved to /tmp/downloads" # prints "downloads will be saved to /tmp/downloads"
```


### `interceptFileChooser` (Tab)


```nim
proc interceptFileChooser*(tab: Tab, enabled = true) {.async.}
```


**What it does.** Suppresses the system file-selection dialog. The files themselves still have to be assigned manually via uploadFile() — this command only keeps the dialog from hanging; there is no binding to the "Page.fileChooserOpened" event here.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, default `true`


**Example:**

```nim
await interceptFileChooser(tab, true)
echo "file chooser dialog intercepted" # prints "file chooser dialog intercepted"
```


---

## Console and Page Errors


### `onConsole` (Tab)


```nim
proc onConsole*(tab: Tab, handler: ConsoleHandler)
```


**What it does.** Subscribes to the page's console.log/warn/error/... (the Runtime domain is already enabled in openTab()). The subscription is permanent — it lives as long as the tab's session does (like onDialog()/autoDismissDialogs() above).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `handler` (`ConsoleHandler`) — a callback function that receives the message type ("log"/"warn"/"error", etc.) and its text.


**Example:**

```nim
proc handler(kind, text: string) =
  echo kind, ": ", text # prints, for example, "log: hello from the page console"
onConsole(tab, handler)
```


### `onPageError` (Tab)


```nim
proc onPageError*(tab: Tab, handler: PageErrorHandler)
```


**What it does.** Subscribes to the page's unhandled JS exceptions (the equivalent of window.onerror). The subscription is permanent, like onConsole().


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `handler` (`PageErrorHandler`) — a callback function that receives the text of the page's unhandled exception.


**Example:**

```nim
proc handler(message: string) =
  echo "unhandled error on the page: ", message
onPageError(tab, handler)
```


---

## Page Diagnostics

The three functions below are a toolkit for analyzing a failure, not tied to a
particular selector/event: `installDiagnostics()` injects into the page itself a lightweight
JS interceptor that accumulates a log regardless of whether anyone
is listening to `onConsole()`/`onPageError()` at that moment; `fetchDiagnostics()`
collects what has accumulated at any time; `dumpDebugInfo()` is a ready-made combination
"save a screenshot + HTML + the diagnostics log in a single call" for the place
in the code where the scenario failed.

### `installDiagnostics` (Tab)


```nim
proc installDiagnostics*(tab: Tab) {.async.}
```


**What it does.** Injects into the page a lightweight interceptor that accumulates a log in the page itself: unhandled exceptions (`window.onerror`), unhandled promise rejections (`unhandledrejection`), and unsuccessful fetch/XHR requests (status 0 or ≥400). What has accumulated can be collected at any time — even after a long while — via `fetchDiagnostics()`, without having to keep a subscription like `onConsole()`/`onPageError()` active all that time; unlike them, unsuccessful network requests are additionally visible here. It is safe to call repeatedly — the function itself checks `window.__childtearDiag` and does not reinstall the interceptor. The log is limited to the last 500 entries (older ones are evicted).


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[void]`


**Example:**

```nim
await installDiagnostics(tab)
await goto(tab, "https://example.com")
# ... the scenario keeps running ...
let log = await fetchDiagnostics(tab) # collect what has accumulated at any time
```


### `fetchDiagnostics` (Tab)


```nim
proc fetchDiagnostics*(tab: Tab): Future[JsonNode] {.async.}
```


**What it does.** Collects the log accumulated by `installDiagnostics()` since its installation. If it was not called — returns an empty array rather than an error.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[JsonNode]` — a `JArray` of entries of the form `{"t": <timestamp>, "kind": "js-error"|"promise-rejection"|"fetch-failed"|"fetch-error"|"xhr-failed", "detail": <string>}`.


**Example:**

```nim
let log = await fetchDiagnostics(tab)
for entry in log:
  echo entry["kind"], ": ", entry["detail"]
```


### `dumpDebugInfo` (Tab)


```nim
proc dumpDebugInfo*(tab: Tab, prefix = "debug"): Future[JsonNode] {.async.}
```


**What it does.** A convenient combination for analyzing a failure: saves a full screenshot (`<prefix>.png`), the document's HTML (`<prefix>.html`) and, if `installDiagnostics()` was installed earlier, the diagnostics log (`<prefix>-console.json`) — and returns that log (an empty `JArray` if diagnostics were not installed) for those who want to do something with it right away (for example, print the first entries to the console). Errors in the saving itself (for example, if the tab is already unavailable by that moment) are not thrown — an empty `JArray` is quietly returned, so that the attempt to save debugging information does not itself overshadow the original cause of the failure.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `prefix`, default `"debug"` — the common path prefix for the three saved files (`<prefix>.png`, `<prefix>.html`, `<prefix>-console.json`); it may include a directory, for example `"/tmp/failure-42"`.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
try:
  await click(tab, "#submit")
except ChildTearError:
  let diag = await dumpDebugInfo(tab, "/tmp/scenario-fail")
  echo "scenario failed, debug info saved; entries in the log: ", len(diag)
  raise
```


---

## Network: Waiting for Specific Responses


### `waitForResponse` (Tab)


```nim
proc waitForResponse*(tab: Tab, urlSubstring: string, timeoutMs = 30_000): Future[JsonNode] {.async.}
```


**What it does.** Waits for an HTTP response whose URL contains urlSubstring (the Network domain is enabled automatically, if it was not already, via enableNetwork()). Returns the full "Network.responseReceived" event object — {"requestId", "response": {"url", "status", "headers", ...}, ...}; requestId is needed for the subsequent responseBody(). Unlike waitForNavigation(), it reacts to a specific network request rather than to the page load as a whole — convenient for waiting for a particular XHR/fetch.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `urlSubstring` (`string`) — the substring that the network response's URL must contain for the wait to succeed.
- `timeoutMs`, default `30_000` — how many milliseconds to wait before raising a timeout exception/returning false.


**Returns:** `Future[JsonNode]`


**Exceptions:**

- `ChildTearError` — if no network response with a URL containing `urlSubstring` arrived within `timeoutMs`.

**Example:**

```nim
await click(tab, "#load-more")
let res = await waitForResponse(tab, "/api/items", timeoutMs = 10_000)
echo res["status"] # prints the response's HTTP status, e.g. 200
```


### `responseBody` (Tab)


```nim
proc responseBody*(tab: Tab, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.}
```


**What it does.** The body of a specific network response by requestId (see waitForResponse()). Available only while Chromium has not yet evicted the request's data from memory — it must be called soon after the response is received.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `requestId` (`string`) — the request id, taken from the event object returned by waitForResponse().


**Returns:** `bool]]`


**Example:**

```nim
let
  res = await waitForResponse(tab, "/api/items")
  (body, isBase64) = await responseBody(tab, getStr(res["requestId"]))
echo isBase64 # prints false for JSON/text responses
```


---

## Frames


### `frames` (Tab)


```nim
proc frames*(tab: Tab): Future[seq[JsonNode]] {.async.}
```


**What it does.** Returns a list of all frames (including nested iframes) of the current page — a flat list of {"id", "url", "name", ...} objects from Page.getFrameTree. To work with the content of a specific iframe (clicks, reading text, etc.), you don't have to parse this list manually — frame() below is usually more convenient, finding the needed iframe straight from the CSS selector of the `<iframe>` tag itself.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.


**Returns:** `Future[seq[JsonNode]]`


**Example:**

```nim
let allFrames = await frames(tab)
echo len(allFrames) # prints the number of frames on the page, including the main one
```


### `frame` (Tab)


```nim
proc frame*(tab: Tab, iframeSelector: string): Future[Frame] {.async.}
```


**What it does.** Finds the `<iframe>` matching the CSS selector iframeSelector in the tab's MAIN document (iframes nested inside an iframe are not searched for by this call) and returns a Frame — a separate "entry point" into its content, supporting its own set of click()/hover()/getText()/ fill()/evalJS()/exists() below, which work inside the iframe rather than in the main page's document. Technically: DOM.describeNode(pierce = true) returns, together with the `<iframe>` node itself, also a nested "contentDocument" node — the root document INSIDE the iframe — as well as the "frameId" of that iframe. The nodeId of the iframe's document becomes the root for DOM.querySelector() inside the Frame (see findFrameNode()), while the frameId is needed so that, on the first call to evalJS()/getText()/fill() (see frameContext()), an isolated JS execution context is created for this iframe via Page.createIsolatedWorld — without it, Runtime.evaluate would run in the main page's context rather than the iframe's, and document inside the expression would point to the wrong place.


**Implementation breakdown.** `DOM.describeNode(pierce = true)` returns, together with the `<iframe>` node itself, a nested `"contentDocument"` node — the root document INSIDE the iframe with its own `nodeId`, which becomes the root for finding elements inside the `Frame` (see `click(frame, ...)`/`getText(frame, ...)`, etc.), while the `"frameId"` of that iframe is needed so that, on the first call to `evalJS()`/`getText()`/`fill()`, an isolated JS execution context is created for it via `Page.createIsolatedWorld` — without it, `Runtime.evaluate` would execute in the main page's context rather than the iframe's.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `iframeSelector` (`string`) — the CSS selector of the <iframe> tag in the page's main document.


**Returns:** `Future[Frame]`


**Exceptions:**

- `ChildTearError` — if no element is found by `iframeSelector`, or one is found but is not an `<iframe>`/`<frame>` with accessible content.

**Example:**

```nim
let inner = await frame(tab, "#payment-iframe")
echo inner != nil # prints true
```


### `click` (Frame)


```nim
proc click*(frame: Frame, selector: string) {.async.}
```


**What it does.** Like Tab.click(), but finds and clicks an element inside this iframe's content rather than in the page's main document.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found inside the iframe by `selector`.

**Example:**

```nim
let inner = await frame(tab, "#payment-iframe")
await click(inner, "#pay-button")
echo "click inside the iframe performed" # prints "click inside the iframe performed"
```


### `hover` (Frame)


```nim
proc hover*(frame: Frame, selector: string) {.async.}
```


**What it does.** Like Tab.hover(), but for an element inside this iframe's content.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Exceptions:**

- `ChildTearError` — if no element is found inside the iframe by `selector`.

**Example:**

```nim
let inner = await frame(tab, "#payment-iframe")
await hover(inner, ".card-icon")
echo "cursor hovered inside the iframe" # prints "cursor hovered inside the iframe"
```


### `evalJS` (Frame)


```nim
proc evalJS*(frame: Frame, expression: string): Future[JsonNode] {.async.}
```


**What it does.** Like Tab.evalJS(), but executes expression in this iframe's isolated context (see frameContext()) — document inside the expression points to the iframe's document, not the main page's.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `expression` (`string`) — arbitrary JS code, executed in this iframe's isolated context.


**Returns:** `Future[JsonNode]`


**Example:**

```nim
let
  inner = await frame(tab, "#payment-iframe")
  res = await evalJS(inner, "document.title")
echo res["result"]["value"] # prints the title of the document inside the iframe
```


### `getText` (Frame)


```nim
proc getText*(frame: Frame, selector: string): Future[string] {.async.}
```


**What it does.** Like Tab.getText(), but reads the text of an element inside this iframe's content.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[string]`


**Exceptions:**

- `ChildTearError` — if no element is found inside the iframe by `selector`.

**Example:**

```nim
let inner = await frame(tab, "#payment-iframe")
echo await getText(inner, "#total") # prints the text of the element inside the iframe, e.g. "€42.00"
```


### `getAllText` (Frame)


```nim
proc getAllText*(frame: Frame, selector: string): Future[seq[string]] {.async.}
```


**What it does.** Like Tab.getAllText(), but for elements inside this iframe's content.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[seq[string]]`


**Example:**

```nim
let
  inner = await frame(tab, "#payment-iframe")
  items = await getAllText(inner, ".line-item")
echo len(items) # prints the number of order lines inside the iframe
```


### `fill` (Frame)


```nim
proc fill*(frame: Frame, selector: string, text: string) {.async.}
```


**What it does.** Like Tab.fill(), but fills a field inside this iframe's content. Uses Input.insertText into the tab's current focus (see Tab.fill()) — which is why it first focuses the field via JS in the iframe's context.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `text` (`string`) — the text that will be inserted into the field in place of its current content.


**Exceptions:**

- `ChildTearError` — if the element to fill is not found inside the iframe by `selector`.

**Example:**

```nim
let inner = await frame(tab, "#payment-iframe")
await fill(inner, "#card-number", "4242424242424242")
echo "field inside the iframe filled" # prints "field inside the iframe filled"
```


### `exists` (Frame)


```nim
proc exists*(frame: Frame, selector: string): Future[bool] {.async.}
```


**What it does.** Like Tab.exists(), but checks for the presence of an element inside this iframe's content.


**Parameters:**

- `frame` (`Frame`) — the content of an iframe (`Frame`), obtained via `tab.frame(cssSelector)`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").


**Returns:** `Future[bool]`


**Example:**

```nim
let inner = await frame(tab, "#payment-iframe")
echo await exists(inner, "#error-message") # prints true/false
```


---

## Screenshot of a Single Element


### `screenshotElement` (Tab)


```nim
proc screenshotElement*(tab: Tab, selector, path: string, format = "png", quality = 100) {.async.}
```


**What it does.** A screenshot of a single element (rather than the whole tab) — first scrolls it into view (see boundingBox()), then captures only its rectangle.


**Parameters:**

- `tab` (`Tab`) — an open tab (`Tab`), obtained via `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — the CSS selector of the element being sought (for example, "#id", ".class", "button[type=submit]").
- `path` (`string`) — the path to a file on disk — where to save (a screenshot, PDF, text) or where to load from.
- `format`, default `"png"`
- `quality`, default `100`


**Example:**

```nim
await screenshotElement(tab, "#chart", "/tmp/chart.png")
echo "element screenshot saved" # prints "element screenshot saved"
```


---
## Other Core Functions

### `insertTextAtCursor(tab, text)`

```nim
proc insertTextAtCursor*(tab: Tab, text: string) {.async.}
```

**What it does.** A "raw" `Input.insertText` without prior focusing/selection (unlike `fill()`, which clears the field first) — inserts `text` at the current cursor position, appending to the content already there. Needed where the field is already focused and is being filled in parts (multi-line input: the first line via `fill()`, the rest via `pressEnter()` + `insertTextAtCursor()`).

### `setControlledValue(tab, selector, value)`

```nim
proc setControlledValue*(tab: Tab, selector: string, value: string): Future[bool] {.async.}
```

**What it does.** Like `syncControlledValue()`, but writes a new `value` instead of resetting `el.value` to itself. Needed where `el.value = ''` (see `clearValue()`) does not work for React-controlled (`controlled`) fields: a direct assignment to `el.value` goes through React's instance-level interceptor setter, because of which the subsequent `dispatchEvent('input')` is not perceived by the component as a change.

### `installNetworkFailureLog(tab)`

```nim
proc installNetworkFailureLog*(tab: Tab) {.async.}
```

**What it does.** Enables the Network domain (`enableNetwork()`) and subscribes to `Network.loadingFailed`/`Network.responseReceived` for the entire lifetime of the tab, accumulating in `tab.netFailures` both real network errors (DNS, connection drop, blocking) and HTTP 4xx/5xx responses — for any resources, including `<script src>`/`<link>`, which the browser loads directly, bypassing `fetch()`/XHR (and which are therefore not visible to `installDiagnostics()`/`fetchDiagnostics()`).


---
## Practical Recipes

### Logging in to a site and checking the result

```nim
import childtear
import std/asyncdispatch

proc main() {.async.} =
  let
    browser = newBrowser()
    tab = await openTab(browser, "https://example.com/login")
  await fillForm(tab, @{"#username": "andy", "#password": "secret"})
  await click(tab, "button[type=submit]")
  discard await waitForSelector(tab, ".dashboard")
  echo await getText(tab, ".welcome-message") # prints the welcome text after logging in
  await close(tab)

waitFor main()
```

---

### Working with a form inside an iframe (payment widget)

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/checkout")
  let paymentFrame = await frame(tab, "#payment-iframe")
  await fill(paymentFrame, "#card-number", "4242424242424242")
  await fill(paymentFrame, "#expiry", "12/29")
  await click(paymentFrame, "#pay-button")
  discard await waitForText(tab, "#status", "Paid")
  echo "payment went through" # prints "payment went through"
```

---

### Dragging an element on a site with native HTML5 DnD

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/board")
  # native = true — required for sites with draggable="true" and ondrop
  await dragAndDrop(tab, "#task-1", "#column-done", native = true)
  echo await exists(tab, "#column-done #task-1") # prints true
```

---

### A screenshot and PDF of an entire long report

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/report")
  await screenshot(tab, "/tmp/report.png", fullPage = true)
  await savePDF(tab, "/tmp/report.pdf", printBackground = true)
  echo "report saved as PNG and PDF" # prints "report saved as PNG and PDF"
```

---

### Waiting for the response of a specific API request instead of a fixed pause

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/catalog")
  await click(tab, "#load-more")
  let res = await waitForResponse(tab, "/api/products", timeoutMs = 10_000)
  echo res["status"] # prints 200 — it fired exactly on the response, with no random sleepAsync
```

---

### Clearing the data of only the current site between test cases

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com")
  # ... test case 1 left cookies/localStorage behind ...
  await clearCookiesForOrigin(tab)
  await clearCacheForOrigin(tab)
  echo "state of example.com reset, other sites untouched"
```

---

## Brief Table

| Task | Function |
|---|---|
| Open a browser / a tab | `newBrowser`, `openTab` / `newPage` |
| Navigate to a URL | `goto` |
| Click / hover | `click`, `hover`, `doubleClick`, `rightClick`, `clickAt` |
| Fill in a field / a form | `fill`, `fillForm`, `` `type` `` |
| Read the text of an element / elements | `getText`, `getAllText`, `count` |
| Read an attribute / HTML | `getAttribute`, `getAllAttributes`, `innerHTML`, `outerHTML` |
| Check an element's state | `exists`, `isVisible`, `isChecked`, `isDisabled` |
| Wait for appearance/disappearance/text | `waitForSelector`, `waitForSelectorGone`, `waitForText` |
| Wait for a navigation / URL / custom condition | `waitForNavigation`, `waitForURL`, `waitForFunction` |
| Working with an iframe | `frame`, then `click`/`getText`/`fill`/`evalJS` on the `Frame` |
| Drag and drop (mouse / native HTML5 DnD) | `dragAndDrop(..., native = true/false)` |
| Screenshot / element screenshot / PDF | `screenshot`, `screenshotElement`, `savePDF` |
| Arbitrary JS | `evalJS` |
| Cookies of the current page / of this site only | `cookies`/`setCookie`/`clearCookies` / `clearCookiesForOrigin` |
| localStorage / sessionStorage | `localStorageGet/Set/Remove/Clear`, `sessionStorage...` |
| Fake the device/geolocation/network | `setViewport`, `setGeolocation`, `setOffline`, `throttleNetwork` |
| Intercept the console / page errors | `onConsole`, `onPageError` |
| Handle alert/confirm/prompt | `onDialog`, `acceptDialog`, `dismissDialog`, `autoDismissDialogs` |
| Wait for a specific network response | `waitForResponse`, `responseBody` |
| Browser window size/state | `setWindowSize`, `maximizeWindow` |
| Permissions (geolocation, notifications) | `grantPermissions`, `resetPermissions` |

---

## Summary: Which Function to Choose

- Just open a page and wait for it to load → `goto()` — it waits for `Page.loadEventFired` itself and honestly raises an error if the navigation failed, instead of an opaque timeout.
- Click an ordinary button/link → `click()`. Need a double click, the right button, or a click at arbitrary coordinates rather than by selector → `doubleClick()`/`rightClick()`/`clickAt()`.
- Fill in a single field → `fill()`. Fill in several form fields at once → `fillForm()` — shorter than calling `fill()` in a loop. Need character-by-character typing simulation (JS validation reacts on every keydown) → `` `type`() ``.
- Read the text of one element → `getText()`. The text of several at once (a list, a table) → `getAllText()`. Just find out how many elements match a selector → `count()`.
- Working inside an iframe (payment widgets, embedded forms, third-party widgets) → first `frame()`, then the like-named functions of `Frame`, not of `Tab`.
- Dragging: an ordinary JS list/slider → `dragAndDrop()` with `native = false` (the default); a site that uses genuine HTML5 `draggable`/`ondrop` → `native = true`.
- Need to wait for something specific rather than just sleep — an element, text, a URL, a network response, an arbitrary JS condition → the corresponding `waitFor*()`, not a random `sleepAsync()`.
- Need to clear the cookies/cache of only the current site, without touching the rest of the browser → `clearCookiesForOrigin()`/`clearCacheForOrigin()`, not `clearCookies()`/`clearBrowserCache()` (those affect the whole browser — a limitation of the CDP protocol itself).
- No ready-made function found → `evalJS()` as an escape hatch into arbitrary JS, and at the lowest level — direct access to `tab.session` and the low-level API, see [`cdp_reference_ru.md`](./cdp_reference_ru.md).
