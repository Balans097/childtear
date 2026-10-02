# childtear — справочник высокоуровневого API

> **Импорт:** `import childtear`

> **Область применения:** основной интерфейс библиотеки для управления headless-Chromium — открыть вкладку, кликнуть, заполнить форму, прочитать текст, сделать скриншот и т.п. одной командой. Для случаев, не покрытых этим API, есть низкоуровневый CDP-слой — см. [`cdp_reference_ru.md`](./cdp_reference_ru.md).

Три типа, с которыми работает этот API: `Browser` — соединение с запущенным браузером (`newBrowser()`), `Tab` — открытая вкладка (`openTab()`/`newPage()`), `Frame` — содержимое одного iframe (`tab.frame(cssSelector)`). Большинство функций принимают `Tab` первым параметром; там, где это не так (например, `Frame` или `Browser`), это отдельно указано в подписи. Функции при ошибке (элемент не найден, истёк таймаут и т.п.) поднимают `ChildTearError`, а не молча возвращают пустое значение.

Во всех примерах ниже предполагаются уже открытые `browser: Browser` и `tab: Tab` (см. пример `openTab()` в начале раздела I) — открывать их заново в примере каждой отдельной функции было бы избыточно. Также предполагается выполнение внутри `proc main() {.async.} = ...` с `import childtear` и `import std/asyncdispatch`.


---

## Оглавление
I. [Типы](#типы)
   1. [`Browser`](#browser)
   2. [`Tab`](#tab)
   3. [`Frame`](#frame)
   4. [`ChildTearError`](#childtearerror)
II. [Браузер и вкладки](#браузер-и-вкладки)
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
III. [Навигация](#навигация)
   1. [`goto` (Tab)](#goto-tab)
   2. [`reload` (Tab)](#reload-tab)
IV. [Взаимодействие с элементами](#взаимодействие-с-элементами)
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
V. [JS "аварийный люк" и снимки страницы](#js-аварийный-люк-и-снимки-страницы)
   1. [`evalJS` (Tab)](#evaljs-tab)
   2. [`screenshot` (Tab)](#screenshot-tab)
   3. [`savePDF` (Tab)](#savepdf-tab)
   4. [`title` (Tab)](#title-tab)
   5. [`currentUrl` (Tab)](#currenturl-tab)
VI. [Инжектируемые скрипты и мост JS -> Nim](#инжектируемые-скрипты-и-мост-js-nim)
   1. [`addScriptTag` (Tab)](#addscripttag-tab)
   2. [`evaluateOnNewDocument` (Tab)](#evaluateonnewdocument-tab)
   3. [`removeEvaluateOnNewDocument` (Tab)](#removeevaluateonnewdocument-tab)
   4. [`exposeFunction` (Tab)](#exposefunction-tab)
VII. [Навигация: история, остановка загрузки, фокус вкладки](#навигация-история-остановка-загрузки-фокус-вкладки)
   1. [`goBack` (Tab)](#goback-tab)
   2. [`goForward` (Tab)](#goforward-tab)
   3. [`stop` (Tab)](#stop-tab)
   4. [`bringToFront` (Tab)](#bringtofront-tab)
   5. [`waitForURL` (Tab)](#waitforurl-tab)
VIII. [Мышь и клавиатура: расширенные жесты](#мышь-и-клавиатура-расширенные-жесты)
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
IX. [Формы: чекбоксы, значения, состояние полей](#формы-чекбоксы-значения-состояние-полей)
   1. [`setChecked` (Tab)](#setchecked-tab)
   2. [`check` (Tab)](#check-tab)
   3. [`uncheck` (Tab)](#uncheck-tab)
   4. [`getValue` (Tab)](#getvalue-tab)
   5. [`isChecked` (Tab)](#ischecked-tab)
   6. [`isDisabled` (Tab)](#isdisabled-tab)
   7. [`isVisible` (Tab)](#isvisible-tab)
   8. [`focus` (Tab)](#focus-tab)
   9. [`blur` (Tab)](#blur-tab)
X. [Чтение состояния и содержимого элементов](#чтение-состояния-и-содержимого-элементов)
   1. [`boundingBox` (Tab)](#boundingbox-tab)
   2. [`innerHTML` (Tab)](#innerhtml-tab)
   3. [`outerHTML` (Tab)](#outerhtml-tab)
   4. [`getLinks` (Tab)](#getlinks-tab)
   5. [`getAllAttributes` (Tab)](#getallattributes-tab)
   6. [`getViewportSize` (Tab)](#getviewportsize-tab)
XI. [Дополнительные ожидания](#дополнительные-ожидания)
   1. [`waitForSelectorGone` (Tab)](#waitforselectorgone-tab)
   2. [`waitForText` (Tab)](#waitfortext-tab)
   3. [`waitUntilTrue`](#waituntiltrue)
   4. [`waitUntilCleared` (Tab)](#waituntilcleared-tab)
XII. [localStorage и sessionStorage](#localstorage-и-sessionstorage)
   1. [`localStorageGet` (Tab)](#localstorageget-tab)
   2. [`localStorageSet` (Tab)](#localstorageset-tab)
   3. [`localStorageRemove` (Tab)](#localstorageremove-tab)
   4. [`localStorageClear` (Tab)](#localstorageclear-tab)
   5. [`sessionStorageGet` (Tab)](#sessionstorageget-tab)
   6. [`sessionStorageSet` (Tab)](#sessionstorageset-tab)
   7. [`sessionStorageRemove` (Tab)](#sessionstorageremove-tab)
   8. [`sessionStorageClear` (Tab)](#sessionstorageclear-tab)
XIII. [Эмуляция окружения](#эмуляция-окружения)
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
XIV. [Разрешения и окно браузера](#разрешения-и-окно-браузера)
   1. [`grantPermissions` (Browser)](#grantpermissions-browser)
   2. [`resetPermissions` (Browser)](#resetpermissions-browser)
   3. [`setWindowSize` (Tab)](#setwindowsize-tab)
   4. [`maximizeWindow` (Tab)](#maximizewindow-tab)
XV. [Загрузка файлов](#загрузка-файлов)
   1. [`setDownloadPath` (Tab)](#setdownloadpath-tab)
   2. [`interceptFileChooser` (Tab)](#interceptfilechooser-tab)
XVI. [Консоль и ошибки страницы](#консоль-и-ошибки-страницы)
   1. [`onConsole` (Tab)](#onconsole-tab)
   2. [`onPageError` (Tab)](#onpageerror-tab)
XVII. [Сеть: ожидание конкретных ответов](#сеть-ожидание-конкретных-ответов)
   1. [`waitForResponse` (Tab)](#waitforresponse-tab)
   2. [`responseBody` (Tab)](#responsebody-tab)
XVIII. [Фреймы](#фреймы)
   1. [`frames` (Tab)](#frames-tab)
   2. [`frame` (Tab)](#frame-tab)
   3. [`click` (Frame)](#click-frame)
   4. [`hover` (Frame)](#hover-frame)
   5. [`evalJS` (Frame)](#evaljs-frame)
   6. [`getText` (Frame)](#gettext-frame)
   7. [`getAllText` (Frame)](#getalltext-frame)
   8. [`fill` (Frame)](#fill-frame)
   9. [`exists` (Frame)](#exists-frame)
XIX. [Скриншот отдельного элемента](#скриншот-отдельного-элемента)
   1. [`screenshotElement` (Tab)](#screenshotelement-tab)
XX. [Прочие функции ядра](#прочие-функции-ядра)
   1. [`insertTextAtCursor`](#inserttextatcursortab-text)
   2. [`setControlledValue`](#setcontrolledvaluetab-selector-value)
   3. [`installNetworkFailureLog`](#installnetworkfailurelogtab)
XXI. [Практические рецепты](#практические-рецепты)
XXII. [Краткая таблица](#краткая-таблица)
XXIII. [Сводка: какую функцию выбрать](#сводка-какую-функцию-выбрать)

Инфраструктура, специфичная для сценария сайт-автоматизации
(`siteworkers/*.nim`), но не для одного конкретного сайта, живёт в
отдельных модулях со своими справочниками:
[`siteworker_common_reference_ru.md`](./siteworker_common_reference_ru.md)
(типы `AskResult`/`SiteWorkerPref`/`ImageFormat`, поиск и пометка
элементов по видимому тексту, `vecho`/`warnLoggedOut`),
[`browser_lifecycle_reference_ru.md`](./browser_lifecycle_reference_ru.md)
(`ensureBrowser`/`stopBrowser`/`gotoWithRetry`/`dumpDebugInfoVerbose`) и
[`clipboard_reference_ru.md`](./clipboard_reference_ru.md)
(`captureAnswerScreenshot` и работа с буфером обмена).




---

## Типы

### `Browser`

Соединение с уже запущенным браузером (host:port из `newBrowser()`). Само по себе не открывает ни одной вкладки — точка входа для `openTab()`/`pages()`/`listTabs()` и настроек уровня браузера (`grantPermissions()`, `resetPermissions()`).

### `Tab`

Открытая вкладка браузера с активной WebSocket-сессией CDP. Основной объект, с которым работает почти весь API — `goto`/`click`/`fill`/`getText`/`screenshot` и т.д. принимают `Tab` первым параметром.

### `Frame`

Содержимое одного iframe на странице — получается через `tab.frame(cssSelector)`. В отличие от `Tab`, вся высокоуровневая работа с элементами внутри `Frame` идёт не по главному документу вкладки, а по документу конкретного iframe — у него свой DOM-поддокумент и свой JS execution context, создаваемый лениво при первом обращении к `evalJS()`/`getText()`/`fill()` и т.п.

### `ChildTearError`

Исключение высокого уровня: элемент не найден, навигация не удалась, истёк таймаут ожидания и т.п. — поднимается вместо тихого возврата пустого/ложного значения.


---

## Браузер и вкладки


### `newBrowser`


```nim
proc newBrowser*(host = "127.0.0.1", port = DefaultDebuggingPort): Browser
```


**Что делает.** Описывает подключение к уже запущенному headless-Chromium (см. команду запуска в шапке файла). Само по себе ничего не открывает — соединение устанавливается в openTab().


**Параметры:**

- `host`, по умолчанию `"127.0.0.1"`
- `port`, по умолчанию `DefaultDebuggingPort`


**Возвращает:** `Browser`


**Пример:**

```nim
let browser = newBrowser("127.0.0.1", 9222)
echo browser != nil # выводит true
```


### `openTab` (Browser)


```nim
proc openTab*(browser: Browser, url = ""): Future[Tab] {.async.}
```


**Что делает.** "Открыть вкладку". Создаёт новую вкладку в браузере, подключается к ней по WebSocket и включает домены Page/DOM/Runtime. Если передан url — сразу переходит по нему и дожидается загрузки.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `url`, по умолчанию `""` — адрес — страницы для перехода, скрипта, ресурса и т.п. в зависимости от функции.


**Возвращает:** `Future[Tab]`


**Пример:**

```nim
let
  browser = newBrowser() # 127.0.0.1:9222 по умолчанию
  tab = await openTab(browser, "https://example.com")
echo await title(tab) # выводит "Example Domain"
```


### `listTabs` (Browser)


```nim
proc listTabs*(browser: Browser): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Возвращает список всех уже открытых вкладок браузера (как в chrome://inspect) — каждый элемент содержит "id", "title", "url".


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let tabs = await listTabs(browser)
echo len(tabs) # выводит количество открытых вкладок
```


### `attachTab` (Browser)


```nim
proc attachTab*(browser: Browser, targetId: string): Future[Tab] {.async.}
```


**Что делает.** Подключается к уже существующей вкладке по её id (например, полученному из listTabs()), не создавая новую.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `targetId` (`string`) — id вкладки/цели, обычно взятый из listTabs() или chrome://inspect.


**Возвращает:** `Future[Tab]`


**Исключения:**

- `ChildTearError` — если вкладки с указанным `targetId` не существует (например, она уже закрыта).

**Пример:**

```nim
let
  tabs = await listTabs(browser)
  tab = await attachTab(browser, getStr(tabs[0]["id"]))
echo await currentUrl(tab) # выводит текущий URL уже открытой вкладки
```


### `close` (Tab)


```nim
proc close*(tab: Tab) {.async.}
```


**Что делает.** Закрывает вкладку: сначала WebSocket-сессию, затем саму вкладку в браузере (через HTTP /json/close). Если для этой вкладки уже была лениво создана browser-level сессия (см. tabBrowserSession(), используется setWindowSize()/maximizeWindow()), закрывает и её — иначе она осталась бы висеть до конца жизни процесса браузера.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await close(tab)
echo "вкладка закрыта" # выводит "вкладка закрыта"
```


### `newPage` (Browser)


```nim
proc newPage*(browser: Browser, url = ""): Future[Tab] {.async.}
```


**Что делает.** Синоним openTab() — так этот метод называется в Puppeteer (browser.newPage()).


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `url`, по умолчанию `""` — адрес — страницы для перехода, скрипта, ресурса и т.п. в зависимости от функции.


**Возвращает:** `Future[Tab]`


**Пример:**

```nim
let tab = await newPage(browser, "https://example.com")
echo await title(tab) # выводит "Example Domain"
```


### `newPageWithRetry` (Browser)


```nim
proc newPageWithRetry*(browser: Browser, url: string, attempts = 3, delayMs = 2_000,
                        onRetry: RetryCallback = nil): Future[Tab] {.async.}
```


**Что делает.** Как `newPage()`, но при неудаче первого перехода повторяет попытку до `attempts` раз с паузой `delayMs` между ними. Полезно на холодном старте только что запущенного Chromium: `waitForReady()` дожидается лишь готовности CDP-порта, а не того, что браузер уже разрешил сетевые/прокси-настройки (WPAD/PAC и т.п.) — первый переход по URL в этот момент изредка падает с сетевой ошибкой (например, `net::ERR_TUNNEL_CONNECTION_FAILED`), хотя сеть в целом рабочая.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `url` (`string`) — адрес страницы для перехода (в отличие от `newPage()`, здесь параметр обязателен — без URL повторные попытки не имели бы смысла).
- `attempts`, по умолчанию `3` — сколько раз всего пытаться перейти по `url`, прежде чем дать ошибке распространиться дальше.
- `delayMs`, по умолчанию `2_000` — пауза в миллисекундах между неудачными попытками.
- `onRetry` (`RetryCallback`), по умолчанию `nil` — `proc(attempt, attempts: int, msg: string)`, вызывается перед каждой повторной попыткой (номер неудавшейся попытки, общее число попыток, текст ошибки)


**Возвращает:** `Future[Tab]`


**Исключения:**

- `ChildTearError` — если переход не удался все `attempts` раз подряд; поднимается то же исключение, что и у последней попытки `newPage()`.


**Пример:**

```nim
discard startProcess("chromium", args = @["--remote-debugging-port=9222", "--headless=new"])
let browser = newBrowser("localhost", 9222)
await waitForReady(browser)
let tab = await newPageWithRetry(browser, "https://example.com") # переживёт временный сетевой сбой сразу после старта
```


### `pages` (Browser)


```nim
proc pages*(browser: Browser): Future[seq[Tab]] {.async.}
```


**Что делает.** Подключается ко всем уже открытым вкладкам браузера (аналог browser.pages() в Puppeteer) — воркеры/сервис-воркеры и т.п. из списка целей пропускаются, остаются только настоящие вкладки.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.


**Возвращает:** `Future[seq[Tab]]`


**Пример:**

```nim
let tabs = await pages(browser)
echo len(tabs) # выводит количество открытых вкладок как Tab-объектов
```


### `version` (Browser)


```nim
proc version*(browser: Browser): Future[JsonNode]
```


**Что делает.** Метаданные браузера: версия Chromium, User-Agent по умолчанию, версия протокола и т.д.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let ver = await version(browser)
echo ver["product"] # выводит что-то вроде "HeadlessChrome/120.0.0.0"
```


### `waitForReady` (Browser)


```nim
proc waitForReady*(browser: Browser, timeoutMs = 15_000) {.async.}
```


**Что делает.** Ждёт, пока Chromium поднимет отладочный HTTP/CDP-эндпоинт, опрашивая `/json/version` с шагом 200мс. Полезно сразу после того, как сам процесс браузера только что запущен вызывающим кодом (childtear его не запускает — процесс браузера нужно стартовать самостоятельно, например через `osproc.startProcess` с флагом `--remote-debugging-port`): между стартом процесса и готовностью порта есть небольшая задержка, и первый же `openTab()`/`newPage()` без этого ожидания может упасть с отказом соединения.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()` (сам объект `Browser` создать можно и до того, как порт реально откроется — соединение по HTTP/WS происходит только при первом реальном вызове).
- `timeoutMs`, по умолчанию `15_000` — сколько миллисекунд суммарно ждать, прежде чем сдаться.


**Возвращает:** `Future[void]`


**Исключения:**

- `ChildTearError` — если Chromium не поднял отладочный порт за `timeoutMs`.


**Пример:**

```nim
discard startProcess("chromium", args = @["--remote-debugging-port=9222", "--headless=new"])
let browser = newBrowser("localhost", 9222)
await waitForReady(browser) # дождаться, пока порт реально откроется
let tab = await newPage(browser)
```


### `close` (Browser)


```nim
proc close*(browser: Browser) {.async.}
```


**Что делает.** Закрывает браузер целиком (все вкладки, весь процесс) — в отличие от Tab.close(), которая закрывает только одну вкладку.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.


**Пример:**

```nim
await close(browser)
echo "браузер закрыт целиком" # выводит "браузер закрыт целиком"
```


### `createIncognitoContext` (Browser)


```nim
proc createIncognitoContext*(browser: Browser): Future[string] {.async.}
```


**Что делает.** Создаёт изолированный профиль (свои куки/кэш/localStorage) — аналог browser.createIncognitoBrowserContext() в Puppeteer. Возвращает browserContextId для newPageInContext()/closeContext().


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let ctxId = await createIncognitoContext(browser)
echo len(ctxId) > 0 # выводит true — создан изолированный профиль без общих кук с обычными вкладками
```


### `newPageInContext` (Browser)


```nim
proc newPageInContext*(browser: Browser, browserContextId: string, url = ""): Future[Tab] {.async.}
```


**Что делает.** Открывает вкладку внутри изолированного профиля, созданного createIncognitoContext().


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `browserContextId` (`string`) — id изолированного профиля, полученный от createIncognitoContext().
- `url`, по умолчанию `""` — адрес — страницы для перехода, скрипта, ресурса и т.п. в зависимости от функции.


**Возвращает:** `Future[Tab]`


**Пример:**

```nim
let
  ctxId = await createIncognitoContext(browser)
  tab = await newPageInContext(browser, ctxId, "https://example.com")
echo await title(tab) # выводит "Example Domain", но с чистыми куками этого профиля
```


### `closeContext` (Browser)


```nim
proc closeContext*(browser: Browser, browserContextId: string) {.async.}
```


**Что делает.** Уничтожает изолированный профиль и закрывает все его вкладки.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `browserContextId` (`string`) — id изолированного профиля, полученный от createIncognitoContext(); уничтожается вместе со всеми его вкладками.


**Пример:**

```nim
let ctxId = await createIncognitoContext(browser)
await closeContext(browser, ctxId)
echo "профиль и все его вкладки закрыты" # выводит "профиль и все его вкладки закрыты"
```


### `enableNetwork` (Tab)


```nim
proc enableNetwork*(tab: Tab) {.async.}
```


**Что делает.** Включает домен Network — не делается по умолчанию, чтобы не тратить лишний трафик на события, если они не нужны.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await enableNetwork(tab)
echo "отслеживание сети включено" # выводит "отслеживание сети включено"
```


### `setExtraHeaders` (Tab)


```nim
proc setExtraHeaders*(tab: Tab, headers: openArray[(string, string)]) {.async.}
```


**Что делает.** Добавляет заданные заголовки ко всем последующим HTTP-запросам этой вкладки (например, авторизацию или кастомный User-Agent-подобный заголовок) — действует, пока не будет вызван повторно с другим набором. Требует включённого домена Network (см. enableNetwork()).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `headers` (`openArray[(string, string)]`) — пары (имя, значение) заголовков, например `{("X-My-Header", "value")}`.


**Пример:**

```nim
await setExtraHeaders(tab, {"X-Debug": "1"})
echo "заголовок будет добавляться ко всем запросам вкладки" # выводит "заголовок будет добавляться ко всем запросам вкладки"
```


### `blockUrls` (Tab)


```nim
proc blockUrls*(tab: Tab, urlSubstrings: seq[string]) {.async.}
```


**Что делает.** Блокирует запросы, чей URL содержит любую из подстрок urlSubstrings (например, домены рекламы/трекеров), пропуская остальные без изменений. Построено на домене Fetch.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `urlSubstrings` (`seq[string]`) — список подстрок — запрос блокируется, если его URL содержит любую из них (например, домены рекламы/трекеров).


**Пример:**

```nim
await blockUrls(tab, @["*.png", "*doubleclick.net*"])
echo "паттерны заблокированы" # выводит "паттерны заблокированы"
```


### `setViewport` (Tab)


```nim
proc setViewport*(tab: Tab, width, height: int, deviceScaleFactor = 1.0, mobile = false) {.async.}
```


**Что делает.** Подделывает размер вьюпорта и плотность пикселей (аналог page.setViewport() в Puppeteer). Действует, пока не будет вызван повторно с другими значениями — на размер самого окна браузера (в headless-режиме не имеющего экрана) не влияет.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `width` (`int`) — ширина вьюпорта в CSS-пикселях.
- `height` (`int`) — высота вьюпорта в CSS-пикселях.
- `deviceScaleFactor`, по умолчанию `1.0`
- `mobile`, по умолчанию `false`


**Пример:**

```nim
await setViewport(tab, 1280, 800)
echo "вьюпорт установлен 1280x800" # выводит "вьюпорт установлен 1280x800"
```


### `setUserAgent` (Tab)


```nim
proc setUserAgent*(tab: Tab, userAgent: string, acceptLanguage = "", platform = "") {.async.}
```


**Что делает.** Подделывает navigator.userAgent (и, опционально, Accept-Language и navigator.platform) для всех последующих запросов и скриптов этой вкладки — действует до следующего вызова с другими значениями.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `userAgent` (`string`) — строка User-Agent, которую будет видеть navigator.userAgent страницы и заголовок HTTP User-Agent.
- `acceptLanguage`, по умолчанию `""`
- `platform`, по умолчанию `""`


**Пример:**

```nim
await setUserAgent(tab, "Mozilla/5.0 (compatible; childtear-bot)")
echo "User-Agent подменён" # выводит "User-Agent подменён"
```


### `cookies` (Tab)


```nim
proc cookies*(tab: Tab, urls: seq[string] = @[]): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Без urls возвращает куки, видимые текущей странице.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `urls` (`seq[string]`), по умолчанию `@[]`


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let cks = await cookies(tab, @["https://example.com"])
echo len(cks) # выводит количество кук, видимых этому URL
```


### `setCookie` (Tab)


```nim
proc setCookie*(tab: Tab, name, value: string, domain = "", path = "/", secure = false, httpOnly = false, sameSite = ""): Future[bool] {.async.}
```


**Что делает.** Нужно указать domain, либо кука будет привязана к текущему URL вкладки (запрашивается автоматически, если domain не передан).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `name` (`string`) — имя — куки, атрибута, ключа хранилища или JS-функции, в зависимости от контекста функции.
- `value` (`string`) — значение, которое нужно установить — куки, ключа хранилища и т.п.
- `domain`, по умолчанию `""`
- `path`, по умолчанию `"/"` — путь к файлу на диске — куда сохранить (скриншот, PDF, текст) или откуда загрузить.
- `secure`, по умолчанию `false`
- `httpOnly`, по умолчанию `false`
- `sameSite`, по умолчанию `""`


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let ok = await setCookie(tab, "session_id", "abc123", domain = "example.com", secure = true)
echo ok # выводит true, если кука успешно установлена
```


### `deleteCookie` (Tab)


```nim
proc deleteCookie*(tab: Tab, name: string, url = "") {.async.}
```


**Что делает.** Удаляет одну куку по имени (и, опционально, url — если не передан, берётся текущий URL вкладки). В отличие от clearCookies(), затрагивает только эту одну куку, а не весь браузер.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `name` (`string`) — имя — куки, атрибута, ключа хранилища или JS-функции, в зависимости от контекста функции.
- `url`, по умолчанию `""` — адрес — страницы для перехода, скрипта, ресурса и т.п. в зависимости от функции.


**Пример:**

```nim
await deleteCookie(tab, "session_id")
echo "кука удалена" # выводит "кука удалена"
```


### `clearCookies` (Tab)


```nim
proc clearCookies*(tab: Tab) {.async.}
```


**Что делает.** ВНИМАНИЕ: у Chromium нет способа очистить куки только одной вкладки — эта команда чистит куки всего браузера целиком (все вкладки, все сайты, все открытые профили). Если нужно очистить куки только текущего сайта — см. clearCookiesForOrigin().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await clearCookies(tab)
echo "куки браузера очищены" # выводит "куки браузера очищены" — весь браузер, все сайты и вкладки
```


### `clearCookiesForOrigin` (Tab)


```nim
proc clearCookiesForOrigin*(tab: Tab) {.async.}
```


**Что делает.** В отличие от clearCookies() (чистит весь браузер сразу — так устроен сам протокол CDP, отдельной команды "куки одной вкладки" в нём нет), удаляет только куки, видимые текущей странице: сначала получает их список через cookies() (Network.getCookies), затем удаляет каждую по отдельности через Network.deleteCookies, уже привязанные к конкретному URL. Другие сайты и вкладки не затрагиваются.


**Разбор реализации.** У CDP нет отдельной команды "очистить куки одной вкладки" — `Network.clearBrowserCookies` всегда действует на весь браузер сразу. Функция обходит это ограничение вручную: получает список кук, видимых текущему URL, через `cookies()` (`Network.getCookies`), и удаляет каждую по отдельности через `Network.deleteCookies`, уже привязанные к конкретному URL — другие сайты и вкладки не затрагиваются.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await clearCookiesForOrigin(tab)
echo "куки текущего сайта очищены" # выводит "куки текущего сайта очищены" — только текущий origin
```


### `content` (Tab)


```nim
proc content*(tab: Tab): Future[string] {.async.}
```


**Что делает.** Полный HTML документа (document.documentElement.outerHTML) — аналог page.content() в Puppeteer.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let html = await content(tab)
echo len(html) > 0 # выводит true — получена полная HTML-разметка страницы
```


### `setContent` (Tab)


```nim
proc setContent*(tab: Tab, html: string) {.async.}
```


**Что делает.** Заменяет содержимое страницы на произвольный HTML без перехода по URL (аналог page.setContent() в Puppeteer) — удобно для тестов, когда нужна страница с точно заданной разметкой.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `html` (`string`) — HTML-разметка, которой будет заменено содержимое текущего документа.


**Пример:**

```nim
await setContent(tab, "<h1>Заменено вручную</h1>")
echo await getText(tab, "h1") # выводит "Заменено вручную"
```


---

## Навигация


### `goto` (Tab)


```nim
proc goto*(tab: Tab, url: string, timeoutMs = 30_000) {.async.}
```


**Что делает.** "Перейти по ссылке" (загрузить произвольный URL в текущей вкладке). Дожидается события Page.loadEventFired, то есть возвращает управление уже после полной загрузки страницы. Если сама навигация не смогла даже начаться (например, DNS-имя не резолвится или URL некорректен), Page.navigate возвращает в ответе поле "errorText" — в этом случае Page.loadEventFired никогда не придёт, поэтому errorText проверяется сразу же, до ожидания события, и превращается в понятную ошибку с указанием причины и URL, вместо непрозрачного таймаута через timeoutMs.


**Разбор реализации.** Если сама навигация не смогла даже начаться (например, DNS-имя не резолвится или URL некорректен), `Page.navigate` возвращает в ответе поле `"errorText"` — событие `Page.loadEventFired` в этом случае никогда не придёт. `goto()` проверяет `errorText` сразу же, до ожидания события, и поднимает понятную ошибку с причиной и URL, вместо непрозрачного таймаута через `timeoutMs`.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `url` (`string`) — адрес — страницы для перехода, скрипта, ресурса и т.п. в зависимости от функции.
- `timeoutMs`, по умолчанию `30_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.


**Исключения:**

- `ChildTearError` — если навигация не смогла начаться (DNS не резолвится, некорректный URL и т.п. — CDP вернул `errorText`); в сообщении указаны причина и сам URL. Если `Page.loadEventFired` не пришло за `timeoutMs` по другой причине — таймаут ожидания события (тоже `ChildTearError`).

**Пример:**

```nim
await goto(tab, "https://example.com")
echo await title(tab) # выводит "Example Domain"
```


### `reload` (Tab)


```nim
proc reload*(tab: Tab, ignoreCache = false) {.async.}
```


**Что делает.** Перезагружает текущую страницу и дожидается Page.loadEventFired (как и goto()). ignoreCache = true — то же, что Ctrl+Shift+R, жёсткая перезагрузка мимо HTTP-кэша.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `ignoreCache`, по умолчанию `false`


**Пример:**

```nim
await reload(tab, ignoreCache = true)
echo "страница перезагружена мимо кэша" # выводит "страница перезагружена мимо кэша"
```


---

## Взаимодействие с элементами


### `click` (Tab)


```nim
proc click*(tab: Tab, selector: string) {.async.}
```


**Что делает.** "Нажать на кнопку" (или на любой другой элемент по CSS-селектору). Вычисляет центр элемента на экране и эмулирует настоящий клик мышью через домен Input — так же, как это делает пользователь.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await click(tab, "button[type=submit]")
echo "клик выполнен" # выводит "клик выполнен"
```


### `hover` (Tab)


```nim
proc hover*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Наводит курсор на элемент, не кликая — эмулирует mouseover (полезно для выпадающих меню/тултипов, показывающихся по hover).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await hover(tab, ".dropdown-trigger")
echo "курсор наведён" # выводит "курсор наведён" — сработают обработчики mouseover/mouseenter
```


### `fill` (Tab)


```nim
proc fill*(tab: Tab, selector: string, text: string) {.async.}
```


**Что делает.** "Заполнить поле данными". Фокусирует элемент, выделяет его текущее содержимое (чтобы новый текст замещал старый, а не дописывался) и вставляет текст через Input.insertText.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `text` (`string`) — текст, который будет вставлен в поле вместо его текущего содержимого.


**Исключения:**

- `ChildTearError` — если элемент для заполнения не найден по `selector`.

**Пример:**

```nim
await fill(tab, "#username", "andy")
echo await getValue(tab, "#username") # выводит "andy"
```


### `syncControlledValue` (Tab)


```nim
proc syncControlledValue*(tab: Tab, selector: string): Future[bool] {.async.}
```


**Что делает.** Чинит поля, которыми управляет React/Vue-подобный фреймворк ("controlled" input-компонент): такой фреймворк переопределяет нативный сеттер свойства `value` у `<input>`/`<textarea>` собственным — поэтому `fill()`/`type()` (события клавиатуры/`Input.insertText`) меняют `.value` в обход этого переопределения, сам компонент остаётся не в курсе изменения, и на следующем ре-рендере откатывает поле к своему (обычно пустому) внутреннему состоянию. Достаёт НАТИВНЫЙ сеттер через дескриптор прототипа `HTMLInputElement`/`HTMLTextAreaElement` (а не текущий, переопределённый фреймворком) и вызывает его явно тем же значением, что уже лежит в поле, затем диспатчит событие `input` с `bubbles: true` — после этого фреймворк пересчитывает состояние компонента и видит введённый текст. Вызывать ПОСЛЕ `fill()`/`type()`, если есть подозрение, что фреймворк не заметил изменения (типичный симптом: поле визуально показывает текст, но зависящая от него кнопка остаётся неактивной, либо значение пропадает при следующем действии на странице).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[bool]` — `false`, если элемент не найден (не считается ошибкой), иначе `true`.


**Пример:**

```nim
await fill(tab, "#react-input", "andy")
discard await syncControlledValue(tab, "#react-input") # заставить React-компонент заметить новое значение
```


### `fillForm` (Tab)


```nim
proc fillForm*(tab: Tab, fields: seq[(string, string)]) {.async.}
```


**Что делает.** "Заполнить форму данными". Принимает список пар (селектор, значение) и последовательно заполняет каждое поле, например: await fillForm(tab, @[("#login", "andy"), ("#password", "secret")])


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `fields` (`seq[(string, string)]`) — пары (CSS-селектор, значение); каждое поле заполняется по очереди тем же способом, что и `fill()`. Именно `seq`, а не `openArray`: см. пояснение у `pressKeyCombo()` — `openArray`-параметр нельзя захватить в замыкание async-процедуры.


**Пример:**

```nim
await fillForm(tab, @{"#username": "andy", "#password": "secret"})
echo "форма заполнена" # выводит "форма заполнена"
```


### `typeText` (Tab)


```nim
proc typeText*(tab: Tab, selector: string, text: string, delayMs = 0) {.async.}
```


**Что делает.** В отличие от fill() (вставляет текст одним куском через insertText), печатает по одному символу настоящими событиями клавиатуры — так страница видит keydown/keypress/input на каждый символ отдельно (нужно для полей с масками ввода, автодополнением и т.п., как page.type() в Puppeteer). delayMs — пауза между символами в миллисекундах, для более "человечного" набора.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `text` (`string`) — текст, печатаемый посимвольно настоящими событиями клавиатуры.
- `delayMs`, по умолчанию `0`


**Пример:**

```nim
await typeText(tab, "#search", "childtear nim", delayMs = 50)
echo await getValue(tab, "#search") # выводит "childtear nim"
```


### `selectOption` (Tab)


```nim
proc selectOption*(tab: Tab, selector: string, value: string) {.async.}
```


**Что делает.** Выбирает option с указанным value в элементе `<select>` и генерирует событие "change", как это делает браузер при реальном выборе.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `value` (`string`) — значение, которое нужно установить — куки, ключа хранилища и т.п.


**Исключения:**

- `ChildTearError` — если элемент `<select>` не найден по `selector`.

**Пример:**

```nim
await selectOption(tab, "#country", "NL")
echo await getValue(tab, "#country") # выводит "NL"
```


### `uploadFile` (Tab)


```nim
proc uploadFile*(tab: Tab, selector: string, paths: seq[string]) {.async.}
```


**Что делает.** Назначает файлы элементу <input type="file"> напрямую, без системного диалога выбора файла. paths — абсолютные пути на диске, где выполняется сам браузер (а не обязательно та машина, где работает childtear, если Chromium запущен удалённо).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `paths` (`seq[string]`) — абсолютные пути к файлам на диске, где выполняется сам браузер (а не обязательно та машина, где работает childtear).


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await uploadFile(tab, "input[type=file]", @["/tmp/photo.jpg"])
echo "файл выбран" # выводит "файл выбран"
```


### `submitForm` (Tab)


```nim
proc submitForm*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Отправляет форму программно (эквивалент form.submit()) — полезно, когда у формы нет явной кнопки "Submit" под курсором.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Пример:**

```nim
await submitForm(tab, "#login-form")
echo "форма отправлена" # выводит "форма отправлена"
```


### `getText` (Tab)


```nim
proc getText*(tab: Tab, selector: string): Future[string] {.async.}
```


**Что делает.** Возвращает видимый текст элемента (innerText, либо textContent, если innerText недоступен, как в случае с SVG-узлами).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[string]`


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
let heading = await getText(tab, "h1")
echo heading # выводит "Example Domain"
```


### `getAllText` (Tab)


```nim
proc getAllText*(tab: Tab, selector: string): Future[seq[string]] {.async.}
```


**Что делает.** Как getText(), но для ВСЕХ элементов, подходящих под селектор, — например, чтобы одним вызовом собрать текст всех заголовков новостей на странице (селектор вида "h3.headline"). Порядок результата совпадает с порядком элементов в документе.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[seq[string]]`


**Пример:**

```nim
let items = await getAllText(tab, "li.product-name")
echo len(items) # выводит количество найденных элементов списка
```


### `getLastText` (Tab)


```nim
proc getLastText*(tab: Tab, selector: string): Future[string] {.async.}
```


**Что делает.** Как `getText()`, но берёт ПОСЛЕДНИЙ подходящий под `selector` узел документа (через `document.querySelectorAll()`), а не первый (`getText()` использует `document.querySelector()`, который всегда возвращает первое совпадение). Полезно на страницах со списком одинаково размеченных повторяющихся элементов (история сообщений чата, лента и т.п.), когда нужен именно самый свежий из них. В отличие от `getText()`, отсутствие совпадений НЕ считается ошибкой — возвращается `""` (на динамических страницах нужного узла может ещё не быть в DOM в момент вызова). Используется как строительный блок внутри `waitForStableText()` (см. ниже).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомых элементов (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[string]` — текст последнего совпадения, либо `""`, если совпадений нет.


**Пример:**

```nim
let lastMessage = await getLastText(tab, ".chat-message")
echo lastMessage # выводит текст самого последнего сообщения в чате
```


### `count` (Tab)


```nim
proc count*(tab: Tab, selector: string): Future[int] {.async.}
```


**Что делает.** Считает число элементов, подходящих под CSS-селектор, — удобно как быстрая проверка вида "на странице есть хотя бы N карточек товара", не читая сам текст элементов.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[int]`


**Пример:**

```nim
let n = await count(tab, "a")
echo n # выводит количество ссылок на странице
```


### `saveText` (Tab)


```nim
proc saveText*(tab: Tab, selector: string, path: string) {.async.}
```


**Что делает.** Удобная связка getText() + запись в файл: получает видимый текст элемента (например, всей статьи целиком, если селектор указывает на её контейнер — браузер уже вставит переносы строк между абзацами в самом innerText) и сохраняет его в текстовый файл path.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `path` (`string`) — путь к файлу на диске — куда сохранить (скриншот, PDF, текст) или откуда загрузить.


**Пример:**

```nim
await saveText(tab, "article", "/tmp/article.txt")
echo "текст статьи сохранён в файл" # выводит "текст статьи сохранён в файл"
```


### `getAttribute` (Tab)


```nim
proc getAttribute*(tab: Tab, selector, name: string): Future[string] {.async.}
```


**Что делает.** HTML-атрибут элемента (Element.getAttribute) — например, "href" у ссылки или "data-id" у произвольного data-атрибута. Возвращает пустую строку, если атрибута нет (не отличимо от атрибута с пустым значением — если это важно, проверяйте через exists()/evalJS() с hasAttribute()).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `name` (`string`) — имя — куки, атрибута, ключа хранилища или JS-функции, в зависимости от контекста функции.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let href = await getAttribute(tab, "a.main-link", "href")
echo href # выводит значение атрибута href, например "https://example.com/more"
```


### `exists` (Tab)


```nim
proc exists*(tab: Tab, selector: string): Future[bool] {.async.}
```


**Что делает.** Проверяет наличие элемента на странице прямо сейчас, без ожидания.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let found = await exists(tab, "#cookie-banner")
echo found # выводит true/false в зависимости от наличия элемента
```


### `existsWithText` (Tab)


```nim
proc existsWithText*(tab: Tab, tag: string, textSubstring: string): Future[bool] {.async.}
```


**Что делает.** Ищет элемент по HTML-тегу (например "button"), содержащий заданную подстроку в видимом тексте (сравнение регистронезависимое) — замена отсутствующему в обычном CSS псевдоселектору `:has-text(...)` из Playwright. Полезно, когда единственный надёжный признак нужного элемента — его текст, а не класс/id/атрибут (например, проверка "нет ли на странице кнопки с текстом 'Log in'", то есть сессия не авторизована).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `tag` (`string`) — имя HTML-тега без CSS-декораций, например "button", "a", "div".
- `textSubstring` (`string`) — подстрока видимого текста, которую ищем внутри элементов с тегом `tag` (регистр не важен).


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let loggedOut = await existsWithText(tab, "button", "Log in")
echo loggedOut # выводит true, если на странице есть кнопка с текстом "Log in"
```


### `waitForSelector` (Tab)


```nim
proc waitForSelector*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**Что делает.** Ждёт появления элемента на странице (например, после AJAX-запроса или анимации), опрашивая DOM с заданным интервалом. Возвращает true, если элемент появился до истечения timeoutMs, иначе false.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `timeoutMs`, по умолчанию `5_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.
- `pollIntervalMs`, по умолчанию `100` — как часто (в миллисекундах) перепроверять условие при ожидании — компромисс между отзывчивостью и нагрузкой на CDP-соединение.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let appeared = await waitForSelector(tab, "#result", timeoutMs = 5_000)
echo appeared # выводит true, если элемент появился до истечения таймаута
```


### `waitForNavigation` (Tab)


```nim
proc waitForNavigation*(tab: Tab, timeoutMs = 30_000): Future[JsonNode]
```


**Что делает.** В отличие от goto(), не запускает переход сама, а лишь ждёт следующую загрузку страницы — регистрация ожидания происходит синхронно в момент вызова, поэтому типичный сценарий Puppeteer "нажать на ссылку и дождаться перехода" работает без гонки: let navigated = waitForNavigation(tab) await click(tab, "a.some-link") discard await navigated


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `timeoutMs`, по умолчанию `30_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
await click(tab, "a.next-page")
discard await waitForNavigation(tab, timeoutMs = 10_000)
echo "переход на новую страницу завершён" # выводит "переход на новую страницу завершён"
```


### `waitForFunction` (Tab)


```nim
proc waitForFunction*(tab: Tab, expression: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[JsonNode] {.async.}
```


**Что делает.** Опрашивает JS-выражение, пока оно не вернёт "истинное" (в смысле JS) значение — аналог page.waitForFunction() в Puppeteer. Возвращает итоговое значение выражения.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `expression` (`string`) — JS-выражение, опрашиваемое до тех пор, пока оно не вернёт «истинное» (в смысле JS) значение.
- `timeoutMs`, по умолчанию `5_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.
- `pollIntervalMs`, по умолчанию `100` — как часто (в миллисекундах) перепроверять условие при ожидании — компромисс между отзывчивостью и нагрузкой на CDP-соединение.


**Возвращает:** `Future[JsonNode]`


**Исключения:**

- `ChildTearError` — если `expression` не стало истинным (в смысле JS) за `timeoutMs`.

**Пример:**

```nim
discard await waitForFunction(tab, "document.readyState === 'complete'")
echo "документ полностью загружен" # выводит "документ полностью загружен"
```


### `pressEnter` (Tab)


```nim
proc pressEnter*(tab: Tab, selector = "") {.async.}
```


**Что делает.** Нажимает Enter — либо в текущем сфокусированном элементе, либо (если передан selector) предварительно кликая на него.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector`, по умолчанию `""` — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Пример:**

```nim
await fill(tab, "#search", "childtear")
await pressEnter(tab, "#search")
echo "поиск отправлен по Enter" # выводит "поиск отправлен по Enter"
```


### `onDialog` (Tab)


```nim
proc onDialog*(tab: Tab, handler: DialogHandler)
```


**Что делает.** Подписывается на открытие JS-диалогов (alert/confirm/prompt/ beforeunload). ВАЖНО: пока диалог открыт, вкладка "заморожена" — навигация и большинство команд не выполняются, пока диалог не закрыт через acceptDialog()/dismissDialog(). В отличие от интерактивного режима, Chromium НЕ закрывает диалоги сам — если не подписаться (или воспользоваться autoDismissDialogs()), вкладка может зависнуть на первом же alert().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `handler` (`DialogHandler`) — функция обратного вызова, получающая текст диалога, его тип ("alert"/"confirm"/"prompt"/"beforeunload") и текст по умолчанию для prompt().


**Пример:**

```nim
proc handler(kind, message: string): bool =
  echo message # выводит текст диалога, например "Вы уверены?"
  result = true # true — подтвердить (OK), false — отклонить (Cancel)
onDialog(tab, handler)
```


### `acceptDialog` (Tab)


```nim
proc acceptDialog*(tab: Tab, promptText = "") {.async.}
```


**Что делает.** Подтверждает открытый JS-диалог (OK у alert/confirm, Enter у prompt). promptText — что "ввести" в диалог prompt() перед подтверждением; для alert()/confirm() игнорируется.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `promptText`, по умолчанию `""`


**Пример:**

```nim
await acceptDialog(tab, promptText = "мой ответ")
echo "диалог подтверждён" # выводит "диалог подтверждён"
```


### `dismissDialog` (Tab)


```nim
proc dismissDialog*(tab: Tab) {.async.}
```


**Что делает.** Отклоняет открытый JS-диалог (Cancel у confirm/prompt; у alert() эквивалентно acceptDialog(), так как у него нет варианта "отмена").


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await dismissDialog(tab)
echo "диалог отклонён" # выводит "диалог отклонён"
```


### `autoDismissDialogs` (Tab)


```nim
proc autoDismissDialogs*(tab: Tab)
```


**Что делает.** Удобный дефолт: все диалоги автоматически отклоняются, чтобы страница не зависала, если явная обработка не нужна.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
autoDismissDialogs(tab)
echo "все дальнейшие диалоги будут закрываться автоматически" # выводит "все дальнейшие диалоги будут закрываться автоматически"
```


---

## JS "аварийный люк" и снимки страницы


### `evalJS` (Tab)


```nim
proc evalJS*(tab: Tab, expression: string): Future[JsonNode] {.async.}
```


**Что делает.** Исполняет произвольный JS-код и возвращает результат в виде JSON — для случаев, не покрытых готовыми командами выше.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `expression` (`string`) — произвольный JS-код, исполняемый в контексте главного документа страницы.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let res = await evalJS(tab, "document.querySelectorAll('a').length")
echo res["result"]["value"] # выводит количество ссылок на странице
```


### `screenshot` (Tab)


```nim
proc screenshot*(tab: Tab, path: string, format = "png", fullPage = false, quality = 100) {.async.}
```


**Что делает.** Сохраняет скриншот текущего состояния вкладки в файл по пути path. format: "png" или "jpeg". fullPage = true снимает всю страницу целиком (включая то, что за пределами текущего вьюпорта), а не только видимую область.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `path` (`string`) — путь к файлу на диске — куда сохранить (скриншот, PDF, текст) или откуда загрузить.
- `format`, по умолчанию `"png"`
- `fullPage`, по умолчанию `false`
- `quality`, по умолчанию `100`


**Пример:**

```nim
await screenshot(tab, "/tmp/page.png", fullPage = true)
echo "скриншот сохранён" # выводит "скриншот сохранён"
```


### `savePDF` (Tab)


```nim
proc savePDF*(tab: Tab, path: string, landscape = false, printBackground = true) {.async.}
```


**Что делает.** Сохраняет текущую страницу в PDF (аналог "печати в PDF" из браузера).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `path` (`string`) — путь к файлу на диске — куда сохранить (скриншот, PDF, текст) или откуда загрузить.
- `landscape`, по умолчанию `false`
- `printBackground`, по умолчанию `true`


**Пример:**

```nim
await savePDF(tab, "/tmp/page.pdf", landscape = false)
echo "PDF сохранён" # выводит "PDF сохранён"
```


### `title` (Tab)


```nim
proc title*(tab: Tab): Future[string] {.async.}
```


**Что делает.** Текущий заголовок страницы (document.title).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let pageTitle = await title(tab)
echo pageTitle # выводит "Example Domain"
```


### `currentUrl` (Tab)


```nim
proc currentUrl*(tab: Tab): Future[string] {.async.}
```


**Что делает.** Текущий URL страницы (location.href) — с учётом редиректов и клиентской навигации (в отличие от того URL, что был передан в последний goto()).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let url = await currentUrl(tab)
echo url # выводит "https://example.com/", с учётом редиректов
```


---

## Инжектируемые скрипты и мост JS -> Nim


### `addScriptTag` (Tab)


```nim
proc addScriptTag*(tab: Tab, url = "", content = "") {.async.}
```


**Что делает.** Добавляет `<script>` на текущую страницу — либо по url (дожидается его загрузки), либо с готовым содержимым content (нужно указать ровно один из двух вариантов). Аналог page.addScriptTag() в Puppeteer.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `url`, по умолчанию `""` — адрес — страницы для перехода, скрипта, ресурса и т.п. в зависимости от функции.
- `content`, по умолчанию `""`


**Исключения:**

- `ChildTearError` — если не указан ровно один из `url`/`content` (ни одного или оба сразу).

**Пример:**

```nim
await addScriptTag(tab, content = "window.__marker = 42;")
echo "скрипт добавлен и выполнен" # выводит "скрипт добавлен и выполнен"
```


### `evaluateOnNewDocument` (Tab)


```nim
proc evaluateOnNewDocument*(tab: Tab, script: string): Future[string] {.async.}
```


**Что делает.** Скрипт будет выполняться перед любым JS самой страницы при каждой следующей загрузке документа (аналог page.evaluateOnNewDocument() в Puppeteer). Возвращает identifier для removeEvaluateOnNewDocument().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `script` (`string`) — JS-код, который будет выполняться перед любым скриптом самой страницы при каждой следующей загрузке документа.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let scriptId = await evaluateOnNewDocument(tab, "window.__injected = true;")
echo len(scriptId) > 0 # выводит true — теперь скрипт выполнится на каждой новой навигации
```


### `removeEvaluateOnNewDocument` (Tab)


```nim
proc removeEvaluateOnNewDocument*(tab: Tab, identifier: string) {.async.}
```


**Что делает.** Отменяет скрипт, добавленный evaluateOnNewDocument(), по identifier, который она вернула — на уже загруженный документ не влияет, только на следующие навигации.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `identifier` (`string`) — идентификатор, возвращённый evaluateOnNewDocument().


**Пример:**

```nim
await removeEvaluateOnNewDocument(tab, scriptId)
echo "автозапуск скрипта отменён" # выводит "автозапуск скрипта отменён"
```


### `exposeFunction` (Tab)


```nim
proc exposeFunction*(tab: Tab, name: string, callback: ExposedCallback) {.async.}
```


**Что делает.** Добавляет функцию `name` в window страницы: код на JS может вызвать её как обычную (асинхронную) функцию, а выполняться она будет здесь, на стороне Nim — аналог page.exposeFunction() в Puppeteer. callback получает массив аргументов вызова в виде JsonNode и должен вернуть JSON-сериализуемый результат. Технически это Runtime.addBinding (низкоуровневый мост, который умеет только "выстрелить и забыть" со стороны страницы) плюс инжектированный JS-шим, оборачивающий его в настоящий Promise, и обработчик события "Runtime.bindingCalled", вызывающий callback и резолвящий соответствующий Promise через Runtime.evaluate.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `name` (`string`) — имя — куки, атрибута, ключа хранилища или JS-функции, в зависимости от контекста функции.
- `callback` (`ExposedCallback`) — функция на стороне Nim, вызываемая при каждом обращении к name из JS страницы; получает аргументы вызова в виде JsonNode и должна вернуть JSON-сериализуемый результат.


**Пример:**

```nim
proc onNimSide(args: seq[JsonNode]): JsonNode =
  echo "вызвано из JS со страницы: ", args # выводит переданные аргументы
  result = %*{"ok": true}
await exposeFunction(tab, "nimCallback", onNimSide)
discard await evalJS(tab, "window.nimCallback('hello')")
```


---

## Навигация: история, остановка загрузки, фокус вкладки


### `goBack` (Tab)


```nim
proc goBack*(tab: Tab): Future[bool] {.async.}
```


**Что делает.** Аналог кнопки "назад" браузера. Возвращает false (и никуда не переходит), если в истории вкладки нет предыдущей записи.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let moved = await goBack(tab)
echo moved # выводит true, если в истории была предыдущая запись
```


### `goForward` (Tab)


```nim
proc goForward*(tab: Tab): Future[bool] {.async.}
```


**Что делает.** Аналог кнопки "вперёд". Возвращает false, если в истории вкладки нет следующей записи (например, назад ещё не переходили).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let moved = await goForward(tab)
echo moved # выводит true, если в истории была следующая запись
```


### `stop` (Tab)


```nim
proc stop*(tab: Tab) {.async.}
```


**Что делает.** Останавливает текущую загрузку страницы (аналог кнопки "стоп" в браузере/Escape во время загрузки).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await stop(tab)
echo "загрузка остановлена" # выводит "загрузка остановлена"
```


### `bringToFront` (Tab)


```nim
proc bringToFront*(tab: Tab) {.async.}
```


**Что делает.** Делает вкладку активной среди остальных вкладок того же браузера.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await bringToFront(tab)
echo "вкладка выведена на передний план" # выводит "вкладка выведена на передний план"
```


### `waitForURL` (Tab)


```nim
proc waitForURL*(tab: Tab, substring: string, timeoutMs = 10_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**Что делает.** Ждёт, пока location.href не станет содержать substring — например, после клика по ссылке, ведущей через несколько промежуточных редиректов, когда одного Page.loadEventFired недостаточно.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `substring` (`string`) — подстрока, которую должен содержать location.href, чтобы ожидание завершилось успехом.
- `timeoutMs`, по умолчанию `10_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.
- `pollIntervalMs`, по умолчанию `100` — как часто (в миллисекундах) перепроверять условие при ожидании — компромисс между отзывчивостью и нагрузкой на CDP-соединение.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
await click(tab, "a.checkout")
let arrived = await waitForURL(tab, "/checkout", timeoutMs = 10_000)
echo arrived # выводит true, если URL стал содержать "/checkout" до истечения таймаута
```


---

## Мышь и клавиатура: расширенные жесты


### `doubleClick` (Tab)


```nim
proc doubleClick*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Двойной клик — как click(), но с двумя нажатиями подряд и правильным clickCount, чтобы страница увидела настоящий dblclick, а не два независимых одиночных клика.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await doubleClick(tab, ".editable-cell")
echo "двойной клик выполнен" # выводит "двойной клик выполнен"
```


### `rightClick` (Tab)


```nim
proc rightClick*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Открывает контекстное меню (эмулирует правый клик мышью). Само системное меню в headless Chromium не рендерится, но страница получает настоящее событие "contextmenu", как от живого клика.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await rightClick(tab, "#file-item")
echo "правый клик выполнен" # выводит "правый клик выполнен" — откроется контекстное меню страницы, если оно есть
```


### `clickAt` (Tab)


```nim
proc clickAt*(tab: Tab, x, y: float) {.async.}
```


**Что делает.** Клик по абсолютным координатам вьюпорта в обход поиска по CSS-селектору — например, когда важна конкретная точка внутри элемента (canvas, карта, кастомный слайдер), а не он целиком.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `x` (`float`) — координата по горизонтали в системе координат страницы (CSS-пиксели от левого края вьюпорта).
- `y` (`float`) — координата по вертикали в системе координат страницы (CSS-пиксели от верхнего края вьюпорта).


**Пример:**

```nim
await clickAt(tab, 400.0, 300.0)
echo "клик по координатам (400, 300)" # выводит "клик по координатам (400, 300)"
```


### `scrollBy` (Tab)


```nim
proc scrollBy*(tab: Tab, deltaX, deltaY: float) {.async.}
```


**Что делает.** Прокручивает страницу колесом мыши (положительный deltaY — вниз).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `deltaX` (`float`) — горизонтальное смещение прокрутки в пикселях.
- `deltaY` (`float`) — вертикальное смещение прокрутки в пикселях (положительное значение — вниз).


**Пример:**

```nim
await scrollBy(tab, 0.0, 600.0)
echo "страница прокручена на 600px вниз" # выводит "страница прокручена на 600px вниз"
```


### `scrollIntoView` (Tab)


```nim
proc scrollIntoView*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Прокручивает страницу так, чтобы элемент оказался в видимой области, — без клика/наведения (click()/hover() делают это сами).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await scrollIntoView(tab, "#footer")
echo "футер в зоне видимости" # выводит "футер в зоне видимости"
```


### `dragAndDrop` (Tab)


```nim
proc dragAndDrop*(tab: Tab, sourceSelector, targetSelector: string, native = false) {.async.}
```


**Что делает.** Перетаскивает sourceSelector на targetSelector. native = false (по умолчанию) — "честная мышь": наведение и нажатие кнопки на источнике, перемещение к цели, отпускание, через Input.dispatchMouseEvent. Работает для всего, что реагирует на обычные mouse-события (сортируемые списки на JS вроде Sortable.js, кастомные слайдеры), но НЕ гарантирует срабатывание нативного HTML5 drag-and-drop (dragstart/dragover/drop) — часть сайтов ждёт именно эти события, которые мышиные Input.dispatchMouseEvent не генерируют в принципе (так устроен сам браузер: HTML5 DnD — это отдельный механизм, не следствие обычных mouse-событий). native = true — вместо мыши напрямую диспатчит на source/target последовательность настоящих DragEvent (dragstart, dragenter, dragover, drop, dragend) с общим объектом DataTransfer, как это делает браузер при реальном HTML5-перетаскивании. Нужен для элементов с draggable="true" и обработчиками ondrop/ondragover — того, что мышиный режим не триггерит. Ограничение: реальные файлы (перетаскивание файла из ОС в input) этим способом не подделать — DataTransfer.files доступен только для чтения из настоящего системного Drag'n'Drop, для загрузки файлов используйте uploadFile().


**Разбор реализации.** При `native = false` — "честная мышь": `Input.dispatchMouseEvent` с наведением, нажатием, перемещением и отпусканием — работает для сортируемых списков и слайдеров на обычных mouse-событиях, но НЕ гарантирует срабатывание нативного HTML5 drag-and-drop, потому что браузер генерирует `dragstart`/`dragover`/`drop` отдельно от обычных событий мыши, а не как их следствие. При `native = true` вместо мыши на источник и цель напрямую диспатчится настоящая последовательность `DragEvent` с общим объектом `DataTransfer` — так, как это делает сам браузер при перетаскивании — что и требуется элементам с `draggable="true"` и обработчиками `ondrop`/`ondragover`.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `sourceSelector` (`string`) — CSS-селектор перетаскиваемого элемента (источник).
- `targetSelector` (`string`) — CSS-селектор элемента, на который выполняется перетаскивание (цель).
- `native`, по умолчанию `false` — true — настоящие события HTML5 drag-and-drop (dragstart/dragover/drop); false (по умолчанию) — эмуляция мышью.


**Исключения:**

- `ChildTearError` — если источник или цель не найдены по своим селекторам; при `native = true` — отдельное сообщение, если синтетическое HTML5 drag-and-drop событие не сработало.

**Пример:**

```nim
# native = true — настоящие dragstart/dragover/drop, а не эмуляция мышью
await dragAndDrop(tab, "#drag-item", "#drop-zone", native = true)
echo "перетаскивание выполнено" # выводит "перетаскивание выполнено"
```


### `dragBy` (Tab, Frame)


```nim
proc dragBy*(tab: Tab, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.}
proc dragBy*(frame: Frame, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.}
```


**Что делает.** Зажимает левую кнопку мыши на центре элемента `selector`, ведёт курсор на `(dx, dy)` пикселей (`dx > 0` — вправо, `dy > 0` — вниз) и отпускает кнопку. Предназначена для слайдеров без элемента-цели (`input[type=range]`, noUiSlider, «проведите для подтверждения»). Ввод настоящий (`isTrusted = true`), траектория сглажена (smoothstep), в каждом `mouseMoved` передаётся `buttons = 1`. Версия для `Frame` работает с элементом внутри `<iframe>`.

**Параметры:** `steps` — число промежуточных перемещений; `stepDelayMs` — пауза между ними, мс; `holdMs` — пауза после нажатия до начала движения, мс.

**Пример:**

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


**Что делает.** Тащит ручку `handleSelector` до правого края дорожки `trackSelector`; расстояние вычисляется из геометрии обоих элементов (`boundingBox()`), а не задаётся числом.

**Пример:**

```nim
await dragToEnd(tab, ".slider-handle", ".slider-track")
```


### `pressKey` (Tab)


```nim
proc pressKey*(tab: Tab, key: string, modifiers = 0) {.async.}
```


**Что делает.** Нажатие и отпускание одной именованной клавиши (например "Tab", "Escape", "ArrowDown") в текущем сфокусированном элементе.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — имя клавиши по номенклатуре CDP, например "Tab", "Escape", "ArrowDown" (обычно совпадает с KeyboardEvent.key в браузере).
- `modifiers`, по умолчанию `0`


**Пример:**

```nim
await pressKey(tab, "Escape")
echo "клавиша Escape нажата" # выводит "клавиша Escape нажата"
```


### `pressKeyCombo` (Tab)


```nim
proc pressKeyCombo*(tab: Tab, keys: seq[string]) {.async.}
```


**Что делает.** Нажимает сочетание клавиш, например @["Control", "a"] для Ctrl+A. Все клавиши, кроме последней, считаются модификаторами (Control/ Alt/Shift/Meta) и удерживаются, пока не нажата и не отпущена последняя (основная) клавиша, — так реальная клавиатура и посылает сочетания.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `keys` (`seq[string]`) — клавиши сочетания по порядку, например @["Control", "a"]; все клавиши, кроме последней, считаются модификаторами и удерживаются до нажатия и отпускания последней (основной) клавиши. Именно `seq`, а не `openArray`: openArray-параметр нельзя захватить в замыкание async-процедуры Nim (компилятор отказывает после первого await в теле — "cannot be captured as it would violate memory safety").


**Пример:**

```nim
await pressKeyCombo(tab, @["Control", "a"])
echo "нажата комбинация Ctrl+A" # выводит "нажата комбинация Ctrl+A"
```


### `selectAllText` (Tab)


```nim
proc selectAllText*(tab: Tab, selector = "") {.async.}
```


**Что делает.** Выделяет весь текст (Ctrl+A) — либо в текущем сфокусированном элементе, либо (если передан selector) предварительно кликая на него.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector`, по умолчанию `""` — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Пример:**

```nim
await selectAllText(tab, "#editor")
echo "весь текст поля выделен" # выводит "весь текст поля выделен"
```


### `clearValue` (Tab)


```nim
proc clearValue*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Очищает значение поля ввода напрямую (el.value = ''), с событиями input/change, — надёжнее, чем select-all + Backspace, для полей с произвольной длиной текста.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент для очистки не найден по `selector`.

**Пример:**

```nim
await clearValue(tab, "#search")
echo await getValue(tab, "#search") # выводит "" (поле очищено)
```


---

## Формы: чекбоксы, значения, состояние полей


### `setChecked` (Tab)


```nim
proc setChecked*(tab: Tab, selector: string, checked: bool) {.async.}
```


**Что делает.** Устанавливает состояние чекбокса/радиокнопки напрямую и генерирует событие "change", как это делает браузер при реальном клике.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `checked` (`bool`) — true — отметить чекбокс/радиокнопку, false — снять отметку.


**Исключения:**

- `ChildTearError` — если чекбокс/радиокнопка не найдены по `selector`.

**Пример:**

```nim
await setChecked(tab, "#agree", true)
echo await isChecked(tab, "#agree") # выводит true
```


### `check` (Tab)


```nim
proc check*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Отмечает чекбокс/радиокнопку (setChecked(tab, selector, true)).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Пример:**

```nim
await check(tab, "#subscribe")
echo await isChecked(tab, "#subscribe") # выводит true
```


### `uncheck` (Tab)


```nim
proc uncheck*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Снимает отметку с чекбокса (setChecked(tab, selector, false)); для радиокнопки обычно бессмысленно — радиокнопки снимаются выбором другой радиокнопки в той же группе, а не программным сбросом.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Пример:**

```nim
await uncheck(tab, "#subscribe")
echo await isChecked(tab, "#subscribe") # выводит false
```


### `getValue` (Tab)


```nim
proc getValue*(tab: Tab, selector: string): Future[string] {.async.}
```


**Что делает.** Значение поля ввода/textarea/select (el.value).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[string]`


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
let val = await getValue(tab, "#username")
echo val # выводит текущее значение поля, например "andy"
```


### `isChecked` (Tab)


```nim
proc isChecked*(tab: Tab, selector: string): Future[bool] {.async.}
```


**Что делает.** Отмечен ли чекбокс/радиокнопка (el.checked). Возвращает false, если элемент не найден (см. isVisible() насчёт этого же выбора "не найден = false" вместо исключения).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let checked = await isChecked(tab, "#agree")
echo checked # выводит true/false
```


### `isDisabled` (Tab)


```nim
proc isDisabled*(tab: Tab, selector: string): Future[bool] {.async.}
```


**Что делает.** Отключён ли элемент формы (el.disabled) — недоступен для ввода и не отправляется вместе с формой. Возвращает false, если элемент не найден.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let disabled = await isDisabled(tab, "button[type=submit]")
echo disabled # выводит true, если кнопка недоступна для нажатия
```


### `isVisible` (Tab)


```nim
proc isVisible*(tab: Tab, selector: string): Future[bool] {.async.}
```


**Что делает.** "Видимость" в бытовом смысле: элемент существует, имеет ненулевые размеры и не скрыт через display:none/visibility:hidden. НЕ проверяет перекрытие другими элементами поверх него.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let visible = await isVisible(tab, "#modal")
echo visible # выводит true/false
```


### `focus` (Tab)


```nim
proc focus*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Программно фокусирует элемент (el.focus() через домен DOM — см. domApi.focus()); элемент должен быть фокусируемым.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await focus(tab, "#search")
echo "поле сфокусировано" # выводит "поле сфокусировано"
```


### `blur` (Tab)


```nim
proc blur*(tab: Tab, selector: string) {.async.}
```


**Что делает.** Снимает фокус с элемента (el.blur()) — например, чтобы спровоцировать событие "blur"/валидацию поля, не переводя фокус на что-то конкретное другое.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
await blur(tab, "#search")
echo "фокус снят" # выводит "фокус снят"
```


---

## Чтение состояния и содержимого элементов


### `boundingBox` (Tab)


```nim
proc boundingBox*(tab: Tab, selector: string): Future[tuple[x, y, width, height: float]] {.async.}
```


**Что делает.** Координаты и размеры элемента на странице (viewport-относительные, после прокрутки его в видимую область) — например, чтобы вручную навести курсор в произвольную точку внутри элемента, а не только в его центр (см. nodeCenter()/click()/hover()), или посчитать clip для screenshotElement().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `float]]`


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
let box = await boundingBox(tab, "#header")
echo box.width # выводит ширину элемента в CSS-пикселях
```


### `innerHTML` (Tab)


```nim
proc innerHTML*(tab: Tab, selector: string): Future[string] {.async.}
```


**Что делает.** HTML-разметка ВНУТРИ элемента, без самого элемента (Element.innerHTML) — в отличие от outerHTML() ниже.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[string]`


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
let html = await innerHTML(tab, "#card")
echo html # выводит HTML-разметку внутри элемента, например "<h2>Заголовок</h2><p>Текст</p>"
```


### `outerHTML` (Tab)


```nim
proc outerHTML*(tab: Tab, selector: string): Future[string] {.async.}
```


**Что делает.** В отличие от innerHTML() (через JS), получен через домен DOM (DOM.getOuterHTML) — оба подхода равноценны по результату, здесь просто показан альтернативный путь, уже не завязанный на eval.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[string]`


**Исключения:**

- `ChildTearError` — если элемент не найден по `selector`.

**Пример:**

```nim
let html = await outerHTML(tab, "#card")
echo html # выводит "<div id=\"card\">...</div>" вместе с самим элементом
```


### `getLinks` (Tab)


```nim
proc getLinks*(tab: Tab): Future[seq[tuple[text, href: string]]] {.async.}
```


**Что делает.** Все ссылки на странице: видимый текст и значение href как есть (относительные пути не разрешаются в абсолютные — используйте getAttribute()/absoluteUrl-подобную логику на своей стороне, если это важно).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `string]]]`


**Пример:**

```nim
let links = await getLinks(tab)
echo len(links) # выводит количество ссылок на странице
```


### `getAllAttributes` (Tab)


```nim
proc getAllAttributes*(tab: Tab, selector, name: string): Future[seq[string]] {.async.}
```


**Что делает.** Значение атрибута name у ВСЕХ элементов, подходящих под селектор (аналог getAllText(), но для атрибута, а не текста); отсутствующий атрибут даёт пустую строку на соответствующей позиции.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `name` (`string`) — имя — куки, атрибута, ключа хранилища или JS-функции, в зависимости от контекста функции.


**Возвращает:** `Future[seq[string]]`


**Пример:**

```nim
let ids = await getAllAttributes(tab, "li.item", "data-id")
echo ids # выводит @["101", "102", "103"]
```


### `getViewportSize` (Tab)


```nim
proc getViewportSize*(tab: Tab): Future[tuple[width, height: int]] {.async.}
```


**Что делает.** Текущий размер видимой области страницы (window.innerWidth/Height) — реальный, с учётом того, что подделал setViewport(), если он вызывался.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `int]]`


**Пример:**

```nim
let size = await getViewportSize(tab)
echo size.width # выводит текущую ширину видимой области, например 1280
```


---

## Дополнительные ожидания


### `waitForSelectorGone` (Tab)


```nim
proc waitForSelectorGone*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**Что делает.** Противоположность waitForSelector() — ждёт, пока элемент исчезнет со страницы (например, спиннер загрузки или закрывшийся модал).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `timeoutMs`, по умолчанию `5_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.
- `pollIntervalMs`, по умолчанию `100` — как часто (в миллисекундах) перепроверять условие при ожидании — компромисс между отзывчивостью и нагрузкой на CDP-соединение.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let gone = await waitForSelectorGone(tab, ".spinner", timeoutMs = 5_000)
echo gone # выводит true, если спиннер исчез до истечения таймаута
```


### `waitForText` (Tab)


```nim
proc waitForText*(tab: Tab, selector, text: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**Что делает.** Ждёт, пока видимый текст элемента не будет содержать text (например, счётчик корзины сменится с "0" на "1" после клика).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `text` (`string`) — подстрока, которую должен содержать видимый текст элемента, чтобы ожидание завершилось успехом.
- `timeoutMs`, по умолчанию `5_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.
- `pollIntervalMs`, по умолчанию `100` — как часто (в миллисекундах) перепроверять условие при ожидании — компромисс между отзывчивостью и нагрузкой на CDP-соединение.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let appeared = await waitForText(tab, "#status", "Готово", timeoutMs = 5_000)
echo appeared # выводит true, если текст элемента стал содержать "Готово"
```


### `waitForStableText` (Tab)


```nim
proc waitForStableText*(tab: Tab, selector: string, pollMs = 500, stableForMs = 2_000, timeoutMs = 30_000): Future[string] {.async.}
```


**Что делает.** Ждёт, пока текст элемента (см. `getLastText()` — берётся ПОСЛЕДНИЙ подходящий под `selector` узел) перестанет меняться на протяжении `stableForMs` подряд, и возвращает финальный текст. Типичный случай применения — потоково дописывающийся ответ чат-бота или другого стримингового интерфейса, где нет отдельного надёжного события "готово", кроме самого факта, что текст перестал расти. Пустой текст (после `strip()`) не считается стабильным — ожидание продолжается, пока не появится непустой контент. Если к моменту истечения `timeoutMs` текст так и не стабилизировался, но при этом уже непустой — возвращает то, что успело накопиться, вместо того чтобы выбросить исключение на пустом месте; исключение бросается, только если за всё время ожидания текст ни разу не появился.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `pollMs`, по умолчанию `500` — как часто (в миллисекундах) перечитывать текст при ожидании.
- `stableForMs`, по умолчанию `2_000` — сколько миллисекунд подряд текст должен оставаться неизменным, чтобы считаться стабильным.
- `timeoutMs`, по умолчанию `30_000` — сколько миллисекунд суммарно ждать, прежде чем сдаться (или вернуть уже накопленный непустой текст).


**Возвращает:** `Future[string]` — финальный (стабилизировавшийся, либо накопленный к моменту таймаута) текст.


**Исключения:**

- `ChildTearError` — если непустой текст по `selector` так и не появился за `timeoutMs`.


**Пример:**

```nim
await click(tab, "#send-button")
let reply = await waitForStableText(tab, ".assistant-message:last-child")
echo reply # выводит полный текст ответа чат-бота, когда он перестал дописываться
```


### `waitUntilTrue`


```nim
proc waitUntilTrue*(cond: proc(): Future[bool] {.async.}, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.}
```


**Что делает.** Опрашивает произвольное асинхронное условие `cond` с интервалом `pollIntervalMs`, пока оно не вернёт `true`, либо не истечёт `timeoutMs`. Обобщение одного и того же цикла ожидания, на котором построены `waitForSelector()`/`waitForURL()`/`waitForSelectorGone()`/`waitForText()` выше (сами они реализованы через этот примитив) — в отличие от них, `cond` не привязано к конкретному `Tab`/селектору и может проверять что угодно, поэтому пригодно и для прикладного кода поверх childtear (сценарии `askQwen()`/`askKimi()` из `siteworkers/qwen.nim`/`siteworkers/kimi.nim` построены на нём же). Возвращает `true`, если `cond` стало истинным до истечения `timeoutMs`, иначе `false` — таймаут сам по себе не считается ошибкой; поднимать исключение при необходимости остаётся на усмотрение вызывающего кода (как это делает, например, `waitForFunction()`).


**Параметры:**

- `cond` (`proc(): Future[bool] {.async.}`) — произвольное асинхронное условие без аргументов; как правило, замыкание, захватывающее `tab` и остальной контекст.
- `timeoutMs`, по умолчанию `5_000` — сколько миллисекунд ждать перед тем, как вернуть `false`.
- `pollIntervalMs`, по умолчанию `100` — как часто (в миллисекундах) перепроверять условие при ожидании.


**Возвращает:** `Future[bool]`


**Пример:**

```nim
proc noSpinner(): Future[bool] {.async.} = result = not (await exists(tab, ".spinner"))
let ready = await waitUntilTrue(noSpinner, timeoutMs = 5_000, pollIntervalMs = 200)
echo ready # выводит true, если спиннер исчез до истечения таймаута
```


### `waitUntilCleared` (Tab)


```nim
proc waitUntilCleared*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 250, byValue = false): Future[bool] {.async.}
```


**Что делает.** Ждёт, пока текст элемента `selector` (см. `getText()`), либо, при `byValue = true`, значение поля ввода (см. `getValue()`) не станет пустым после `strip()` — типичный признак того, что поле формы очистилось само после отправки (текстовые чат-интерфейсы обычно очищают поле ввода сразу после отправки промпта/сообщения). Как и `waitUntilTrue()`, на котором построена, не поднимает исключение по таймауту — возвращает `false`; исчезновение самого элемента `selector` из DOM в процессе ожидания приводит к `ChildTearError` от `getText()`/`getValue()`, как и при их прямом вызове.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор поля ввода или другого элемента, чьё содержимое должно опустеть.
- `timeoutMs`, по умолчанию `5_000` — сколько миллисекунд ждать перед тем, как вернуть `false`.
- `pollIntervalMs`, по умолчанию `250` — как часто (в миллисекундах) перепроверять условие при ожидании.
- `byValue`, по умолчанию `false` — читать значение через `getValue()` (для `<input>`/`<textarea>`) вместо `getText()` (для `contenteditable`-элементов и прочего видимого текста).


**Возвращает:** `Future[bool]`


**Пример:**

```nim
await pressEnter(tab, "#prompt")
let cleared = await waitUntilCleared(tab, "#prompt", timeoutMs = 5_000, byValue = true)
echo cleared # выводит true, если поле ввода очистилось после отправки
```


---

## localStorage и sessionStorage


### `localStorageGet` (Tab)


```nim
proc localStorageGet*(tab: Tab, key: string): Future[string] {.async.}
```


**Что делает.** Значение ключа key в window.localStorage текущей страницы — хранилище, привязанное к origin'у и переживающее закрытие вкладки. Возвращает "" и для отсутствующего ключа, и для ключа со значением "" (localStorage хранит только строки, отличить эти случаи можно через evalJS("localStorage.getItem(...) === null")).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — ключ в localStorage/sessionStorage.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let val = await localStorageGet(tab, "theme")
echo val # выводит сохранённое значение, например "dark", или "" если ключа нет
```


### `localStorageSet` (Tab)


```nim
proc localStorageSet*(tab: Tab, key, value: string) {.async.}
```


**Что делает.** Записывает пару key/value в window.localStorage (создаёт ключ или перезаписывает существующий).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — ключ в localStorage/sessionStorage.
- `value` (`string`) — значение, которое нужно установить — куки, ключа хранилища и т.п.


**Пример:**

```nim
await localStorageSet(tab, "theme", "dark")
echo await localStorageGet(tab, "theme") # выводит "dark"
```


### `localStorageRemove` (Tab)


```nim
proc localStorageRemove*(tab: Tab, key: string) {.async.}
```


**Что делает.** Удаляет один ключ из window.localStorage; не ошибается, если ключа и так не было.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — ключ в localStorage/sessionStorage.


**Пример:**

```nim
await localStorageRemove(tab, "theme")
echo await localStorageGet(tab, "theme") # выводит ""
```


### `localStorageClear` (Tab)


```nim
proc localStorageClear*(tab: Tab) {.async.}
```


**Что делает.** Полностью очищает window.localStorage текущего origin'а.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await localStorageClear(tab)
echo "localStorage очищен" # выводит "localStorage очищен"
```


### `sessionStorageGet` (Tab)


```nim
proc sessionStorageGet*(tab: Tab, key: string): Future[string] {.async.}
```


**Что делает.** Как localStorageGet(), но для window.sessionStorage — хранилища, привязанного не только к origin'у, но и к конкретной вкладке (закрывается вместе с ней, в отличие от localStorage).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — ключ в localStorage/sessionStorage.


**Возвращает:** `Future[string]`


**Пример:**

```nim
let val = await sessionStorageGet(tab, "draftId")
echo val # выводит сохранённое значение или "" если ключа нет
```


### `sessionStorageSet` (Tab)


```nim
proc sessionStorageSet*(tab: Tab, key, value: string) {.async.}
```


**Что делает.** Как localStorageSet(), но для window.sessionStorage.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — ключ в localStorage/sessionStorage.
- `value` (`string`) — значение, которое нужно установить — куки, ключа хранилища и т.п.


**Пример:**

```nim
await sessionStorageSet(tab, "draftId", "42")
echo await sessionStorageGet(tab, "draftId") # выводит "42"
```


### `sessionStorageRemove` (Tab)


```nim
proc sessionStorageRemove*(tab: Tab, key: string) {.async.}
```


**Что делает.** Как localStorageRemove(), но для window.sessionStorage.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `key` (`string`) — ключ в localStorage/sessionStorage.


**Пример:**

```nim
await sessionStorageRemove(tab, "draftId")
echo await sessionStorageGet(tab, "draftId") # выводит ""
```


### `sessionStorageClear` (Tab)


```nim
proc sessionStorageClear*(tab: Tab) {.async.}
```


**Что делает.** Как localStorageClear(), но для window.sessionStorage.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await sessionStorageClear(tab)
echo "sessionStorage очищен" # выводит "sessionStorage очищен"
```


---

## Эмуляция окружения


### `setGeolocation` (Tab)


```nim
proc setGeolocation*(tab: Tab, latitude, longitude: float, accuracy = 1.0) {.async.}
```


**Что делает.** Подделывает координаты navigator.geolocation — страница получает их как настоящий ответ геолокации, без системного диалога разрешения.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `latitude` (`float`) — широта в градусах.
- `longitude` (`float`) — долгота в градусах.
- `accuracy`, по умолчанию `1.0`


**Пример:**

```nim
await setGeolocation(tab, 55.7558, 37.6173, accuracy = 10.0)
echo "координаты подменены на Москву" # выводит "координаты подменены на Москву"
```


### `clearGeolocation` (Tab)


```nim
proc clearGeolocation*(tab: Tab) {.async.}
```


**Что делает.** Сбрасывает override, сделанный setGeolocation().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await clearGeolocation(tab)
echo "override геолокации снят" # выводит "override геолокации снят"
```


### `setTimezone` (Tab)


```nim
proc setTimezone*(tab: Tab, timezoneId: string) {.async.}
```


**Что делает.** timezoneId — имя IANA, например "Europe/Amsterdam".


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `timezoneId` (`string`) — имя часового пояса IANA, например "Europe/Amsterdam".


**Пример:**

```nim
await setTimezone(tab, "Europe/Amsterdam")
echo "часовой пояс подменён" # выводит "часовой пояс подменён"
```


### `setLocale` (Tab)


```nim
proc setLocale*(tab: Tab, locale = "") {.async.}
```


**Что делает.** Пустая строка сбрасывает override на системную локаль.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `locale`, по умолчанию `""`


**Пример:**

```nim
await setLocale(tab, "nl-NL")
echo "локаль подменена" # выводит "локаль подменена"
```


### `emulateMedia` (Tab)


```nim
proc emulateMedia*(tab: Tab, media = "", features: seq[(string, string)] = @[]) {.async.}
```


**Что делает.** media: "screen"/"print"/"" (сбросить). features — пары вида ("prefers-color-scheme", "dark"): @[("prefers-color-scheme", "dark")].


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `media`, по умолчанию `""`
- `features` (`seq[(string, string)]`), по умолчанию `@[]`


**Пример:**

```nim
await emulateMedia(tab, media = "print")
echo "эмуляция медиа-типа print включена" # выводит "эмуляция медиа-типа print включена"
```


### `setCPUThrottle` (Tab)


```nim
proc setCPUThrottle*(tab: Tab, rate: float) {.async.}
```


**Что делает.** rate = 1 — без замедления, rate = 4 — CPU "в 4 раза медленнее".


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `rate` (`float`) — коэффициент замедления CPU: 1 — без изменений, 4 — в 4 раза медленнее.


**Пример:**

```nim
await setCPUThrottle(tab, 4.0)
echo "CPU замедлен в 4 раза" # выводит "CPU замедлен в 4 раза"
```


### `setBackgroundColor` (Tab)


```nim
proc setBackgroundColor*(tab: Tab, r, g, b: int, a = 1.0) {.async.}
```


**Что делает.** Полезно перед screenshot(): например, a = 0 для прозрачного фона.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `r` (`int`) — компонента red фона, 0–255.
- `g` (`int`) — компонента green фона, 0–255.
- `b` (`int`) — компонента blue фона, 0–255.
- `a`, по умолчанию `1.0`


**Пример:**

```nim
await setBackgroundColor(tab, 0, 0, 0, a = 0.0)
echo "фон страницы стал прозрачным" # выводит "фон страницы стал прозрачным"
```


### `clearBackgroundColor` (Tab)


```nim
proc clearBackgroundColor*(tab: Tab) {.async.}
```


**Что делает.** Сбрасывает override, сделанный setBackgroundColor() (выше по файлу).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await clearBackgroundColor(tab)
echo "override фона снят" # выводит "override фона снят"
```


### `enableTouchEmulation` (Tab)


```nim
proc enableTouchEmulation*(tab: Tab, enabled = true, maxTouchPoints = 1) {.async.}
```


**Что делает.** Подделывает признаки поддержки сенсорного ввода (navigator.maxTouchPoints, 'ontouchstart' in window) — сами тач-события эмулируются отдельно, через touchTap()/touchSwipe() (см. ниже), использующие Input.dispatchTouchEvent напрямую.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, по умолчанию `true`
- `maxTouchPoints`, по умолчанию `1`


**Пример:**

```nim
await enableTouchEmulation(tab, true, maxTouchPoints = 5)
echo "признаки touch-устройства включены" # выводит "признаки touch-устройства включены"
```


### `setJavaScriptEnabled` (Tab)


```nim
proc setJavaScriptEnabled*(tab: Tab, enabled: bool) {.async.}
```


**Что делает.** Полностью включает/выключает выполнение JS на странице — удобно, чтобы проверить, как выглядит и работает страница без скриптов (progressive enhancement, доступность разметки без JS).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `enabled` (`bool`) — false — полностью отключить выполнение JS на странице; true — включить обратно.


**Пример:**

```nim
await setJavaScriptEnabled(tab, false)
echo "выполнение JS отключено" # выводит "выполнение JS отключено"
```


### `setBypassCSP` (Tab)


```nim
proc setBypassCSP*(tab: Tab, enabled = true) {.async.}
```


**Что делает.** Отключает Content-Security-Policy страницы (нужно, например, чтобы addScriptTag() мог инжектить произвольные скрипты на сайтах со строгим CSP).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, по умолчанию `true`


**Пример:**

```nim
await setBypassCSP(tab, true)
echo "Content-Security-Policy обходится" # выводит "Content-Security-Policy обходится"
```


### `setCacheEnabled` (Tab)


```nim
proc setCacheEnabled*(tab: Tab, enabled = true) {.async.}
```


**Что делает.** enabled = false — Chromium игнорирует HTTP-кэш для запросов этой вкладки (аналог DevTools -> Network -> "Disable cache"); полезно перед reload(ignoreCache = false), чтобы гарантированно получить свежие ответы сети.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, по умолчанию `true`


**Пример:**

```nim
await setCacheEnabled(tab, false)
echo "HTTP-кэш отключён для вкладки" # выводит "HTTP-кэш отключён для вкладки"
```


### `clearBrowserCache` (Tab)


```nim
proc clearBrowserCache*(tab: Tab) {.async.}
```


**Что делает.** ВНИМАНИЕ: как и clearCookies(), чистит HTTP-дисковый кэш всего браузера целиком, а не только текущей вкладки — сам CDP не даёт способа ограничить именно эту команду одним origin'ом, это ограничение протокола, а не недоработка childtear.nim. Если нужна по-настоящему изолированная очистка (пусть и не HTTP-кэша, а Cache Storage — кэша service worker'ов), см. clearCacheForOrigin().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await clearBrowserCache(tab)
echo "HTTP-кэш браузера очищен целиком" # выводит "HTTP-кэш браузера очищен целиком"
```


### `clearCacheForOrigin` (Tab)


```nim
proc clearCacheForOrigin*(tab: Tab, storageTypes = storageApi.AllStorageTypes) {.async.}
```


**Что делает.** В отличие от clearBrowserCache() (браузер целиком — ограничение самого протокола, см. её описание выше), по-настоящему очищает данные ТОЛЬКО текущего origin'а вкладки через Storage.clearDataForOrigin: по умолчанию — localStorage/sessionStorage/IndexedDB/Cache Storage/ service worker'ы и т.д. (см. storageApi.AllStorageTypes), при желании можно передать более узкий список storageTypes (например, "cache_storage" — только Cache API). ВАЖНО: "cache_storage" здесь — это Cache API service worker'ов, а не HTTP-дисковый кэш, который per-origin очистить нельзя (см. clearBrowserCache()).


**Разбор реализации.** В отличие от `clearBrowserCache()` (браузер целиком — ограничение самого протокола CDP, отдельной команды для одного origin'а для HTTP-кэша не существует), эта функция по-настоящему очищает данные ТОЛЬКО текущего origin'а через `Storage.clearDataForOrigin` — по умолчанию localStorage/sessionStorage/IndexedDB/Cache Storage/service worker'ы и т.д.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `storageTypes`, по умолчанию `storageApi.AllStorageTypes`


**Пример:**

```nim
await clearCacheForOrigin(tab)
echo "данные текущего сайта очищены" # выводит "данные текущего сайта очищены" — Cache Storage, localStorage и т.п.
```


### `setOffline` (Tab)


```nim
proc setOffline*(tab: Tab, offline = true) {.async.}
```


**Что делает.** offline = true имитирует полное отсутствие сети (аналог DevTools -> Network -> "Offline") — все запросы страницы начинают проваливаться, как при реальном обрыве соединения.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `offline`, по умолчанию `true`


**Пример:**

```nim
await setOffline(tab, true)
echo "сеть отключена" # выводит "сеть отключена" — все запросы вкладки начнут проваливаться
```


### `throttleNetwork` (Tab)


```nim
proc throttleNetwork*(tab: Tab, latencyMs: float, downloadThroughput = -1.0, uploadThroughput = -1.0) {.async.}
```


**Что делает.** throughput — байт/сек, -1 — без ограничения.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `latencyMs` (`float`) — искусственная задержка каждого запроса в миллисекундах.
- `downloadThroughput`, по умолчанию `-1.0`
- `uploadThroughput`, по умолчанию `-1.0`


**Пример:**

```nim
await throttleNetwork(tab, latencyMs = 300.0, downloadThroughput = 50_000.0)
echo "эмуляция медленной сети включена" # выводит "эмуляция медленной сети включена"
```


---

## Разрешения и окно браузера


### `grantPermissions` (Browser)


```nim
proc grantPermissions*(browser: Browser, permissions: seq[string], origin = "", browserContextId = "") {.async.}
```


**Что делает.** permissions — например @["geolocation", "notifications"]. Без browserContextId действует на разрешения браузера в целом, а не одного изолированного профиля.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `permissions` (`seq[string]`) — имена разрешений, например @["geolocation", "notifications"].
- `origin`, по умолчанию `""`
- `browserContextId`, по умолчанию `""`


**Пример:**

```nim
await grantPermissions(browser, @["geolocation", "notifications"], origin = "https://example.com")
echo "разрешения выданы" # выводит "разрешения выданы"
```


### `resetPermissions` (Browser)


```nim
proc resetPermissions*(browser: Browser, browserContextId = "") {.async.}
```


**Что делает.** Сбрасывает все разрешения, выданные через grantPermissions(), для указанного изолированного профиля (или основного, если не указан) назад к дефолтному поведению браузера.


**Параметры:**

- `browser` (`Browser`) — соединение с браузером (`Browser`), полученное через `newBrowser()`.
- `browserContextId`, по умолчанию `""`


**Пример:**

```nim
await resetPermissions(browser)
echo "разрешения сброшены" # выводит "разрешения сброшены"
```


### `setWindowSize` (Tab)


```nim
proc setWindowSize*(tab: Tab, width, height: int) {.async.}
```


**Что делает.** Меняет размер окна браузера, которому принадлежит вкладка (Browser.setWindowBounds) — в отличие от setViewport(), это размер самого окна, а не подделываемого вьюпорта страницы; в headless-режиме эффект зависит от версии Chromium. Использует browser-level сессию, кешируемую на самой вкладке (см. tabBrowserSession()) — при повторных вызовах для одной и той же вкладки новое соединение не открывается.


**Разбор реализации.** Команды изменения окна относятся к домену `Browser`, а не `Page`, и требуют browser-level CDP-сессии, а не обычной сессии вкладки. У `Tab` нет постоянной ссылки на `Browser`, поэтому такая сессия создаётся лениво при первом обращении и кешируется на самой `Tab` (закрывается вместе с ней в `close()`) — вместо того чтобы открывать новое browser-level соединение на каждый вызов `setWindowSize()`/`maximizeWindow()`.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `width` (`int`) — ширина окна браузера в пикселях.
- `height` (`int`) — высота окна браузера в пикселях.


**Пример:**

```nim
await setWindowSize(tab, 1280, 800)
echo "окно браузера изменено до 1280x800" # выводит "окно браузера изменено до 1280x800"
```


### `maximizeWindow` (Tab)


```nim
proc maximizeWindow*(tab: Tab) {.async.}
```


**Что делает.** Разворачивает окно браузера, которому принадлежит вкладка, на весь экран (Browser.setWindowBounds с windowState = "maximized") — как и setWindowSize(), переиспользует кешируемую browser-level сессию вкладки вместо того, чтобы открывать новую при каждом вызове.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Пример:**

```nim
await maximizeWindow(tab)
echo "окно развёрнуто на весь экран" # выводит "окно развёрнуто на весь экран"
```


---

## Загрузка файлов


### `setDownloadPath` (Tab)


```nim
proc setDownloadPath*(tab: Tab, path: string) {.async.}
```


**Что делает.** Разрешает скачивание файлов и сохраняет их в каталог path (должен существовать заранее) — без этого Chromium в headless-режиме молча блокирует любые скачивания.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `path` (`string`) — путь к файлу на диске — куда сохранить (скриншот, PDF, текст) или откуда загрузить.


**Пример:**

```nim
await setDownloadPath(tab, "/tmp/downloads")
echo "скачивания будут сохраняться в /tmp/downloads" # выводит "скачивания будут сохраняться в /tmp/downloads"
```


### `interceptFileChooser` (Tab)


```nim
proc interceptFileChooser*(tab: Tab, enabled = true) {.async.}
```


**Что делает.** Подавляет системный диалог выбора файла. Сами файлы всё равно нужно назначать вручную через uploadFile() — эта команда только не даёт диалогу зависнуть; привязки к событию "Page.fileChooserOpened" здесь нет.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `enabled`, по умолчанию `true`


**Пример:**

```nim
await interceptFileChooser(tab, true)
echo "диалог выбора файла перехватывается" # выводит "диалог выбора файла перехватывается"
```


---

## Консоль и ошибки страницы


### `onConsole` (Tab)


```nim
proc onConsole*(tab: Tab, handler: ConsoleHandler)
```


**Что делает.** Подписывается на console.log/warn/error/... страницы (домен Runtime уже включён в openTab()). Подписка постоянна — живёт, пока жива сессия вкладки (как onDialog()/autoDismissDialogs() выше).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `handler` (`ConsoleHandler`) — функция обратного вызова, получающая тип сообщения ("log"/"warn"/"error" и т.п.) и его текст.


**Пример:**

```nim
proc handler(kind, text: string) =
  echo kind, ": ", text # выводит, например, "log: привет из консоли страницы"
onConsole(tab, handler)
```


### `onPageError` (Tab)


```nim
proc onPageError*(tab: Tab, handler: PageErrorHandler)
```


**Что делает.** Подписывается на необработанные JS-исключения страницы (аналог window.onerror). Подписка постоянна, как onConsole().


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `handler` (`PageErrorHandler`) — функция обратного вызова, получающая текст необработанного исключения страницы.


**Пример:**

```nim
proc handler(message: string) =
  echo "необработанная ошибка на странице: ", message
onPageError(tab, handler)
```


---

## Диагностика страницы

Три функции ниже — набор для разбора сбоя, не привязанный к конкретному
селектору/событию: `installDiagnostics()` внедряет в саму страницу лёгкий
JS-перехватчик, который копит журнал независимо от того, слушает ли
кто-то `onConsole()`/`onPageError()` в этот момент; `fetchDiagnostics()`
в любой момент забирает накопленное; `dumpDebugInfo()` — готовая связка
"сохранить скриншот + HTML + журнал диагностики одним вызовом" для места
в коде, где сценарий упал.

### `installDiagnostics` (Tab)


```nim
proc installDiagnostics*(tab: Tab) {.async.}
```


**Что делает.** Внедряет в страницу лёгкий перехватчик, копящий в самой странице журнал: необработанные исключения (`window.onerror`), необработанные отклонения промисов (`unhandledrejection`) и неуспешные fetch/XHR-запросы (статус 0 или ≥400). Забрать накопленное можно в любой момент — даже спустя долгое время — через `fetchDiagnostics()`, без необходимости держать подписку вроде `onConsole()`/`onPageError()` активной всё это время; в отличие от них, здесь дополнительно видны именно неуспешные сетевые запросы. Безопасно вызывать повторно — сама функция проверяет `window.__childtearDiag` и не переустанавливает перехватчик. Журнал ограничен последними 500 записями (более старые вытесняются).


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[void]`


**Пример:**

```nim
await installDiagnostics(tab)
await goto(tab, "https://example.com")
# ... сценарий продолжает работать ...
let log = await fetchDiagnostics(tab) # забрать накопленное в любой момент
```


### `fetchDiagnostics` (Tab)


```nim
proc fetchDiagnostics*(tab: Tab): Future[JsonNode] {.async.}
```


**Что делает.** Забирает журнал, накопленный `installDiagnostics()` с момента установки. Если она не вызывалась — возвращает пустой массив, а не ошибку.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[JsonNode]` — `JArray` записей вида `{"t": <timestamp>, "kind": "js-error"|"promise-rejection"|"fetch-failed"|"fetch-error"|"xhr-failed", "detail": <string>}`.


**Пример:**

```nim
let log = await fetchDiagnostics(tab)
for entry in log:
  echo entry["kind"], ": ", entry["detail"]
```


### `dumpDebugInfo` (Tab)


```nim
proc dumpDebugInfo*(tab: Tab, prefix = "debug"): Future[JsonNode] {.async.}
```


**Что делает.** Удобная связка для разбора сбоя: сохраняет полный скриншот (`<prefix>.png`), HTML документа (`<prefix>.html`) и, если `installDiagnostics()` была установлена ранее, журнал диагностики (`<prefix>-console.json`) — и возвращает этот журнал (пустой `JArray`, если диагностика не устанавливалась) для тех, кто хочет сразу же что-то с ним сделать (например, вывести первые записи в консоль). Ошибки самого сохранения (например, если вкладка к этому моменту уже недоступна) не выбрасываются — молча возвращается пустой `JArray`, чтобы попытка сохранить отладочную информацию сама не заслонила собой исходную причину сбоя.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `prefix`, по умолчанию `"debug"` — общий префикс путей для трёх сохраняемых файлов (`<prefix>.png`, `<prefix>.html`, `<prefix>-console.json`); может включать каталог, например `"/tmp/failure-42"`.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
try:
  await click(tab, "#submit")
except ChildTearError:
  let diag = await dumpDebugInfo(tab, "/tmp/scenario-fail")
  echo "сбой сценария, отладочная информация сохранена; записей в журнале: ", len(diag)
  raise
```


---

## Сеть: ожидание конкретных ответов


### `waitForResponse` (Tab)


```nim
proc waitForResponse*(tab: Tab, urlSubstring: string, timeoutMs = 30_000): Future[JsonNode] {.async.}
```


**Что делает.** Ждёт HTTP-ответ, чей URL содержит urlSubstring (домен Network включается автоматически, если ещё не был, через enableNetwork()). Возвращает полный объект события "Network.responseReceived" — {"requestId", "response": {"url", "status", "headers", ...}, ...}; requestId нужен для последующего responseBody(). В отличие от waitForNavigation(), реагирует на конкретный сетевой запрос, а не на загрузку страницы целиком — удобно ждать конкретный XHR/fetch.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `urlSubstring` (`string`) — подстрока, которую должен содержать URL сетевого ответа, чтобы ожидание завершилось успехом.
- `timeoutMs`, по умолчанию `30_000` — сколько миллисекунд ждать перед тем, как поднять исключение таймаута/вернуть false.


**Возвращает:** `Future[JsonNode]`


**Исключения:**

- `ChildTearError` — если ни один сетевой ответ с URL, содержащим `urlSubstring`, не пришёл за `timeoutMs`.

**Пример:**

```nim
await click(tab, "#load-more")
let res = await waitForResponse(tab, "/api/items", timeoutMs = 10_000)
echo res["status"] # выводит HTTP-статус ответа, например 200
```


### `responseBody` (Tab)


```nim
proc responseBody*(tab: Tab, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.}
```


**Что делает.** Тело конкретного сетевого ответа по requestId (см. waitForResponse()). Доступно только пока Chromium ещё не вытолкнул данные запроса из памяти — вызывать нужно вскоре после получения ответа.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `requestId` (`string`) — id запроса, взятый из объекта события, возвращённого waitForResponse().


**Возвращает:** `bool]]`


**Пример:**

```nim
let
  res = await waitForResponse(tab, "/api/items")
  (body, isBase64) = await responseBody(tab, getStr(res["requestId"]))
echo isBase64 # выводит false для JSON/текстовых ответов
```


---

## Фреймы


### `frames` (Tab)


```nim
proc frames*(tab: Tab): Future[seq[JsonNode]] {.async.}
```


**Что делает.** Возвращает список всех фреймов (включая вложенные iframe) текущей страницы — плоский список объектов {"id", "url", "name", ...} из Page.getFrameTree. Чтобы работать с содержимым конкретного iframe (клики, чтение текста и т.п.), не обязательно разбирать этот список вручную — обычно удобнее frame() ниже, находящий нужный iframe сразу по CSS-селектору самого тега `<iframe>`.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.


**Возвращает:** `Future[seq[JsonNode]]`


**Пример:**

```nim
let allFrames = await frames(tab)
echo len(allFrames) # выводит количество фреймов на странице, включая главный
```


### `frame` (Tab)


```nim
proc frame*(tab: Tab, iframeSelector: string): Future[Frame] {.async.}
```


**Что делает.** Находит `<iframe>`, подходящий под CSS-селектор iframeSelector, в ГЛАВНОМ документе вкладки (вложенные iframe внутри iframe этим вызовом не ищутся) и возвращает Frame — отдельный "вход" в его содержимое, поддерживающий свой набор click()/hover()/getText()/ fill()/evalJS()/exists() ниже, работающих внутри iframe, а не в документе основной страницы. Технически: DOM.describeNode(pierce = true) возвращает вместе с самим узлом `<iframe>` ещё и вложенный узел "contentDocument" — корневой документ ВНУТРИ iframe, — а также "frameId" этого iframe. nodeId документа iframe становится корнем для DOM.querySelector() внутри Frame (см. findFrameNode()), а frameId нужен, чтобы при первом обращении к evalJS()/getText()/fill() (см. frameContext()) создать для этого iframe изолированный JS execution context через Page.createIsolatedWorld — без него Runtime.evaluate выполнялся бы в контексте главной страницы, а не iframe, и document внутри выражения указывал бы не туда.


**Разбор реализации.** `DOM.describeNode(pierce = true)` возвращает вместе с самим узлом `<iframe>` вложенный узел `"contentDocument"` — корневой документ ВНУТРИ iframe со своим `nodeId`, который становится корнем для поиска элементов внутри `Frame` (см. `click(frame, ...)`/`getText(frame, ...)` и т.п.), а `"frameId"` этого iframe нужен, чтобы при первом обращении к `evalJS()`/`getText()`/`fill()` создать для него изолированный JS execution context через `Page.createIsolatedWorld` — без него `Runtime.evaluate` исполнялся бы в контексте главной страницы, а не iframe.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `iframeSelector` (`string`) — CSS-селектор тега <iframe> в главном документе страницы.


**Возвращает:** `Future[Frame]`


**Исключения:**

- `ChildTearError` — если элемент по `iframeSelector` не найден, либо найден, но не является `<iframe>`/`<frame>` с доступным содержимым.

**Пример:**

```nim
let inner = await frame(tab, "#payment-iframe")
echo inner != nil # выводит true
```


### `click` (Frame)


```nim
proc click*(frame: Frame, selector: string) {.async.}
```


**Что делает.** Как Tab.click(), но ищет и кликает элемент внутри содержимого этого iframe, а не в главном документе страницы.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден внутри iframe по `selector`.

**Пример:**

```nim
let inner = await frame(tab, "#payment-iframe")
await click(inner, "#pay-button")
echo "клик внутри iframe выполнен" # выводит "клик внутри iframe выполнен"
```


### `hover` (Frame)


```nim
proc hover*(frame: Frame, selector: string) {.async.}
```


**Что делает.** Как Tab.hover(), но для элемента внутри содержимого этого iframe.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Исключения:**

- `ChildTearError` — если элемент не найден внутри iframe по `selector`.

**Пример:**

```nim
let inner = await frame(tab, "#payment-iframe")
await hover(inner, ".card-icon")
echo "курсор наведён внутри iframe" # выводит "курсор наведён внутри iframe"
```


### `evalJS` (Frame)


```nim
proc evalJS*(frame: Frame, expression: string): Future[JsonNode] {.async.}
```


**Что делает.** Как Tab.evalJS(), но исполняет expression в изолированном контексте этого iframe (см. frameContext()) — document внутри выражения указывает на документ iframe, а не главной страницы.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `expression` (`string`) — произвольный JS-код, исполняемый в изолированном контексте этого iframe.


**Возвращает:** `Future[JsonNode]`


**Пример:**

```nim
let
  inner = await frame(tab, "#payment-iframe")
  res = await evalJS(inner, "document.title")
echo res["result"]["value"] # выводит заголовок документа внутри iframe
```


### `getText` (Frame)


```nim
proc getText*(frame: Frame, selector: string): Future[string] {.async.}
```


**Что делает.** Как Tab.getText(), но читает текст элемента внутри содержимого этого iframe.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[string]`


**Исключения:**

- `ChildTearError` — если элемент не найден внутри iframe по `selector`.

**Пример:**

```nim
let inner = await frame(tab, "#payment-iframe")
echo await getText(inner, "#total") # выводит текст элемента внутри iframe, например "€42.00"
```


### `getAllText` (Frame)


```nim
proc getAllText*(frame: Frame, selector: string): Future[seq[string]] {.async.}
```


**Что делает.** Как Tab.getAllText(), но для элементов внутри содержимого этого iframe.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[seq[string]]`


**Пример:**

```nim
let
  inner = await frame(tab, "#payment-iframe")
  items = await getAllText(inner, ".line-item")
echo len(items) # выводит количество строк заказа внутри iframe
```


### `fill` (Frame)


```nim
proc fill*(frame: Frame, selector: string, text: string) {.async.}
```


**Что делает.** Как Tab.fill(), но заполняет поле внутри содержимого этого iframe. Использует Input.insertText в текущий фокус вкладки (см. Tab.fill()) — поэтому сначала фокусирует поле через JS в контексте iframe.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `text` (`string`) — текст, который будет вставлен в поле вместо его текущего содержимого.


**Исключения:**

- `ChildTearError` — если элемент для заполнения не найден внутри iframe по `selector`.

**Пример:**

```nim
let inner = await frame(tab, "#payment-iframe")
await fill(inner, "#card-number", "4242424242424242")
echo "поле внутри iframe заполнено" # выводит "поле внутри iframe заполнено"
```


### `exists` (Frame)


```nim
proc exists*(frame: Frame, selector: string): Future[bool] {.async.}
```


**Что делает.** Как Tab.exists(), но проверяет наличие элемента внутри содержимого этого iframe.


**Параметры:**

- `frame` (`Frame`) — содержимое iframe (`Frame`), полученное через `tab.frame(cssSelector)`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").


**Возвращает:** `Future[bool]`


**Пример:**

```nim
let inner = await frame(tab, "#payment-iframe")
echo await exists(inner, "#error-message") # выводит true/false
```


---

## Скриншот отдельного элемента


### `screenshotElement` (Tab)


```nim
proc screenshotElement*(tab: Tab, selector, path: string, format = "png", quality = 100) {.async.}
```


**Что делает.** Скриншот одного элемента (а не всей вкладки целиком) — сначала прокручивает его в видимую область (см. boundingBox()), затем снимает только его прямоугольник.


**Параметры:**

- `tab` (`Tab`) — открытая вкладка (`Tab`), полученная через `openTab()`/`newPage()`/`attachTab()`.
- `selector` (`string`) — CSS-селектор искомого элемента (например, "#id", ".class", "button[type=submit]").
- `path` (`string`) — путь к файлу на диске — куда сохранить (скриншот, PDF, текст) или откуда загрузить.
- `format`, по умолчанию `"png"`
- `quality`, по умолчанию `100`


**Пример:**

```nim
await screenshotElement(tab, "#chart", "/tmp/chart.png")
echo "скриншот элемента сохранён" # выводит "скриншот элемента сохранён"
```


---
## Прочие функции ядра

### `insertTextAtCursor(tab, text)`

```nim
proc insertTextAtCursor*(tab: Tab, text: string) {.async.}
```

**Что делает.** "Сырой" `Input.insertText` без предварительного фокуса/выделения (в отличие от `fill()`, который сначала чистит поле) — вставляет `text` в текущую позицию курсора, дописывая к уже имеющемуся содержимому. Нужен там, где поле уже сфокусировано и заполняется по частям (многострочный ввод: первая строка через `fill()`, остальные — через `pressEnter()` + `insertTextAtCursor()`).

### `setControlledValue(tab, selector, value)`

```nim
proc setControlledValue*(tab: Tab, selector: string, value: string): Future[bool] {.async.}
```

**Что делает.** Как `syncControlledValue()`, но пишет новое `value`, а не переустанавливает `el.value` само в себя. Нужна там, где `el.value = ''` (см. `clearValue()`) не срабатывает для React-управляемых (`controlled`) полей: прямое присваивание `el.value` проходит через инстанс-уровневый сеттер-перехватчик React'а, из-за чего последующий `dispatchEvent('input')` не воспринимается компонентом как изменение.

### `installNetworkFailureLog(tab)`

```nim
proc installNetworkFailureLog*(tab: Tab) {.async.}
```

**Что делает.** Включает домен Network (`enableNetwork()`) и подписывается на `Network.loadingFailed`/`Network.responseReceived` на весь срок жизни вкладки, накапливая в `tab.netFailures` как реальные сетевые ошибки (DNS, обрыв соединения, блокировка), так и HTTP-ответы 4xx/5xx — для любых ресурсов, включая `<script src>`/`<link>`, которые браузер грузит напрямую, минуя `fetch()`/XHR (и потому не видны `installDiagnostics()`/`fetchDiagnostics()`).


---
## Практические рецепты

### Логин на сайт и проверка результата

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
  echo await getText(tab, ".welcome-message") # выводит текст приветствия после входа
  await close(tab)

waitFor main()
```

---

### Работа с формой внутри iframe (виджет оплаты)

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/checkout")
  let paymentFrame = await frame(tab, "#payment-iframe")
  await fill(paymentFrame, "#card-number", "4242424242424242")
  await fill(paymentFrame, "#expiry", "12/29")
  await click(paymentFrame, "#pay-button")
  discard await waitForText(tab, "#status", "Оплачено")
  echo "оплата прошла" # выводит "оплата прошла"
```

---

### Перетаскивание элемента на сайте с нативным HTML5 DnD

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/board")
  # native = true — обязательно для сайтов с draggable="true" и ondrop
  await dragAndDrop(tab, "#task-1", "#column-done", native = true)
  echo await exists(tab, "#column-done #task-1") # выводит true
```

---

### Скриншот и PDF длинного отчёта целиком

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/report")
  await screenshot(tab, "/tmp/report.png", fullPage = true)
  await savePDF(tab, "/tmp/report.pdf", printBackground = true)
  echo "отчёт сохранён как PNG и PDF" # выводит "отчёт сохранён как PNG и PDF"
```

---

### Дождаться ответа конкретного API-запроса вместо фиксированной паузы

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com/catalog")
  await click(tab, "#load-more")
  let res = await waitForResponse(tab, "/api/products", timeoutMs = 10_000)
  echo res["status"] # выводит 200 — сработало точно на ответ, без sleepAsync наугад
```

---

### Очистить данные только текущего сайта между тест-кейсами

```nim
proc main() {.async.} =
  await goto(tab, "https://example.com")
  # ... тест-кейс 1 оставил куки/localStorage ...
  await clearCookiesForOrigin(tab)
  await clearCacheForOrigin(tab)
  echo "состояние example.com сброшено, остальные сайты не затронуты"
```

---

## Краткая таблица

| Задача | Функция |
|---|---|
| Открыть браузер / вкладку | `newBrowser`, `openTab` / `newPage` |
| Перейти по URL | `goto` |
| Кликнуть / навести курсор | `click`, `hover`, `doubleClick`, `rightClick`, `clickAt` |
| Заполнить поле / форму | `fill`, `fillForm`, `` `type` `` |
| Прочитать текст элемента(ов) | `getText`, `getAllText`, `count` |
| Прочитать атрибут / HTML | `getAttribute`, `getAllAttributes`, `innerHTML`, `outerHTML` |
| Проверить состояние элемента | `exists`, `isVisible`, `isChecked`, `isDisabled` |
| Дождаться появления/исчезновения/текста | `waitForSelector`, `waitForSelectorGone`, `waitForText` |
| Дождаться навигации / URL / кастомного условия | `waitForNavigation`, `waitForURL`, `waitForFunction` |
| Работа с iframe | `frame`, затем `click`/`getText`/`fill`/`evalJS` от `Frame` |
| Перетаскивание (мышь / нативный HTML5 DnD) | `dragAndDrop(..., native = true/false)` |
| Скриншот / скриншот элемента / PDF | `screenshot`, `screenshotElement`, `savePDF` |
| Произвольный JS | `evalJS` |
| Куки текущей страницы / только этого сайта | `cookies`/`setCookie`/`clearCookies` / `clearCookiesForOrigin` |
| localStorage / sessionStorage | `localStorageGet/Set/Remove/Clear`, `sessionStorage...` |
| Подделать устройство/геолокацию/сеть | `setViewport`, `setGeolocation`, `setOffline`, `throttleNetwork` |
| Перехват консоли / ошибок страницы | `onConsole`, `onPageError` |
| Обработка alert/confirm/prompt | `onDialog`, `acceptDialog`, `dismissDialog`, `autoDismissDialogs` |
| Дождаться конкретного сетевого ответа | `waitForResponse`, `responseBody` |
| Размер/состояние окна браузера | `setWindowSize`, `maximizeWindow` |
| Разрешения (геолокация, уведомления) | `grantPermissions`, `resetPermissions` |

---

## Сводка: какую функцию выбрать

- Просто открыть страницу и подождать загрузки → `goto()` — сама дожидается `Page.loadEventFired` и честно поднимает ошибку, если навигация не удалась, вместо непрозрачного таймаута.
- Кликнуть по обычной кнопке/ссылке → `click()`. Нужен двойной клик, правая кнопка или клик по произвольным координатам, а не по селектору → `doubleClick()`/`rightClick()`/`clickAt()`.
- Заполнить одно поле → `fill()`. Заполнить сразу несколько полей формы → `fillForm()` — короче, чем звать `fill()` в цикле. Нужна посимвольная имитация набора (реагирует JS-валидация на каждый keydown) → `` `type`() ``.
- Прочитать текст одного элемента → `getText()`. Текст сразу нескольких (список, таблица) → `getAllText()`. Просто узнать, сколько элементов подходит под селектор → `count()`.
- Работа внутри iframe (виджеты оплаты, встроенные формы, чужие виджеты) → сначала `frame()`, дальше — одноимённые функции от `Frame`, а не от `Tab`.
- Перетаскивание: обычный список/слайдер на JS → `dragAndDrop()` с `native = false` (по умолчанию); сайт использует настоящий HTML5 `draggable`/`ondrop` → `native = true`.
- Нужно дождаться чего-то конкретного, а не просто поспать — элемент, текст, URL, сетевой ответ, произвольное JS-условие → соответствующий `waitFor*()`, а не `sleepAsync()` наугад.
- Нужно очистить куки/кэш только текущего сайта, не трогая остальной браузер → `clearCookiesForOrigin()`/`clearCacheForOrigin()`, а не `clearCookies()`/`clearBrowserCache()` (те — весь браузер, ограничение самого протокола CDP).
- Готовой функции не нашлось → `evalJS()` как аварийный люк в произвольный JS, а на самом низком уровне — прямой доступ к `tab.session` и низкоуровневый API, см. [`cdp_reference_ru.md`](./cdp_reference_ru.md).
