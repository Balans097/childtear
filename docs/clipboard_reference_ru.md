# siteworkers/clipboard — справочник скриншота ответа и буфера обмена

> **Импорт:** `import siteworkers/clipboard`

> **Область применения:** снимок последнего сообщения ассистента для чат-сценариев (`captureAnswerScreenshot`) и работа с системным буфером обмена через внешние утилиты командной строки (`wl-copy`/`xclip`). Не имеет отношения к CDP/childtear-ядру как таковому — выделено из `childtear.nim` при разделении на модули по слоям ответственности, см. [README.md](../README.md#архитектура). Опирается на типы из [`siteworker_common_reference_ru.md`](./siteworker_common_reference_ru.md) (`ImageFormat`, `SiteWorkerPref`).
>
> Функции представления результата чат-сценариев (`aiText2File`, `aiText2Clipboard`, `aiScreenshot2File`, `aiScreenshot2Clipboard`) документированы в [`siteworker_reference_ru.md`](./siteworker_reference_ru.md) вместе с остальным публичным API `askQwen()`/`askKimi()`, хотя физически определены в этом же файле (`cdp/clipboard.nim`).

---

## Оглавление

1. [`captureAnswerScreenshot`](#captureanswerscreenshottab-lastmessageselector-pref)

---

### `captureAnswerScreenshot(tab, lastMessageSelector, pref)`

```nim
proc captureAnswerScreenshot*(tab: Tab, lastMessageSelector: string,
                               pref: set[SiteWorkerPref]): Future[tuple[data: string, format: ImageFormat, has: bool]] {.async.}
```

**Что делает.** Общая точка входа для `askQwen()`/`askKimi()`: снимает скриншот ответа согласно `pref` (`pNoScreenshot`/`pFullPage`/`pJpeg`) сразу после того, как текст ответа стабилизировался, пока вкладка ещё открыта. Возвращает пустой `data` и `has = false`, если был передан `pNoScreenshot`.
