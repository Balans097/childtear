<div align="center">

# childtear

**A library for controlling headless Chrome/Chromium from Nim via the Chrome DevTools Protocol.**

The library provides a high-level interface for common browser
automation operations: opening a tab, interacting with page elements,
filling in forms, extracting text, and taking screenshots.
The implementation does not use code generators: every function is
written and documented by hand.

[![Nim](https://img.shields.io/badge/Nim-%3E%3D1.6-ffc200?logo=nim&logoColor=black)](https://nim-lang.org)
[![Chrome DevTools Protocol](https://img.shields.io/badge/CDP-Chrome%20DevTools%20Protocol-4285F4?logo=googlechrome&logoColor=white)](https://chromedevtools.github.io/devtools-protocol/)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

[Quick start](#quick-start) •
[Features](#features) •
[Examples](#examples) •
[Function reference](./docs/childtear_reference_ru.md) •
[Low-level CDP layer](./docs/cdp_reference_ru.md) •
[siteworkers: ready-made automation scenarios](#siteworkers-ready-made-automation-scenarios)

</div>

---

## Purpose

The library addresses browser automation in Nim without relying on
tools implemented in JavaScript or Python (Puppeteer, Playwright), and
without having to bundle a Node.js runtime into the project. The main
implementation principles are:

- **No code generation.** Every wrapper around a CDP command is
  implemented and commented by hand; the module source code can be
  used as reference documentation.
- **Two levels of application interface.** The high-level API (`click`,
  `fill`, `getText`, etc.) is intended for the majority of practical
  tasks. The low-level API (`tab.session` and the `cdp/domains/*`
  modules) provides direct access to protocol commands in cases not
  covered by the high-level layer.
- **Explicit statement of protocol limitations.** Where CDP itself does
  not provide the required functionality (for example, clearing the
  HTTP cache within a single tab), this limitation is stated in the
  documentation of the corresponding function rather than masked by an
  approximate implementation.

## Installation

```bash
nimble install https://github.com/Balans097/childtear
```

An alternative is to copy the `childtear.nim` file and the `cdp/`
directory into your project. Requirements: Nim ≥ 2.0 and the `checksums`
package (`nimble install checksums`; needed by `cdp/wsclient.nim` for
SHA-1 in the WebSocket handshake). There are no other external
dependencies.

The library requires a running headless Chromium/Chrome with the
debugging port open:

```bash
chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox &
```

When using the `siteworkers/*.nim` modules (ready-made scenarios for
Qwen, Kimi, RedCircle and mave.digital — see the
[section below](#siteworkers-ready-made-automation-scenarios)), there is no
need to start Chromium manually: the process is launched automatically
by the library via `browser_lifecycle.ensureBrowser()`, once per
profile, and is reused between calls. An additional dependency is
`wl-copy` (the `wl-clipboard` package) or `xclip`; it is required only
for the `aiText2Clipboard()`/`aiScreenshot2Clipboard()` functions.

## Structure

```
childtear.nim                high-level API (Browser/Tab/Frame, similar in
                                spirit to Puppeteer) — navigation, clicks, forms,
                                screenshots, network, emulation, diagnostics.
                                See docs/childtear_reference_ru.md
siteworkers/
  siteworker_common.nim       infrastructure shared by all siteworkers/*.nim:
                                AskResult/SiteWorkerPref/ImageFormat,
                                finding and marking page elements by visible
                                text (mark*)
  qwen.nim                    askQwen() — request/response to chat.qwen.ai
  kimi.nim                    askKimi() — request/response to www.kimi.com
  browser_lifecycle.nim        launching/reusing Chromium with a persistent
                                profile (ensureBrowser/stopBrowser),
                                gotoWithRetry, dumpDebugInfoVerbose
  clipboard.nim                screenshot of the last assistant message and
                                working with the system clipboard
                                (aiText2File, etc.)
  redcircle.nim                uploadToRedcircle() — publishing a podcast
                                episode to app.redcircle.com
  mavedigital.nim               uploadToMave() — publishing a podcast episode
                                to app.mave.digital (several channels per
                                account) — see the section below and
                                docs/siteworker_reference_ru.md
docs/
  childtear_reference_ru.md    reference for the CDP wrapper core (all
                                childtear.nim functions with signatures and
                                descriptions)
  siteworker_common_reference_ru.md   reference for siteworkers/siteworker_common.nim
  browser_lifecycle_reference_ru.md   reference for siteworkers/browser_lifecycle.nim
  clipboard_reference_ru.md    reference for siteworkers/clipboard.nim
  cdp_reference_ru.md          reference for the low-level CDP layer (cdp/*)
  siteworker_reference_ru.md   reference for the shared siteworker
                                infrastructure types (AskResult,
                                SiteWorkerPref, etc.) and askQwen/askKimi
cdp/
  wsclient.nim                WebSocket client "from scratch" (handshake + RFC 6455 framing)
  transport.nim                JSON-RPC over WebSocket: call() / on() / onSession() / waitForEvent()
  browser.nim                  HTTP wrapper for /json/new, /json/list, /json/close, /json/version
  domains/
    page.nim                   navigation, history, dialogs, isolated worlds,
                                injected scripts, download behavior, screenshots/PDF
    dom.nim                    querySelector(All), boxModel/contentQuads, attributes,
                                outerHTML, file upload, node removal/scrolling
    runtime.nim                 evaluate/callFunctionOn, getProperties, release*,
                                 addBinding/removeBinding (JS -> native code bridge)
    input.nim                   mouse (including wheel), keyboard, touch events
    network.nim                  cookies, response body, URL blocking, network throttling
    fetch.nim                    request interception/substitution/blocking, Basic auth
    target.nim                   multi-tab mode, browser contexts (incognito)
    emulation.nim                viewport, User-Agent, geolocation, time zone, CPU throttling
    browserdomain.nim            browser-level commands (Browser.close, permissions, windows)
    log.nim                      Log.entryAdded (browser log messages)
tests/
  mock_cdp_server.nim          test WS server for verifying the transport layer
  test_wsclient.nim            WebSocket client: handshake, fragmentation, ping/pong, close
  test_transport.nim           call(), on(), waitForEvent(), connection drop
  test_browser_http.nim        HTTP wrapper for /json/*: PUT methods, non-2xx errors
  run_tests.sh                 runs all tests
  example.nim                  demonstration of the main API (navigation, cookies, typeText(), dialogs, exposeFunction())
  bbc_article_example.nim      example of extracting an article from bbc.com/russian into a text file
```

## Quick start

```nim
import childtear
import std/asyncdispatch

proc main() {.async.} =
  let browser = newBrowser()                 # localhost:9222 by default
  let tab = await openTab(browser, "https://example.com")

  await click(tab, "#login-button")
  await fillForm(tab, @{"#username": "andy", "#password": "secret"})
  await click(tab, "button[type=submit]")

  echo await getText(tab, "h1")
  await screenshot(tab, "result.png")

  await close(tab)

waitFor main()
```

## Features

|                                  |                                                                                                                                                                                        |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Interaction**                  | `click`, `hover`, `doubleClick`, `rightClick`, `clickAt`, `fill`, `fillForm`, `selectOption`, `uploadFile`, `submitForm`, `dragAndDrop` (mouse emulation and native HTML5 DnD)        |
| **Reading the page**             | `getText`, `getAllText`, `getAttribute`, `getLinks`, `innerHTML`/`outerHTML`, `count`, `exists`, `boundingBox`                                                                         |
| **iframe**                       | `tab.frame(selector)` returns a `Frame` object with its own `click`/`getText`/`fill`/`evalJS` methods, executed in the context of the iframe document rather than the page's main document |
| **Waiting**                      | `waitForSelector`, `waitForSelectorGone`, `waitForText`, `waitForNavigation`, `waitForFunction`, `waitForURL`, `waitForResponse`                                                       |
| **Cookies and storage**          | `cookies`, `setCookie`, `deleteCookie`, `clearCookies` / `clearCookiesForOrigin`, `localStorage*`, `sessionStorage*`                                                                   |
| **Environment emulation**        | `setViewport`, `setUserAgent`, `setGeolocation`, `setTimezone`, `setLocale`, `emulateMedia`, `setCPUThrottle`, `enableTouchEmulation`, `setOffline`, `throttleNetwork`                 |
| **Page snapshots**               | `screenshot`, `screenshotElement`, `savePDF`, `content`/`setContent`                                                                                                                   |
| **JS bridge**                    | `evalJS`, `addScriptTag`, `evaluateOnNewDocument`, `exposeFunction` (calling Nim code from the page's JavaScript context)                                                              |
| **Network**                      | `enableNetwork`, `setExtraHeaders`, `blockUrls`, `waitForResponse`, `responseBody`, `setOffline`, `throttleNetwork`                                                                    |
| **Multiple tabs and profiles**   | `pages`, `attachTab`, `createIncognitoContext`, `newPageInContext`, `closeContext`                                                                                                     |

The full list — about 290 high- and low-level functions, with
signatures and descriptions — is given in
[`docs/childtear_reference_ru.md`](./docs/childtear_reference_ru.md) (high
level) and [`docs/cdp_reference_ru.md`](./docs/cdp_reference_ru.md) (low
level, direct access to CDP domains).

## Examples

A demonstration of working with a form, native drag-and-drop and an
iframe is given in [`tests/example.nim`](./tests/example.nim); the example
runs on a self-contained `data:` page and does not depend on external
sites:

```bash
nim c -d:release tests/example.nim
./tests/example
```

An example of extracting the contents of an article from an external
site — [`tests/bbc_article_example.nim`](./tests/bbc_article_example.nim).

### iframe

```nim
let inner = await frame(tab, "#inner-frame")
await click(inner, "#submit-btn")
echo await getText(inner, "#result")
```

### Native HTML5 drag-and-drop

```nim
# native = true — dispatches the actual sequence of
# dragstart/dragover/drop events rather than emulating it with the mouse
await dragAndDrop(tab, "#drag-item", "#drop-zone", native = true)
```

### Clearing data within the current origin

```nim
# Unlike clearCookies()/clearBrowserCache(), which affect the whole
# browser (a limitation of the CDP protocol itself), the functions
# below are limited to the current origin
await clearCookiesForOrigin(tab)
await clearCacheForOrigin(tab)
```

## siteworkers: ready-made automation scenarios

`siteworkers/*.nim` are add-ons on top of childtear, each implementing
a typical scenario for a single site. The shared infrastructure
(`AskResult`, `SiteWorkerPref`, `ImageFormat`, `SiteWorkerError`,
finding elements by visible text, launching/reusing the Chromium
process) lives in `siteworkers/siteworker_common.nim` and
`siteworkers/browser_lifecycle.nim`; the individual `siteworkers/*.nim`
modules use it and add nothing to page control directly, bypassing
childtear.

Two modules implement interaction with chat services:

```nim
import siteworkers/qwen
import siteworkers/kimi

let answer = waitFor askQwen("Draw up a plan for the week")
aiText2File(answer.text, "plan.txt")
aiScreenshot2Clipboard(answer.screenshotData, answer.screenshotFormat)
```

Two more handle publishing a podcast episode on a specific platform:

```nim
import siteworkers/redcircle
import siteworkers/mavedigital

waitFor uploadToRedcircle("Title", "Description", "file.mp3")
waitFor uploadToMave(mcHistory, "Guest — Title", "00:00 — intro", "file.mp3")
```

Key decisions underlying the implementation:

- **The functions do not perform authorization themselves.** Each module
  uses a Chromium profile previously saved on disk — the same directory
  as the corresponding CLI utility (`qwenclient`, `kimiclient`,
  `redcircleclient`). If the profile is missing or the session has
  expired, the function terminates with a `SiteWorkerError` exception
  stating that the profile must be prepared beforehand through an
  interactive login.
- **One isolated Chromium process per profile**, launched and reused by
  the library (`browser_lifecycle.ensureBrowser()`) on a separate
  debugging port for each site; this allows scenarios for different
  sites to be called in parallel.
- **The result of chat scenarios is represented by the `AskResult` type,
  not a string.** Besides the text of the answer, the object contains a
  screenshot of it, taken in the same browser session immediately after
  the answer has stabilized.
- **Result-presentation functions accept data, not the whole `AskResult`
  object** (`aiText2File`, `aiText2Clipboard`, `aiScreenshot2File`,
  `aiScreenshot2Clipboard`) — this allows them to be applied to data
  obtained from any source.
- **Modifier flags** (`SiteWorkerPref`) control the visibility of the
  browser window, console output, saving of debug files on error, and the
  format and scope of the screenshot. The default value (the empty set
  `{}`) corresponds to headless mode with no side output.

The full reference for the shared infrastructure and askQwen/askKimi is
given in [`docs/siteworker_reference_ru.md`](./docs/siteworker_reference_ru.md);
redcircle.nim and mavedigital.nim are documented directly in the source
code (a module header plus a comment on each exported function).

## Architecture

```
childtear.nim          — high-level CDP API (Browser/Tab/Frame): navigation,
                          clicks, forms, screenshots, network, emulation, diagnostics —
                          the main entry point for library users
siteworkers/
  siteworker_common.nim — infrastructure shared by siteworkers/*.nim: AskResult,
                          SiteWorkerPref, ImageFormat, finding and marking
                          page elements by visible text (mark*)
  qwen.nim, kimi.nim    — askQwen()/askKimi() scenarios for chat services
  redcircle.nim,
  mavedigital.nim       — podcast episode publishing scenarios
                          (uploadToRedcircle()/uploadToMave())
                          None of the four modules accesses the
                          CDP protocol directly — only through the public
                          API of childtear.nim and siteworkers/browser_lifecycle.nim,
                          siteworkers/clipboard.nim.
cdp/
  transport.nim        — WebSocket JSON-RPC over CDP, event subscription
  wsclient.nim          — low-level WebSocket client (handshake, framing)
  browser.nim           — HTTP interface /json/* (tab list, open/close)
  browser_lifecycle.nim — launching/reusing Chromium with a persistent
                          profile (ensureBrowser/stopBrowser), gotoWithRetry
  clipboard.nim         — screenshot of the last assistant message + working
                          with the system clipboard
  domains/
    page.nim, dom.nim, runtime.nim, input.nim, network.nim,
    emulation.nim, fetch.nim, target.nim, browserdomain.nim,
    storage.nim, log.nim
                        — wrappers implementing a one-to-one mapping
                          to the CDP domains
```

Each CDP domain is implemented as a separate module in `cdp/domains/`;
`childtear.nim` composes these modules into high-level commands.
If there is no ready-made function for a particular task, access to
an arbitrary protocol command is available through `tab.session`.

The shared scenario infrastructure (`AskResult`/`SiteWorkerPref`,
`mark*ByLabel/Text`, `ensureBrowser`/`stopBrowser`, the clipboard)
lives in `siteworkers/siteworker_common.nim`,
`siteworkers/browser_lifecycle.nim` and `siteworkers/clipboard.nim`.
`childtear.nim` contains only the core of the CDP wrapper
(Browser/Tab/Frame). The `cdp/` layer does not depend on `childtear.nim`
or `siteworkers/`: dependencies go strictly downward
(`siteworkers/` → `childtear.nim` → `cdp/`). Each `siteworkers/*.nim`
module imports from these files only what it actually needs.

## License

MIT.
