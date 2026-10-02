## siteworkers/siteworker_common.nim
##
## Общая инфраструктура для siteworkers/*.nim, не привязанная к одному
## сайту: типы ошибок, настроек и результата запроса к AI-чату, поиск и
## пометка элементов страницы по видимому тексту (устойчивая замена
## нестабильным CSS-классам).
##
## childtear.nim содержит только ядро CDP (Browser/Tab/Frame); сценарные
## помощники лежат здесь и в соседних ./browser_lifecycle.nim (запуск и
## переиспользование Chromium, gotoWithRetry, отладочные дампы) и
## ./clipboard.nim (скриншот ответа, представление результата AI-чата).

import std/[asyncdispatch, json, strutils, strformat, unicode]
import ../childtear

# -----------------------------------------------------------------
# Общие типы и вывод
# -----------------------------------------------------------------
#
# SiteWorkerError, SiteWorkerPref, ImageFormat, AskResult, условный вывод
# (vecho/warnLoggedOut) и поиск элементов по тексту (mark*). Модули сайтов
# (kimi, qwen, redcircle, mavedigital) содержат только селекторы и сценарий
# своего сайта.

type
  SiteWorkerError* = object of CatchableError
    ## Ошибки уровня этой библиотеки: не удалось авторизоваться, не
    ## нашёлся элемент для скриншота, не нашлась команда буфера обмена
    ## и т.п. Ошибки childtear (ChildTearError — не найден селектор,
    ## истёк таймаут ожидания) наружу пробрасываются как есть, без
    ## переоборачивания — оборачивать их в SiteWorkerError было бы просто
    ## лишним уровнем косвенности.

  SiteWorkerPref* = enum
    ## Флаги-модификаторы поведения askQwen()/askKimi(), передаются как
    ## множество, например {pVerbose, pVisible}. Пустое множество {} —
    ## поведение "как в headless-режиме исходных CLI-клиентов": без
    ## лишнего вывода в консоль, без сохранения debug-файлов на диск,
    ## со скриншотом блока ответа в PNG.
    pVisible
      ## Запускать Chromium в видимом (не headless) окне — полезно для
      ## отладки, когда неясно, на чём именно застрял сценарий.
    pVerbose
      ## Печатать в stdout построчный прогресс сценария askQwen()/
      ## askKimi() (см. vecho ниже).
    pDumpDebug
      ## Сохранять отладочные файлы (скриншот страницы, HTML, журнал
      ## консоли/сети — см. dumpDebugInfoVerbose) в контрольных точках
      ## сценария. По умолчанию ничего не пишется на диск ни при успехе, ни
      ## при ошибке, чтобы библиотека не копила debug-*.png/html/json в
      ## каталоге вызывающего. Независим от pVerbose: тот лишь печатает
      ## сводку по сохранённым файлам.
    pNoScreenshot
      ## Не снимать скриншот блока с ответом — быстрее, если из
      ## AskResult нужен только текст (aiScreenshot2File/2Clipboard на
      ## пустом screenshotData тогда закономерно упадут с ошибкой).
    pFullPage
      ## Снимать скриншот всей страницы вкладки целиком, а не только
      ## прямоугольника последнего сообщения ассистента.
    pJpeg
      ## Снимать скриншот в JPEG, а не в PNG по умолчанию (см. ImageFormat).

  ImageFormat* = enum
    ## Формат байтов в AskResult.screenshotData / аргументов
    ## aiScreenshot2File/aiScreenshot2Clipboard.
    ifPng
    ifJpeg

  AskResult* = object
    ## Результат одного обращения к askQwen()/askKimi().
    text*: string
      ## Текст последнего ответа ассистента, как получено со страницы
      ## (childtear.getLastText() — фактический innerText/textContent
      ## блока ответа, без дополнительной markdown-нормализации).
    screenshotData*: string
      ## Сырые байты скриншота (НЕ base64) в формате screenshotFormat.
      ## Пусто, если pNoScreenshot был среди переданных флагов.
    screenshotFormat*: ImageFormat
      ## Формат screenshotData. Значим, только пока hasScreenshot == true.
    hasScreenshot*: bool
      ## false <=> screenshotData не заполнялся (см. pNoScreenshot).


# ---------------------------------------------------------------------------
# Общие мелкие утилиты
# ---------------------------------------------------------------------------

template vecho*(pref: set[SiteWorkerPref], args: varargs[string, `$`]) =
  ## Аналог echo, но печатает, только если в pref установлен pVerbose —
  ## по умолчанию (без явного pVerbose) молчаливый: библиотека, в
  ## отличие от CLI-утилиты, не должна засорять stdout вызывающего
  ## по умолчанию.
  if pVerbose in pref:
    echo(args)

proc warnLoggedOut*(service: string, hint: string) =
  ## В отличие от vecho(), печатает безусловно и в stderr: разлогинивание
  ## сервиса (Qwen/Kimi/RedCircle) нельзя оставлять невидимым при
  ## выключенном pVerbose или обобщённом логе вызывающего кода, потому что
  ## без ручного входа все следующие вызовы провалятся по той же причине.
  ## Вызывается в точке обнаружения (до raise), а не в общем catch, чтобы
  ## предупреждение дошло до терминала, даже если исключение выше по стеку
  ## будет обработано тихо.
  stderr.writeLine("⚠ " & service & " разлогинен: " & hint)

proc warnSelectorMismatch*(service: string, brokenSelector: string, fixLocation: string,
                            candidates: seq[tuple[label: string, detail: string]]) =
  ## Диагностика устаревшего или переименованного селектора. Печатается
  ## безусловно в stderr (по той же причине, что warnLoggedOut()), с
  ## достаточной информацией, чтобы поправить код без похода на сайт: что
  ## искали (brokenSelector), где править (fixLocation — константа/proc и
  ## файл) и что реально нашлось на странице (candidates).
  ##
  ## candidates собирает модуль сайта через evalJS (например, все
  ## div[role="menuitem"] с текстом и иконками, см.
  ## qwenCollectAttachMenuCandidates()); процедура лишь форматирует
  ## готовый список и от разметки сайта не зависит.
  stderr.writeLine("⚠ " & service & ": похоже, устарел селектор — " & brokenSelector)
  stderr.writeLine("  Поправить в исходном коде: " & fixLocation)
  if len(candidates) == 0:
    stderr.writeLine("  На странице сейчас нет ни одного похожего элемента-кандидата " &
                      "(возможно, элемент вообще пропал из разметки, а не просто " &
                      "переименовался).")
  else:
    stderr.writeLine("  Вместо этого на странице сейчас есть (кандидаты на замену, " &
                      $len(candidates) & "):")
    for c in candidates:
      stderr.writeLine("    - " & c.label & (if len(c.detail) > 0: "  [" & c.detail & "]" else: ""))

proc extOf*(format: ImageFormat): string =
  ## Расширение файла без точки, соответствующее формату картинки.
  case format
  of ifPng: "png"
  of ifJpeg: "jpg"

proc cdpFormatOf*(format: ImageFormat): string =
  ## Строка формата, которую понимает Page.captureScreenshot (через
  ## childtear.screenshot*/screenshotElement*) — "png" или "jpeg".
  case format
  of ifPng: "png"
  of ifJpeg: "jpeg"

proc mimeOf*(format: ImageFormat): string =
  ## MIME-тип для передачи картинки в системный буфер обмена.
  case format
  of ifPng: "image/png"
  of ifJpeg: "image/jpeg"


# ---------------------------------------------------------------------------
# Поиск элементов по видимому тексту
# ---------------------------------------------------------------------------
#
# CSS-классы SPA (React/Vue) нестабильны между сборками ("css-xxxxx").
# Надёжнее найти элемент по видимому тексту (кнопки, метки поля) через
# evalJS, пометить временным атрибутом markAttr и дальше обращаться к нему
# обычным селектором ("[" & markAttr & "]"): click()/fill() тогда работают
# "по-настоящему" (координаты + Input.dispatchMouseEvent/insertText), а не
# синтетическим el.click() из JS.
#
# Исключение — rcMarkByButtonText() в redcircle.nim: она использует свой
# RcMarkAttr и намеренно названа иначе, чтобы вызов с явным markAttr не
# перепутался с markByButtonText() отсюда.

const
  DefaultMarkAttr* = "data-ct-mark"
    ## Атрибут по умолчанию для mark*() ниже. Вызывающий код может
    ## передать свой markAttr, если на одной странице нужно параллельно
    ## отслеживать несколько независимо помеченных элементов (иначе
    ## unmark() внутри следующего mark*() снял бы предыдущую пометку).

proc unmark*(tab: Tab, markAttr: string = DefaultMarkAttr) {.async.} =
  ## Снимает markAttr со всех элементов страницы, где он есть — чтобы
  ## перед новым поиском на странице остался максимум один помеченный
  ## им элемент. Вызывается автоматически в начале каждого mark*() ниже;
  ## экспортирован на случай, если вызывающему коду нужно явно "забыть"
  ## предыдущую пометку самостоятельно (например, перед повторной
  ## попыткой по другому кандидату текста).
  discard await evalJS(tab, &"""(function() {{
    var prev = document.querySelectorAll('[{markAttr}]');
    for (var i = 0; i < prev.length; i++) {{ prev[i].removeAttribute('{markAttr}'); }}
  }})()""")

proc pageHasText*(tab: Tab, textSubstring: string): Future[bool] {.async.} =
  ## Есть ли на странице подстрока textSubstring (без учёта регистра) —
  ## типовая проверка "открылось ли окно с таким заголовком" / "появился
  ## ли текст об успехе".
  ##
  ## needle приводится к нижнему регистру через unicode.toLower(), а не
  ## strutils.toLowerAscii(): последняя не трогает кириллицу, а JS-сторона
  ## сравнивает с document.body.textContent.toLowerCase(), которая
  ## обрабатывает и non-ASCII. Иначе indexOf() не находил бы такой текст
  ## даже при его наличии на странице.
  let needleLit = escapeJson(unicode.toLower(textSubstring))
  let js = &"""(function() {{
    var needle = {needleLit};
    return (document.body.textContent || '').toLowerCase().indexOf(needle) !== -1;
  }})()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc markBySelectorText*(tab: Tab, cssSelector: string, textSubstring: string,
                          exact = false, markAttr: string = DefaultMarkAttr): Future[bool] {.async.} =
  ## Ищет первый элемент, подходящий под cssSelector (например, 'button,
  ## a, [role="button"]' или '[role="option"], li'), чей видимый текст
  ## содержит (или, при exact=true, равен целиком) textSubstring без
  ## учёта регистра, и помечает его markAttr.
  await unmark(tab, markAttr)
  # unicode.toLower(), а не toLowerAscii() — см. пояснение в pageHasText()
  # выше про кириллицу и другой не-ASCII текст.
  let needleLit = escapeJson(unicode.toLower(strutils.strip(textSubstring)))
  let selLit = escapeJson(cssSelector)
  let markLit = escapeJson(markAttr)
  let exactLit = if exact: "true" else: "false"
  let js = &"""(function() {{
    var needle = {needleLit};
    var exact = {exactLit};
    var nodes = document.querySelectorAll({selLit});
    for (var i = 0; i < nodes.length; i++) {{
      var txt = (nodes[i].textContent || '').trim().toLowerCase();
      var hit = exact ? (txt === needle) : (txt.indexOf(needle) !== -1);
      if (hit) {{ nodes[i].setAttribute({markLit}, '1'); return true; }}
    }}
    return false;
  }})()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc markByButtonText*(tab: Tab, textSubstring: string, exact = false,
                        markAttr: string = DefaultMarkAttr): Future[bool] {.async.} =
  ## Частный случай markBySelectorText() для кнопок/ссылок
  ## ('button, a, [role="button"]') — самый частый случай кликабельного
  ## элемента, адресуемого по тексту.
  result = await markBySelectorText(tab, "button, a, [role=\"button\"]",
                                     textSubstring, exact, markAttr)

proc markFieldByLabel*(tab: Tab, labelText: string,
                        markAttr: string = DefaultMarkAttr): Future[bool] {.async.} =
  ## Находит "лист" (элемент без детей) с текстом labelText без учёта
  ## регистра и завершающих "*"/":"/пробелов (метки вида "Название*",
  ## "Title:"), затем среди input/textarea/[contenteditable], идущих ПОСЛЕ
  ## метки в порядке документа (иначе при похожих полях взялось бы поле
  ## другой метки), поднимается по родителям (до 5 уровней) к ближайшему
  ## общему контейнеру и помечает найденное поле markAttr. Возвращает
  ## false, если страница ещё не отрисована или текст метки другой.
  await unmark(tab, markAttr)
  # unicode.toLower(), а не toLowerAscii() — см. пояснение в pageHasText()
  # выше про кириллицу и другой не-ASCII текст.
  let needleLit = escapeJson(unicode.toLower(strutils.strip(labelText)))
  let markLit = escapeJson(markAttr)
  let js = &"""(function() {{
    var needle = {needleLit};
    var all = document.querySelectorAll('label, div, span, p, legend');
    var DOCUMENT_POSITION_FOLLOWING = 4;
    for (var i = 0; i < all.length; i++) {{
      var el = all[i];
      if (el.children.length > 0) continue;
      var txt = (el.textContent || '').trim().toLowerCase().replace(/[\*:\s]+$/, '').trim();
      if (txt !== needle) continue;

      var fields = document.querySelectorAll('input, textarea, [contenteditable="true"]');
      var after = [];
      for (var f = 0; f < fields.length; f++) {{
        var pos = el.compareDocumentPosition(fields[f]);
        if (pos & DOCUMENT_POSITION_FOLLOWING) {{ after.push(fields[f]); }}
      }}
      if (after.length === 0) continue;

      var container = el.parentElement;
      for (var hop = 0; hop < 5 && container; hop++) {{
        var candidate = null;
        for (var j = 0; j < after.length; j++) {{
          if (container.contains(after[j])) {{ candidate = after[j]; break; }}
        }}
        if (candidate) {{ candidate.setAttribute({markLit}, '1'); return true; }}
        container = container.parentElement;
      }}
    }}
    return false;
  }})()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc markFieldByAnyLabel*(tab: Tab, labelCandidates: seq[string],
                           markAttr: string = DefaultMarkAttr): Future[string] {.async.} =
  ## Пробует markFieldByLabel() по очереди для каждой метки из
  ## labelCandidates (например, @["Название", "Заголовок", "Title"] — на
  ## случай другой или сменившейся формулировки) и возвращает сработавшую
  ## метку либо "", если не нашлась ни одна.
  ##
  ## Параметр seq[string], а не openArray[string]: процедура async, её
  ## замыкание должно пережить await, а openArray — временный вид на чужую
  ## память и не может быть в нём захвачен ("cannot be captured as it would
  ## violate memory safety").
  for candidate in labelCandidates:
    if await markFieldByLabel(tab, candidate, markAttr):
      return candidate
  result = ""

proc markInputByAccept*(tab: Tab, acceptSubstring: string,
                         markAttr: string = DefaultMarkAttr): Future[bool] {.async.} =
  ## Ищет <input type="file"> с атрибутом accept, содержащим
  ## acceptSubstring (например, "audio") без учёта регистра, и помечает
  ## его markAttr — пригодится на страницах с несколькими дропзонами
  ## (например, аудио эпизода + обложка эпизода отдельно).
  await unmark(tab, markAttr)
  let needleLit = escapeJson(toLowerAscii(acceptSubstring))
  let markLit = escapeJson(markAttr)
  let js = &"""(function() {{
    var needle = {needleLit};
    var inputs = document.querySelectorAll('input[type="file"]');
    for (var i = 0; i < inputs.length; i++) {{
      var accept = (inputs[i].getAttribute('accept') || '').toLowerCase();
      if (accept.indexOf(needle) !== -1) {{ inputs[i].setAttribute({markLit}, '1'); return true; }}
    }}
    return false;
  }})()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)


