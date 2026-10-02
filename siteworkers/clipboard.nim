## siteworkers/clipboard.nim
##
## Скриншот последнего сообщения ассистента и работа с системным буфером
## обмена через внешние утилиты (wl-copy/xclip). К ядру CDP не относится:
## общая инфраструктура сценариев, как ./siteworker_common.nim (типы) и
## ./browser_lifecycle.nim (запуск Chromium).

import std/[asyncdispatch, os, osproc, json, strformat, strutils, times, streams]
import ../childtear
import ./siteworker_common

# ---------------------------------------------------------------------------
# Скриншот последнего сообщения ассистента
# ---------------------------------------------------------------------------
#
# childtear.screenshotElement() снимает первый элемент по CSS-селектору
# (document.querySelector), а нужен последний (последняя реплика
# ассистента). Поэтому последний подходящий элемент временно помечается
# уникальным data-атрибутом через evalJS(), screenshotElement() снимает
# его по этому атрибуту, затем атрибут снимается.

const ScreenshotMarkAttr = "data-siteworker-shot"

var tempFileCounter = 0
  ## Монотонный счётчик для уникальности имён временных файлов
  ## скриншотов (см. ниже) — проще и не требует std/random, а
  ## коллизий не бывает: все вызовы идут последовательно в рамках
  ## одного asyncdispatch-цикла.

proc nextTempScreenshotPath(format: ImageFormat): string =
  ## Путь к новому временному файлу скриншота с уникальным именем
  ## (см. tempFileCounter выше) и расширением, соответствующим format.
  inc(tempFileCounter)
  result = getTempDir() / &"siteworker-shot-{epochTime().int64}-{tempFileCounter}.{extOf(format)}"

proc screenshotLastMatchBytes(tab: Tab, selector: string,
                               format: ImageFormat): Future[string] {.async.} =
  ## См. пояснение к разделу выше. Возвращает сырые байты картинки.
  let
    sel = escapeJson(selector)
    markJs = &"""(function() {{
    var prevMarked = document.querySelectorAll('[{ScreenshotMarkAttr}]');
    for (var i = 0; i < prevMarked.length; i++) {{
      prevMarked[i].removeAttribute('{ScreenshotMarkAttr}');
    }}
    var els = document.querySelectorAll({sel});
    if (els.length === 0) return false;
    var el = els[els.length - 1];
    el.setAttribute('{ScreenshotMarkAttr}', '1');
    el.scrollIntoView({{block: 'center', inline: 'nearest'}});
    return true;
  }})()"""
  let marked = await evalJS(tab, markJs)
  if marked.kind != JBool or not getBool(marked):
    raise newException(SiteWorkerError,
      &"не удалось найти элемент для скриншота по селектору: {selector}")

  # childtear.screenshotElement() пишет результат сразу в файл — публичный
  # API не предоставляет варианта, возвращающего байты напрямую в память.
  # Снимаем во временный файл и тут же читаем его обратно, после чего
  # временный файл удаляется.
  let tmpPath = nextTempScreenshotPath(format)
  await screenshotElement(tab, "[" & ScreenshotMarkAttr & "]", tmpPath, format = cdpFormatOf(format))
  try:
    result = readFile(tmpPath)
  finally:
    if fileExists(tmpPath):
      removeFile(tmpPath)

  # Атрибут-маркер не обязателен к уборке (следующий вызов сам вычищает
  # старые пометки в начале markJs), но лучше не оставлять его в DOM
  # дольше, чем нужно — вдруг сайт сам на него как-то отреагирует.
  discard await evalJS(tab, &"""(function() {{
    var el = document.querySelector('[{ScreenshotMarkAttr}]');
    if (el) el.removeAttribute('{ScreenshotMarkAttr}');
  }})()""")

proc captureAnswerScreenshot*(tab: Tab, lastMessageSelector: string,
                               pref: set[SiteWorkerPref]): Future[tuple[data: string, format: ImageFormat, has: bool]] {.async.} =
  ## Общая точка входа для askQwen()/askKimi(): снимает скриншот ответа
  ## согласно pref (pNoScreenshot/pFullPage/pJpeg) сразу после того, как
  ## текст ответа стабилизировался — пока вкладка ещё открыта.
  if pNoScreenshot in pref:
    return ("", ifPng, false)

  let format = if pJpeg in pref: ifJpeg else: ifPng
  vecho(pref, "Снимаю скриншот ответа...")

  if pFullPage in pref:
    let tmpPath = nextTempScreenshotPath(format)
    await screenshot(tab, tmpPath, format = cdpFormatOf(format), fullPage = true)
    let data =
      try: readFile(tmpPath)
      finally: (if fileExists(tmpPath): removeFile(tmpPath))
    return (data, format, true)

  let data = await screenshotLastMatchBytes(tab, lastMessageSelector, format)
  result = (data, format, true)



# ===========================================================================
# Буфер обмена
# ===========================================================================
#
# Работа через внешние утилиты командной строки, CDP не используется.
# Приоритет у wl-copy (пакет wl-clipboard, Wayland), запасной вариант —
# xclip (X11).

proc findClipboardCmd(): tuple[cmd: string, isWlCopy: bool] =
  ## Ищет в PATH wl-copy (приоритет — см. пояснение к разделу выше),
  ## затем xclip; исключение, если не найдено ни одного.
  let wlCopy = findExe("wl-copy")
  if len(wlCopy) > 0:
    return (wlCopy, true)
  let xclip = findExe("xclip")
  if len(xclip) > 0:
    return (xclip, false)
  raise newException(SiteWorkerError,
    "не найдено ни wl-copy, ни xclip в PATH — установите один из них, " &
    "чтобы пользоваться aiText2Clipboard/aiScreenshot2Clipboard " &
    "(на Fedora/GNOME/Wayland: sudo dnf install wl-clipboard)")

proc runClipboardPipe(cmd: string, args: seq[string], data: string) =
  ## Запускает cmd с args, передаёт data в его stdin и дожидается
  ## завершения. Общая часть copyTextToClipboard()/copyBytesToClipboard().
  var process = startProcess(cmd, args = args, options = {poUsePath})
  let stdinStream = inputStream(process)
  write(stdinStream, data)
  close(stdinStream)
  let code = waitForExit(process)
  close(process)
  if code != 0:
    raise newException(SiteWorkerError,
      &"команда буфера обмена завершилась с кодом {code}: {cmd} {join(args, \" \")}")

proc copyTextToClipboard(text: string) =
  ## Копирует text в системный буфер обмена как обычный текст
  ## (через wl-copy/xclip, см. findClipboardCmd()).
  let (cmd, isWlCopy) = findClipboardCmd()
  let args = if isWlCopy: newSeq[string]() else: @["-selection", "clipboard"]
  runClipboardPipe(cmd, args, text)

proc copyBytesToClipboard(data: string, mime: string) =
  ## Копирует бинарные data (например, PNG-скриншот) в буфер обмена с
  ## указанием MIME-типа mime, чтобы приложения-получатели (редакторы,
  ## мессенджеры) распознали содержимое как изображение, а не текст.
  let (cmd, isWlCopy) = findClipboardCmd()
  let args =
    if isWlCopy: @["--type", mime]
    else: @["-selection", "clipboard", "-t", mime]
  runClipboardPipe(cmd, args, data)




# ===========================================================================
# Представление результата: файл / буфер обмена × текст / скриншот
# ===========================================================================

proc aiText2File*(text: string, file: string) =
  ## Сохраняет текст ответа (AskResult.text) в текстовый файл file.
  writeFile(file, text)

proc aiText2Clipboard*(text: string) =
  ## Копирует текст ответа (AskResult.text) в системный буфер обмена.
  copyTextToClipboard(text)

proc aiScreenshot2File*(image: string, file: string, format = ifPng) =
  ## Сохраняет байты скриншота (AskResult.screenshotData) в файл file.
  ## format ничего не конвертирует (байты уже в снятом формате, см.
  ## AskResult.screenshotFormat), а лишь дописывает расширение к file, если
  ## его нет: aiScreenshot2File(r.screenshotData, "ответ", r.screenshotFormat)
  ## сохранит "ответ.png" или "ответ.jpg".
  let finalPath =
    if len(splitFile(file).ext) == 0: file & "." & extOf(format)
    else: file
  writeFile(finalPath, image)

proc aiScreenshot2Clipboard*(image: string, format = ifPng) =
  ## Копирует байты скриншота (AskResult.screenshotData) в системный
  ## буфер обмена как картинку соответствующего MIME-типа — большинство
  ## приложений (мессенджеры, редакторы) тогда вставляют его как
  ## изображение, а не как текст.
  copyBytesToClipboard(image, mimeOf(format))
