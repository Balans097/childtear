# siteworkers/browser_lifecycle — справочник запуска и переиспользования Chromium

> **Импорт:** `import siteworkers/browser_lifecycle`

> **Область применения:** запуск/переиспользование Chromium с постоянным профилем и диагностика при сбоях — общая для всех `siteworkers/*.nim` инфраструктура, ничего специфичного для конкретного сайта здесь нет. Выделено из `childtear.nim` при разделении на модули по слоям ответственности — см. [README.md](../README.md#архитектура). Опирается на типы из [`siteworker_common_reference_ru.md`](./siteworker_common_reference_ru.md) (`SiteWorkerPref`).

---

## Оглавление

1. [`ensureBrowser`](#ensurebrowserprofiledir-port-headless-proxyurl--)
2. [`stopBrowser`](#stopbrowserport)
3. [`ensureBrowserForLogin`](#ensurebrowserforloginprofiledir-port)
4. [`gotoWithRetry`](#gotowithretrybrowser-url-attempts--3-delayms--2000-verbose--true)
5. [`dumpDebugInfoVerbose`](#dumpdebuginfoverbosetab-prefix-pref)

---

### `ensureBrowser(profileDir, port, headless, proxyUrl = "")`

```nim
proc ensureBrowser*(profileDir: string, port: int, headless: bool,
                     proxyUrl: string = ""): Future[BrowserHandle] {.async.}
```

**Что делает.** Возвращает подключение к Chromium на порту `port` с профилем `profileDir`: либо к уже работающему процессу (`attached = true` в результате), либо к только что запущенному этим самым вызовом (`attached = false`). Безопасна при параллельных вызовах на один и тот же порт в рамках текущего процесса ОС. Основа, на которой строится запуск браузера во всех `siteworkers/*.nim`.

### `stopBrowser(port)`

```nim
proc stopBrowser*(port: int): Future[void] {.async.}
```

**Что делает.** Явно завершает Chromium, слушающий данный порт, вне зависимости от того, кто и когда его запустил. Если порт уже пуст — ничего не делает. Ни `ensureBrowser()`, ни сценарии `siteworkers/*.nim` эту функцию сами не вызывают (кроме внутреннего вызова из `ensureBrowser()` при обнаружении устаревшего относительно диска профиля процесса) — явное управление жизненным циклом общего экземпляра в остальном остаётся на усмотрение вызывающего кода.

### `ensureBrowserForLogin(profileDir, port)`

```nim
proc ensureBrowserForLogin*(profileDir: string, port: int): Future[BrowserHandle] {.async.}
```

**Что делает.** Готовит Chromium для интерактивного входа в постоянный профиль `profileDir` на этом порту. В отличие от `ensureBrowser()`, не переиспользует то, что уже отвечает CDP на порту, а безусловно останавливает это (`stopBrowser()`) и поднимает взамен свежий процесс с `headless = false` — иначе, если на порту уже фоново живёт headless-процесс от предыдущего автоматического прогона, обычный `ensureBrowser()` просто подключился бы к нему, и видимое окно для входа не появилось бы вовсе. Используется интерактивными CLI-командами входа (`loginQwen()`/`loginKimi()`/`loginMave()` и т.п. в `siteworkers/*.nim`), а не обычным путём `askQwen()`/`uploadToMave()`.

### `gotoWithRetry(browser, url, attempts = 3, delayMs = 2000, verbose = true)`

```nim
proc gotoWithRetry*(browser: Browser, url: string,
                     attempts = 3, delayMs = 2_000, verbose = true): Future[Tab] {.async.}
```

**Что делает.** Тонкая обёртка над `newPage()`: на холодном старте первый переход изредка падает с `net::ERR_TUNNEL_CONNECTION_FAILED`, пока Chromium ещё разрешает прокси-настройки, хотя сеть в целом рабочая — повторяет попытку до `attempts` раз с паузой `delayMs`, при `verbose` печатая прогресс. Используется всеми `siteworkers/*.nim`, не только чат-сценариями.

### `dumpDebugInfoVerbose(tab, prefix, pref)`

```nim
proc dumpDebugInfoVerbose*(tab: Tab, prefix: string, pref: set[SiteWorkerPref]) {.async.}
```

**Что делает.** Сохраняет снимок страницы (screenshot + HTML + консоль браузера) через `dumpDebugInfo()` (из [`childtear.nim`](../childtear.nim)) и, при `pVerbose`, печатает краткую сводку. Сама запись файлов на диск происходит только при `pDumpDebug` в `pref` — без этого флага функция не делает вообще ничего, даже при вызове из ветки обработки ошибки.
