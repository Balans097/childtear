## siteworkers/redcircle.nim
##
## Автоматизация загрузки эпизода подкаста на https://app.redcircle.com
## поверх childtear: открыть список эпизодов шоу, нажать "New Episode",
## заполнить заголовок и описание, прикрепить аудио, опубликовать (или
## сохранить черновик).
##
##   import siteworkers/redcircle
##   waitFor uploadToRedcircle("Название", "Описание", "Файл.mp3")
##
## Chromium запускается один раз с постоянным профилем и переиспользуется
## между вызовами (browser_lifecycle.ensureBrowser()/stopBrowser()).
## Логиниться модуль не умеет: используется сохранённый профиль
## (~/.cache/redcircleclient/profile), первичный вход выполняется вручную
## в Chromium с тем же --user-data-dir.
##
## Экспортированы также шаги сценария для внешних CLI-инструментов
## (вход, подбор селекторов, диагностика showId): RedcircleShowId,
## ProfileDir, DebugPort, ShowsListUrl, NewEpisodeButtonText,
## FieldTimeoutMs, rcMarkByButtonText(), verifyShowId(), clickShowLink(),
## openEpisodesPageForShow().
##
## Классы разметки сайта ("css-xxxxx") нестабильны между сборками, поэтому
## элементы ищутся по видимому тексту метки/кнопки через evalJS и
## помечаются атрибутом data-rc-mark, к которому затем обращаются
## селектором "[data-rc-mark]". Предположение: ближайший к метке
## "Title"/"Description" input/textarea/[contenteditable] — нужное поле,
## а ближайший к тексту "Publish"/"Save as Draft" узел — сама кнопка. Если
## оно нарушится, поправьте markByLabel()/rcMarkByButtonText() или
## константы-селекторы.




import std/[os, strutils, strformat, asyncdispatch, json, times, sequtils, unicode]
import ../childtear
import ./siteworker_common
import ./browser_lifecycle




# ---------------------------------------------------------------------------
# Ошибки модуля
# ---------------------------------------------------------------------------
#
# Используется общий SiteWorkerError из ./siteworker_common.nim; ошибки
# childtear (ChildTearError) пробрасываются как есть.


const
  RedcircleBaseUrl = "https://app.redcircle.com"

  RedcircleShowId* = "bbd2d699-b4ba-4b55-bb47-4cb6e44936ed"
    ## Взято из скриншота списка эпизодов ("АНАЛИТИКА и НОВОСТИ"). Если
    ## нужно грузить в другое шоу — переопределяется аргументом showId в
    ## uploadToRedcircle(). Экспортирован для внешних CLI-обёрток, чтобы
    ## они могли использовать то же значение по умолчанию, не дублируя его.

  NewEpisodeButtonText* = "New Episode"
    ## Экспортирован для внешних CLI-инструментов (проверка наличия
    ## кнопки — та же, что и в реальном сценарии, см. rcMarkByButtonText()
    ## ниже).
  CreateEpisodeHeaderText = "Create Episode"
  TitleFieldLabel = "Title"
  DescriptionFieldLabel = "Description"
  UploadContentLabel = "Upload Content"
    ## Текст блока-метки над дропзоной файла (на скриншоте — "UPLOAD
    ## CONTENT*"); поиск метки регистронезависимый и без учёта "*", см.
    ## findFieldByLabel().
  UploadFileButtonText = "Upload File"
  PublishButtonText = "Publish"
  SaveDraftButtonText = "Save as Draft"
  PublishDateFieldLabel = "Publish Date"
    ## При открытии окна "Create Episode" поле может уже содержать время
    ## на несколько минут впереди текущего: приложение считает значение
    ## по умолчанию раз в сессию, а Chromium переиспользуется между
    ## эпизодами. С таким значением "Publish" лишь планирует эпизод
    ## ("Draft, To Publish on <дата>"), и он не попадает в RSS. Поэтому
    ## дату выставляют явно (setPublishDateToNow()), а результат проверяют
    ## в submitEpisode(): закрытие окна и смена URL одинаковы и при
    ## публикации, и при планировании.
  PublishDateSafetyMarginMin = 2
    ## На сколько минут в прошлое сдвигается значение "Publish Date": запас
    ## на рассинхронизацию часов и на время до обработки клика сервером,
    ## чтобы дата не оказалась в будущем с точки зрения сервера.

  RcMarkAttr = "data-rc-mark"
    ## Временный атрибут-метка для приёма "найти по тексту -> пометить ->
    ## адресоваться как к обычному CSS-селектору" (см. пояснение в шапке
    ## файла и markByLabel()/rcMarkByButtonText() ниже).
  RcMarkSelector = "[" & RcMarkAttr & "]"

  ModalTimeoutMs = 20_000
    ## Ожидание появления модального окна "Create Episode" после клика
    ## по "New Episode".
  FieldTimeoutMs* = 10_000
    ## Ожидание появления полей Title/Description/Upload Content внутри
    ## уже открытого модального окна. Экспортирован — та же величина
    ## пригодна внешним CLI-инструментам для ожидания кнопки
    ## 'New Episode'.
  ContentAckTimeoutMs = 60_000
    ## Ожидание появления на странице признака "файл принят" (например,
    ## его имени рядом с дропзоной) после назначения файла инпуту —
    ## для больших аудиофайлов может занимать время.
  ProcessingOverlayTexts = ["uploading episode", "processing your episode"]
    ## Текст модального окна, которое сайт показывает после Publish/Save as
    ## Draft, пока загружает и обрабатывает аудио (настоящая загрузка
    ## идёт здесь, а не при выборе файла). См. submitEpisode().
  PublishConfirmTimeoutMs = 300_000
    ## Ожидание подтверждения публикации после закрытия окна обработки:
    ## появление заголовка эпизода или смена URL на страницу эпизода (см.
    ## submitEpisode()). Файл уже загружен, поэтому 5 минут — запас на
    ## серверную пост-обработку.
  UploadStallTimeoutMs = 180_000
    ## Сколько ждать без роста процента в оверлее "Uploading your
    ## episode's file... N%" (getUploadProgressPercent), прежде чем считать
    ## загрузку зависшей. Крупные файлы грузятся дольше 10 минут при
    ## растущем проценте, поэтому ограничивается отсутствие прогресса, а
    ## не общее время. Не путать с PublishConfirmTimeoutMs.
  UploadAbsoluteMaxMs = 45 * 60_000
    ## Абсолютный потолок ожидания загрузки (45 минут), даже если процент
    ## изредка растёт: защита от бесконечно "живого" прогресс-бара. В норме
    ## не срабатывает (медленные загрузки укладываются в минуты).


  DebugPort* = 9225
    ## Порт отладки, отдельный от Qwen и Kimi (QwenDebugPort, KimiDebugPort),
    ## чтобы их профили и вкладки не пересекались. Экспортирован: внешние
    ## CLI-инструменты подключаются к тому же Chromium через
    ## ensureBrowser()/stopBrowser(), а не запускают свой процесс.
  ProfileDir* = getHomeDir() / ".cache" / "redcircleclient" / "profile"
    ## См. пояснение про авторизацию в шапке файла. Экспортирован по той
    ## же причине, что и DebugPort.


# ---------------------------------------------------------------------------
# Поиск элементов по видимому тексту метки/кнопки (см. пояснение в шапке)
# ---------------------------------------------------------------------------

proc unmarkAll(tab: Tab) {.async.} =
  ## Снимает предыдущую метку (если была) — чтобы на странице всегда был
  ## максимум один элемент, помеченный RcMarkAttr.
  discard await evalJS(tab, &"""(function() {{
    var prev = document.querySelectorAll('[{RcMarkAttr}]');
    for (var i = 0; i < prev.length; i++) {{ prev[i].removeAttribute('{RcMarkAttr}'); }}
  }})()""")

proc markByLabel(tab: Tab, labelText: string): Future[bool] {.async.} =
  ## Находит "лист" (элемент без детей) с текстом labelText (без учёта
  ## регистра и завершающей "*": на странице "TITLE*"/"DESCRIPTION*"),
  ## затем среди input/textarea/[contenteditable], идущих ПОСЛЕ метки в
  ## порядке документа (compareDocumentPosition), поднимается по
  ## родителям (до 5 уровней) к ближайшему общему контейнеру и помечает
  ## найденное поле RcMarkAttr. Условие "после метки" нужно, чтобы в
  ## общем предке Title и Description не взять поле соседней метки.
  ## Возвращает false, если страница ещё не отрисована или текст метки другой.
  await unmarkAll(tab)
  # unicode.toLower(), не toLowerAscii() — та же кириллическая ловушка,
  # что в siteworker_common.pageHasText() (см. её комментарий): JS ниже сравнивает
  # с textContent.toLowerCase(), которая корректно приводит к нижнему
  # регистру и не-ASCII текст (например, кириллические названия эпизодов).
  let needleLit = escapeJson(unicode.toLower(strutils.strip(labelText)))
  let markLit = escapeJson(RcMarkAttr)
  let js = &"""(function() {{
    var needle = {needleLit};
    var all = document.querySelectorAll('label, div, span, p, legend');
    var DOCUMENT_POSITION_FOLLOWING = 4;
    for (var i = 0; i < all.length; i++) {{
      var el = all[i];
      if (el.children.length > 0) continue;
      var txt = (el.textContent || '').trim().toLowerCase().replace(/\*\s*$/, '').trim();
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

proc rcMarkByButtonText*(tab: Tab, textSubstring: string, exact = false): Future[bool] {.async.} =
  ## Помечает RcMarkAttr первую button/a/[role="button"], чей видимый
  ## текст содержит textSubstring (при exact = true — равен ему), чтобы
  ## click(tab, RcMarkSelector) выполнил настоящий клик мышью (координаты +
  ## Input.dispatchMouseEvent), а не синтетический el.click().
  ##
  ## Имя отлично от siteworker_common.markByButtonText() намеренно: та
  ## версия использует DefaultMarkAttr, а этот модуль кликает по
  ## RcMarkSelector. Одноимённая перегрузка с другим значением markAttr
  ## по умолчанию молча перехватила бы вызов с совпавшей арностью.
  ##
  ## Экспортирован: годится для быстрой проверки "видна ли кнопка
  ## 'New Episode'" без полного сценария.
  await unmarkAll(tab)
  # unicode.toLower(), не toLowerAscii() — см. пояснение в markByLabel() выше.
  let needleLit = escapeJson(unicode.toLower(strutils.strip(textSubstring)))
  let markLit = escapeJson(RcMarkAttr)
  let exactLit = if exact: "true" else: "false"
  let js = &"""(function() {{
    var needle = {needleLit};
    var exact = {exactLit};
    var nodes = document.querySelectorAll('button, a, [role="button"]');
    for (var i = 0; i < nodes.length; i++) {{
      var txt = (nodes[i].textContent || '').trim().toLowerCase();
      var hit = exact ? (txt === needle) : (txt.indexOf(needle) !== -1);
      if (hit) {{ nodes[i].setAttribute({markLit}, '1'); return true; }}
    }}
    return false;
  }})()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc markContentFileInput(tab: Tab): Future[bool] {.async.} =
  ## Ищет <input type="file"> для аудио (на странице два дропзона:
  ## "Episode Cover Image" и "Upload Content"). Порядок выбора: инпут с
  ## accept, содержащим "audio"; иначе ближайший по тексту к
  ## UploadFileButtonText/UploadContentLabel; иначе, если инпутов ровно
  ## два (обложка + контент), второй.
  await unmarkAll(tab)
  let markLit = escapeJson(RcMarkAttr)
  # unicode.toLower(), не toLowerAscii() — см. пояснение в markByLabel() выше.
  let uploadTextLit = escapeJson(unicode.toLower(UploadFileButtonText))
  let contentLabelLit = escapeJson(unicode.toLower(UploadContentLabel))
  let js = &"""(function() {{
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input[type="file"]'));
    if (inputs.length === 0) return false;

    for (var i = 0; i < inputs.length; i++) {{
      var accept = (inputs[i].getAttribute('accept') || '').toLowerCase();
      if (accept.indexOf('audio') !== -1) {{ inputs[i].setAttribute({markLit}, '1'); return true; }}
    }}

    var needle1 = {uploadTextLit};
    var needle2 = {contentLabelLit};
    var best = null, bestDist = Infinity;
    var texted = document.querySelectorAll('button, div, span, label, p');
    for (var t = 0; t < texted.length; t++) {{
      var txt = (texted[t].textContent || '').trim().toLowerCase();
      if (txt.indexOf(needle1) === -1 && txt.indexOf(needle2) === -1) continue;
      var rect1 = texted[t].getBoundingClientRect();
      for (var i = 0; i < inputs.length; i++) {{
        var rect2 = inputs[i].getBoundingClientRect();
        var dist = Math.abs(rect1.top - rect2.top) + Math.abs(rect1.left - rect2.left);
        if (dist < bestDist) {{ bestDist = dist; best = inputs[i]; }}
      }}
    }}
    if (best) {{ best.setAttribute({markLit}, '1'); return true; }}

    if (inputs.length === 2) {{ inputs[1].setAttribute({markLit}, '1'); return true; }}
    inputs[inputs.length - 1].setAttribute({markLit}, '1');
    return true;
  }})()"""
  let found = await evalJS(tab, js)
  result = found.kind == JBool and getBool(found)

proc dumpOnFailure(tab: Tab, prefix: string, screenshotDir: string = "") {.async.} =
  ## В отличие от dumpDebugInfoVerbose() у qwen/kimi, не зависит от флага
  ## pDumpDebug: дампы пишутся при каждой ошибке, если передан непустой
  ## screenshotDir (тот же каталог, что у StepRecorder, — дамп лежит рядом
  ## со скриншотами шагов). Пустой screenshotDir отключает дампы.
  if len(screenshotDir) == 0:
    return
  try:
    createDir(screenshotDir)
    let fullPrefix = screenshotDir / prefix
    discard await dumpDebugInfo(tab, fullPrefix)
    echo "Отладочные файлы сохранены: ", fullPrefix, ".png, ", fullPrefix, ".html, ", fullPrefix, "-console.json"
  except CatchableError:
    discard

# ---------------------------------------------------------------------------
# Диагностика: ID шоу текущего аккаунта (см. verifyShowId)
# ---------------------------------------------------------------------------
#
# Для неверного или недоступного showId страница /shows/{showId}/episodes
# не даёт ни ошибки, ни редиректа: <div class="main-content"> остаётся
# пустым при нормальной шапке. Это неотличимо от незагруженной страницы
# и приводит к невнятной ошибке "не нашлась кнопка 'New Episode'", поэтому
# перед поиском кнопки showId сверяется со списком шоу аккаунта.

type
  RedcircleNotLoggedInError* = object of SiteWorkerError
    ## Подтип SiteWorkerError для разлогиненного профиля (см.
    ## fetchShowIdsFromShowsPage()): verifyShowId() пробрасывает его как есть,
    ## а не подменяет мягким "пропускаю проверку".

const
  ShowsListUrl* = RedcircleBaseUrl & "/shows"
    ## Экспортирован: тот же URL используют внешние инструменты для входа
    ## и диагностики showId (RedcircleBaseUrl намеренно не экспортируется).
  ShowIdUuidPattern = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

proc fetchShowIdsFromShowsPage(tab: Tab, timeoutMs = 15_000): Future[seq[string]] {.async.} =
  ## Открывает /shows и собирает UUID-подобные подстроки из href всех
  ## ссылок — это ID шоу, видимые текущему аккаунту. Опирается только на
  ## то, что ссылки на шоу — обычные <a href>, а не на неподтверждённые
  ## data-атрибуты.
  ##
  ## Список дорисовывается после события load (отдельный XHR, затем
  ## рендер React), поэтому DOM опрашивается с интервалом до появления
  ## хотя бы одной ссылки или до timeoutMs. На каждой итерации проверяется
  ## и текущий URL: редирект на /sign-in означает разлогиненный профиль,
  ## об этом сообщается сразу, без ожидания таймаута.
  await goto(tab, ShowsListUrl)
  let js = &"""(function() {{
    var re = /{ShowIdUuidPattern}/g;
    var found = {{}};
    var anchors = document.querySelectorAll('a[href]');
    for (var i = 0; i < anchors.length; i++) {{
      var href = anchors[i].getAttribute('href') || '';
      var m = href.match(re);
      if (m) {{ for (var j = 0; j < m.length; j++) {{ found[m[j]] = true; }} }}
    }}
    return Object.keys(found);
  }})()"""
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  while true:
    if "/sign-in" in (await currentUrl(tab)):
      let hint = "Сохранённый профиль Chromium (~/.cache/redcircleclient/profile), " &
        "видимо, разлогинился — выполните loginRedcircle(), " &
        "войдите в аккаунт и повторите запуск."
      warnLoggedOut("RedCircle", hint)
      raise newException(RedcircleNotLoggedInError,
        "аккаунт RedCircle не залогинен: /shows перенаправил на /sign-in. " & hint)
    let idsJson = await evalJS(tab, js)
    result = @[]
    if idsJson.kind == JArray:
      for item in items(idsJson):
        add(result, getStr(item))
    if len(result) > 0 or epochTime() >= deadline:
      return
    await sleepAsync(300)

proc verifyShowId*(tab: Tab, showId: string, verbose: bool): Future[void] {.async.} =
  ## Сверяет showId со списком ID на /shows. Экспортирован для
  ## диагностики отдельно от uploadToRedcircle(). Если список получить не
  ## удалось (разметка /shows не на <a href>), лишь предупреждает и
  ## продолжает; если список получен и showId в нём отсутствует — это
  ## самая частая причина пустой страницы эпизодов, и ошибка бросается
  ## сразу, а не после таймаута поиска кнопки.
  if verbose: echo "Проверяю, виден ли showId текущему аккаунту (через /shows)..."
  var ids: seq[string]
  try:
    ids = await fetchShowIdsFromShowsPage(tab)
  except RedcircleNotLoggedInError:
    # Разлогиненный профиль пробрасывается как есть: причина точно известна
    # (нужен повторный вход), а молчание превратило бы её в невнятный
    # "клик не нашёл ссылку" выше по цепочке.
    raise
  except CatchableError as e:
    if verbose: echo "  Не удалось получить список шоу с /shows: ", e.msg, " — пропускаю проверку."
    return
  if len(ids) == 0:
    if verbose: echo "  На /shows за 15 секунд не появилось ни одной ссылки, похожей на ID шоу " &
      "(возможно, аккаунт не залогинен, список шоу пуст, или разметка страницы " &
      "устроена иначе, чем предполагалось) — пропускаю проверку."
    return
  if toLowerAscii(showId) notin mapIt(ids, toLowerAscii(it)):
    raise newException(SiteWorkerError,
      &"showId '{showId}' не найден среди шоу, видных текущему аккаунту на /shows " &
      &"(найдено: {ids.join(\", \")}). Скорее всего, именно поэтому список эпизодов " &
      "оказался пустым — передайте правильный --show или обновите RedcircleShowId.")
  if verbose: echo "  showId подтверждён — виден в списке шоу аккаунта."

proc clickShowLink*(tab: Tab, showId: string, verbose: bool): Future[void] {.async.} =
  ## Кликает настоящую ссылку на шоу на открытой /shows вместо goto() на
  ## /shows/{showId}/episodes. Холодная загрузка этого маршрута оставляет
  ## main-content пустым даже для верного showId (видимо, состояние
  ## инициализируется только клиентским pushState-переходом из списка),
  ## поэтому клик отдаёт переход SPA-роутеру. Экспортирован для проверки
  ## перехода после verifyShowId().
  await unmarkAll(tab)
  let needleLit = escapeJson(toLowerAscii(showId))
  let markLit = escapeJson(RcMarkAttr)
  let js = &"""(function() {{
    var needle = {needleLit};
    var anchors = document.querySelectorAll('a[href]');
    for (var i = 0; i < anchors.length; i++) {{
      var href = (anchors[i].getAttribute('href') || '').toLowerCase();
      if (href.indexOf(needle) !== -1) {{
        anchors[i].setAttribute({markLit}, '1');
        return true;
      }}
    }}
    return false;
  }})()"""
  let found = await evalJS(tab, js)
  if not (found.kind == JBool and getBool(found)):
    raise newException(SiteWorkerError,
      &"на /shows не нашлась ссылка на showId '{showId}' для клика " &
      "(хотя verifyShowId() её видел — возможно, разметка изменилась между вызовами)")
  if verbose: echo "Кликаю по ссылке на шоу (вместо прямого перехода по URL эпизодов)..."
  await click(tab, RcMarkSelector)

  let episodesFragment = toLowerAscii(&"/shows/{showId}/ep")
  proc urlMatches(): Future[bool] {.async.} =
    result = episodesFragment in toLowerAscii(await currentUrl(tab))
  if not await waitUntilTrue(urlMatches, 15_000, 200):
    raise newException(SiteWorkerError,
      "клик по ссылке на шоу не привёл к переходу на страницу эпизодов " &
      &"(ожидался URL с '{episodesFragment}') за 15 секунд")

proc openEpisodesPageForShow*(browser: Browser, showId: string, verbose: bool,
                               screenshotDir: string = ""): Future[Tab] {.async.} =
  ## Открывает страницу эпизодов шоу showId (вместо прямого
  ## gotoWithRetry(), см. clickShowLink()). Экспортирован для внешних
  ## инструментов; screenshotDir необязателен (пусто — dumpOnFailure()
  ## ничего не пишет). Ошибки дампятся здесь, пока вкладка жива в
  ## локальной области: вызывающий получает tab только при успехе.
  result = await gotoWithRetry(browser, ShowsListUrl, verbose = verbose)
  try:
    await verifyShowId(result, showId, verbose)
    await clickShowLink(result, showId, verbose)
  except CatchableError:
    await dumpOnFailure(result, "redcircle-debug-shows-list", screenshotDir)
    raise

# ---------------------------------------------------------------------------
# Шаги сценария
# ---------------------------------------------------------------------------


# Пошаговые скриншоты (StepRecorder)
# ---------------------------------------------------------------------------
#
# В отличие от dumpOnFailure() (снимок при ошибке), StepRecorder снимает
# страницу после каждого шага, чтобы прогон можно было проверить
# визуально. Файлы нумеруются (01-..., 02-...) по порядку шагов.

type
  StepRecorder = ref object
    ## ref, а не object: index меняется внутри async-процедуры step(), а Nim
    ## не разрешает захватывать "var object" в замыкании async-процедуры.
    dir: string
      ## Пустая строка — запись скриншотов отключена (см. --no-screens).
    index: int

proc newStepRecorder(dir: string): StepRecorder =
  result = StepRecorder(dir: dir, index: 0)
  if len(dir) > 0:
    createDir(dir)

proc step(rec: StepRecorder, tab: Tab, label: string) {.async.} =
  ## Сохраняет "<index>-<label>.png" в каталог рекордера. Отсутствие
  ## каталога (StepRecorder с dir = "") или сбой самого сохранения
  ## (например, вкладка уже закрылась) не прерывает сценарий — скриншоты
  ## это диагностика, а не часть бизнес-логики.
  if len(rec.dir) == 0:
    return
  inc(rec.index)
  let safeLabel = multiReplace(label, {" ": "-", "/": "-", "\\": "-"})
  let path = rec.dir / (&"{rec.index:02}-{safeLabel}.png")
  try:
    await screenshot(tab, path, fullPage = true)
    echo "  [скриншот] ", path
  except CatchableError as e:
    echo "  [скриншот] не удалось сохранить ", path, ": ", e.msg


# ---------------------------------------------------------------------------
# Ожидание окна обработки после Publish/Save as Draft
# ---------------------------------------------------------------------------
#
# Файл грузится после клика Publish/Save as Draft: сайт показывает окно
# "Uploading Episode..." / "Processing your episode's file..."
# (ProcessingOverlayTexts). Его исчезновение — первый сигнал завершения;
# submitEpisode() дополнительно проверяет URL и заголовок эпизода.

proc getUploadProgressPercent(tab: Tab): Future[int] {.async.} =
  ## Вытаскивает N из текста "Uploading your episode's file... N%"; -1,
  ## если процента сейчас нет. Ищет в самом маленьком элементе, содержащем и
  ## один из ProcessingOverlayTexts, и "%": поиск по всему
  ## document.body.innerText подхватил бы чужой процент (баннер, счётчик).
  let js = """(function (needles) {
    var all = document.querySelectorAll('body *');
    var best = null;
    for (var i = 0; i < all.length; i++) {
      var t = all[i].textContent || '';
      if (!/%/.test(t)) continue;
      var matches = false;
      for (var j = 0; j < needles.length; j++) {
        if (t.toLowerCase().indexOf(needles[j]) !== -1) { matches = true; break; }
      }
      if (!matches) continue;
      if (best === null || t.length < best.length) best = t;
    }
    if (best === null) return -1;
    var m = best.match(/(\d{1,3})\s*%/);
    return m ? parseInt(m[1], 10) : -1;
  })(""" & $(%ProcessingOverlayTexts) & ")"
  let found = await evalJS(tab, js)
  result = if found.kind == JInt: int(getInt(found)) else: -1

proc waitForProcessingOverlayGone(tab: Tab, stallTimeoutMs, absoluteMaxMs: int,
                                   verbose: bool): Future[void] {.async.} =
  ## Ждёт исчезновения оверлея загрузки по отсутствию прогресса: пока
  ## процент (getUploadProgressPercent) растёт, ожидание продлевается;
  ## таймаут — при простое дольше stallTimeoutMs или по absoluteMaxMs.
  proc overlayPresent(): Future[bool] {.async.} =
    for text in ProcessingOverlayTexts:
      if await pageHasText(tab, text):
        return true
    return false
  if not await overlayPresent():
    return
  if verbose: echo "  Вижу окно обработки файла — жду его закрытия ",
    "(без прогресса — максимум ", stallTimeoutMs div 1000, " сек; в целом — не дольше ",
    absoluteMaxMs div 1000, " сек)..."

  let startTime = epochTime()
  var lastPercent = -1
  var lastProgressAt = epochTime()
  var disappeared = false

  while true:
    if not await overlayPresent():
      disappeared = true
      break

    let now = epochTime()
    if (now - startTime) * 1000.0 >= absoluteMaxMs.float:
      if verbose: echo "  Достигнут абсолютный потолок ожидания загрузки (",
        absoluteMaxMs div 1000, " сек) — прекращаю ждать."
      break

    let percent = await getUploadProgressPercent(tab)
    if percent > lastPercent:
      if verbose and percent != lastPercent:
        echo "    ...загрузка идёт: ", percent, "%"
      lastPercent = percent
      lastProgressAt = now
    elif (now - lastProgressAt) * 1000.0 >= stallTimeoutMs.float:
      if verbose: echo "  Процент загрузки не растёт уже ", stallTimeoutMs div 1000,
        " сек (последний виденный: ", (if lastPercent >= 0: $lastPercent & "%" else: "неизвестен"),
        ") — считаю загрузку зависшей."
      break

    await sleepAsync(1_000)

  if verbose:
    echo "  ", (if disappeared: "Окно обработки закрылось."
                else: "Окно обработки всё ещё видно по истечении ожидания.")

proc clickNewEpisode(tab: Tab, verbose: bool, screenshotDir: string = "") {.async.} =
  ## Находит и кликает "New Episode" повторно, пока не откроется окно (до
  ## ModalTimeoutMs): React может перерисовать <header> между пометкой и
  ## кликом, и метка пропадёт. Пометка и клик повторяются на каждой попытке.
  if verbose: echo "Ищу и кликаю кнопку '", NewEpisodeButtonText, "'..."
  proc modalOpened(): Future[bool] {.async.} = result = await pageHasText(tab, CreateEpisodeHeaderText)

  let deadline = epochTime() + (ModalTimeoutMs.float / 1000.0)
  var opened = false
  var sawButton = false
  while epochTime() < deadline:
    if await rcMarkByButtonText(tab, NewEpisodeButtonText):
      sawButton = true
      try:
        await click(tab, RcMarkSelector)
      except ChildTearError, CDPError:
        # Метка устарела (React перерисовал <header>): findNode() не нашёл
        # узел (ChildTearError) или Chromium ответил "Could not find node
        # with given id" (CDPError). Следующая итерация пометит кнопку заново.
        discard
    if await modalOpened():
      opened = true
      break
    await sleepAsync(300)

  if not opened:
    await dumpOnFailure(tab, "redcircle-debug-no-modal", screenshotDir)
    if not sawButton:
      raise newException(SiteWorkerError,
        &"не нашлась кнопка '{NewEpisodeButtonText}' на странице списка эпизодов")
    raise newException(SiteWorkerError,
      &"после клика(ов) по '{NewEpisodeButtonText}' не появился текст '{CreateEpisodeHeaderText}' — " &
      "модальное окно создания эпизода, похоже, не открылось")

proc markedFieldText(tab: Tab): Future[string] {.async.} =
  ## Текущее содержимое поля с RcMarkAttr: .value у input/textarea, иначе
  ## innerText/textContent. Нужна сразу после fill(), чтобы заметить текст,
  ## попавший не в то поле (см. verifyFieldFilled()).
  let js = &"""(function() {{
    var el = document.querySelector('{RcMarkSelector}');
    if (!el) return null;
    if (el.value !== undefined) return el.value;
    return el.innerText !== undefined ? el.innerText : el.textContent;
  }})()"""
  let res = await evalJS(tab, js)
  result = if res.kind == JString: getStr(res) else: ""

proc normalizeForCompare(s: string): string =
  ## Нормализует текст для сравнения в verifyFieldFilled(): убирает все
  ## пустые строки. Lexical хранит каждую строку Description отдельным
  ## <p>, и innerText добавляет пустую строку между <p> (CSS-отступ, а не
  ## символ); в исходном тексте таких строк нет. Слова и их порядок
  ## сравниваются строго, поэтому перепутанное поле ловится.
  var nonEmpty: seq[string] = @[]
  for line in splitLines(s):
    let t = strutils.strip(line)
    if len(t) > 0:
      add(nonEmpty, t)
  result = join(nonEmpty, "\n")

proc shortPreview(s: string, maxLen = 200): string =
  ## Укороченная версия текста для сообщений об ошибке — чтобы при
  ## настоящем расхождении (не том, что чинит normalizeForCompare выше)
  ## в терминал/лог не улетал целиком многотысячный текст описания.
  let oneLine = join(splitLines(s), " ⏎ ")
  result = if len(oneLine) > maxLen: oneLine[0 ..< maxLen] & &"… (всего {len(s)} симв.)"
           else: oneLine

proc verifyFieldFilled(tab: Tab, expected: string, fieldLabel: string) {.async.} =
  ## Читает поле, в которое только что писали (по метке RcMarkAttr), и
  ## бросает SiteWorkerError при расхождении с ожидаемым текстом: перепутанное
  ## или не принявшее ввод поле ловится сразу, а не отказом валидации на Publish.
  let actual = await markedFieldText(tab)
  if normalizeForCompare(actual) != normalizeForCompare(expected):
    raise newException(SiteWorkerError,
      &"после заполнения поля '{fieldLabel}' его содержимое не совпало с ожидаемым " &
      &"(похоже, текст попал не в то поле) — ожидалось: {shortPreview(expected)} | " &
      &"получено: {shortPreview(actual)}")

proc fillTitle(tab: Tab, title: string, verbose: bool, screenshotDir: string = "") {.async.} =
  if verbose: echo "Заполняю заголовок..."
  proc tryMark(): Future[bool] {.async.} = result = await markByLabel(tab, TitleFieldLabel)
  if not await waitUntilTrue(tryMark, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "redcircle-debug-no-title-field", screenshotDir)
    raise newException(SiteWorkerError, &"не нашлось поле рядом с меткой '{TitleFieldLabel}'")
  await fill(tab, RcMarkSelector, title)
  await verifyFieldFilled(tab, title, TitleFieldLabel)

proc fillDescription(tab: Tab, description: string, verbose: bool, screenshotDir: string = "") {.async.} =
  if verbose: echo "Заполняю описание..."
  proc tryMark(): Future[bool] {.async.} = result = await markByLabel(tab, DescriptionFieldLabel)
  if not await waitUntilTrue(tryMark, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "redcircle-debug-no-description-field", screenshotDir)
    raise newException(SiteWorkerError, &"не нашлось поле рядом с меткой '{DescriptionFieldLabel}'")

  # Description — Lexical-редактор (contenteditable): "\n" внутри одного
  # insertText() он не считает разрывом абзаца. Поэтому текст печатается
  # построчно: первая строка — fill() (очищает поле), остальные — Enter
  # (pressEnter(), создаёт абзац) + insertTextAtCursor() без очистки.
  let lines = splitLines(description)
  await fill(tab, RcMarkSelector, if len(lines) > 0: lines[0] else: "")
  for i in 1 ..< len(lines):
    await pressEnter(tab)
    if len(lines[i]) > 0:
      await insertTextAtCursor(tab, lines[i])

  await verifyFieldFilled(tab, description, DescriptionFieldLabel)

proc contentFileAttached(tab: Tab): Future[bool] {.async.} =
  ## Проверяет через DOM (input.files.length > 0), назначен ли файл
  ## помеченному <input type="file">. Это источник истины: при пустом
  ## input.files аудио не уйдёт, что бы ни показывала дропзона. Если узел
  ## заменился, результат false.
  let js = &"""(function() {{
    var el = document.querySelector('{RcMarkSelector}');
    return !!(el && el.files && el.files.length > 0);
  }})()"""
  let res = await evalJS(tab, js)
  result = res.kind == JBool and getBool(res)

proc waitForContentAcknowledged(tab: Tab, fileName: string, verbose: bool): Future[bool] {.async.} =
  ## Ждёт появления имени файла на странице (признак, что сайт принял
  ## файл). По ContentAckTimeoutMs возвращает false без исключения: имя
  ## могло не показаться. Сигнал неполный, поэтому attachContent()
  ## требует и эту проверку, и contentFileAttached().
  proc ack(): Future[bool] {.async.} = result = await pageHasText(tab, fileName)
  result = await waitUntilTrue(ack, ContentAckTimeoutMs, 300)
  if verbose:
    if result: echo "  Имя файла обнаружено на странице — файл принят."
    else: echo "  Не удалось распознать подтверждение приёма файла по имени (текстовая проверка) — сверяюсь с DOM."

proc attachContent(tab: Tab, absPath: string, verbose: bool, screenshotDir: string = "") {.async.} =
  if verbose: echo "Прикрепляю аудиофайл: ", absPath
  var attached = false
  for attempt in 1 .. 3:
    if attempt > 1 and verbose:
      echo "  Попытка прикрепления #", attempt, " — предыдущая не подтвердилась через DOM."

    var found = await markContentFileInput(tab)
    if not found:
      # Возможно, дропзона ещё не отрисовалась — пробуем ещё раз чуть позже,
      # и, если не помогло, кликаем по кнопке "Upload File" на случай, если
      # инпут монтируется в DOM только после клика (как у Kimi, см.
      # kimiAttachFiles() в siteworkers/kimi.nim).
      proc tryAgain(): Future[bool] {.async.} = result = await markContentFileInput(tab)
      found = await waitUntilTrue(tryAgain, FieldTimeoutMs, 200)
    if not found:
      if await rcMarkByButtonText(tab, UploadFileButtonText):
        try:
          await click(tab, RcMarkSelector)
        except ChildTearError, CDPError:
          # Та же гонка с устаревшей меткой, что в clickNewEpisode(): found
          # остаётся false, и дальше решает внешний цикл "for attempt in 1..3"
          # (или запасной путь "inputs.length == 2" в markContentFileInput()).
          discard
        proc tryAfterClick(): Future[bool] {.async.} = result = await markContentFileInput(tab)
        found = await waitUntilTrue(tryAfterClick, FieldTimeoutMs, 200)
    if not found:
      if attempt == 3:
        await dumpOnFailure(tab, "redcircle-debug-no-file-input", screenshotDir)
        raise newException(SiteWorkerError, "не нашёлся input[type=file] для загрузки аудио")
      continue

    await uploadFile(tab, RcMarkSelector, @[absPath])

    # DOM.setFileInputFiles обычно сам шлёт 'input'/'change', но бывало,
    # что input.files заполнен, а React-состояние дропзоны не обновлялось и
    # "Publish" не отправлял форму. События дублируются с bubbles: true.
    discard await evalJS(tab, &"""(function() {{
      var el = document.querySelector('{RcMarkSelector}');
      if (!el) return false;
      el.dispatchEvent(new Event('input', {{ bubbles: true }}));
      el.dispatchEvent(new Event('change', {{ bubbles: true }}));
      return true;
    }})()""")

    let ackByUi = await waitForContentAcknowledged(tab, extractFilename(absPath), verbose)
    let ackByDom = await contentFileAttached(tab)
    attached = ackByDom and ackByUi

    if attached:
      if verbose: echo "  Подтверждено и через DOM (input.files), и по имени файла на странице."
      break

    if ackByDom and not ackByUi:
      # Нативный input файл получил, а React-состояние нет: "Publish" либо
      # не отправит форму, либо создаст эпизод без аудио (см. submitEpisode()).
      # Это не успех — повторяем (markContentFileInput() найдёт input заново).
      if verbose: echo "  input.files заполнен, но UI файл не подтвердил — " &
        "похоже на рассинхронизацию с React, повторяю попытку."
      attached = false

  if not attached:
    await dumpOnFailure(tab, "redcircle-debug-file-not-attached", screenshotDir)
    raise newException(SiteWorkerError,
      "аудиофайл не подтверждён после нескольких попыток прикрепления — либо input.files " &
      "остался пуст, либо (реже) файл физически назначен инпуту, но интерфейс сайта его так " &
      "и не отобразил (возможная рассинхронизация React-состояния с native DOM после " &
      "программного назначения файла) — публикация остановлена, чтобы не создать эпизод без аудио")

proc formatDateTimeForPicker(t: DateTime): string =
  ## Формат редактируемой части "Publish Date" ("20.08.2026, 13:56", без
  ## дня недели и часового пояса — те лежат отдельными текстовыми узлами).
  result = format(t, "dd'.'MM'.'yyyy, HH:mm")

proc isoDateTimeForNativeInput(t: DateTime): string =
  ## Формат .value у <input type="datetime-local">: "yyyy-MM-ddTHH:mm".
  ## Собран конкатенацией: в паттерне format() этой версии Nim буква "T" в
  ## кавычках не поддерживается.
  result = format(t, "yyyy-MM-dd") & "T" & format(t, "HH:mm")

proc describeMarkedField(tab: Tab): Future[string] {.async.} =
  ## Диагностическая строка о помеченном поле (тег/type/readonly/disabled/
  ## value) для вывода и дампа при сбое в setPublishDateToNow().
  let js = &"""(function() {{
    var el = document.querySelector('{RcMarkSelector}');
    if (!el) return null;
    return el.tagName + ' type=' + (el.type || '-') +
      ' readonly=' + (!!el.readOnly) + ' disabled=' + (!!el.disabled) +
      ' value=' + JSON.stringify(el.value !== undefined ? el.value : null);
  }})()"""
  let res = await evalJS(tab, js)
  result = if res.kind == JString: getStr(res) else: "(поле не найдено)"

proc publishDateLooksSet(actual: string, target: DateTime): bool =
  ## Проверяет, что поле "Publish Date" приняло значение: ищет target как
  ## подстроку в отображаемом ("dd.MM.yyyy, HH:mm") и в ISO ("yyyy-MM-ddTHH:mm",
  ## для нативного datetime-local) формате. Допуск ±1 минута на случай
  ## перехода часов через границу минуты между расчётом и записью.
  let normalized = toLowerAscii(strutils.strip(actual))
  if len(normalized) == 0: return false
  for deltaMin in [-1, 0, 1]:
    let t = target + initDuration(minutes = deltaMin)
    if toLowerAscii(formatDateTimeForPicker(t)) in normalized: return true
    if toLowerAscii(isoDateTimeForNativeInput(t)) in normalized: return true
  result = false

proc publishDateSegmentsText(tab: Tab): Future[string] {.async.} =
  ## Читает day/month/year/hour/minute всего виджета "Publish Date".
  ## Поле реализовано как react-aria DateField: несколько
  ## <span role="spinbutton" data-type="day|month|year|hour|minute"> в
  ## общем <div role="group">, у которых нет общего .value. markByLabel()
  ## помечает первый из них (день), поэтому от RcMarkSelector идёт подъём
  ## до ближайшего role="group", где собираются aria-valuenow всех
  ## спинбаттонов. Возвращает "", если элемента, группы или спинбаттонов
  ## нет (тогда сравнивайте через publishDateLooksSet()).
  let js = &"""(function() {{
    var el = document.querySelector('{RcMarkSelector}');
    if (!el) return null;
    var group = el.closest('[role="group"]');
    if (!group) return null;
    var segs = group.querySelectorAll('[role="spinbutton"]');
    if (segs.length === 0) return null;
    var parts = [];
    for (var i = 0; i < segs.length; i++) {{
      var s = segs[i];
      var t = s.getAttribute('data-type') || ('#' + i);
      parts.push(t + '=' + (s.getAttribute('aria-valuenow') || ''));
    }}
    return parts.join(';');
  }})()"""
  let res = await evalJS(tab, js)
  result = if res.kind == JString: getStr(res) else: ""

proc publishDateSegmentsLookSet(actual: string, target: DateTime): bool =
  ## Аналог publishDateLooksSet() для формата publishDateSegmentsText()
  ## ("day=21;month=8;year=2026;hour=12;minute=33"): сегменты сравниваются
  ## по отдельности. В вёрстке react-aria DateField ни один сегмент не
  ## содержит полной даты, поэтому publishDateLooksSet() на этом формате
  ## всегда проваливается. Токены сверяются точно ("hour=1" не должно
  ## совпасть с "hour=12"); допуск ±1 минута, как в publishDateLooksSet().
  if len(strutils.strip(actual)) == 0: return false
  let actualParts = toSeq(split(actual, ';'))
  for deltaMin in [-1, 0, 1]:
    let t = target + initDuration(minutes = deltaMin)
    let wantParts = @[&"day={t.monthday}", &"month={ord(t.month)}",
                       &"year={t.year}", &"hour={t.hour}", &"minute={t.minute}"]
    if allIt(wantParts, it in actualParts): return true
  result = false

proc setPublishDateToNow(tab: Tab, verbose: bool, screenshotDir: string = "") {.async.} =
  ## Перезаписывает "Publish Date" текущим временем (со сдвигом в прошлое
  ## на PublishDateSafetyMarginMin), не доверяя значению по умолчанию (см.
  ## PublishDateFieldLabel). Если поле не найдено, сохраняется отладочный
  ## снимок и сценарий продолжается: submitEpisode() всё равно поймает
  ## случай, когда эпизод запланирован, а не опубликован.
  ##
  ## Помеченное поле может быть readonly-полем пикера, нативным
  ## datetime-local (.value только в ISO) или controlled-полем React (см.
  ## setControlledValue()). Способы записи пробуются по очереди, и после
  ## каждого значение читается обратно (publishDateLooksSet()): успешное
  ## выполнение команды не доказывает, что поле приняло запись.
  if verbose: echo "Устанавливаю дату публикации на текущий момент..."
  proc tryMark(): Future[bool] {.async.} = result = await markByLabel(tab, PublishDateFieldLabel)
  if not await waitUntilTrue(tryMark, FieldTimeoutMs, 200):
    await dumpOnFailure(tab, "redcircle-debug-no-publish-date-field", screenshotDir)
    if verbose: echo "  Поле '", PublishDateFieldLabel, "' не найдено — оставляю значение по умолчанию."
    return

  let target = now() - initDuration(minutes = PublishDateSafetyMarginMin)
  let displayFormatted = formatDateTimeForPicker(target)
  let isoFormatted = isoDateTimeForNativeInput(target)

  if verbose: echo "  Поле найдено: ", await describeMarkedField(tab)

  proc verifyNow(): Future[bool] {.async.} =
    # Проверяются обе вёрстки: единое поле с .value (publishDateLooksSet())
    # и сегментированный react-aria DateField (publishDateSegmentsLookSet()),
    # актуальный сейчас.
    if publishDateLooksSet(await markedFieldText(tab), target): return true
    result = publishDateSegmentsLookSet(await publishDateSegmentsText(tab), target)

  # Попытка 1: обычный insertText() — как для остальных текстовых полей.
  await fill(tab, RcMarkSelector, displayFormatted)
  if await verifyNow():
    if verbose: echo "  Дата публикации выставлена на ", displayFormatted, " (insertText)."
    return

  # Попытка 2: нативный сеттер прототипа в обход перехватчика controlled-
  # компонента (см. setControlledValue()), тем же отображаемым форматом —
  # на случай readonly-поля или отката React значения insertText().
  discard await setControlledValue(tab, RcMarkSelector, displayFormatted)
  if await verifyNow():
    if verbose: echo "  Дата публикации выставлена на ", displayFormatted,
      " (setControlledValue, отображаемый формат)."
    return

  # Попытка 3: то же самое, но ISO-форматом — на случай, если это
  # нативный <input type="datetime-local"> (см. пояснение выше).
  discard await setControlledValue(tab, RcMarkSelector, isoFormatted)
  if await verifyNow():
    if verbose: echo "  Дата публикации выставлена на ", displayFormatted,
      " (setControlledValue, ISO-формат ", isoFormatted, ")."
    return

  # Попытка 4: настоящие посимвольные события клавиатуры (type(), а не
  # insertText()) — для сегментированных/masked полей, которые слушают
  # keydown, а не beforeinput/input, и поэтому не реагируют ни на
  # insertText(), ни на программную запись value (попытки 1-3 выше).
  await typeText(tab, RcMarkSelector, displayFormatted)
  if await verifyNow():
    if verbose: echo "  Дата публикации выставлена на ", displayFormatted, " (посимвольный ввод)."
    return

  # Ни один способ не сработал. Ошибка не бросается: submitEpisode()
  # поймает итог (эпизод останется "To Publish on ...") с понятным
  # сообщением; здесь сохраняется максимум диагностики.
  await dumpOnFailure(tab, "redcircle-debug-publish-date-not-set", screenshotDir)
  let fieldNow = await describeMarkedField(tab)
  let valueNow = await markedFieldText(tab)
  let segmentsNow = await publishDateSegmentsText(tab)
  if verbose:
    echo "  ПРЕДУПРЕЖДЕНИЕ: ни один из способов не перевёл поле '", PublishDateFieldLabel,
      "' на целевое значение ", displayFormatted, " (ISO: ", isoFormatted, ")."
    echo "    Поле сейчас: ", fieldNow
    echo "    Содержимое сейчас: ", valueNow
    echo "    Сегменты (если это react-aria DateField): ",
      (if len(segmentsNow) > 0: segmentsNow else: "(не найдены — вероятно, поле не сегментировано)")

proc submitEpisode(tab: Tab, title: string, draft: bool, verbose: bool, screenshotDir: string = "") {.async.} =
  ## Подтверждение публикации — не закрытие окна "Create Episode" и не
  ## текст "published"/"success" (бывают ложноположительными, например при
  ## ошибке валидации), а проверяемое состояние: заголовок эпизода на
  ## странице или смена URL на страницу эпизода.
  let buttonText = if draft: SaveDraftButtonText else: PublishButtonText

  proc modalOpen(): Future[bool] {.async.} = result = await pageHasText(tab, CreateEpisodeHeaderText)

  # Клик по кнопке публикации повторяется, пока модальное окно не закроется —
  # по тем же соображениям, что и в clickNewEpisode(): между тем, как
  # rcMarkByButtonText() пометил кнопку, и самим click(), React мог
  # перерисовать модальное окно, и метка "протухнет" — синтетический клик
  # ударит в уже отсоединённый от DOM узел, ничего не произойдёт, а
  # сценарий будет ждать закрытия окна, которое никто не закрывал.
  if verbose: echo "Нажимаю '", buttonText, "'..."
  let prePublishUrl = await currentUrl(tab)
  let clickDeadline = epochTime() + (ModalTimeoutMs.float / 1000.0)
  var sawButton = false
  var modalClosed = false
  while epochTime() < clickDeadline:
    if not await modalOpen():
      modalClosed = true
      break
    if await rcMarkByButtonText(tab, buttonText, exact = true):
      sawButton = true
      try:
        await click(tab, RcMarkSelector)
      except ChildTearError, CDPError:
        # Та же гонка, что в clickNewEpisode(): метка или узел исчезли
        # между пометкой и кликом (ChildTearError от findNode() либо
        # CDPError "Could not find node with given id"). Реально
        # наблюдался второй вариант при клике 'Publish' после выставленной
        # даты. Обе формы обрабатываются переходом к следующей итерации,
        # которая заново помечает актуальную кнопку, не обрывая публикацию.
        discard
    await sleepAsync(300)
    if not await modalOpen():
      modalClosed = true
      break

  if not modalClosed:
    await dumpOnFailure(tab, "redcircle-debug-no-submit-button", screenshotDir)
    if not sawButton:
      raise newException(SiteWorkerError, &"не нашлась кнопка '{buttonText}'")
    raise newException(SiteWorkerError,
      &"после нажатия(ий) '{buttonText}' модальное окно создания эпизода не закрылось")

  if verbose:
    let softSuccessText = (await pageHasText(tab, "published")) or
                          (await pageHasText(tab, "draft saved")) or
                          (await pageHasText(tab, "success"))
    echo "  Модальное окно закрылось. Неспецифичный текст об успехе на странице: ",
      (if softSuccessText: "найден" else: "не найден"), " (это лишь дополнительный сигнал)."

  await waitForProcessingOverlayGone(tab, UploadStallTimeoutMs, UploadAbsoluteMaxMs, verbose)

  let overlayGone = not (await pageHasText(tab, ProcessingOverlayTexts[0])) and
                     not (await pageHasText(tab, ProcessingOverlayTexts[1]))
  if not overlayGone:
    # Загрузка не зависла (иначе сработал бы stallTimeout), а выбрала весь
    # UploadAbsoluteMaxMs при растущем проценте. Ждать подтверждения ниже
    # бессмысленно: дампим и прерываем, не тратя PublishConfirmTimeoutMs.
    await dumpOnFailure(tab, "redcircle-debug-upload-still-running", screenshotDir)
    raise newException(SiteWorkerError,
      &"загрузка файла эпизода не завершилась за отведённый предел ({UploadAbsoluteMaxMs div 1000} сек) " &
      "— похоже, эпизод не был реально создан.")

  if verbose: echo "  Жду подтверждения публикации — смены URL на страницу эпизода " &
    "или появления заголовка (сервер может ещё обрабатывать аудио)..."
  proc confirmedByUrl(): Future[bool] {.async.} =
    let url = await currentUrl(tab)
    result = url != prePublishUrl and "/create" notin url
  proc confirmedByTitle(): Future[bool] {.async.} = result = await pageHasText(tab, title)

  var confirmedVia = ""
  var waitedMs = 0
  const progressEveryMs = 15_000
  while waitedMs <= PublishConfirmTimeoutMs:
    if await confirmedByUrl():
      confirmedVia = "URL страницы эпизода"
      break
    if await confirmedByTitle():
      confirmedVia = "заголовок на странице"
      break
    await sleepAsync(300)
    waitedMs += 300
    if verbose and waitedMs mod progressEveryMs < 300:
      echo "    ...жду ещё (", waitedMs div 1000, "/", PublishConfirmTimeoutMs div 1000, " сек)"

  if len(confirmedVia) == 0:
    await dumpOnFailure(tab, "redcircle-debug-no-episode-in-list", screenshotDir)
    raise newException(SiteWorkerError,
      &"после нажатия '{buttonText}' модальное окно закрылось, но ни URL страницы, ни " &
      &"заголовок '{title}' не подтвердили публикацию за {PublishConfirmTimeoutMs div 1000} сек " &
      "— похоже, эпизод не был реально создан.")

  # Смена URL и появление заголовка не отличают "опубликован" от
  # "запланирован на будущее" (см. PublishDateFieldLabel), поэтому при
  # draft = false страница эпизода проверяется на признаки отложенной
  # публикации.
  if not draft:
    let stillScheduled = await pageHasText(tab, "to publish on")
    if stillScheduled:
      await dumpOnFailure(tab, "redcircle-debug-still-scheduled", screenshotDir)
      raise newException(SiteWorkerError,
        "после публикации эпизод остался в статусе ожидания будущей даты " &
        "('...To Publish on ...') вместо немедленной публикации — вероятно, поле " &
        &"'{PublishDateFieldLabel}' не удалось перевести на текущий момент " &
        "(см. setPublishDateToNow()); эпизод не появится в списке/RSS шоу, пока это " &
        "не будет исправлено.")

  if verbose: echo "Готово: ", (if draft: "черновик сохранён" else: "эпизод опубликован"),
    " — подтверждено по сигналу: ", confirmedVia, "."



# ---------------------------------------------------------------------------
# Вход в аккаунт и сохранение сессии
# ---------------------------------------------------------------------------

const
  SessionCookieLifetimeDays = 30
    ## На сколько дней вперёд продлеваются сессионные cookie RedCircle —
    ## см. persistSessionCookies().

proc persistSessionCookies*(tab: Tab, days = SessionCookieLifetimeDays): Future[int] {.async.} =
  ## Превращает сессионные cookie RedCircle (без Expires/Max-Age) в
  ## постоянные со сроком жизни days дней; возвращает число переписанных.
  ##
  ## Chromium не сохраняет сессионные cookie на диск и теряет их при
  ## завершении процесса. Если вход хранится именно в такой cookie, после
  ## перезапуска /shows перенаправляет на /sign-in, хотя вход был выполнен
  ## в этом же профиле. Вызывать на уже залогиненной вкладке
  ## app.redcircle.com.
  result = 0
  let pageUrl = await currentUrl(tab)
  if "redcircle.com" notin pageUrl:
    return
  let expiresAt = epochTime() + float(days) * 86_400.0
  for c in await cookies(tab, @[RedcircleBaseUrl]):
    if not getBool(getOrDefault(c, "session"), false):
      continue
    let
      name = getStr(getOrDefault(c, "name"))
      value = getStr(getOrDefault(c, "value"))
      domain = getStr(getOrDefault(c, "domain"))
      path = getStr(getOrDefault(c, "path"), "/")
      sameSite = getStr(getOrDefault(c, "sameSite"))
    if len(name) == 0:
      continue
    # Cookie с доменом ".redcircle.com" задаётся по domain; host-only cookie
    # (домен без точки) — по URL текущей вкладки, с привязкой к хосту.
    let domainArg = if startsWith(domain, "."): domain else: ""
    try:
      if await setCookie(tab, name, value, domain = domainArg, path = path,
                         secure = getBool(getOrDefault(c, "secure"), false),
                         httpOnly = getBool(getOrDefault(c, "httpOnly"), false),
                         sameSite = sameSite, expires = expiresAt):
        inc result
    except CatchableError:
      discard

proc loginRedcircle*(): Future[void] {.async.} =
  ## Интерактивный вход в RedCircle: открывает видимый Chromium с профилем
  ## ProfileDir, ждёт, пока пользователь войдёт и нажмёт Enter, проверяет
  ## вход, сохраняет сессионные cookie на диск и закрывает браузер, чтобы
  ## всё записалось в профиль. Использует ensureBrowserForLogin(): иначе
  ## произошло бы подключение к фоновому headless-процессу, и окно входа не
  ## появилось бы.
  let handle = await ensureBrowserForLogin(ProfileDir, DebugPort)
  var tab: Tab
  try:
    tab = await gotoWithRetry(handle.browser, ShowsListUrl, verbose = false)
    echo "Открыт app.redcircle.com в видимом окне Chromium."
    echo "Профиль: ", ProfileDir
    echo "Войдите в аккаунт в открывшемся окне, дождитесь списка шоу (/shows), затем нажмите Enter здесь..."
    discard readLine(stdin)

    await sleepAsync(1_000)
    let url = await currentUrl(tab)
    if "/sign-in" in url:
      echo "⚠ Всё ещё открыта страница входа (", url, ") — похоже, войти не удалось. ",
           "Запустите команду ещё раз."
    else:
      let saved = await persistSessionCookies(tab)
      echo "✓ Вход выполнен (", url, "). Сессионных cookie сохранено на диск: ", saved, "."
  finally:
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard
    # Штатное закрытие браузера сбрасывает cookie на диск. Следующий
    # автоматический прогон поднимет свежий headless-процесс сам.
    await stopBrowser(DebugPort)

# ---------------------------------------------------------------------------
# Публичная функция: uploadToRedcircle
# ---------------------------------------------------------------------------

proc uploadToRedcircle*(title: string, description: string, file: string,
                         showId: string = RedcircleShowId, draft = false,
                         headless = true, verbose = true,
                         screenshotDir: string = ""): Future[void] {.async.} =
  ## Загружает эпизод на RedCircle: открывает список эпизодов шоу showId,
  ## создаёт эпизод с заголовком title, описанием description и аудио file,
  ## публикует его (при draft = true — сохраняет как черновик).
  ##
  ## Использует сохранённый профиль Chromium (ProfileDir); если сессия не
  ## авторизована, войдите вручную (см. шапку файла). Браузер
  ## переиспользуется (browser_lifecycle.ensureBrowser()): функция
  ## открывает вкладку и закрывает только её, процесс не трогает.
  ##
  ## Бросает SiteWorkerError, если ожидаемый элемент/текст не найден, и
  ## ChildTearError при низкоуровневых сбоях. При ошибке пишет отладочный
  ## снимок (redcircle-debug-*.png/.html/-console.json), см. dumpOnFailure().
  if len(strutils.strip(title)) == 0:
    raise newException(ValueError, "title не должен быть пустым")
  if len(strutils.strip(description)) == 0:
    raise newException(ValueError, "description не должен быть пустым")
  if not fileExists(file):
    raise newException(IOError, "файл не найден: " & file)
  let absPath = absolutePath(file)

  let handle = await ensureBrowser(ProfileDir, DebugPort, headless = headless)
  if verbose:
    echo (if handle.attached: "Подключаюсь к уже работающему Chromium (RedCircle)..."
          else: "Запускаю headless-Chromium (RedCircle) с сохранённым профилем...")

  let rec = newStepRecorder(screenshotDir)
  if len(screenshotDir) > 0 and verbose:
    echo "Пошаговые скриншоты будут сохранены в: ", screenshotDir

  var tab: Tab
  try:
    tab = await openEpisodesPageForShow(handle.browser, showId, verbose, screenshotDir)
    await step(rec, tab, "episodes-list")

    await clickNewEpisode(tab, verbose, screenshotDir)
    await step(rec, tab, "new-episode-modal-open")

    await fillTitle(tab, title, verbose, screenshotDir)
    await step(rec, tab, "title-filled")

    await fillDescription(tab, description, verbose, screenshotDir)
    await step(rec, tab, "description-filled")

    await attachContent(tab, absPath, verbose, screenshotDir)
    await step(rec, tab, "content-attached")

    if not draft:
      await setPublishDateToNow(tab, verbose, screenshotDir)
      await step(rec, tab, "publish-date-set")

    await submitEpisode(tab, title, draft, verbose, screenshotDir)
    await step(rec, tab, "submitted-confirmed")

  except CatchableError as e:
    if verbose: echo "Ошибка: ", e.msg
    if not isNil(tab):
      await step(rec, tab, "error")
      await dumpOnFailure(tab, "redcircle-debug-failure", screenshotDir)
    raise
  finally:
    # Закрываем только свою вкладку — общий процесс Chromium (см. модель
    # владения в browser_lifecycle.ensureBrowser()) не трогаем ни при успехе, ни
    # при ошибке.
    if not isNil(tab):
      try:
        await close(tab)
      except CatchableError:
        discard


