# siteworkers — справочник общей инфраструктуры и чат-сценариев

Описание общих типов siteworker-инфраструктуры (`SiteWorkerPref`,
`ImageFormat`, `AskResult`, `SiteWorkerError` — физически определены в
[`siteworkers/siteworker_common.nim`](../siteworkers/siteworker_common.nim), см.
[справочник этого модуля](./siteworker_common_reference_ru.md)) и публичного API
двух чат-сценариев — `siteworkers/qwen.nim` (`askQwen()`) и
`siteworkers/kimi.nim` (`askKimi()`): отправить промпт в веб-чат Qwen
или Kimi и получить ответ текстом и/или скриншотом.

Два других готовых сценария — `siteworkers/redcircle.nim`
(`uploadToRedcircle()`) и `siteworkers/mavedigital.nim`
(`uploadToMave()`), публикация эпизода подкаста — документированы
непосредственно в исходном коде каждого модуля (заголовок файла +
комментарий к каждой экспортируемой функции), а не в этом справочнике.

Если вы ищете высокоуровневый API самого браузера (клики, селекторы,
скриншоты произвольных элементов и т.д.) — он не здесь, а в
[`childtear_reference_ru.md`](./childtear_reference_ru.md): ни один из
`siteworkers/*.nim` не обращается к протоколу CDP напрямую и ничего не
добавляет к управлению страницей в обход childtear.

---

## Содержание

- [Быстрый пример](#быстрый-пример)
- [Авторизация](#авторизация)
- [Типы](#типы)
  - [SiteWorkerPref](#siteworkerpref)
  - [ImageFormat](#imageformat)
  - [AskResult](#askresult)
  - [SiteWorkerError](#siteworkererror)
- [Запросы к чат-сервисам](#запросы-к-чат-сервисам)
  - [askQwen](#askqwenprompt-files--askresult)
  - [askKimi](#askkimiprompt-files--askresult)
- [Представление результата](#представление-результата)
  - [aiText2File](#aitext2filetext-file)
  - [aiText2Clipboard](#aitext2clipboardtext)
  - [aiScreenshot2File](#aiscreenshot2fileimage-file-format--ifpng)
  - [aiScreenshot2Clipboard](#aiscreenshot2clipboardimage-format--ifpng)
- [Обработка ошибок](#обработка-ошибок)
- [Параллельный вызов askQwen/askKimi](#параллельный-вызов-askqwenaskkimi)

---

## Быстрый пример

```nim
import std/asyncdispatch
import siteworkers/qwen
import siteworkers/kimi

proc main() {.async.} =
  let answer = await askQwen("Сформулируй план на неделю")
  aiText2File(answer.text, "план.txt")

  let withFile = await askKimi("Резюмируй документ", @["/путь/к/файлу.pdf"],
                                pref = {pVerbose})
  aiScreenshot2File(withFile.screenshotData, "резюме", withFile.screenshotFormat)

waitFor main()
```

## Авторизация

`askQwen()`/`askKimi()` сами не умеют логиниться — они переиспользуют уже
сохранённый на диске профиль Chromium, причём смотрят в те же самые
каталоги, что и CLI-инструменты `qwenclient`/`kimiclient`:

| Сайт | Каталог профиля |
|---|---|
| Qwen (chat.qwen.ai) | `~/.cache/qwenclient/profile` |
| Kimi (www.kimi.com) | `~/.cache/kimiclient/profile` |

Если `qwenclient setup` / `kimiclient setup` уже когда-то выполнялись,
siteworker сразу окажется авторизован без отдельного шага настройки. Если
профиля ещё нет или сессия истекла — `askQwen()`/`askKimi()` упадут с
`SiteWorkerError`, в тексте которой прямо названа нужная команда `setup`.

Сама библиотека переиспользует процесс Chromium между вызовами вместо
того, чтобы поднимать новый на каждый запрос: `askQwen()`/`askKimi()`
вызывают `browser_lifecycle.ensureBrowser()`, который либо подключается к уже
отвечающему на отладочном порту сайта (9223 для Qwen, 9224 для Kimi)
процессу, либо запускает новый и оставляет его работать дальше. По
завершении вызова (в том числе при ошибке) закрывается только своя
вкладка — сам процесс браузера не останавливается ни при успехе, ни при
ошибке. Остановить его явно можно через `browser_lifecycle.stopBrowser(port)`.

## Типы

### SiteWorkerPref

```nim
SiteWorkerPref* = enum
  pVisible, pVerbose, pDumpDebug, pNoScreenshot, pFullPage, pJpeg
```

Флаги-модификаторы поведения `askQwen()`/`askKimi()`, передаются
множеством, например `{pVerbose, pVisible}`. Пустое множество `{}` —
поведение по умолчанию: headless, без консольного вывода, без
отладочных файлов на диске, со скриншотом блока ответа в PNG.

| Флаг | Действие |
|---|---|
| `pVisible` | Запускать Chromium в видимом (не headless) окне — для отладки сценария. |
| `pVerbose` | Печатать в stdout построчный прогресс выполнения. |
| `pDumpDebug` | Сохранять отладочные файлы (полный скриншот, HTML, консольный/сетевой журнал) в контрольных точках сценария и при финальном сбое. Без флага не пишется ничего — ни при успехе, ни при ошибке. |
| `pNoScreenshot` | Не снимать скриншот блока с ответом — быстрее, если из `AskResult` нужен только текст. `aiScreenshot2File`/`aiScreenshot2Clipboard` на пустом `screenshotData` в этом случае закономерно упадут. |
| `pFullPage` | Снимать скриншот всей страницы вкладки целиком, а не только прямоугольника последнего сообщения ассистента. |
| `pJpeg` | Снимать скриншот в JPEG, а не в PNG по умолчанию. |

`pVerbose` и `pDumpDebug` независимы друг от друга: первый решает, печатать
ли в stdout сводку по уже сохранённым файлам, второй — сохранять ли их
вообще.

### ImageFormat

```nim
ImageFormat* = enum
  ifPng, ifJpeg
```

Формат байтов в `AskResult.screenshotData` и одноимённых аргументах
`aiScreenshot2File`/`aiScreenshot2Clipboard`.

### AskResult

```nim
AskResult* = object
  text*: string
  screenshotData*: string
  screenshotFormat*: ImageFormat
  hasScreenshot*: bool
```

Результат одного обращения к `askQwen()`/`askKimi()`.

| Поле | Значение |
|---|---|
| `text` | Текст последнего ответа ассистента как есть со страницы (фактический `innerText`/`textContent` блока ответа, без markdown-нормализации). |
| `screenshotData` | Сырые байты скриншота (**не** base64) в формате `screenshotFormat`. Пусто, если среди `pref` был `pNoScreenshot`. |
| `screenshotFormat` | Формат `screenshotData`. Значим, только пока `hasScreenshot == true`. |
| `hasScreenshot` | `false` ⟺ `screenshotData` не заполнялся (см. `pNoScreenshot`). |

### SiteWorkerError

```nim
SiteWorkerError* = object of CatchableError
```

Ошибки уровня самой библиотеки: не удалось авторизоваться, не нашёлся
элемент для скриншота, не нашлась команда буфера обмена и т.п.

Ошибки `childtear` (`ChildTearError` — не найден селектор, истёк таймаут
ожидания) пробрасываются наружу как есть, без переоборачивания в
`SiteWorkerError` — так что `except CatchableError` на стороне вызывающего
кода ловит оба вида ошибок одинаково, а `except SiteWorkerError` /
`except ChildTearError` по отдельности позволяют различить, была ли причина
в самом сайте (селекторы устарели, таймаут) или в организации сценария
(не авторизован, файл не найден, нет команды буфера обмена).

## Запросы к чат-сервисам

### `askQwen(prompt, files = @[], pref = {}): AskResult`

```nim
proc askQwen*(prompt: string, files: seq[string] = @[],
              pref: set[SiteWorkerPref] = {}): Future[AskResult] {.async.}
```

Отправляет `prompt` (при необходимости — с приложенными `files`) в
chat.qwen.ai и возвращает `AskResult` с текстом ответа и (если не задан
`pNoScreenshot`) скриншотом блока с ответом.

- `prompt` не должен быть пустым (после `strip()`) — иначе `ValueError`.
- Каждый путь в `files` должен существовать на диске к моменту вызова —
  иначе `IOError`; пути передаются как абсолютные (см. `absolutePath()`).
- При нескольких файлах все они прикрепляются одним вложением.
- Если Qwen-сессия не авторизована — `SiteWorkerError` с указанием
  выполнить `qwenclient setup`.
- Если разметка сайта разошлась с зашитыми селекторами (устарел
  `QwenPromptInputSelector`/`QwenSendButtonSelector`/
  `QwenLastAssistantMessageSelector` и т.п.) — `ChildTearError` с описанием,
  на каком именно шаге и с каким признаком не сошлось ожидание.

### `askKimi(prompt, files = @[], pref = {}): AskResult`

```nim
proc askKimi*(prompt: string, files: seq[string] = @[],
              pref: set[SiteWorkerPref] = {}): Future[AskResult] {.async.}
```

То же самое, но для www.kimi.com — с профилем `~/.cache/kimiclient/profile`
и сообщением `kimiclient setup` в ошибке авторизации. Отличия в
устройстве от `askQwen()` — только в деталях протокола конкретного сайта
(поле ввода — `contenteditable`-div, а не `<textarea>`; ожидание ответа
следит дополнительно за "пульсом" ещё не раскрытого блока "Обдумывание");
для вызывающего кода сигнатура и семантика полностью симметричны `askQwen()`.

## Представление результата

Все четыре функции ниже принимают "сырые" данные (`string` с текстом или
`string` с байтами картинки), а не сам `AskResult` целиком — это позволяет
использовать их отдельно от `askQwen`/`askKimi`, например для текста или
скриншота из какого-то другого источника.

### `aiText2File(text, file)`

Сохраняет текст ответа (`AskResult.text`) в текстовый файл `file`.

### `aiText2Clipboard(text)`

Копирует текст ответа в системный буфер обмена (`wl-copy`, с откатом на
`xclip` для X11).

### `aiScreenshot2File(image, file, format = ifPng)`

Сохраняет байты скриншота (`AskResult.screenshotData`) в файл `file`.
`format` ничего не конвертирует (байты уже в том формате, в котором были
сняты — см. `AskResult.screenshotFormat`) — используется только чтобы
дописать расширение к `file`, если оно ещё не указано: например,
`aiScreenshot2File(r.screenshotData, "ответ", r.screenshotFormat)` сохранит
`ответ.png` или `ответ.jpg`.

### `aiScreenshot2Clipboard(image, format = ifPng)`

Копирует байты скриншота в системный буфер обмена как картинку
соответствующего MIME-типа (`image/png`/`image/jpeg`) — большинство
приложений (мессенджеры, редакторы) вставляют её как изображение, а не
как текст.

## Обработка ошибок

```nim
try:
  let r = await askQwen("...")
except SiteWorkerError as e:
  # не авторизован, файл вложения не найден, нет wl-copy/xclip и т.п.
  echo "организационная ошибка: ", e.msg
except ChildTearError as e:
  # сайт не откликнулся так, как ожидалось (устаревший селектор, таймаут)
  echo "сайт повёл себя не так, как ожидалось: ", e.msg
```

При `pDumpDebug` в `pref` любой сбой внутри `askQwen()`/`askKimi()`
(включая исключения `childtear`) сначала сохраняет `debug-ask.png` /
`debug-ask.html` / `debug-ask-console.json` в текущий рабочий каталог, и
уже затем пробрасывает исходную ошибку дальше — так что причину обычно
можно установить постфактум, не переигрывая сценарий заново с `pVisible`.

## Параллельный вызов askQwen/askKimi

Qwen и Kimi используют разные отладочные порты (9223 и 9224 против общего
9222 у CLI-инструментов), поэтому их можно запускать даже одновременно:

```nim
import std/asyncdispatch
import siteworkers/qwen
import siteworkers/kimi

proc compare(prompt: string): Future[(AskResult, AskResult)] {.async.} =
  let
    qwenFut = askQwen(prompt)
    kimiFut = askKimi(prompt)
  result = (await qwenFut, await kimiFut)

let (qwenAnswer, kimiAnswer) = waitFor compare("Сформулируй план на неделю")
```

Два вызова с одним и тем же сайтом (например, два параллельных `askQwen()`)
при этом всё равно будут конкурировать за один и тот же порт и один и тот
же профиль браузера — параллелизм рассчитан на разные сайты, а не на
несколько одновременных запросов к одному.
