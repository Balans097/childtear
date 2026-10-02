# Changelog

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/).

## [Unreleased]

### Fixed

- **`siteworkers/kimi.nim`, `siteworkers/qwen.nim`, `siteworkers/redcircle.nim`:
  неразрешимый импорт `import childtear`.** Импорт указывал модуль без
  относительного пути, хотя `childtear.nim` лежит на директорию выше
  `siteworkers/` — компиляция этих трёх файлов (в отличие от
  `siteworkers/mavedigital.nim`, где путь был указан верно) падала с
  "cannot open file: childtear". Исправлено на `import ../childtear`.
- **`childtear.nim`, `siteworkers/redcircle.nim`: неоднозначный вызов
  `strip()`.** Оба файла импортируют одновременно `strutils` и
  `unicode`, у которых `strip()` имеет совпадающую по количеству
  аргументов сигнатуру — несколько мест (`isAttachedBrowserStale()`,
  `markFieldByLabel()` и ещё пять в `redcircle.nim`) вызывали `strip()`
  без уточнения модуля, что не компилируется. Исправлено явным
  указанием `strutils.strip(...)`.
- **`siteworkers/redcircle.nim`, `formatDateTimeForPicker()`: неверный
  паттерн `times.format()`.** `format(t, "dd.MM.yyyy, HH:mm")` падает с
  `TimeFormatParseError` — точка не входит в набор символов, которые
  `std/times` пропускает как литерал без экранирования (в отличие от
  запятой и двоеточия, которые уже были в порядке). Исправлено на
  `"dd'.'MM'.'yyyy, HH:mm"`.
- **`cdp/wsclient.nim`, `receiveMessage()`: неиспользуемая переменная
  `messageOpcode`.** Присваивалась, но нигде не читалась — вызывающий
  код (`receiveMessage()` возвращает `string`) не различает text/binary
  фреймы CDP, и переменная не была нужна ни для какой другой цели.
  Удалена, с комментарием на месте объясняющим почему.

- **`cdp/wsclient.nim`: незасеянный ГПСЧ.** `std/random` использовался
  для маскирующего ключа клиентских фреймов и nonce
  `Sec-WebSocket-Key` без вызова `randomize()` — глобальный RNG Nim без
  него стартует с фиксированным сидом, то есть оба значения были
  детерминированы от запуска к запуску процесса, что противоречит
  требованию RFC 6455 к непредсказуемости этих значений. Добавлена
  ленивая `ensureRngSeeded()`, вызываемая из `newWebSocket()`.
- **`cdp/browser.nim`: `newTarget()` кодировал пробелы в url как `+`.**
  `encodeUrl(url)` по умолчанию кодирует в стиле
  `application/x-www-form-urlencoded` (`usePlus = true`), а `/json/new`
  декодирует query-часть как обычный percent-encoding (RFC 3986) — URL
  с буквальным пробелом уходил бы в Chromium с символом `+` вместо
  пробела. Исправлено на `encodeUrl(url, usePlus = false)`.
- **`docs/childtear_reference_ru.md`, `docs/cdp_reference_ru.md`: 115
  параметров без описания.** Часть параметров (например, `text` у
  `fill()`, `key` у `pressKeyCombo()`, `meth` у `call()`) была указана
  в справочниках только именем и типом, без пояснения смысла —
  дописаны содержательные описания для всех.
- **`docs/childtear_reference_ru.md`: неверное описание параметра
  `key` у `pressKey (Tab)`.** Было по ошибке скопировано из
  `localStorageGet`/`sessionStorageGet` («ключ в
  localStorage/sessionStorage») — заменено на описание, соответствующее
  фактическому смыслу параметра (имя клавиши).
- **`docs/childtear_reference_ru.md`: 10 экспортированных функций
  отсутствовали в справочнике целиком** — `waitForReady`,
  `newPageWithRetry`, `getLastText`, `syncControlledValue`,
  `existsWithText`, `waitForStableText`, `installDiagnostics`,
  `fetchDiagnostics`, `dumpDebugInfo` (и параметры `headers`/`fields`,
  пропущенные в первом проходе из-за типов с вложенными скобками).
  Добавлены полные разделы (сигнатура, параметры, возвращаемое
  значение, исключения, пример) для всех десяти; сверка списка
  экспортированных имён `childtear.nim`/`cdp/*.nim`/`siteworker.nim` с
  соответствующими справочниками пробелов больше не показывает.
- **`docs/childtear_reference_ru.md`: добавлены секции «Исключения»**
  для 28 функций, поднимающих `ChildTearError` напрямую или
  транзитивно (через внутренние `findNode`/`findFrameNode`) — `click`,
  `fill`, `goto`, `waitForFunction`, `dragAndDrop`, `frame` и другие —
  с указанием точного условия ошибки.

### Changed

- **`childtear.nim` разделён по слоям ответственности.** Файл (2987
  строк) фактически содержал четыре разных слоя — ядро CDP-обёртки
  (`Browser`/`Tab`/`Frame`), общую инфраструктуру `siteworkers/*.nim`,
  управление жизненным циклом процесса Chromium и работу с системным
  буфером обмена — под заголовком, называвшим его "тонкой обёрткой над
  headless-Chromium". Три последних слоя вынесены в новые модули:
  `siteworkers/siteworker_common.nim` (`AskResult`/`SiteWorkerPref`/
  `ImageFormat`, поиск и пометка элементов по видимому тексту,
  `vecho`/`warnLoggedOut`), `cdp/browser_lifecycle.nim`
  (`ensureBrowser`/`stopBrowser`/`gotoWithRetry`/`dumpDebugInfoVerbose`)
  и `cdp/clipboard.nim` (`captureAnswerScreenshot` и функции
  работы с буфером обмена). `childtear.nim` теперь содержит только
  ядро CDP-обёртки. `siteworkers/kimi.nim`, `siteworkers/qwen.nim`,
  `siteworkers/redcircle.nim` и `siteworkers/mavedigital.nim` обновлены
  под новые импорты; справочники разделены соответственно —
  `docs/siteworker_common_reference_ru.md`,
  `docs/browser_lifecycle_reference_ru.md`, `docs/clipboard_reference_ru.md`.
  Итоговое размещение — по явному указанию: `siteworker_common.nim`
  вместе с остальными `siteworkers/*.nim`, а `browser_lifecycle.nim` и
  `clipboard.nim` — в `cdp/` (см. примечание в README.md#архитектура о
  зависимости `cdp/` → `siteworkers/`, которую это создаёт).
- **`siteworkers/redcircle.nim`: `markByButtonText` переименован в
  `rcMarkByButtonText`.** Локальная функция называлась так же, как
  общая `markByButtonText` из `siteworker_common.nim`, и полагалась на
  то, что Nim выбирает точное совпадение по количеству аргументов —
  случайный будущий вызов с явным `markAttr` молча ушёл бы в чужую
  функцию без ошибки компиляции. Переименование убирает саму
  возможность такой путаницы, а не только документирует её.

### Added

- **`waitUntilTrue()` (childtear.nim)** — обобщённый примитив ожидания:
  опрашивает произвольное асинхронное условие с заданным интервалом,
  пока оно не станет истинным или не истечёт таймаут. На нём теперь
  построены `waitForSelector()`, `waitForURL()`, `waitForSelectorGone()`
  и `waitForText()` — эти четыре функции реализовывали один и тот же
  цикл ожидания по отдельности; дублирование устранено без изменения
  их публичных сигнатур и поведения.
- **`waitUntilCleared()` (childtear.nim)** — ждёт, пока текст или
  значение поля ввода не станет пустым после `strip()`. Вынесено из
  `siteworker.nim`, где один и тот же цикл ("поле очистилось после
  Enter — проверить снова после клика по кнопке отправки") был
  продублирован почти дословно в `askQwen()` и `askKimi()`. Обе функции
  теперь используют общий хелпер из childtear вместо собственных копий
  цикла; аналогично на `waitUntilTrue()` переведены циклы ожидания
  "включился пункт меню вложения"/"закончился анализ вложения на
  сервере"/"началась генерация ответа" в `qwenAttachFiles()`,
  `kimiAttachFiles()`, `askQwen()`, `askKimi()` и
  `kimiResolvePromptInputSelector()`. Решение о размещении в
  childtear.nim, а не в siteworker.nim: обе функции работают с
  произвольным `Tab`/селектором и не завязаны на специфику Qwen или
  Kimi, поэтому полезны любому коду поверх childtear, а не только
  siteworker — та же логика, по которой в childtear уже жили
  `waitForSelector`/`waitForText` и им подобные.

### Fixed / Documentation

- **`tests/example0.nim` действительно удалён.** Раздел "Removed" записи
  1.0 ниже утверждал, что этот файл убран из проекта (устаревший дубликат
  `example.nim`, писавший вызовы через точку на значениях —
  `tab.setViewport(...)`, `browser.newPage()` и т.п. — то есть в стиле,
  который сам `childtear.nim` в шапке отдельно оговаривает как не
  используемый в проекте). По факту файл всё ещё лежал в дереве —
  несоответствие между CHANGELOG и содержимым репозитория устранено.
- **Побиты ссылки в README.md и docs/siteworker_reference_ru.md.**
  Справочники были перенесены из корня проекта (`REFERENCE.md`) в `docs/`
  и разделены на три файла (`childtear_reference_ru.md`, `cdp_reference_ru.md`,
  `siteworker_reference_ru.md`), но ссылки на них в README.md и друг на
  друга не были обновлены под новые пути/имена. Также в README.md не был
  закрыт `<div align="center">` (закрывающий тег был, открывающего не
  было) и не был указан отдельный справочник `cdp_reference_ru.md`
  (низкоуровневый CDP-слой) — оба недочёта исправлены, раздел
  "Структура" теперь перечисляет папку `docs/` целиком.
- Число функций в README.md ("280 функций") обновлено на актуальное —
  публичный API `childtear.nim` вместе с `cdp/domains/*` даёт около 290
  экспортируемых имён (`proc`/`func`/`template`/`macro`).

## [1.0] - 2026-08-10

Первый версионированный релиз.

### Added

- **Поддержка iframe.** Новый тип `Frame` и `tab.frame(cssSelector)`:
  находит `<iframe>` по CSS-селектору, резолвит его `contentDocument` через
  `DOM.describeNode(pierce = true)` и лениво создаёт изолированный JS
  execution context через `Page.createIsolatedWorld`. У `Frame` свой набор
  `click()`, `hover()`, `getText()`, `getAllText()`, `fill()`, `exists()`,
  `evalJS()` — работают внутри документа iframe, а не главной страницы.
  Раньше вся высокоуровневая работа с элементами была жёстко привязана к
  главному фрейму вкладки.
- **Нативный HTML5 drag-and-drop.** У `dragAndDrop()` появился параметр
  `native = true`: вместо эмуляции мышью диспатчит настоящую
  последовательность событий `DragEvent`/`DataTransfer`
  (`dragstart → dragenter → dragover → drop → dragend`) — для сайтов,
  которые слушают именно нативные HTML5 DnD-события, а не обычные события
  мыши. Мышиный режим (`native = false`) остался поведением по умолчанию.
- **Origin-scoped очистка данных.** `clearCookiesForOrigin(tab)` — удаляет
  куки только текущего origin'а (через `getCookies` + поштучный
  `deleteCookies`, вместо очистки куки всего браузера). `clearCacheForOrigin(tab)`
  — то же для Cache Storage/localStorage/IndexedDB и т.д. через новый домен
  `Storage.clearDataForOrigin` (см. новый модуль `cdp/domains/storage.nim`).
  Честно задокументировано, что HTTP-дисковый кэш и куки браузера целиком
  всё равно нельзя ограничить одним origin'ом — это ограничение самого
  протокола CDP, а не библиотеки.
- Новый модуль `cdp/domains/storage.nim` — обёртка над доменом `Storage`
  (`clearDataForOrigin`, `getCookies`, `clearCookies` на уровне профиля).
- `REFERENCE.md` — полный справочник всех публичных функций, собранный
  напрямую из doc-комментариев кода.
- **Функции, перенесённые из qwenclient.nim** (обкатаны на автоматизации
  chat.qwen.ai, обобщены до библиотечного вида):
  - `syncControlledValue(tab, selector)` — чинит поля, которыми управляет
    React/Vue-подобный "controlled"-компонент: вызывает нативный сеттер
    `value` через дескриптор прототипа `HTMLInputElement`/
    `HTMLTextAreaElement` в обход переопределённого фреймворком, затем
    диспатчит `input`-событие. Раньше `fill()`/`type()` в таких полях
    иногда приводили к пустой отправке или откату поля на следующем
    ре-рендере.
  - `existsWithText(tab, tag, textSubstring)` — поиск элемента по тегу и
    подстроке видимого текста (регистронезависимо); замена
    отсутствующему в обычном CSS `:has-text(...)` из Playwright.
  - `getLastText(tab, selector)` — как `getText()`, но берёт последний, а
    не первый узел, подходящий под селектор; полезно для списков
    одинаково размеченных повторяющихся элементов (история сообщений,
    лента).
  - `waitForStableText(tab, selector, pollMs, stableForMs, timeoutMs)` —
    ждёт, пока текст элемента перестанет меняться заданное время подряд,
    и возвращает финальное значение; для стримингового контента без
    отдельного события "готово".
  - `installDiagnostics(tab)` / `fetchDiagnostics(tab)` — лёгкий
    перехватчик на самой странице, копящий необработанные исключения,
    отклонения промисов и неуспешные `fetch`/`XHR`-запросы; журнал можно
    забрать в любой момент, не держа подписку активной всё время (в
    отличие от `onConsole()`/`onPageError()`).
  - `dumpDebugInfo(tab, prefix)` — сохраняет скриншот, HTML и журнал
    диагностики одним вызовом; ошибки самого сохранения не выбрасывает
    (молча возвращает пустой журнал), чтобы не заслонить собой исходную
    причину сбоя.
  - `waitForReady(browser, timeoutMs)` — ждёт, пока Chromium поднимет
    отладочный HTTP/CDP-эндпоинт после запуска процесса (опрос
    `/json/version`).
  - `newPageWithRetry(browser, url, attempts, delayMs)` — как `newPage()`,
    но с повторными попытками при неудаче первого перехода — на холодном
    старте Chromium сеть иногда ещё не готова, хотя CDP-порт уже отвечает.
- Константа `ChildTearVersion* = "1.0"` — версия библиотеки, доступна
  программно.

### Changed

- **`setWindowSize()`/`maximizeWindow()`** больше не открывают новую
  browser-level CDP-сессию на каждый вызов — сессия кешируется на самой
  `Tab` (`tabBrowserSession`) и переиспользуется при повторных вызовах;
  закрывается автоматически вместе с вкладкой в `close(tab)`.
- **`Runtime.evaluate`/`evaluateValue`** (`cdp/domains/runtime.nim`) получили
  параметр `contextId` — низкоуровневая опора для работы с изолированными
  JS-контекстами iframe (используется новым `Frame`).
- **`DOM.describeNode`** (`cdp/domains/dom.nim`) получил параметры `depth` и
  `pierce` — нужны, чтобы получить `contentDocument` вложенного iframe.
- `tests/example.nim` переписан: вместо набора закомментированных вариантов
  — рабочая демонстрация на самодостаточной `data:`-странице (форма,
  нативный drag-and-drop, iframe), не зависящая от разметки внешних сайтов.
- **qwenclient.nim** обновлён под childtear 1.0: локальные копии
  `syncControlledInputValue`, `existsWithText`, `getLastText`,
  `installDiagnostics`, `fetchDiagnostics` и `dumpDebugInfo` удалены —
  используются одноимённые функции самой библиотеки. `dumpDebugInfo`
  обёрнут локально в `dumpDebugInfoVerbose` (та же логика плюс вывод в
  консоль — уместно для CLI, но не для библиотеки).
  `waitForDebuggerReady` заменён на `childtear.waitForReady`; `gotoWithRetry`
  оставлен локальным (нужен консольный прогресс между попытками), но
  теперь зеркалит `childtear.newPageWithRetry`.

### Removed

- `tests/example0.nim` — устаревший дубликат `example.nim`, писавший вызовы
  через точку на значениях (`str.startsWith(...)`); сам файл `childtear.nim`
  уже отдельно оговаривает, что такой стиль в проекте не используется.
- Из шапки `childtear.nim` убран блок "Пример использования" — не нужен
  версионированному релизу с отдельным `REFERENCE.md`.

### Fixed / Documentation

- Из комментариев `goto()`, `listenLoop()` (`cdp/transport.nim`) и
  `tests/test_transport.nim` убран нарратив вида "раньше было так, теперь
  исправлено" — оставлено только описание актуального поведения.
- Добавлены содержательные doc-комментарии более чем к 80 ранее
  недокументированным функциям во всех модулях (`childtear.nim` и все
  `cdp/*.nim`) — теперь каждая публичная функция библиотеки задокументирована.
- Исправлена неоднозначность вызова `strip()` в `waitForStableText()`
  (совпадала с `std/strutils.strip` и `std/unicode.strip` — оба модуля
  импортированы) — устранена явной квалификацией `strutils.strip`.
- Ревизия всей кодовой базы: `childtear.nim`, все `cdp/*.nim` и
  `qwenclient.nim` компилируются чисто (`nim check`), без ошибок и
  предупреждений.
- В шапку `childtear.nim` добавлена версия ("Версия 1.0").
