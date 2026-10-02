# siteworkers/siteworker_common — справочник общей инфраструктуры siteworkers

> **Импорт:** `import siteworkers/siteworker_common`

> **Область применения:** общая для всех `siteworkers/*.nim` инфраструктура, не специфичная ни для одного конкретного сайта — типы ошибок/настроек/результата запроса к AI-чату, и поиск/пометка элементов страницы по видимому тексту (устойчивая альтернатива нестабильным между сборками сайта CSS-классам). Обычному прикладному коду, работающему только с [`childtear.nim`](../childtear.nim) напрямую, эти функции обычно не нужны — они рассчитаны на авторов новых `siteworkers/*.nim`-модулей.

Выделено из `childtear.nim` при разделении на модули по слоям
ответственности — см. [README.md](../README.md#архитектура). Соседние
модули того же слоя: [`browser_lifecycle_reference_ru.md`](./browser_lifecycle_reference_ru.md)
(запуск/остановка Chromium), [`clipboard_reference_ru.md`](./clipboard_reference_ru.md)
(скриншот ответа и буфер обмена).

---

## Оглавление

I. [Типы](#типы)
   1. [`SiteWorkerError`](#siteworkererror)
   2. [`SiteWorkerPref`](#siteworkerpref)
   3. [`ImageFormat`](#imageformat)
   4. [`AskResult`](#askresult)
II. [Поиск и пометка элементов по видимому тексту](#поиск-и-пометка-элементов-по-видимому-тексту)
   1. [`pageHasText`](#pagehastexttab-textsubstring)
   2. [`unmark`](#unmarktab-markattr--defaultmarkattr)
   3. [`markBySelectorText`](#markbyselectortexttab-cssselector-textsubstring-exact--false-markattr--defaultmarkattr)
   4. [`markByButtonText`](#markbybuttontexttab-textsubstring-exact--false-markattr--defaultmarkattr)
   5. [`markFieldByLabel`](#markfieldbylabeltab-labeltext-markattr--defaultmarkattr)
   6. [`markFieldByAnyLabel`](#markfieldbyanylabeltab-labelcandidates-markattr--defaultmarkattr)
   7. [`markInputByAccept`](#markinputbyaccepttab-acceptsubstring-markattr--defaultmarkattr)
III. [Вывод для siteworker-сценариев](#вывод-для-siteworker-сценариев)
   1. [`vecho`](#vechopref-args)
   2. [`warnLoggedOut`](#warnloggedoutservice-hint)

---

## Типы

### `SiteWorkerError`

```nim
SiteWorkerError* = object of CatchableError
```

**Что это.** Общий тип ошибки для всех `siteworkers/*.nim` — поднимается, когда сценарий не может продолжить работу по причине, специфичной для домена сайт-автоматизации (истёкшая сессия, разлогинивание, не найден нужный элемент после всех попыток), а не из-за сбоя самого CDP-соединения (для этого есть `ChildTearError`/`CDPError` из `childtear.nim`).

### `SiteWorkerPref`

```nim
SiteWorkerPref* = enum
  pVisible, pVerbose, pDumpDebug, pNoScreenshot, pFullPage, pJpeg
```

**Что это.** Множество флагов-модификаторов поведения, общее для всех сценариев `siteworkers/*.nim`. Передаётся как `set[SiteWorkerPref]`, значение по умолчанию — пустое множество `{}` (headless, без побочного вывода). `pVisible` — не скрывать окно браузера; `pVerbose` — печатать прогресс через `vecho()`; `pDumpDebug` — сохранять скриншот+HTML+консоль при ошибке; `pNoScreenshot`/`pFullPage`/`pJpeg` — управляют скриншотом ответа в `AskResult` (см. `captureAnswerScreenshot()`).

### `ImageFormat`

```nim
ImageFormat* = enum
  ifPng, ifJpeg
```

**Что это.** Формат снимка экрана в `AskResult.screenshotFormat`. Определяет расширение файла, CDP-формат (`"png"`/`"jpeg"`) и MIME-тип, используемые функциями представления результата (`aiScreenshot2File`/`aiScreenshot2Clipboard` в [`siteworkers/clipboard.nim`](./clipboard_reference_ru.md)) через три маленькие вспомогательные функции: `extOf(format): string` (расширение файла без точки — `"png"`/`"jpg"`), `cdpFormatOf(format): string` (строка формата для `Page.captureScreenshot` — `"png"`/`"jpeg"`) и `mimeOf(format): string` (MIME-тип для буфера обмена — `"image/png"`/`"image/jpeg"`). Обычному коду, использующему готовые `askQwen()`/`askKimi()` и `ai*`-функции, вызывать их напрямую не требуется.

### `AskResult`

```nim
AskResult* = object
  text*: string
  screenshotData*: string
  screenshotFormat*: ImageFormat
  hasScreenshot*: bool
```

**Что это.** Результат запроса к AI-чату (`askQwen()`/`askKimi()`) — текст ответа плюс, если не был передан `pNoScreenshot`, его снимок экрана, полученный в той же сессии браузера сразу после стабилизации ответа. `hasScreenshot = false`, если скриншот не снимался (см. `pNoScreenshot`) — в этом случае `screenshotData` пуст, и передавать его в `aiScreenshot2File`/`aiScreenshot2Clipboard` не нужно.

---

## Поиск и пометка элементов по видимому тексту

Разметка большинства современных сайтов построена на нестабильных
между сборками CSS-классах (`css-xxxxx`), поэтому нужный элемент сначала
ищется по видимому тексту через `evalJS`, затем помечается временным
атрибутом (`DefaultMarkAttr` по умолчанию — `"data-ct-mark"`,
если сценарий не переопределяет `markAttr` своим), к которому уже можно
адресоваться обычным CSS-селектором вида `[markAttr]`.

### `pageHasText(tab, textSubstring)`

```nim
proc pageHasText*(tab: Tab, textSubstring: string): Future[bool] {.async.}
```

**Что делает.** Есть ли где-то на странице (в любом элементе) подстрока `textSubstring` без учёта регистра, включая не-ASCII текст (кириллицу и т.п.) — типовая проверка вида "открылось ли модальное окно с таким заголовком" / "появился ли текст об успехе".

### `unmark(tab, markAttr = DefaultMarkAttr)`

```nim
proc unmark*(tab: Tab, markAttr: string = DefaultMarkAttr) {.async.}
```

**Что делает.** Снимает `markAttr` со всех элементов страницы, где он есть, — вызывается автоматически в начале каждой `mark*()`-функции ниже; экспортирована на случай, если вызывающему коду нужно явно "забыть" предыдущую пометку самостоятельно (например, перед повторной попыткой по другому кандидату текста).

### `markBySelectorText(tab, cssSelector, textSubstring, exact = false, markAttr = DefaultMarkAttr)`

```nim
proc markBySelectorText*(tab: Tab, cssSelector: string, textSubstring: string,
                          exact = false, markAttr: string = DefaultMarkAttr): Future[bool] {.async.}
```

**Что делает.** Ищет первый элемент, подходящий под `cssSelector` (например, `'button, a, [role="button"]'`), чей видимый текст содержит (или, при `exact = true`, равен целиком) `textSubstring` без учёта регистра, и помечает его `markAttr`. Базовый примитив, на котором построены `markByButtonText()` и остальные `mark*()`-функции ниже.

### `markByButtonText(tab, textSubstring, exact = false, markAttr = DefaultMarkAttr)`

```nim
proc markByButtonText*(tab: Tab, textSubstring: string, exact = false,
                        markAttr: string = DefaultMarkAttr): Future[bool] {.async.}
```

**Что делает.** Частный случай `markBySelectorText()` для кнопок/ссылок (`'button, a, [role="button"]'`) — самый частый случай кликабельного элемента, адресуемого по тексту.

> В `siteworkers/redcircle.nim` есть отдельная функция `rcMarkByButtonText`
> с похожим назначением, но она помечает найденный элемент другим
> атрибутом (`RcMarkAttr`, не `DefaultMarkAttr`) и специально
> переименована (а не названа так же), чтобы её нельзя было случайно
> перепутать с этой при вызове с явным `markAttr` — см. комментарий над
> ней в исходном коде.

### `markFieldByLabel(tab, labelText, markAttr = DefaultMarkAttr)`

```nim
proc markFieldByLabel*(tab: Tab, labelText: string,
                        markAttr: string = DefaultMarkAttr): Future[bool] {.async.}
```

**Что делает.** Ищет "лист" (элемент без дочерних элементов) с видимым текстом, равным `labelText` без учёта регистра и завершающих `*`/`:`/пробелов (метки часто выглядят как `"Название*"`/`"Title:"`), затем среди всех `input`/`textarea`/`[contenteditable]` на странице оставляет только те, что идут ПОСЛЕ метки в порядке документа, и поднимается от метки вверх по родителям (до 5 уровней) в поисках ближайшего общего контейнера с одним из них. Помечает найденное поле `markAttr`. Возвращает `false`, если ничего не нашлось.

### `markFieldByAnyLabel(tab, labelCandidates, markAttr = DefaultMarkAttr)`

```nim
proc markFieldByAnyLabel*(tab: Tab, labelCandidates: seq[string],
                           markAttr: string = DefaultMarkAttr): Future[string] {.async.}
```

**Что делает.** Пробует `markFieldByLabel()` по очереди для каждого варианта метки из `labelCandidates` (например, `@["Название", "Заголовок", "Title"]` — на случай, если конкретная формулировка на сайте отличается от ожидаемой или сменится при обновлении интерфейса), и возвращает тот вариант, который сработал первым, либо `""`, если ни один не нашёлся.

**Параметры:** принимает `seq[string]`, а не `openArray[string]` — это async-процедура, и её состояние (включая аргумент) должно пережить `await` внутри, а `openArray` — лишь непостоянный вид на чужую память, не годный для захвата в замыкание.

### `markInputByAccept(tab, acceptSubstring, markAttr = DefaultMarkAttr)`

```nim
proc markInputByAccept*(tab: Tab, acceptSubstring: string,
                         markAttr: string = DefaultMarkAttr): Future[bool] {.async.}
```

**Что делает.** Ищет `<input type="file">` с атрибутом `accept`, содержащим `acceptSubstring` (например, `"audio"`) без учёта регистра, и помечает его `markAttr` — пригодится на страницах с несколькими дропзонами (например, аудио эпизода + обложка эпизода отдельно).

---

## Вывод для siteworker-сценариев

### `vecho(pref, args...)`

```nim
template vecho*(pref: set[SiteWorkerPref], args: varargs[string, `$`])
```

**Что делает.** Аналог `echo`, но печатает только если в `pref` установлен `pVerbose` — по умолчанию (без явного `pVerbose`) молчаливый: библиотека, в отличие от CLI-утилиты, не должна засорять stdout вызывающего по умолчанию.

### `warnLoggedOut(service, hint)`

```nim
proc warnLoggedOut*(service: string, hint: string)
```

**Что делает.** В отличие от `vecho()` — печатает безусловно, в stderr, независимо от `pVerbose`/`pref`. Факт разлогинивания сервиса (Qwen/Kimi/RedCircle/mave.digital) нельзя доверять только `vecho()` или тексту исключения, которое вызывающий код может залогировать в общем виде без деталей — а без ручного повторного входа все последующие вызовы будут проваливаться той же самой причиной, так что предупреждение должно быть гарантированно видно в терминале при любых настройках вызывающего кода. Вызывается в точке обнаружения (до/вместо `raise`), а не в общем `catch`.
