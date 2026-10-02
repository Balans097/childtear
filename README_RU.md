<div align="center">

# childtear

**Библиотека для управления headless Chrome/Chromium из Nim через Chrome DevTools Protocol.**

Библиотека предоставляет прикладной интерфейс для типовых операций
автоматизации браузера: открытие вкладки, взаимодействие с элементами
страницы, заполнение форм, извлечение текста, создание снимков экрана.
Реализация не использует генераторы кода: каждая функция написана и
документирована вручную.

[![Nim](https://img.shields.io/badge/Nim-%3E%3D1.6-ffc200?logo=nim&logoColor=black)](https://nim-lang.org)
[![Chrome DevTools Protocol](https://img.shields.io/badge/CDP-Chrome%20DevTools%20Protocol-4285F4?logo=googlechrome&logoColor=white)](https://chromedevtools.github.io/devtools-protocol/)
[![License](https://img.shields.io/badge/license-MIT-green)](#лицензия)

[Быстрый старт](#быстрый-старт) •
[Возможности](#возможности) •
[Примеры](#примеры) •
[Справочник функций](./docs/childtear_reference_ru.md) •
[Низкоуровневый CDP-слой](./docs/cdp_reference_ru.md) •
[siteworkers: готовые сценарии автоматизации](#siteworkers-готовые-сценарии-автоматизации)

</div>

---

## Назначение

Библиотека решает задачу автоматизации браузера на языке Nim без
привлечения инструментов, реализованных на JavaScript или Python
(Puppeteer, Playwright), и без необходимости включения в проект среды
выполнения Node.js. Основные принципы реализации:

- **Отсутствие генерации кода.** Каждая обёртка над командой CDP
  реализована и прокомментирована вручную; исходный код модулей может
  использоваться как справочная документация.
- **Два уровня прикладного интерфейса.** Высокоуровневый API (`click`,
  `fill`, `getText` и др.) предназначен для решения большинства
  прикладных задач. Низкоуровневый API (`tab.session` и модули
  `cdp/domains/*`) предоставляет прямой доступ к командам протокола в
  случаях, не покрытых высокоуровневым слоем.
- **Явное указание ограничений протокола.** В случаях, когда сам CDP не
  предоставляет требуемой функциональности (например, очистка
  HTTP-кэша в границах одной вкладки), это ограничение указывается в
  документации соответствующей функции, а не маскируется приближённой
  реализацией.

## Установка

```bash
nimble install https://github.com/Balans097/childtear
```

Альтернативный способ — копирование файла `childtear.nim` и каталога
`cdp/` в состав проекта. Требования: Nim ≥ 2.0 и пакет `checksums`
(`nimble install checksums`; нужен `cdp/wsclient.nim` для SHA-1 в
WebSocket-handshake). Других внешних зависимостей нет.

Для работы библиотеки требуется запущенный headless Chromium/Chrome с
открытым портом отладки:

```bash
chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox &
```

При использовании модулей `siteworkers/*.nim` (готовые сценарии для
Qwen, Kimi, RedCircle и mave.digital — см.
[раздел ниже](#siteworkers-готовые-сценарии-автоматизации)) ручной
запуск Chromium не требуется: процесс запускается библиотекой
автоматически через `browser_lifecycle.ensureBrowser()`, один раз на профиль, и
переиспользуется между вызовами. Дополнительная зависимость —
`wl-copy` (пакет `wl-clipboard`) либо `xclip`, требуется только для
функций `aiText2Clipboard()`/`aiScreenshot2Clipboard()`.

## Структура

```
childtear.nim                высокоуровневый API (Browser/Tab/Frame, близкий по
                                духу к Puppeteer) — навигация, клики, формы,
                                скриншоты, сеть, эмуляция, диагностика.
                                См. docs/childtear_reference_ru.md
siteworkers/
  siteworker_common.nim       общая для всех siteworkers/*.nim инфраструктура:
                                AskResult/SiteWorkerPref/ImageFormat,
                                поиск и пометка элементов страницы по видимому
                                тексту (mark*)
  qwen.nim                    askQwen() — запрос-ответ к chat.qwen.ai
  kimi.nim                    askKimi() — запрос-ответ к www.kimi.com
  browser_lifecycle.nim        запуск/переиспользование Chromium с постоянным
                                профилем (ensureBrowser/stopBrowser),
                                gotoWithRetry, dumpDebugInfoVerbose
  clipboard.nim                скриншот последнего сообщения ассистента и работа
                                с системным буфером обмена (aiText2File и т.п.)
  redcircle.nim                uploadToRedcircle() — публикация эпизода подкаста
                                на app.redcircle.com
  mavedigital.nim               uploadToMave() — публикация эпизода подкаста
                                на app.mave.digital (несколько каналов на аккаунт)
                                — см. раздел ниже и docs/siteworker_reference_ru.md
docs/
  childtear_reference_ru.md    справочник ядра CDP-обёртки (все функции
                                childtear.nim с сигнатурами и описанием)
  siteworker_common_reference_ru.md   справочник siteworkers/siteworker_common.nim
  browser_lifecycle_reference_ru.md   справочник siteworkers/browser_lifecycle.nim
  clipboard_reference_ru.md    справочник siteworkers/clipboard.nim
  cdp_reference_ru.md          справочник низкоуровневого CDP-слоя (cdp/*)
  siteworker_reference_ru.md   справочник общих типов siteworker-инфраструктуры
                                (AskResult, SiteWorkerPref и т.п.) и askQwen/askKimi
cdp/
  wsclient.nim                WebSocket-клиент "с нуля" (handshake + фрейминг RFC 6455)
  transport.nim                JSON-RPC поверх WebSocket: call() / on() / onSession() / waitForEvent()
  browser.nim                  HTTP-обвязка /json/new, /json/list, /json/close, /json/version
  domains/
    page.nim                   навигация, история, диалоги, изолированные миры,
                                инжектируемые скрипты, download-behavior, скриншоты/PDF
    dom.nim                    querySelector(All), boxModel/contentQuads, атрибуты,
                                outerHTML, upload файлов, удаление/скролл узлов
    runtime.nim                 evaluate/callFunctionOn, getProperties, release*,
                                 addBinding/removeBinding (мост JS -> нативный код)
    input.nim                   мышь (включая колесо), клавиатура, touch-события
    network.nim                  куки, тело ответа, блокировка URL, троттлинг сети
    fetch.nim                    перехват/подмена/блокировка запросов, Basic-auth
    target.nim                   многовкладочный режим, browser context (инкогнито)
    emulation.nim                вьюпорт, User-Agent, геолокация, часовой пояс, CPU throttling
    browserdomain.nim            команды уровня браузера (Browser.close, разрешения, окна)
    log.nim                      Log.entryAdded (сообщения браузерного лога)
tests/
  mock_cdp_server.nim          тестовый WS-сервер для проверки транспортного слоя
  test_wsclient.nim            WebSocket-клиент: handshake, фрагментация, ping/pong, close
  test_transport.nim           call(), on(), waitForEvent(), обрыв соединения
  test_browser_http.nim        HTTP-обвязка /json/*: PUT-методы, ошибки не-2xx
  run_tests.sh                 запуск всех тестов
  example.nim                  демонстрация основного API (навигация, куки, typeText(), диалоги, exposeFunction())
  bbc_article_example.nim      пример извлечения статьи с bbc.com/russian в текстовый файл
```

## Быстрый старт

```nim
import childtear
import std/asyncdispatch

proc main() {.async.} =
  let browser = newBrowser()                 # localhost:9222 по умолчанию
  let tab = await openTab(browser, "https://example.com")

  await click(tab, "#login-button")
  await fillForm(tab, @{"#username": "andy", "#password": "secret"})
  await click(tab, "button[type=submit]")

  echo await getText(tab, "h1")
  await screenshot(tab, "result.png")

  await close(tab)

waitFor main()
```

## Возможности

|                                  |                                                                                                                                                                                        |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Взаимодействие**               | `click`, `hover`, `doubleClick`, `rightClick`, `clickAt`, `fill`, `fillForm`, `selectOption`, `uploadFile`, `submitForm`, `dragAndDrop` (эмуляция мышью и нативный HTML5 DnD)          |
| **Чтение страницы**              | `getText`, `getAllText`, `getAttribute`, `getLinks`, `innerHTML`/`outerHTML`, `count`, `exists`, `boundingBox`                                                                         |
| **iframe**                       | `tab.frame(selector)` возвращает объект `Frame` с собственными методами `click`/`getText`/`fill`/`evalJS`, выполняемыми в контексте документа iframe, а не главного документа страницы |
| **Ожидания**                     | `waitForSelector`, `waitForSelectorGone`, `waitForText`, `waitForNavigation`, `waitForFunction`, `waitForURL`, `waitForResponse`                                                       |
| **Куки и хранилища**             | `cookies`, `setCookie`, `deleteCookie`, `clearCookies` / `clearCookiesForOrigin`, `localStorage*`, `sessionStorage*`                                                                   |
| **Эмуляция окружения**           | `setViewport`, `setUserAgent`, `setGeolocation`, `setTimezone`, `setLocale`, `emulateMedia`, `setCPUThrottle`, `enableTouchEmulation`, `setOffline`, `throttleNetwork`                 |
| **Снимки страницы**              | `screenshot`, `screenshotElement`, `savePDF`, `content`/`setContent`                                                                                                                   |
| **JS-мост**                      | `evalJS`, `addScriptTag`, `evaluateOnNewDocument`, `exposeFunction` (вызов кода Nim из JavaScript-контекста страницы)                                                                  |
| **Сеть**                         | `enableNetwork`, `setExtraHeaders`, `blockUrls`, `waitForResponse`, `responseBody`, `setOffline`, `throttleNetwork`                                                                    |
| **Множество вкладок и профилей** | `pages`, `attachTab`, `createIncognitoContext`, `newPageInContext`, `closeContext`                                                                                                     |

Полный перечень — около 290 функций высокого и низкого уровня, с
сигнатурами и описанием — приведён в
[`docs/childtear_reference_ru.md`](./docs/childtear_reference_ru.md) (высокий
уровень) и [`docs/cdp_reference_ru.md`](./docs/cdp_reference_ru.md) (низкий
уровень, прямой доступ к доменам CDP).

## Примеры

Демонстрация работы с формой, нативным drag-and-drop и iframe приведена
в [`tests/example.nim`](./tests/example.nim); пример выполняется на
самодостаточной `data:`-странице и не зависит от внешних сайтов:

```bash
nim c -d:release tests/example.nim
./tests/example
```

Пример извлечения содержимого статьи с внешнего сайта —
[`tests/bbc_article_example.nim`](./tests/bbc_article_example.nim).

### iframe

```nim
let inner = await frame(tab, "#inner-frame")
await click(inner, "#submit-btn")
echo await getText(inner, "#result")
```

### Нативный HTML5 drag-and-drop

```nim
# native = true — диспатч фактической последовательности событий
# dragstart/dragover/drop, а не эмуляция средствами мыши
await dragAndDrop(tab, "#drag-item", "#drop-zone", native = true)
```

### Очистка данных в границах текущего origin

```nim
# В отличие от clearCookies()/clearBrowserCache(), затрагивающих браузер
# целиком (ограничение самого протокола CDP), приведённые ниже функции
# ограничены текущим origin
await clearCookiesForOrigin(tab)
await clearCacheForOrigin(tab)
```

## siteworkers: готовые сценарии автоматизации

`siteworkers/*.nim` — надстройки над childtear, каждая реализует
типовой сценарий для одного сайта. Общая инфраструктура (`AskResult`,
`SiteWorkerPref`, `ImageFormat`, `SiteWorkerError`, поиск элементов по
видимому тексту, запуск/переиспользование процесса Chromium) находится
в `siteworkers/siteworker_common.nim` и `siteworkers/browser_lifecycle.nim`;
отдельные `siteworkers/*.nim` используют её и ничего не добавляют к
управлению страницей напрямую, минуя childtear.

Два модуля реализуют обращение к чат-сервисам:

```nim
import siteworkers/qwen
import siteworkers/kimi

let answer = waitFor askQwen("Сформулируй план на неделю")
aiText2File(answer.text, "план.txt")
aiScreenshot2Clipboard(answer.screenshotData, answer.screenshotFormat)
```

Ещё два — публикацию эпизода подкаста на конкретной платформе:

```nim
import siteworkers/redcircle
import siteworkers/mavedigital

waitFor uploadToRedcircle("Название", "Описание", "файл.mp3")
waitFor uploadToMave(mcHistory, "Гость — Название", "00:00 — интро", "файл.mp3")
```

Ключевые решения, положенные в основу реализации:

- **Функции не выполняют авторизацию самостоятельно.** Каждый модуль
  использует ранее сохранённый на диске профиль Chromium — тот же
  каталог, что и у соответствующей CLI-утилиты (`qwenclient`,
  `kimiclient`, `redcircleclient`). При отсутствии профиля или
  истёкшей сессии функция завершается исключением `SiteWorkerError` с
  указанием, что профиль нужно подготовить заранее интерактивным
  входом.
- **Один изолированный процесс Chromium на профиль**, запускаемый и
  переиспользуемый библиотекой (`browser_lifecycle.ensureBrowser()`) на
  отдельном отладочном порту для каждого сайта; это позволяет
  вызывать сценарии разных сайтов параллельно.
- **Результат чат-сценариев представлен типом `AskResult`, а не
  строкой.** Помимо текста ответа объект содержит его снимок экрана,
  полученный в той же сессии браузера непосредственно после
  стабилизации ответа.
- **Функции представления результата принимают данные, а не объект
  `AskResult` целиком** (`aiText2File`, `aiText2Clipboard`,
  `aiScreenshot2File`, `aiScreenshot2Clipboard`) — это позволяет
  применять их к данным, полученным из любого источника.
- **Флаги-модификаторы** (`SiteWorkerPref`) управляют видимостью окна
  браузера, выводом в консоль, сохранением отладочных файлов при
  ошибке, форматом и охватом снимка экрана. Значение по умолчанию
  (пустое множество `{}`) соответствует headless-режиму без побочного
  вывода.

Полный справочник общей инфраструктуры и askQwen/askKimi приведён в
[`docs/siteworker_reference_ru.md`](./docs/siteworker_reference_ru.md);
redcircle.nim и mavedigital.nim документированы непосредственно в
исходном коде (заголовок модуля + комментарий к каждой экспортируемой
функции).

## Архитектура

```
childtear.nim          — высокоуровневый CDP-API (Browser/Tab/Frame): навигация,
                          клики, формы, скриншоты, сеть, эмуляция, диагностика —
                          основная точка входа для пользователя библиотеки
siteworkers/
  siteworker_common.nim — общая для siteworkers/*.nim инфраструктура: AskResult,
                          SiteWorkerPref, ImageFormat, поиск и пометка
                          элементов страницы по видимому тексту (mark*)
  qwen.nim, kimi.nim    — сценарии askQwen()/askKimi() для чат-сервисов
  redcircle.nim,
  mavedigital.nim       — сценарии публикации эпизода подкаста
                          (uploadToRedcircle()/uploadToMave())
                          Ни один из четырёх модулей не обращается к
                          протоколу CDP напрямую — только через публичный
                          API childtear.nim и siteworkers/browser_lifecycle.nim,
                          siteworkers/clipboard.nim.
cdp/
  transport.nim        — WebSocket JSON-RPC поверх CDP, подписка на события
  wsclient.nim          — WebSocket-клиент нижнего уровня (handshake, фрейминг)
  browser.nim           — HTTP-интерфейс /json/* (список вкладок, открытие/закрытие)
  browser_lifecycle.nim — запуск/переиспользование Chromium с постоянным
                          профилем (ensureBrowser/stopBrowser), gotoWithRetry
  clipboard.nim         — скриншот последнего сообщения ассистента + работа
                          с системным буфером обмена
  domains/
    page.nim, dom.nim, runtime.nim, input.nim, network.nim,
    emulation.nim, fetch.nim, target.nim, browserdomain.nim,
    storage.nim, log.nim
                        — обёртки, реализующие соответствие один к одному
                          с доменами CDP
```

Каждый домен CDP реализован в виде отдельного модуля в `cdp/domains/`;
`childtear.nim` компонует эти модули в прикладные команды.
При отсутствии готовой функции для конкретной задачи доступ к
произвольной команде протокола предоставляется через `tab.session`.

Общая инфраструктура сценариев (`AskResult`/`SiteWorkerPref`,
`mark*ByLabel/Text`, `ensureBrowser`/`stopBrowser`, буфер обмена)
находится в `siteworkers/siteworker_common.nim`,
`siteworkers/browser_lifecycle.nim` и `siteworkers/clipboard.nim`.
`childtear.nim` содержит только ядро CDP-обёртки (Browser/Tab/Frame).
Слой `cdp/` не зависит от `childtear.nim` и `siteworkers/`: зависимости
идут строго вниз (`siteworkers/` → `childtear.nim` → `cdp/`). Каждый `siteworkers/*.nim`-модуль
импортирует из этих файлов только то, что ему действительно нужно.

## Лицензия

MIT.
