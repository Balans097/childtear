## childtear.nim
##
## Высокоуровневая библиотека для управления headless-Chromium, запущенным
## командой:
##
##   chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox
##
## Простые команды: открыть вкладку, перейти по ссылке, нажать кнопку,
## заполнить форму, получить текст элемента, сделать скриншот. Протокол
## Chrome DevTools скрыт в модулях cdp/*.
##
## Записи вида "pageApi.enable(session)" — вызов процедуры конкретного
## модуля по псевдониму (import ... as pageApi), а не UFCS: так в Nim
## различаются одноимённые "Page.enable"/"DOM.enable"/"Runtime.enable" из
## разных domains/*.nim.
##
## Файл ограничен ядром CDP-обёртки (Browser/Tab/Frame: навигация, клики,
## формы, скриншоты, сеть, эмуляция, диагностика). Инфраструктура
## сценариев сайт-автоматизации лежит в siteworkers/:
##   - siteworker_common.nim — SiteWorkerError/SiteWorkerPref/ImageFormat/
##     AskResult, vecho/warnLoggedOut, поиск элементов по тексту (mark*);
##   - browser_lifecycle.nim — запуск и переиспользование Chromium
##     (ensureBrowser/stopBrowser), gotoWithRetry, dumpDebugInfoVerbose;
##   - clipboard.nim — скриншот ответа ассистента и буфер обмена.
## Зависимости идут вниз: siteworkers/ -> childtear.nim -> cdp/.



import std/[asyncdispatch, json, base64, strformat, strutils, times, uri, unicode]

import ./cdp/browser as browserApi
import ./cdp/transport
import ./cdp/domains/page as pageApi
import ./cdp/domains/dom as domApi
import ./cdp/domains/runtime as runtimeApi
import ./cdp/domains/input as inputApi
import ./cdp/domains/network as networkApi
import ./cdp/domains/fetch as fetchApi
import ./cdp/domains/emulation as emulationApi
import ./cdp/domains/target as targetApi
import ./cdp/domains/browserdomain as browserDomainApi
import ./cdp/domains/storage as storageApi



# CDPError экспортируется отдельно от ChildTearError: ChildTearError
# бросается там, где childtear.nim сам решил, что что-то не так (элемент не
# найден), а "сырые" ошибки протокола (например, {"code":-32000,"message":
# "Could not find node with given id"} при гонке между querySelector() и
# getBoxModel()/dispatchMouseEvent(), когда React заменил узел) приходят как
# CDPError и НЕ являются подтипом ChildTearError. Retry-циклы вида
# "except ChildTearError: discard" эту категорию не ловят, поэтому вызывающие
# модули (siteworkers/*.nim) обрабатывают CDPError отдельно.
export transport.CDPSession # на случай, если понадобится доступ к низкому уровню
export transport.CDPError


const ChildTearVersion* = "1.0"
  ## Версия библиотеки.

const MaxNetFailures = 1000
  ## Предел записей Tab.netFailures: журнал не должен расти бесконечно.

const DefaultDebuggingPort* = 9222
  ## Порт Chrome DevTools Protocol по умолчанию (--remote-debugging-port).
  ## Используется как дефолт в newBrowser(); cdp/browser.nim хранит тот
  ## же литерал отдельно — на случай прямого использования без childtear.



type
  ChildTearError* = object of CatchableError
    ## Ошибки высокого уровня: элемент не найден, таймаут ожидания и т.п.

  Browser* = ref object
    conn: browserApi.BrowserConnection
    bsession: CDPSession
      ## Browser-level сессия (для команд домена Browser/Target,
      ## которые нельзя посылать в сессию отдельной вкладки) —
      ## создаётся лениво при первом обращении, см. browserSession().

  Tab* = ref object
    session*: CDPSession           ## доступен напрямую для низкоуровневых вызовов
    browser: Browser               ## владелец вкладки (HTTP-эндпоинты и browser-level сессия)
    targetId*: string
    wsUrl*: string
    netFailures*: seq[JsonNode]
      ## Заполняется installNetworkFailureLog(): сетевые сбои уровня CDP
      ## (Network.loadingFailed и ответы 4xx/5xx). Ловушка installDiagnostics()
      ## внутри страницы не видит сбоев загрузки <script src> и <link
      ## rel="stylesheet">: браузер грузит их мимо fetch/XHR, поэтому они не
      ## попадают в console.json, а на уровне CDP Network видны всегда.

  Frame* = ref object
    ## Содержимое одного iframe (получается через Tab.frame()) — свой
    ## DOM-поддокумент (docNodeId) и свой JS execution context (contextId,
    ## создаётся лениво при первом evalJS()/getText()/fill()).
    tab: Tab
    frameId: string
    docNodeId: int
    contextId: int

# -----------------------------------------------------------------
# Базовые примитивы
# -----------------------------------------------------------------

proc detach[T](fut: Future[T]) =
  ## Отпускает уже запущенную асинхронную операцию «в фоне» и гасит её
  ## ошибку. В отличие от asyncCheck, не роняет процесс, если операция
  ## упала (например, вкладку закрыли раньше, чем она завершилась).
  fut.addCallback(proc() = discard)

proc evalJS*(tab: Tab, expression: string): Future[JsonNode] {.async.} =
  ## Исполняет произвольный JS-код и возвращает результат в виде JSON —
  ## для случаев, не покрытых готовыми командами.
  result = await runtimeApi.evaluateValue(tab.session, expression)

proc currentUrl*(tab: Tab): Future[string] {.async.} =
  ## Текущий URL страницы (location.href) — с учётом редиректов и
  ## клиентской навигации.
  let value = await runtimeApi.evaluateValue(tab.session, "location.href")
  result = getStr(value)

proc goto*(tab: Tab, url: string, timeoutMs = 30_000) {.async.} =
  ## «Перейти по ссылке»: загружает url и дожидается Page.loadEventFired.
  ## Если навигация не смогла начаться (DNS, некорректный URL),
  ## Page.navigate вернёт "errorText" — он превращается в ChildTearError.
  ##
  ## Ожидание load создаётся ДО Page.navigate: waitForEvent() подписывается
  ## синхронно при вызове, поэтому быстрая (например, закэшированная)
  ## страница не успевает загрузиться раньше подписки.
  let loaded = waitForEvent(tab.session, "Page.loadEventFired", timeoutMs)
  try:
    let navResult = await pageApi.navigate(tab.session, url)
    if hasKey(navResult, "errorText"):
      raise newException(ChildTearError,
        &"переход не удался ({getStr(navResult[\"errorText\"])}): {url}")
  except CatchableError:
    detach(loaded)
    raise
  discard await loaded

proc reload*(tab: Tab, ignoreCache = false) {.async.} =
  ## Перезагружает страницу и дожидается Page.loadEventFired.
  ## ignoreCache = true — жёсткая перезагрузка мимо HTTP-кэша (Ctrl+Shift+R).
  let loaded = waitForEvent(tab.session, "Page.loadEventFired")
  try:
    await pageApi.reload(tab.session, ignoreCache)
  except CatchableError:
    detach(loaded)
    raise
  discard await loaded

# -----------------------------------------------------------------
# Браузер и вкладки
# -----------------------------------------------------------------

proc newBrowser*(host = "127.0.0.1", port = DefaultDebuggingPort): Browser =
  ## Описывает подключение к уже запущенному headless-Chromium
  ## (см. команду запуска в шапке файла). Само по себе ничего не
  ## открывает — соединение устанавливается в openTab().
  Browser(conn: browserApi.newBrowserConnection(host, port))

proc connectTab(browser: Browser, targetId, wsUrl: string): Future[Tab] {.async.} =
  ## Общая часть openTab()/attachTab(): открывает CDP-сессию к вкладке и
  ## включает домены Page/DOM/Runtime. При ошибке сессия закрывается,
  ## чтобы не оставлять «висящий» WebSocket.
  let session = await newCDPSession(wsUrl)
  try:
    await pageApi.enable(session)
    await domApi.enable(session)
    await runtimeApi.enable(session)
  except CatchableError:
    await transport.close(session)
    raise
  result = Tab(session: session, browser: browser, targetId: targetId, wsUrl: wsUrl)

proc closeSafely(tab: Tab) {.async.}

proc openTab*(browser: Browser, url = ""): Future[Tab] {.async.} =
  ## «Открыть вкладку». Создаёт новую вкладку, подключается к ней по
  ## WebSocket и включает домены Page/DOM/Runtime. Если передан url —
  ## переходит по нему и дожидается загрузки. Если подключение или
  ## переход не удались, созданная вкладка закрывается.
  let target = await newTarget(browser.conn, "about:blank")
  let targetId = getStr(target["id"])
  try:
    result = await connectTab(browser, targetId, getStr(target["webSocketDebuggerUrl"]))
    if len(url) > 0:
      await goto(result, url)
  except CatchableError:
    if result != nil:
      await closeSafely(result)
    else:
      try:
        await closeTarget(browser.conn, targetId)
      except CatchableError:
        discard
    raise

proc listTabs*(browser: Browser): Future[seq[JsonNode]] {.async.} =
  ## Список всех открытых вкладок (как в chrome://inspect); каждый
  ## элемент содержит "id", "title", "url".
  result = await listTargets(browser.conn)

proc attachTab*(browser: Browser, targetId: string): Future[Tab] {.async.} =
  ## Подключается к уже существующей вкладке по id (из listTabs()),
  ## не создавая новую.
  let targets = await listTargets(browser.conn)
  var found: JsonNode = nil
  for t in targets:
    if getStr(t["id"]) == targetId:
      found = t
      break
  if found == nil:
    raise newException(ChildTearError, &"вкладка с id={targetId} не найдена")
  result = await connectTab(browser, targetId, getStr(found["webSocketDebuggerUrl"]))

proc close*(tab: Tab) {.async.} =
  ## Закрывает вкладку: сначала CDP-сессию, затем саму вкладку в браузере
  ## (HTTP /json/close). Закрытие вкладки выполняется, даже если сессия
  ## уже оборвана.
  try:
    await transport.close(tab.session)
  finally:
    await closeTarget(tab.browser.conn, tab.targetId)

proc closeSafely(tab: Tab) {.async.} =
  ## close() без исключений — для путей обработки ошибок.
  try:
    await close(tab)
  except CatchableError:
    discard

proc newPage*(browser: Browser, url = ""): Future[Tab] {.async.} =
  ## Синоним openTab() — так этот метод называется в Puppeteer
  ## (browser.newPage()).
  result = await openTab(browser, url)

type RetryCallback* = proc(attempt, attempts: int, msg: string) {.gcsafe.}
  ## Вызывается перед повторной попыткой: номер неудавшейся попытки,
  ## общее число попыток и текст ошибки.

proc newPageWithRetry*(browser: Browser, url: string, attempts = 3,
                        delayMs = 2_000, onRetry: RetryCallback = nil): Future[Tab] {.async.} =
  ## Как newPage(), но при неудаче повторяет попытку до attempts раз с
  ## паузой delayMs — полезно на холодном старте Chromium, когда порт
  ## отладки уже готов, а сеть/прокси ещё нет.
  ##
  ## Ловится любой CatchableError, а не только ChildTearError: обрыв HTTP
  ## к /json/new приходит как httpclient.ProtocolError.
  for attempt in 1 .. attempts:
    try:
      return await newPage(browser, url)
    except CatchableError as e:
      if attempt == attempts:
        raise
      if onRetry != nil:
        onRetry(attempt, attempts, e.msg)
      await sleepAsync(delayMs)

proc pages*(browser: Browser): Future[seq[Tab]] {.async.} =
  ## Подключается ко всем уже открытым вкладкам браузера (аналог
  ## browser.pages() в Puppeteer) — воркеры/сервис-воркеры и т.п.
  ## из списка целей пропускаются, остаются только настоящие вкладки.
  let targets = await listTargets(browser.conn)
  result = @[]
  for t in targets:
    if hasKey(t, "type") and getStr(t["type"]) == "page":
      add(result, await attachTab(browser, getStr(t["id"])))

proc version*(browser: Browser): Future[JsonNode] =
  ## Метаданные браузера: версия Chromium, User-Agent по умолчанию,
  ## версия протокола и т.д.
  browserVersion(browser.conn)

proc waitForReady*(browser: Browser, timeoutMs = 15_000) {.async.} =
  ## Ждёт готовности CDP-порта, опрашивая /json/version с шагом 200мс —
  ## полезно сразу после запуска процесса Chromium (childtear его не
  ## запускает сам, см. шапку файла), пока порт ещё не поднялся.
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  while epochTime() < deadline:
    try:
      discard await version(browser)
      return
    except CatchableError:
      await sleepAsync(200)
  raise newException(ChildTearError,
    &"Chromium не поднял отладочный порт за отведённые {timeoutMs}мс")

proc browserSession(browser: Browser): Future[CDPSession] {.async.} =
  ## Browser-level CDP-сессия (команды Browser.*, Target.*, не привязанные
  ## к вкладке). Создаётся при первом обращении и переиспользуется;
  ## оборвавшаяся сессия пересоздаётся.
  if browser.bsession == nil or not isAlive(browser.bsession):
    let ver = await browserVersion(browser.conn)
    browser.bsession = await newCDPSession(getStr(ver["webSocketDebuggerUrl"]))
  result = browser.bsession

proc close*(browser: Browser) {.async.} =
  ## Закрывает браузер целиком (все вкладки, весь процесс) — в отличие
  ## от close(Tab), которая закрывает одну вкладку.
  let session = await browserSession(browser)
  try:
    await browserDomainApi.close(session)
  except CatchableError:
    discard
  try:
    await transport.close(session)
  except CatchableError:
    discard
  browser.bsession = nil

proc createIncognitoContext*(browser: Browser): Future[string] {.async.} =
  ## Создаёт изолированный профиль (свои куки/кэш/localStorage) —
  ## аналог browser.createIncognitoBrowserContext() в Puppeteer.
  ## Возвращает browserContextId для newPageInContext()/closeContext().
  let session = await browserSession(browser)
  result = await targetApi.createBrowserContext(session)

proc newPageInContext*(browser: Browser, browserContextId: string, url = ""): Future[Tab] {.async.} =
  ## Открывает вкладку внутри изолированного профиля, созданного
  ## createIncognitoContext().
  let
    session = await browserSession(browser)
    targetId = await targetApi.createTarget(session, "about:blank", browserContextId = browserContextId)
  result = await attachTab(browser, targetId)
  if len(url) > 0:
    await goto(result, url)

proc closeContext*(browser: Browser, browserContextId: string) {.async.} =
  ## Уничтожает изолированный профиль и закрывает все его вкладки.
  let session = await browserSession(browser)
  await targetApi.disposeBrowserContext(session, browserContextId)

proc enableNetwork*(tab: Tab) {.async.} =
  ## Включает домен Network — не делается по умолчанию, чтобы не
  ## тратить лишний трафик на события, если они не нужны.
  await networkApi.enable(tab.session)

proc installNetworkFailureLog*(tab: Tab) {.async.} =
  ## Включает домен Network (enableNetwork()) и на всё время жизни
  ## вкладки подписывается на Network.loadingFailed и
  ## Network.responseReceived, накапливая в tab.netFailures сетевые ошибки
  ## (DNS, обрыв, блокировка) и ответы 4xx/5xx для любых ресурсов, а не
  ## только fetch()/XHR (см. поле netFailures у Tab). В отличие от
  ## JS-ловушки installDiagnostics() работает на уровне CDP и не зависит от
  ## выполнения JS страницы.
  ##
  ## Вызывать сразу после открытия вкладки, до навигации: иначе пропустятся
  ## сбои самых ранних запросов (документ, стартовый бандл), важные при
  ## диагностике SPA, зависшей на лоадере. Подписка снимается при close().
  await networkApi.enable(tab.session)

  proc onLoadingFailed(params: JsonNode) {.gcsafe.} =
    try:
      if len(tab.netFailures) >= MaxNetFailures:
        return
      add(tab.netFailures, %*{
        "kind": "loadingFailed",
        "requestId": params{"requestId"},   # url недоступен напрямую в этом событии CDP
        "type": params{"type"},
        "errorText": params{"errorText"},
        "canceled": params{"canceled"},
      })
    except CatchableError:
      discard

  proc onResponseReceived(params: JsonNode) {.gcsafe.} =
    try:
      let status = getInt(params{"response"}{"status"}, 0)
      if status >= 400 and len(tab.netFailures) < MaxNetFailures:
        add(tab.netFailures, %*{
          "kind": "httpError",
          "url": params{"response"}{"url"},
          "type": params{"type"},
          "status": status,
        })
    except CatchableError:
      discard

  on(tab.session, "Network.loadingFailed", onLoadingFailed)
  on(tab.session, "Network.responseReceived", onResponseReceived)

proc setExtraHeaders*(tab: Tab, headers: openArray[(string, string)]) {.async.} =
  ## Добавляет заданные заголовки ко всем последующим HTTP-запросам этой
  ## вкладки (например, авторизацию или кастомный User-Agent-подобный
  ## заголовок) — действует, пока не будет вызван повторно с другим
  ## набором. Требует включённого домена Network (см. enableNetwork()).
  var obj = newJObject()
  for (k, v) in headers:
    obj[k] = %v
  await networkApi.setExtraHTTPHeaders(tab.session, obj)

proc blockUrls*(tab: Tab, urlSubstrings: seq[string]) {.async.} =
  ## Блокирует запросы, чей URL содержит любую из подстрок
  ## urlSubstrings (например, домены рекламы/трекеров), пропуская
  ## остальные без изменений. Построено на домене Fetch.
  await fetchApi.enable(tab.session)
  let session = tab.session

  proc onRequestPaused(params: JsonNode) {.gcsafe.} =
    let
      requestId = getStr(params["requestId"])
      url = getStr(params["request"]["url"])
    var blocked = false
    for pattern in urlSubstrings:
      if pattern in url:
        blocked = true
        break
    if blocked:
      detach fetchApi.failRequest(session, requestId)
    else:
      detach fetchApi.continueRequest(session, requestId)

  on(session, "Fetch.requestPaused", onRequestPaused)

proc setViewport*(tab: Tab, width, height: int, deviceScaleFactor = 1.0, mobile = false) {.async.} =
  ## Подделывает размер вьюпорта и плотность пикселей (аналог
  ## page.setViewport() в Puppeteer). Действует, пока не будет вызван
  ## повторно с другими значениями — на размер самого окна браузера
  ## (в headless-режиме не имеющего экрана) не влияет.
  await emulationApi.setDeviceMetricsOverride(tab.session, width, height, deviceScaleFactor, mobile)

proc setUserAgent*(tab: Tab, userAgent: string, acceptLanguage = "", platform = "") {.async.} =
  ## Подделывает navigator.userAgent (и, опционально, Accept-Language и
  ## navigator.platform) для всех последующих запросов и скриптов этой
  ## вкладки — действует до следующего вызова с другими значениями.
  await emulationApi.setUserAgentOverride(tab.session, userAgent, acceptLanguage, platform)

proc cookies*(tab: Tab, urls: seq[string] = @[]): Future[seq[JsonNode]] {.async.} =
  ## Без urls возвращает куки, видимые текущей странице.
  result = await networkApi.getCookies(tab.session, urls)

proc setCookie*(tab: Tab, name, value: string, domain = "", path = "/", secure = false,
                httpOnly = false, sameSite = "",
                expires = 0.0): Future[bool] {.async.} =
  ## expires > 0 (секунды с эпохи Unix) делает куку постоянной — см.
  ## networkApi.setCookie().
  ## Нужно указать domain, либо кука будет привязана к текущему URL
  ## вкладки (запрашивается автоматически, если domain не передан).
  var url = ""
  if len(domain) == 0:
    url = await currentUrl(tab)
  result = await networkApi.setCookie(tab.session, name, value, url = url, domain = domain,
                                       path = path, secure = secure, httpOnly = httpOnly,
                                       sameSite = sameSite, expires = expires)

proc deleteCookie*(tab: Tab, name: string, url = "") {.async.} =
  ## Удаляет одну куку по имени (и, опционально, url — если не
  ## передан, берётся текущий URL вкладки). В отличие от clearCookies(),
  ## затрагивает только эту одну куку, а не весь браузер.
  var u = url
  if len(u) == 0:
    u = await currentUrl(tab)
  await networkApi.deleteCookies(tab.session, name, url = u)

proc clearCookies*(tab: Tab) {.async.} =
  ## ВНИМАНИЕ: у Chromium нет способа очистить куки только одной
  ## вкладки — эта команда чистит куки всего браузера целиком (все
  ## вкладки, все сайты, все открытые профили). Если нужно очистить
  ## куки только текущего сайта — см. clearCookiesForOrigin().
  await networkApi.clearBrowserCookies(tab.session)

proc clearCookiesForOrigin*(tab: Tab) {.async.} =
  ## В отличие от clearCookies() (весь браузер сразу — так устроен CDP),
  ## удаляет только куки текущей страницы: получает их список через
  ## cookies() и удаляет каждую по отдельности, привязав к её URL.
  let url = await currentUrl(tab)
  for c in await cookies(tab, @[url]):
    await networkApi.deleteCookies(tab.session, getStr(c["name"]), url = url)

proc content*(tab: Tab): Future[string] {.async.} =
  ## Полный HTML документа (document.documentElement.outerHTML) —
  ## аналог page.content() в Puppeteer.
  let value = await runtimeApi.evaluateValue(tab.session, "document.documentElement.outerHTML")
  result = getStr(value)

proc setContent*(tab: Tab, html: string) {.async.} =
  ## Заменяет содержимое страницы на произвольный HTML без перехода по
  ## URL (аналог page.setContent() в Puppeteer) — удобно для тестов,
  ## когда нужна страница с точно заданной разметкой.
  let
    tree = await pageApi.getFrameTree(tab.session)
    frameId = getStr(tree["frameTree"]["frame"]["id"])
  await pageApi.setDocumentContent(tab.session, frameId, html)

# -----------------------------------------------------------------
# Внутренние помощники поиска элементов
# -----------------------------------------------------------------

proc jsStringLiteral(s: string): string = 
  ## Безопасно оборачивает строку в JS/JSON-строковый литерал —
  ## используется, чтобы подставлять пользовательские CSS-селекторы
  ## и текст в JS-выражения, не боясь спецсимволов и кавычек.
  $(%s)

proc findNode(tab: Tab, selector: string): Future[int] {.async.} =
  ## Возвращает nodeId первого элемента, подходящего под CSS-селектор.
  ## Документ запрашивается заново при каждом вызове — на динамических
  ## страницах старые nodeId быстро протухают, а getDocument дёшев.
  let
    doc = await domApi.getDocument(tab.session)
    rootId = getInt(doc["root"]["nodeId"])
    nodeId = await domApi.querySelector(tab.session, rootId, selector)
  if nodeId == 0:
    raise newException(ChildTearError, &"элемент не найден по селектору: {selector}")
  result = nodeId

# -----------------------------------------------------------------
# Взаимодействие с элементами
# -----------------------------------------------------------------

proc nodeCenter(tab: Tab, nodeId: int): Future[(float, float)] {.async.} =
  ## Координаты центра узла на экране — общая логика для click()/hover().
  await domApi.scrollIntoViewIfNeeded(tab.session, nodeId)
  let
    box = await domApi.getBoxModel(tab.session, nodeId)
    quad = getElems(box["content"])
    # quad — четыре точки контура [x1,y1, x2,y2, x3,y3, x4,y4] по часовой
    # стрелке; (x1,y1) и (x3,y3) — противоположные углы прямоугольника.
    x1 = getFloat(quad[0])
    y1 = getFloat(quad[1])
    x3 = getFloat(quad[4])
    y3 = getFloat(quad[5])
  result = ((x1 + x3) / 2, (y1 + y3) / 2)

proc click*(tab: Tab, selector: string) {.async.} =
  ## "Нажать на кнопку" (или на любой другой элемент по CSS-селектору).
  ## Вычисляет центр элемента на экране и эмулирует настоящий клик
  ## мышью через домен Input — так же, как это делает пользователь.
  let nodeId = await findNode(tab, selector)
  let (centerX, centerY) = await nodeCenter(tab, nodeId)
  await inputApi.click(tab.session, centerX, centerY)

proc hover*(tab: Tab, selector: string) {.async.} =
  ## Наводит курсор на элемент, не кликая — эмулирует mouseover
  ## (полезно для выпадающих меню/тултипов, показывающихся по hover).
  let nodeId = await findNode(tab, selector)
  let (centerX, centerY) = await nodeCenter(tab, nodeId)
  await inputApi.moveMouse(tab.session, centerX, centerY)

proc fill*(tab: Tab, selector: string, text: string) {.async.} =
  ## Заполняет поле: фокусирует элемент, выделяет текущее содержимое (новый
  ## текст заменяет старый) и вставляет текст через Input.insertText.
  ##
  ## el.select() работает только у <input>/<textarea>; у contenteditable
  ## (Lexical, ProseMirror) содержимое выделяется через Selection/Range API,
  ## иначе insertText() дописывал бы текст к имеющемуся. В отличие от
  ## присваивания el.value/textContent, Input.insertText порождает настоящие
  ## beforeinput/input, поэтому внутреннее состояние редактора не расходится
  ## с DOM (для React-полей см. setControlledValue()).
  let
    sel = jsStringLiteral(selector)
    focusAndSelectJs = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      el.focus();
      if (typeof el.select === 'function') {{
        el.select();
      }} else if (el.isContentEditable) {{
        var range = document.createRange();
        range.selectNodeContents(el);
        var sel2 = window.getSelection();
        sel2.removeAllRanges();
        sel2.addRange(range);
      }}
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, focusAndSelectJs)
  if found.kind != JBool or not getBool(found):
    raise newException(ChildTearError, &"элемент для заполнения не найден: {selector}")
  await inputApi.insertText(tab.session, text)

proc insertTextAtCursor*(tab: Tab, text: string) {.async.} =
  ## Input.insertText без предварительного фокуса и выделения (в отличие
  ## от fill()): вставляет text в позицию курсора, дописывая к содержимому.
  ## Нужен, когда поле уже сфокусировано и заполняется частями: многострочный
  ## текст одним insertText() не создаёт разрывов абзацев в contenteditable
  ## (Lexical): "\n" схлопывается CSS. Поэтому первая строка идёт через
  ## fill(), остальные — pressEnter() + insertTextAtCursor() (см.
  ## fillDescription() в siteworkers/redcircle.nim).
  await inputApi.insertText(tab.session, text)

proc syncControlledValue*(tab: Tab, selector: string): Future[bool] {.async.} =
  ## Чинит controlled-поля React/Vue: фреймворк переопределяет нативный
  ## сеттер value, поэтому fill()/typeText() меняют .value в обход него, и
  ## компонент откатывает поле при ре-рендере. Вызывает нативный сеттер
  ## прототипа и диспатчит 'input'. Вызывать после fill()/typeText(), если
  ## поле заполнено визуально, а зависящая от него кнопка неактивна.
  ## Возвращает false, если элемент не найден.
  ##
  ## Только для настоящих <input>/<textarea>: нативные аксессоры проверяют
  ## тип получателя, и на другом элементе (например, <span contenteditable>)
  ## setter.call(el, ...) бросает "TypeError: Illegal invocation". Поэтому
  ## тег проверяется заранее, и для "не того" элемента возвращается false.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      if (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') return false;
      var proto = (el.tagName === 'TEXTAREA') ?
        window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
      setter.call(el, el.value);
      el.dispatchEvent(new Event('input', {{ bubbles: true }}));
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  result = found.kind == JBool and getBool(found)

proc setControlledValue*(tab: Tab, selector: string, value: string): Future[bool] {.async.} =
  ## Как syncControlledValue(), но пишет НОВОЕ value, а не переустанавливает
  ## текущее. Нужна, когда el.value = '' (clearValue()) не работает: такое
  ## присваивание идёт через инстанс-сеттер React, обновляет его внутренний
  ## "трекер" значения, и последующий 'input' не воспринимается как
  ## изменение (onChange не срабатывает). Здесь значение пишется через
  ## сеттер прототипа в обход перехватчика: трекер остаётся старым, value —
  ## новым, и React замечает рассинхронизацию.
  ##
  ## Только для <input>/<textarea> (см. syncControlledValue()).
  let
    sel = jsStringLiteral(selector)
    valLit = jsStringLiteral(value)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      if (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') return false;
      var proto = (el.tagName === 'TEXTAREA') ?
        window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
      setter.call(el, {valLit});
      el.dispatchEvent(new Event('input', {{ bubbles: true }}));
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  result = found.kind == JBool and getBool(found)

proc fillForm*(tab: Tab, fields: seq[(string, string)]) {.async.} =
  ## "Заполнить форму данными". Принимает список пар (селектор, значение)
  ## и последовательно заполняет каждое поле, например:
  ##   await fillForm(tab, @[("#login", "andy"), ("#password", "secret")])
  ## Параметр — seq, а не openArray: см. пояснение у pressKeyCombo() —
  ## openArray-параметр нельзя захватить в замыкание async-процедуры.
  for (selector, value) in fields:
    await fill(tab, selector, value)

proc typeText*(tab: Tab, selector: string, text: string, delayMs = 0) {.async.} =
  ## В отличие от fill() печатает по одному символу настоящими событиями
  ## клавиатуры — для полей с масками и автодополнением (как page.type() в
  ## Puppeteer). delayMs — пауза между символами. Перебираются руны
  ## (unicode.runes), а не байты: `for ch in text` разрезал бы
  ## многобайтовые символы UTF-8 (кириллицу) на невалидные половинки.
  await click(tab, selector)
  for rune in runes(text):
    await inputApi.typeChar(tab.session, $rune)
    if delayMs > 0:
      await sleepAsync(delayMs)

proc selectOption*(tab: Tab, selector: string, value: string) {.async.} =
  ## Выбирает option с указанным value в элементе <select> и генерирует
  ## событие "change", как это делает браузер при реальном выборе.
  let
    sel = jsStringLiteral(selector)
    val = jsStringLiteral(value)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      el.value = {val};
      el.dispatchEvent(new Event('change', {{ bubbles: true }}));
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  if found.kind != JBool or not getBool(found):
    raise newException(ChildTearError, &"элемент <select> не найден: {selector}")

proc uploadFile*(tab: Tab, selector: string, paths: seq[string]) {.async.} =
  ## Назначает файлы элементу <input type="file"> напрямую, без
  ## системного диалога выбора файла. paths — абсолютные пути на диске,
  ## где выполняется сам браузер (а не обязательно та машина, где
  ## работает childtear, если Chromium запущен удалённо).
  let nodeId = await findNode(tab, selector)
  await domApi.setFileInputFiles(tab.session, nodeId, paths)

proc submitForm*(tab: Tab, selector: string) {.async.} =
  ## Отправляет форму программно (эквивалент form.submit()) — полезно,
  ## когда у формы нет явной кнопки "Submit" под курсором.
  let sel = jsStringLiteral(selector)
  discard await runtimeApi.evaluate(tab.session, &"document.querySelector({sel}).submit()")

proc getText*(tab: Tab, selector: string): Future[string] {.async.} =
  ## Возвращает видимый текст элемента (innerText, либо textContent,
  ## если innerText недоступен, как в случае с SVG-узлами).
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return null;
      return (el.innerText !== undefined) ? el.innerText : el.textContent;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  if value.kind == JNull:
    raise newException(ChildTearError, &"элемент не найден: {selector}")
  result = getStr(value)

proc getAllText*(tab: Tab, selector: string): Future[seq[string]] {.async.} =
  ## Как getText(), но для ВСЕХ элементов, подходящих под селектор, —
  ## например, чтобы одним вызовом собрать текст всех заголовков
  ## новостей на странице (селектор вида "h3.headline"). Порядок
  ## результата совпадает с порядком элементов в документе.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var list = document.querySelectorAll({sel});
      var out = [];
      for (var i = 0; i < list.length; i++) {{
        var el = list[i];
        out.push((el.innerText !== undefined) ? el.innerText : el.textContent);
      }}
      return out;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = @[]
  for item in getElems(value):
    add(result, getStr(item))

proc getLastText*(tab: Tab, selector: string): Future[string] {.async.} =
  ## Как getText(), но берёт ПОСЛЕДНИЙ подходящий узел, а не первый —
  ## удобно для списков повторяющихся элементов (история чата, лента).
  ## В отличие от getText(), отсутствие совпадений не ошибка — "".
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var nodes = document.querySelectorAll({sel});
      if (nodes.length === 0) return null;
      var el = nodes[nodes.length - 1];
      return (el.innerText !== undefined) ? el.innerText : el.textContent;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = if value.kind == JString: getStr(value) else: ""

proc count*(tab: Tab, selector: string): Future[int] {.async.} =
  ## Считает число элементов, подходящих под CSS-селектор, — удобно
  ## как быстрая проверка вида "на странице есть хотя бы N карточек
  ## товара", не читая сам текст элементов.
  let
    sel = jsStringLiteral(selector)
    value = await runtimeApi.evaluateValue(tab.session, &"document.querySelectorAll({sel}).length")
  result = getInt(value)

proc saveText*(tab: Tab, selector: string, path: string) {.async.} =
  ## Удобная связка getText() + запись в файл: получает видимый текст
  ## элемента (например, всей статьи целиком, если селектор указывает
  ## на её контейнер — браузер уже вставит переносы строк между
  ## абзацами в самом innerText) и сохраняет его в текстовый файл path.
  let text = await getText(tab, selector)
  writeFile(path, text)

proc getAttribute*(tab: Tab, selector, name: string): Future[string] {.async.} =
  ## HTML-атрибут элемента (Element.getAttribute) — например,
  ## "href" у ссылки или "data-id" у произвольного data-атрибута.
  ## Возвращает пустую строку, если атрибута нет (не отличимо от
  ## атрибута с пустым значением — если это важно, проверяйте через
  ## exists()/evalJS() с hasAttribute()).
  let
    sel = jsStringLiteral(selector)
    attr = jsStringLiteral(name)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      return el ? el.getAttribute({attr}) : null;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = if value.kind == JNull: "" else: getStr(value)

proc exists*(tab: Tab, selector: string): Future[bool] {.async.} =
  ## Проверяет наличие элемента на странице прямо сейчас, без ожидания.
  let
    sel = jsStringLiteral(selector)
    value = await runtimeApi.evaluateValue(tab.session, &"document.querySelector({sel}) !== null")
  result = value.kind == JBool and getBool(value)

proc existsWithText*(tab: Tab, tag: string, textSubstring: string): Future[bool] {.async.} =
  ## Ищет элемент по HTML-тегу с подстрокой в видимом тексте
  ## (регистронезависимо) — замена отсутствующему в CSS :has-text(...)
  ## из Playwright, например для проверки "нет ли кнопки 'Log in'".
  let
    tagLit = jsStringLiteral(tag)
    textLit = jsStringLiteral(textSubstring)
    js = &"""(function() {{
      var needle = {textLit}.toLowerCase();
      var nodes = document.querySelectorAll({tagLit});
      for (var i = 0; i < nodes.length; i++) {{
        var text = (nodes[i].textContent || '').toLowerCase();
        if (text.indexOf(needle) !== -1) return true;
      }}
      return false;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  result = found.kind == JBool and getBool(found)

proc waitUntilTrue*(cond: proc(): Future[bool] {.async.}, timeoutMs = 5_000,
                     pollIntervalMs = 100): Future[bool] {.async.} =
  ## Опрашивает асинхронное условие cond каждые pollIntervalMs, пока оно
  ## не вернёт true или не истечёт timeoutMs (по часам, с учётом времени
  ## самих проверок). Возвращает false по таймауту, исключение не бросает.
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while true:
    if await cond():
      return true
    if epochTime() >= deadline:
      return false
    await sleepAsync(pollIntervalMs)

proc waitForSelector*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.} =
  ## Ждёт появления элемента на странице (например, после AJAX-запроса
  ## или анимации), опрашивая DOM с заданным интервалом. Возвращает
  ## true, если элемент появился до истечения timeoutMs, иначе false.
  proc found(): Future[bool] {.async.} = result = await exists(tab, selector)
  result = await waitUntilTrue(found, timeoutMs, pollIntervalMs)

proc waitForNavigation*(tab: Tab, timeoutMs = 30_000): Future[JsonNode] =
  ## В отличие от goto(), сама не запускает переход — лишь ждёт
  ## следующую загрузку. Подписка регистрируется синхронно при вызове,
  ## поэтому сценарий "кликнуть и дождаться перехода" работает без гонки:
  ##   let navigated = waitForNavigation(tab)
  ##   await click(tab, "a.some-link")
  ##   discard await navigated
  waitForEvent(tab.session, "Page.loadEventFired", timeoutMs)

proc waitForFunction*(tab: Tab, expression: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[JsonNode] {.async.} =
  ## Опрашивает JS-выражение, пока оно не вернёт истинное (в смысле JS)
  ## значение, и возвращает его — аналог page.waitForFunction() в
  ## Puppeteer. По таймауту (по часам) бросает ChildTearError.
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while true:
    let
      value = await evalJS(tab, expression)
      truthy = case value.kind
        of JNull: false
        of JBool: getBool(value)
        of JInt: getInt(value) != 0
        of JFloat: getFloat(value) != 0.0
        of JString: len(getStr(value)) > 0
        else: true
    if truthy:
      return value
    if epochTime() >= deadline:
      break
    await sleepAsync(pollIntervalMs)
  raise newException(ChildTearError, &"waitForFunction: условие не стало истинным за {timeoutMs}мс: {expression}")

proc pressEnter*(tab: Tab, selector = "") {.async.} =
  ## Нажимает Enter — в текущем сфокусированном элементе, либо (если
  ## передан selector) предварительно кликая на него. windowsVirtualKeyCode
  ## заполняет event.keyCode — часть обработчиков "отправить по Enter"
  ## проверяет именно его, а не event.key.
  if len(selector) > 0:
    await click(tab, selector)
  await inputApi.pressKey(tab.session, "Enter", "Enter", windowsVirtualKeyCode = 13)

type DialogHandler* = proc(message: string, kind: string, defaultPrompt: string) {.gcsafe.}

proc onDialog*(tab: Tab, handler: DialogHandler) =
  ## Подписывается на открытие JS-диалогов (alert/confirm/prompt/
  ## beforeunload). ВАЖНО: пока диалог открыт, вкладка "заморожена" —
  ## навигация и большинство команд не выполняются, пока диалог не
  ## закрыт через acceptDialog()/dismissDialog(). В отличие от
  ## интерактивного режима, Chromium НЕ закрывает диалоги сам — если
  ## не подписаться (или воспользоваться autoDismissDialogs()), вкладка
  ## может зависнуть на первом же alert().
  proc onOpening(params: JsonNode) {.gcsafe.} =
    let
      message = getStr(getOrDefault(params, "message"), "")
      kind = getStr(getOrDefault(params, "type"), "")
      defaultPrompt = getStr(getOrDefault(params, "defaultPrompt"), "")
    handler(message, kind, defaultPrompt)
  on(tab.session, "Page.javascriptDialogOpening", onOpening)

proc acceptDialog*(tab: Tab, promptText = "") {.async.} =
  ## Подтверждает открытый JS-диалог (OK у alert/confirm, Enter у
  ## prompt). promptText — что "ввести" в диалог prompt() перед
  ## подтверждением; для alert()/confirm() игнорируется.
  await pageApi.handleJavaScriptDialog(tab.session, true, promptText)

proc dismissDialog*(tab: Tab) {.async.} =
  ## Отклоняет открытый JS-диалог (Cancel у confirm/prompt; у alert()
  ## эквивалентно acceptDialog(), так как у него нет варианта "отмена").
  await pageApi.handleJavaScriptDialog(tab.session, false)

proc autoDismissDialogs*(tab: Tab) =
  ## Удобный дефолт: все диалоги автоматически отклоняются, чтобы
  ## страница не зависала, если явная обработка не нужна.
  proc onOpening(params: JsonNode) {.gcsafe.} =
    detach dismissDialog(tab)
  on(tab.session, "Page.javascriptDialogOpening", onOpening)

# -----------------------------------------------------------------
# Снимки страницы
# -----------------------------------------------------------------

proc screenshot*(tab: Tab, path: string, format = "png", fullPage = false, quality = 100) {.async.} =
  ## Сохраняет скриншот текущего состояния вкладки в файл по пути path.
  ## format: "png" или "jpeg". fullPage = true снимает всю страницу
  ## целиком (включая то, что за пределами текущего вьюпорта), а не
  ## только видимую область.
  var
    clip: JsonNode = nil
    captureBeyondViewport = false
  if fullPage:
    let
      metrics = await pageApi.getLayoutMetrics(tab.session)
      contentSize = metrics["contentSize"]
    clip = %*{
      "x": 0,
      "y": 0,
      "width": getFloat(contentSize["width"]),
      "height": getFloat(contentSize["height"]),
      "scale": 1,
    }
    captureBeyondViewport = true
  let dataBase64 = await pageApi.captureScreenshot(tab.session, format, quality, clip, captureBeyondViewport)
  writeFile(path, base64.decode(dataBase64))

proc savePDF*(tab: Tab, path: string, landscape = false, printBackground = true) {.async.} =
  ## Сохраняет текущую страницу в PDF (аналог "печати в PDF" из браузера).
  let dataBase64 = await pageApi.printToPDF(tab.session, landscape = landscape, printBackground = printBackground)
  writeFile(path, base64.decode(dataBase64))

proc title*(tab: Tab): Future[string] {.async.} =
  ## Текущий заголовок страницы (document.title).
  let value = await runtimeApi.evaluateValue(tab.session, "document.title")
  result = getStr(value)

# -----------------------------------------------------------------
# Инжектируемые скрипты и мост JS -> Nim
# -----------------------------------------------------------------

proc addScriptTag*(tab: Tab, url = "", content = "") {.async.} =
  ## Добавляет <script> на текущую страницу — либо по url (дожидается
  ## его загрузки), либо с готовым содержимым content (нужно указать
  ## ровно один из двух вариантов). Аналог page.addScriptTag() в
  ## Puppeteer.
  if (len(url) == 0) == (len(content) == 0):
    raise newException(ChildTearError, "addScriptTag: нужно указать ровно один из url/content")
  if len(url) > 0:
    let
      u = jsStringLiteral(url)
      js = &"""new Promise(function(resolve, reject) {{
        var s = document.createElement('script');
        s.src = {u};
        s.onload = function() {{ resolve(true); }};
        s.onerror = function() {{ reject(new Error('не удалось загрузить скрипт: ' + {u})); }};
        document.head.appendChild(s);
      }})"""
    discard await runtimeApi.evaluate(tab.session, js, awaitPromise = true)
  else:
    let
      c = jsStringLiteral(content)
      js = &"""(function() {{
        var s = document.createElement('script');
        s.textContent = {c};
        document.head.appendChild(s);
        return true;
      }})()"""
    discard await runtimeApi.evaluate(tab.session, js)

proc evaluateOnNewDocument*(tab: Tab, script: string): Future[string] {.async.} =
  ## Скрипт будет выполняться перед любым JS самой страницы при каждой
  ## следующей загрузке документа (аналог page.evaluateOnNewDocument()
  ## в Puppeteer). Возвращает identifier для removeEvaluateOnNewDocument().
  result = await pageApi.addScriptToEvaluateOnNewDocument(tab.session, script)

proc removeEvaluateOnNewDocument*(tab: Tab, identifier: string) {.async.} =
  ## Отменяет скрипт, добавленный evaluateOnNewDocument(), по identifier,
  ## который она вернула — на уже загруженный документ не влияет,
  ## только на следующие навигации.
  await pageApi.removeScriptToEvaluateOnNewDocument(tab.session, identifier)

type ExposedCallback* = proc(args: JsonNode): Future[JsonNode] {.gcsafe.}

proc exposeFunction*(tab: Tab, name: string, callback: ExposedCallback) {.async.} =
  ## Добавляет функцию `name` в window страницы: JS может вызвать её как
  ## обычную асинхронную функцию, а выполняется она здесь, на стороне
  ## Nim — аналог page.exposeFunction() в Puppeteer. callback получает
  ## аргументы вызова как JsonNode и должен вернуть JSON-сериализуемый
  ## результат. Технически — Runtime.addBinding плюс JS-шим, оборачивающий
  ## его в Promise, и обработчик "Runtime.bindingCalled".
  let rawName = "__childtear_binding_" & name
  await runtimeApi.addBinding(tab.session, rawName)

  let shimJs = &"""(function() {{
    window['__childtear_cbs'] = window['__childtear_cbs'] || {{}};
    window['__childtear_seq'] = window['__childtear_seq'] || 0;
    window[{jsStringLiteral(name)}] = function() {{
      var args = Array.prototype.slice.call(arguments);
      return new Promise(function(resolve, reject) {{
        var callId = ++window['__childtear_seq'];
        window['__childtear_cbs'][callId] = {{resolve: resolve, reject: reject}};
        window[{jsStringLiteral(rawName)}](JSON.stringify({{seq: callId, args: args}}));
      }});
    }};
  }})();"""

  # На уже загруженном документе функции ещё нет — добавляем её и туда,
  # а не только в addScriptToEvaluateOnNewDocument (который сработает
  # лишь при следующей навигации).
  discard await pageApi.addScriptToEvaluateOnNewDocument(tab.session, shimJs)
  discard await runtimeApi.evaluate(tab.session, shimJs)

  proc onBindingCalled(params: JsonNode) {.gcsafe.} =
    if getStr(getOrDefault(params, "name"), "") != rawName:
      return
    let payloadStr = getStr(getOrDefault(params, "payload"), "")

    proc handle() {.async.} =
      let
        payload = parseJson(payloadStr)
        callId = payload["seq"]
        args = payload["args"]
      var
        isError = false
        errorMsg = ""
        resultJson: JsonNode = newJNull()
      try:
        resultJson = await callback(args)
      except CatchableError as e:
        isError = true
        errorMsg = e.msg

      let resolveJs =
        if isError:
          &"""(function() {{
            var cb = window['__childtear_cbs'][{callId}];
            if (cb) {{ delete window['__childtear_cbs'][{callId}]; cb.reject(new Error({jsStringLiteral(errorMsg)})); }}
          }})();"""
        else:
          &"""(function() {{
            var cb = window['__childtear_cbs'][{callId}];
            if (cb) {{ delete window['__childtear_cbs'][{callId}]; cb.resolve({($resultJson)}); }}
          }})();"""
      discard await runtimeApi.evaluate(tab.session, resolveJs)

    detach handle()

  on(tab.session, "Runtime.bindingCalled", onBindingCalled)

# -----------------------------------------------------------------
# Навигация: история, остановка загрузки, фокус вкладки
# -----------------------------------------------------------------

proc goBack*(tab: Tab): Future[bool] {.async.} =
  ## Аналог кнопки "назад" браузера. Возвращает false (и никуда не
  ## переходит), если в истории вкладки нет предыдущей записи.
  let
    history = await pageApi.getNavigationHistory(tab.session)
    currentIndex = getInt(history["currentIndex"])
  if currentIndex <= 0:
    return false
  let entryId = getInt(getElems(history["entries"])[currentIndex - 1]["id"])
  let loaded = waitForEvent(tab.session, "Page.loadEventFired")
  try:
    await pageApi.navigateToHistoryEntry(tab.session, entryId)
  except CatchableError:
    detach(loaded)
    raise
  discard await loaded
  result = true

proc goForward*(tab: Tab): Future[bool] {.async.} =
  ## Аналог кнопки "вперёд". Возвращает false, если в истории вкладки
  ## нет следующей записи (например, назад ещё не переходили).
  let
    history = await pageApi.getNavigationHistory(tab.session)
    currentIndex = getInt(history["currentIndex"])
    entries = getElems(history["entries"])
  if currentIndex >= len(entries) - 1:
    return false
  let entryId = getInt(entries[currentIndex + 1]["id"])
  let loaded = waitForEvent(tab.session, "Page.loadEventFired")
  try:
    await pageApi.navigateToHistoryEntry(tab.session, entryId)
  except CatchableError:
    detach(loaded)
    raise
  discard await loaded
  result = true

proc stop*(tab: Tab) {.async.} =
  ## Останавливает текущую загрузку страницы (аналог кнопки "стоп" в
  ## браузере/Escape во время загрузки).
  await pageApi.stopLoading(tab.session)

proc bringToFront*(tab: Tab) {.async.} =
  ## Делает вкладку активной среди остальных вкладок того же браузера.
  await pageApi.bringToFront(tab.session)

proc waitForURL*(tab: Tab, substring: string, timeoutMs = 10_000, pollIntervalMs = 100): Future[bool] {.async.} =
  ## Ждёт, пока location.href не станет содержать substring — например,
  ## после клика по ссылке, ведущей через несколько промежуточных
  ## редиректов, когда одного Page.loadEventFired недостаточно.
  proc matches(): Future[bool] {.async.} = result = substring in (await currentUrl(tab))
  result = await waitUntilTrue(matches, timeoutMs, pollIntervalMs)

# -----------------------------------------------------------------
# Перетаскивание мышью (общие помощники dragAndDrop/dragBy/dragToEnd)

proc mouseEvent(session: CDPSession, kind, button: string,
                x, y: float, buttons, clickCount: int) {.async.} =
  ## Одно событие мыши с явной маской удерживаемых кнопок (buttons: левая = 1).
  await inputApi.dispatchMouseEvent(session, kind, x, y, button = button,
                                     clickCount = clickCount, buttons = buttons)

proc easeInOut(t: float): float =
  ## Сглаживание smoothstep для доли пути t (0.0 .. 1.0): живая рука
  ## движется неравномерно, а часть слайдер-капч отсеивает равномерный ход.
  result = t * t * (3.0 - 2.0 * t)

proc dragPath(session: CDPSession, startX, startY, endX, endY: float,
              steps, stepDelayMs, holdMs: int) {.async.} =
  ## Нажимает левую кнопку в (startX, startY), ведёт курсор в (endX, endY)
  ## за steps шагов по кривой easeInOut и отпускает кнопку. buttons = 1 в
  ## каждом mouseMoved нужен: обработчики pointermove/mousemove слайдеров
  ## без него считают кнопку отпущенной. При ошибке CDP кнопка всё равно
  ## отпускается, чтобы страница не осталась в состоянии «мышь зажата».
  let n = max(1, steps)
  await mouseEvent(session, "mouseMoved", "none", startX, startY, 0, 0)
  await mouseEvent(session, "mousePressed", "left", startX, startY, 1, 1)
  try:
    await sleepAsync(holdMs)
    for i in 1 .. n:
      let t = easeInOut(float(i) / float(n))
      await mouseEvent(session, "mouseMoved", "left",
                       startX + (endX - startX) * t,
                       startY + (endY - startY) * t, 1, 0)
      await sleepAsync(stepDelayMs)
  except CatchableError as e:
    try:
      await mouseEvent(session, "mouseReleased", "left", startX, startY, 0, 1)
    except CatchableError:
      discard
    raise e
  await mouseEvent(session, "mouseReleased", "left", endX, endY, 0, 1)

type DragBox = tuple[x, y, width, height: float]
  ## Прямоугольник элемента в координатах viewport (результат boundingBox()).

proc dragCenterBy(session: CDPSession, handle: DragBox, dx, dy: float,
                  steps, stepDelayMs, holdMs: int) {.async.} =
  ## Тащит центр прямоугольника handle на (dx, dy) пикселей.
  let
    startX = handle.x + handle.width / 2.0
    startY = handle.y + handle.height / 2.0
  await dragPath(session, startX, startY, startX + dx, startY + dy,
                 steps, stepDelayMs, holdMs)

proc toTrackEnd(handle, track: DragBox): float =
  ## Смещение по X, при котором правый край ручки совпадает с правым краем дорожки.
  (track.x + track.width) - (handle.x + handle.width)

# -----------------------------------------------------------------
# Мышь и клавиатура: расширенные жесты
# -----------------------------------------------------------------

proc doubleClick*(tab: Tab, selector: string) {.async.} =
  ## Двойной клик — как click(), но с двумя нажатиями подряд и
  ## правильным clickCount, чтобы страница увидела настоящий dblclick,
  ## а не два независимых одиночных клика.
  let
    nodeId = await findNode(tab, selector)
    (centerX, centerY) = await nodeCenter(tab, nodeId)
  await inputApi.dispatchMouseEvent(tab.session, "mouseMoved", centerX, centerY)
  await inputApi.dispatchMouseEvent(tab.session, "mousePressed", centerX, centerY, clickCount = 1)
  await inputApi.dispatchMouseEvent(tab.session, "mouseReleased", centerX, centerY, clickCount = 1)
  await inputApi.dispatchMouseEvent(tab.session, "mousePressed", centerX, centerY, clickCount = 2)
  await inputApi.dispatchMouseEvent(tab.session, "mouseReleased", centerX, centerY, clickCount = 2)

proc rightClick*(tab: Tab, selector: string) {.async.} =
  ## Открывает контекстное меню (эмулирует правый клик мышью). Само
  ## системное меню в headless Chromium не рендерится, но страница
  ## получает настоящее событие "contextmenu", как от живого клика.
  let
    nodeId = await findNode(tab, selector)
    (centerX, centerY) = await nodeCenter(tab, nodeId)
  await inputApi.dispatchMouseEvent(tab.session, "mouseMoved", centerX, centerY, button = "right")
  await inputApi.dispatchMouseEvent(tab.session, "mousePressed", centerX, centerY, button = "right")
  await inputApi.dispatchMouseEvent(tab.session, "mouseReleased", centerX, centerY, button = "right")

proc clickAt*(tab: Tab, x, y: float) {.async.} =
  ## Клик по абсолютным координатам вьюпорта в обход поиска по
  ## CSS-селектору — например, когда важна конкретная точка внутри
  ## элемента (canvas, карта, кастомный слайдер), а не он целиком.
  await inputApi.click(tab.session, x, y)

proc scrollBy*(tab: Tab, deltaX, deltaY: float) {.async.} =
  ## Прокручивает страницу колесом мыши (положительный deltaY — вниз).
  await inputApi.scroll(tab.session, 0, 0, deltaX, deltaY)

proc scrollIntoView*(tab: Tab, selector: string) {.async.} =
  ## Прокручивает страницу так, чтобы элемент оказался в видимой
  ## области, — без клика/наведения (click()/hover() делают это сами).
  let nodeId = await findNode(tab, selector)
  await domApi.scrollIntoViewIfNeeded(tab.session, nodeId)

proc dragAndDrop*(tab: Tab, sourceSelector, targetSelector: string, native = false) {.async.} =
  ## Перетаскивает sourceSelector на targetSelector.
  ##
  ## native = false (по умолчанию) — настоящая мышь через
  ## Input.dispatchMouseEvent: подходит для сортируемых списков
  ## (Sortable.js), но не гарантирует нативный HTML5 DnD (dragstart/
  ## dragover/drop — отдельный от mouse-событий механизм).
  ##
  ## native = true — последовательность DragEvent с общим DataTransfer, для
  ## draggable="true"/ondrop. Реальные файлы так не подделать
  ## (DataTransfer.files только для чтения): для загрузки есть uploadFile().
  if native:
    let
      sel1 = jsStringLiteral(sourceSelector)
      sel2 = jsStringLiteral(targetSelector)
      js = &"""(function() {{
        var src = document.querySelector({sel1});
        var dst = document.querySelector({sel2});
        if (!src || !dst) return false;
        var dt = new DataTransfer();
        function fire(el, kind) {{
          var rect = el.getBoundingClientRect();
          var ev = new DragEvent(kind, {{
            bubbles: true,
            cancelable: true,
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2,
          }});
          Object.defineProperty(ev, 'dataTransfer', {{ value: dt }});
          el.dispatchEvent(ev);
        }}
        fire(src, 'dragstart');
        fire(dst, 'dragenter');
        fire(dst, 'dragover');
        fire(dst, 'drop');
        fire(src, 'dragend');
        return true;
      }})()"""
      found = await runtimeApi.evaluateValue(tab.session, js)
    if found.kind != JBool or not getBool(found):
      raise newException(ChildTearError,
        &"dragAndDrop(native=true): элемент не найден: источник={sourceSelector}, цель={targetSelector}")
  else:
    let
      sourceId = await findNode(tab, sourceSelector)
      targetId = await findNode(tab, targetSelector)
      (sx, sy) = await nodeCenter(tab, sourceId)
      (tx, ty) = await nodeCenter(tab, targetId)
    await dragPath(tab.session, sx, sy, tx, ty, steps = 2, stepDelayMs = 0, holdMs = 0)

proc pressKey*(tab: Tab, key: string, modifiers = 0) {.async.} =
  ## Нажатие и отпускание одной именованной клавиши (например "Tab",
  ## "Escape", "ArrowDown") в текущем сфокусированном элементе.
  await inputApi.pressKey(tab.session, key, modifiers = modifiers)

func modifierBit(key: string): int =
  ## Битовая маска модификатора по имени клавиши — см. комментарий к
  ## Input.dispatchKeyEvent в cdp/domains/input.nim (Alt=1, Ctrl=2,
  ## Meta=4, Shift=8). Немодификаторные клавиши дают 0.
  case key
  of "Alt": 1
  of "Control", "Ctrl": 2
  of "Meta", "Cmd", "Command": 4
  of "Shift": 8
  else: 0

proc pressKeyCombo*(tab: Tab, keys: seq[string]) {.async.} =
  ## Нажимает сочетание клавиш, например @["Control", "a"] для Ctrl+A.
  ## Все клавиши, кроме последней, — модификаторы, удерживаются, пока не
  ## нажата и отпущена последняя (основная).
  ##
  ## Параметр — seq, а не openArray: openArray нельзя захватить в
  ## замыкание async-процедуры Nim (компилятор отказывает после первого
  ## await в теле — "cannot be captured as it would violate memory safety").
  if len(keys) == 0:
    raise newException(ChildTearError, "pressKeyCombo: пустой список клавиш")
  var modifiers = 0
  for i in 0 ..< len(keys) - 1:
    modifiers = modifiers or modifierBit(keys[i])
    await inputApi.dispatchKeyEvent(tab.session, "keyDown", keys[i], modifiers = modifiers)
  let mainKey = keys[^1]
  await inputApi.dispatchKeyEvent(tab.session, "keyDown", mainKey, modifiers = modifiers)
  await inputApi.dispatchKeyEvent(tab.session, "keyUp", mainKey, modifiers = modifiers)
  for i in countdown(len(keys) - 2, 0):
    modifiers = modifiers and not modifierBit(keys[i])
    await inputApi.dispatchKeyEvent(tab.session, "keyUp", keys[i], modifiers = modifiers)

proc selectAllText*(tab: Tab, selector = "") {.async.} =
  ## Выделяет весь текст (Ctrl+A) — либо в текущем сфокусированном
  ## элементе, либо (если передан selector) предварительно кликая на
  ## него.
  if len(selector) > 0:
    await click(tab, selector)
  await pressKeyCombo(tab, @["Control", "a"])

proc clearValue*(tab: Tab, selector: string) {.async.} =
  ## Очищает значение поля напрямую (el.value = '') с событиями
  ## input/change — надёжнее select-all + Backspace для длинного текста.
  ##
  ## У contenteditable нет .value (присваивание создало бы лишь пустое
  ## свойство), поэтому очищается textContent = ''. Этого достаточно:
  ## Lexical и подобные редакторы следят за input/beforeinput, а не за
  ## "трекером" значения (как React, см. setControlledValue()).
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      if (el.isContentEditable) {{
        el.textContent = '';
      }} else {{
        el.value = '';
      }}
      el.dispatchEvent(new Event('input', {{ bubbles: true }}));
      el.dispatchEvent(new Event('change', {{ bubbles: true }}));
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  if found.kind != JBool or not getBool(found):
    raise newException(ChildTearError, &"элемент для очистки не найден: {selector}")

# -----------------------------------------------------------------
# Формы: чекбоксы, значения, состояние полей
# -----------------------------------------------------------------

proc setChecked*(tab: Tab, selector: string, checked: bool) {.async.} =
  ## Устанавливает состояние чекбокса/радиокнопки напрямую и генерирует
  ## событие "change", как это делает браузер при реальном клике.
  let
    sel = jsStringLiteral(selector)
    checkedLit = if checked: "true" else: "false"
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      el.checked = {checkedLit};
      el.dispatchEvent(new Event('change', {{ bubbles: true }}));
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  if found.kind != JBool or not getBool(found):
    raise newException(ChildTearError, &"чекбокс/радио не найден: {selector}")

proc check*(tab: Tab, selector: string) {.async.} =
  ## Отмечает чекбокс/радиокнопку (setChecked(tab, selector, true)).
  await setChecked(tab, selector, true)

proc uncheck*(tab: Tab, selector: string) {.async.} =
  ## Снимает отметку с чекбокса (setChecked(tab, selector, false));
  ## для радиокнопки обычно бессмысленно — радиокнопки снимаются выбором
  ## другой радиокнопки в той же группе, а не программным сбросом.
  await setChecked(tab, selector, false)

proc getValue*(tab: Tab, selector: string): Future[string] {.async.} =
  ## Значение поля ввода/textarea/select (el.value).
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      return el ? el.value : null;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  if value.kind == JNull:
    raise newException(ChildTearError, &"элемент не найден: {selector}")
  result = getStr(value)

proc isChecked*(tab: Tab, selector: string): Future[bool] {.async.} =
  ## Отмечен ли чекбокс/радиокнопка (el.checked). Возвращает false,
  ## если элемент не найден (см. isVisible() насчёт этого же выбора
  ## "не найден = false" вместо исключения).
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      return el ? !!el.checked : false;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = value.kind == JBool and getBool(value)

proc isDisabled*(tab: Tab, selector: string): Future[bool] {.async.} =
  ## Отключён ли элемент формы (el.disabled) — недоступен для ввода и
  ## не отправляется вместе с формой. Возвращает false, если элемент
  ## не найден.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      return el ? !!el.disabled : false;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = value.kind == JBool and getBool(value)

proc isVisible*(tab: Tab, selector: string): Future[bool] {.async.} =
  ## "Видимость" в бытовом смысле: элемент существует, имеет ненулевые
  ## размеры и не скрыт через display:none/visibility:hidden. НЕ
  ## проверяет перекрытие другими элементами поверх него.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      var style = getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden') return false;
      var box = el.getBoundingClientRect();
      return box.width > 0 && box.height > 0;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = value.kind == JBool and getBool(value)

proc focus*(tab: Tab, selector: string) {.async.} =
  ## Программно фокусирует элемент (el.focus() через домен DOM —
  ## см. domApi.focus()); элемент должен быть фокусируемым.
  let nodeId = await findNode(tab, selector)
  await domApi.focus(tab.session, nodeId)

proc blur*(tab: Tab, selector: string) {.async.} =
  ## Снимает фокус с элемента (el.blur()) — например, чтобы
  ## спровоцировать событие "blur"/валидацию поля, не переводя фокус
  ## на что-то конкретное другое.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      el.blur();
      return true;
    }})()"""
    found = await runtimeApi.evaluateValue(tab.session, js)
  if found.kind != JBool or not getBool(found):
    raise newException(ChildTearError, &"элемент не найден: {selector}")

# -----------------------------------------------------------------
# Чтение состояния и содержимого элементов
# -----------------------------------------------------------------

proc boundingBox*(tab: Tab, selector: string): Future[tuple[x, y, width, height: float]] {.async.} =
  ## Координаты и размеры элемента на странице (viewport-относительные,
  ## после прокрутки его в видимую область) — например, чтобы вручную
  ## навести курсор в произвольную точку внутри элемента, а не только
  ## в его центр (см. nodeCenter()/click()/hover()), или посчитать clip
  ## для screenshotElement().
  let nodeId = await findNode(tab, selector)
  await domApi.scrollIntoViewIfNeeded(tab.session, nodeId)
  let
    box = await domApi.getBoxModel(tab.session, nodeId)
    quad = getElems(box["content"])
    x1 = getFloat(quad[0])
    y1 = getFloat(quad[1])
    x3 = getFloat(quad[4])
    y3 = getFloat(quad[5])
  result = (x1, y1, x3 - x1, y3 - y1)

proc innerHTML*(tab: Tab, selector: string): Future[string] {.async.} =
  ## HTML-разметка ВНУТРИ элемента, без самого элемента (Element.innerHTML) —
  ## в отличие от outerHTML() ниже.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      return el ? el.innerHTML : null;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  if value.kind == JNull:
    raise newException(ChildTearError, &"элемент не найден: {selector}")
  result = getStr(value)

proc outerHTML*(tab: Tab, selector: string): Future[string] {.async.} =
  ## В отличие от innerHTML() (через JS), получен через домен DOM
  ## (DOM.getOuterHTML) — оба подхода равноценны по результату, здесь
  ## просто показан альтернативный путь, уже не завязанный на eval.
  let nodeId = await findNode(tab, selector)
  result = await domApi.getOuterHTML(tab.session, nodeId)

proc getLinks*(tab: Tab): Future[seq[tuple[text, href: string]]] {.async.} =
  ## Все ссылки на странице: видимый текст и значение href как есть
  ## (относительные пути не разрешаются в абсолютные — используйте
  ## getAttribute()/absoluteUrl-подобную логику на своей стороне, если
  ## это важно).
  let js = """(function() {
    var out = [];
    var list = document.querySelectorAll('a[href]');
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      out.push({text: (el.innerText || el.textContent || ''), href: el.getAttribute('href') || ''});
    }
    return out;
  })()"""
  let value = await runtimeApi.evaluateValue(tab.session, js)
  result = @[]
  for item in getElems(value):
    add(result, (getStr(item["text"]), getStr(item["href"])))

proc getAllAttributes*(tab: Tab, selector, name: string): Future[seq[string]] {.async.} =
  ## Значение атрибута name у ВСЕХ элементов, подходящих под селектор
  ## (аналог getAllText(), но для атрибута, а не текста); отсутствующий
  ## атрибут даёт пустую строку на соответствующей позиции.
  let
    sel = jsStringLiteral(selector)
    attr = jsStringLiteral(name)
    js = &"""(function() {{
      var list = document.querySelectorAll({sel});
      var out = [];
      for (var i = 0; i < list.length; i++) {{
        out.push(list[i].getAttribute({attr}) || '');
      }}
      return out;
    }})()"""
    value = await runtimeApi.evaluateValue(tab.session, js)
  result = @[]
  for item in getElems(value):
    add(result, getStr(item))

proc getViewportSize*(tab: Tab): Future[tuple[width, height: int]] {.async.} =
  ## Текущий размер видимой области страницы (window.innerWidth/Height) —
  ## реальный, с учётом того, что подделал setViewport(), если он вызывался.
  let
    value = await runtimeApi.evaluateValue(tab.session, "[window.innerWidth, window.innerHeight]")
    arr = getElems(value)
  result = (getInt(arr[0]), getInt(arr[1]))

# -----------------------------------------------------------------
# Дополнительные ожидания
# -----------------------------------------------------------------

proc waitForSelectorGone*(tab: Tab, selector: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.} =
  ## Противоположность waitForSelector() — ждёт, пока элемент исчезнет
  ## со страницы (например, спиннер загрузки или закрывшийся модал).
  proc gone(): Future[bool] {.async.} = result = not await exists(tab, selector)
  result = await waitUntilTrue(gone, timeoutMs, pollIntervalMs)

proc waitForText*(tab: Tab, selector, text: string, timeoutMs = 5_000, pollIntervalMs = 100): Future[bool] {.async.} =
  ## Ждёт, пока видимый текст элемента не будет содержать text
  ## (например, счётчик корзины сменится с "0" на "1" после клика).
  proc hasText(): Future[bool] {.async.} =
    result = (await exists(tab, selector)) and (text in (await getText(tab, selector)))
  result = await waitUntilTrue(hasText, timeoutMs, pollIntervalMs)

proc waitUntilCleared*(tab: Tab, selector: string, timeoutMs = 5_000,
                        pollIntervalMs = 250, byValue = false): Future[bool] {.async.} =
  ## Ждёт, пока текст элемента (или, при byValue = true, значение поля
  ## ввода) не станет пустым после strip() — признак того, что поле
  ## формы очистилось само после отправки. Не бросает исключение по
  ## таймауту (возвращает false); исчезновение элемента из DOM даёт
  ## ChildTearError от getText()/getValue(), как и при их прямом вызове.
  proc isEmpty(): Future[bool] {.async.} =
    let current = if byValue: await getValue(tab, selector) else: await getText(tab, selector)
    result = len(strutils.strip(current)) == 0
  result = await waitUntilTrue(isEmpty, timeoutMs, pollIntervalMs)

proc waitForStableText*(tab: Tab, selector: string, pollMs = 500,
                         stableForMs = 2_000, timeoutMs = 30_000): Future[string] {.async.} =
  ## Ждёт, пока текст элемента (см. getLastText()) не перестанет меняться
  ## stableForMs подряд, и возвращает его — для потокового ответа чат-бота
  ## без события "готово". Пустой текст стабильным не считается. По
  ## timeoutMs возвращает накопленное (если оно непустое); исключение — если
  ## текст ни разу не появился.
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  var
    lastSeenText = ""
    stableMs = 0
  while epochTime() < deadline:
    let current = await getLastText(tab, selector)
    if len(strutils.strip(current)) > 0:
      if current == lastSeenText:
        inc(stableMs, pollMs)
        if stableMs >= stableForMs:
          return current
      else:
        lastSeenText = current
        stableMs = 0
    await sleepAsync(pollMs)
  if len(strutils.strip(lastSeenText)) > 0:
    return lastSeenText
  raise newException(ChildTearError,
    &"waitForStableText: текст так и не появился за {timeoutMs}мс по селектору: {selector}")

# -----------------------------------------------------------------
# localStorage и sessionStorage
# -----------------------------------------------------------------

proc localStorageGet*(tab: Tab, key: string): Future[string] {.async.} =
  ## Значение ключа key в window.localStorage текущей страницы —
  ## хранилище, привязанное к origin'у и переживающее закрытие вкладки.
  ## Возвращает "" и для отсутствующего ключа, и для ключа со значением
  ## "" (localStorage хранит только строки, отличить эти случаи можно
  ## через evalJS("localStorage.getItem(...) === null")).
  let value = await runtimeApi.evaluateValue(tab.session, &"window.localStorage.getItem({jsStringLiteral(key)})")
  result = if value.kind == JNull: "" else: getStr(value)

proc localStorageSet*(tab: Tab, key, value: string) {.async.} =
  ## Записывает пару key/value в window.localStorage (создаёт ключ или
  ## перезаписывает существующий).
  discard await runtimeApi.evaluate(tab.session,
    &"window.localStorage.setItem({jsStringLiteral(key)}, {jsStringLiteral(value)})")

proc localStorageRemove*(tab: Tab, key: string) {.async.} =
  ## Удаляет один ключ из window.localStorage; не ошибается, если
  ## ключа и так не было.
  discard await runtimeApi.evaluate(tab.session, &"window.localStorage.removeItem({jsStringLiteral(key)})")

proc localStorageClear*(tab: Tab) {.async.} =
  ## Полностью очищает window.localStorage текущего origin'а.
  discard await runtimeApi.evaluate(tab.session, "window.localStorage.clear()")

proc sessionStorageGet*(tab: Tab, key: string): Future[string] {.async.} =
  ## Как localStorageGet(), но для window.sessionStorage — хранилища,
  ## привязанного не только к origin'у, но и к конкретной вкладке
  ## (закрывается вместе с ней, в отличие от localStorage).
  let value = await runtimeApi.evaluateValue(tab.session, &"window.sessionStorage.getItem({jsStringLiteral(key)})")
  result = if value.kind == JNull: "" else: getStr(value)

proc sessionStorageSet*(tab: Tab, key, value: string) {.async.} =
  ## Как localStorageSet(), но для window.sessionStorage.
  discard await runtimeApi.evaluate(tab.session,
    &"window.sessionStorage.setItem({jsStringLiteral(key)}, {jsStringLiteral(value)})")

proc sessionStorageRemove*(tab: Tab, key: string) {.async.} =
  ## Как localStorageRemove(), но для window.sessionStorage.
  discard await runtimeApi.evaluate(tab.session, &"window.sessionStorage.removeItem({jsStringLiteral(key)})")

proc sessionStorageClear*(tab: Tab) {.async.} =
  ## Как localStorageClear(), но для window.sessionStorage.
  discard await runtimeApi.evaluate(tab.session, "window.sessionStorage.clear()")

# -----------------------------------------------------------------
# Эмуляция окружения
# -----------------------------------------------------------------

proc setGeolocation*(tab: Tab, latitude, longitude: float, accuracy = 1.0) {.async.} =
  ## Подделывает координаты navigator.geolocation — страница получает их
  ## как настоящий ответ геолокации, без системного диалога разрешения.
  await emulationApi.setGeolocationOverride(tab.session, latitude, longitude, accuracy)

proc clearGeolocation*(tab: Tab) {.async.} =
  ## Сбрасывает override, сделанный setGeolocation().
  await emulationApi.clearGeolocationOverride(tab.session)

proc setTimezone*(tab: Tab, timezoneId: string) {.async.} =
  ## timezoneId — имя IANA, например "Europe/Amsterdam".
  await emulationApi.setTimezoneOverride(tab.session, timezoneId)

proc setLocale*(tab: Tab, locale = "") {.async.} =
  ## Пустая строка сбрасывает override на системную локаль.
  await emulationApi.setLocaleOverride(tab.session, locale)

proc emulateMedia*(tab: Tab, media = "", features: seq[(string, string)] = @[]) {.async.} =
  ## media: "screen"/"print"/"" (сбросить). features — пары вида
  ## ("prefers-color-scheme", "dark"): @[("prefers-color-scheme", "dark")].
  var arr = newJArray()
  for (name, value) in features:
    add(arr, %*{"name": name, "value": value})
  await emulationApi.setEmulatedMedia(tab.session, media, arr)

proc setCPUThrottle*(tab: Tab, rate: float) {.async.} =
  ## rate = 1 — без замедления, rate = 4 — CPU "в 4 раза медленнее".
  await emulationApi.setCPUThrottlingRate(tab.session, rate)

proc setBackgroundColor*(tab: Tab, r, g, b: int, a = 1.0) {.async.} =
  ## Полезно перед screenshot(): например, a = 0 для прозрачного фона.
  await emulationApi.setDefaultBackgroundColorOverride(tab.session, r, g, b, a)

proc clearBackgroundColor*(tab: Tab) {.async.} =
  ## Сбрасывает override, сделанный setBackgroundColor() (выше по файлу).
  await emulationApi.clearDefaultBackgroundColorOverride(tab.session)

proc enableTouchEmulation*(tab: Tab, enabled = true, maxTouchPoints = 1) {.async.} =
  ## Подделывает признаки поддержки сенсорного ввода
  ## (navigator.maxTouchPoints, 'ontouchstart' in window). Сами тач-жесты
  ## (Input.dispatchTouchEvent) высокоуровневым API пока не покрыты —
  ## при необходимости их можно послать напрямую через tab.session.
  await emulationApi.setTouchEmulationEnabled(tab.session, enabled, maxTouchPoints)

proc setJavaScriptEnabled*(tab: Tab, enabled: bool) {.async.} =
  ## Полностью включает/выключает выполнение JS на странице — удобно,
  ## чтобы проверить, как выглядит и работает страница без скриптов
  ## (progressive enhancement, доступность разметки без JS).
  await emulationApi.setScriptExecutionDisabled(tab.session, not enabled)

proc setBypassCSP*(tab: Tab, enabled = true) {.async.} =
  ## Отключает Content-Security-Policy страницы (нужно, например, чтобы
  ## addScriptTag() мог инжектить произвольные скрипты на сайтах со
  ## строгим CSP).
  await pageApi.setBypassCSP(tab.session, enabled)

proc setCacheEnabled*(tab: Tab, enabled = true) {.async.} =
  ## enabled = false — Chromium игнорирует HTTP-кэш для запросов этой
  ## вкладки (аналог DevTools -> Network -> "Disable cache"); полезно
  ## перед reload(ignoreCache = false), чтобы гарантированно получить
  ## свежие ответы сети.
  await networkApi.setCacheDisabled(tab.session, not enabled)

proc originOf(url: string): string =
  ## Origin (схема + хост + порт, без пути) для передачи в
  ## Storage.clearDataForOrigin — например, "https://example.com" из
  ## "https://example.com/path?query". Порт включается, только если он
  ## указан явно в url (нестандартный порт вроде :8080).
  let u = parseUri(url)
  result = u.scheme & "://" & u.hostname
  if len(u.port) > 0:
    add(result, ":" & u.port)

proc clearBrowserCache*(tab: Tab) {.async.} =
  ## ВНИМАНИЕ: как и clearCookies(), чистит HTTP-дисковый кэш всего
  ## браузера целиком, а не только текущей вкладки — сам CDP не даёт
  ## способа ограничить именно эту команду одним origin'ом, это
  ## ограничение протокола, а не недоработка childtear.nim. Если нужна
  ## по-настоящему изолированная очистка (пусть и не HTTP-кэша, а Cache
  ## Storage — кэша service worker'ов), см. clearCacheForOrigin().
  await networkApi.clearBrowserCache(tab.session)

proc clearCacheForOrigin*(tab: Tab, storageTypes = storageApi.AllStorageTypes) {.async.} =
  ## В отличие от clearBrowserCache() (ограничение протокола: чистит браузер
  ## целиком) очищает данные только текущего origin вкладки через
  ## Storage.clearDataForOrigin: по умолчанию localStorage/sessionStorage/
  ## IndexedDB/Cache Storage/service worker'ы (storageApi.AllStorageTypes),
  ## либо более узкий список storageTypes. "cache_storage" — это Cache API
  ## service worker'ов, а не HTTP-дисковый кэш, который по origin очистить
  ## нельзя (см. clearBrowserCache()).
  let origin = originOf(await currentUrl(tab))
  await storageApi.clearDataForOrigin(tab.session, origin, storageTypes)

proc setOffline*(tab: Tab, offline = true) {.async.} =
  ## offline = true имитирует полное отсутствие сети (аналог DevTools ->
  ## Network -> "Offline") — все запросы страницы начинают проваливаться,
  ## как при реальном обрыве соединения.
  await networkApi.emulateNetworkConditions(tab.session, offline = offline)

proc throttleNetwork*(tab: Tab, latencyMs: float, downloadThroughput = -1.0, uploadThroughput = -1.0) {.async.} =
  ## throughput — байт/сек, -1 — без ограничения.
  await networkApi.emulateNetworkConditions(tab.session, latencyMs = latencyMs,
    downloadThroughput = downloadThroughput, uploadThroughput = uploadThroughput)

# -----------------------------------------------------------------
# Разрешения и окно браузера
# -----------------------------------------------------------------

proc grantPermissions*(browser: Browser, permissions: seq[string], origin = "", browserContextId = "") {.async.} =
  ## permissions — например @["geolocation", "notifications"]. Без
  ## browserContextId действует на разрешения браузера в целом, а не
  ## одного изолированного профиля.
  let session = await browserSession(browser)
  await browserDomainApi.grantPermissions(session, permissions, origin, browserContextId)

proc resetPermissions*(browser: Browser, browserContextId = "") {.async.} =
  ## Сбрасывает все разрешения, выданные через grantPermissions(), для
  ## указанного изолированного профиля (или основного, если не указан)
  ## назад к дефолтному поведению браузера.
  let session = await browserSession(browser)
  await browserDomainApi.resetPermissions(session, browserContextId)

proc setWindowSize*(tab: Tab, width, height: int) {.async.} =
  ## Меняет размер окна браузера, которому принадлежит вкладка
  ## (Browser.setWindowBounds) — в отличие от setViewport(), это размер
  ## самого окна, а не подделываемого вьюпорта страницы; в
  ## headless-режиме эффект зависит от версии Chromium.
  let
    session = await browserSession(tab.browser)
    win = await browserDomainApi.getWindowForTarget(session, tab.targetId)
  await browserDomainApi.setWindowBounds(session, getInt(win["windowId"]),
    %*{"width": width, "height": height, "windowState": "normal"})

proc maximizeWindow*(tab: Tab) {.async.} =
  ## Разворачивает окно браузера, которому принадлежит вкладка, на весь
  ## экран (Browser.setWindowBounds с windowState = "maximized").
  let
    session = await browserSession(tab.browser)
    win = await browserDomainApi.getWindowForTarget(session, tab.targetId)
  await browserDomainApi.setWindowBounds(session, getInt(win["windowId"]), %*{"windowState": "maximized"})

# -----------------------------------------------------------------
# Загрузка файлов
# -----------------------------------------------------------------

proc setDownloadPath*(tab: Tab, path: string) {.async.} =
  ## Разрешает скачивание файлов и сохраняет их в каталог path (должен
  ## существовать заранее) — без этого Chromium в headless-режиме
  ## молча блокирует любые скачивания.
  await pageApi.setDownloadBehavior(tab.session, "allow", path)

proc interceptFileChooser*(tab: Tab, enabled = true) {.async.} =
  ## Подавляет системный диалог выбора файла. Сами файлы всё равно
  ## нужно назначать вручную через uploadFile() — эта команда только не
  ## даёт диалогу зависнуть; привязки к событию "Page.fileChooserOpened"
  ## здесь нет.
  await pageApi.setInterceptFileChooserDialog(tab.session, enabled)

# -----------------------------------------------------------------
# Консоль и ошибки страницы
# -----------------------------------------------------------------

type ConsoleHandler* = proc(kind: string, text: string) {.gcsafe.}

proc onConsole*(tab: Tab, handler: ConsoleHandler) =
  ## Подписывается на console.log/warn/error/... страницы (домен
  ## Runtime уже включён в openTab()). Подписка постоянна — живёт, пока
  ## жива сессия вкладки (как onDialog()/autoDismissDialogs() выше).
  proc onCalled(params: JsonNode) {.gcsafe.} =
    let
      kind = getStr(getOrDefault(params, "type"), "log")
      argsList = getElems(getOrDefault(params, "args"))
    var parts: seq[string] = @[]
    for a in argsList:
      if hasKey(a, "value"):
        let v = a["value"]
        add(parts, (if v.kind == JString: getStr(v) else: $v))
      elif hasKey(a, "description"):
        add(parts, getStr(a["description"]))
    handler(kind, join(parts, " "))
  on(tab.session, "Runtime.consoleAPICalled", onCalled)

type PageErrorHandler* = proc(message: string) {.gcsafe.}

proc onPageError*(tab: Tab, handler: PageErrorHandler) =
  ## Подписывается на необработанные JS-исключения страницы
  ## (аналог window.onerror). Подписка постоянна, как onConsole().
  proc onThrown(params: JsonNode) {.gcsafe.} =
    let details = getOrDefault(params, "exceptionDetails")
    var message = getStr(getOrDefault(details, "text"), "необработанное исключение")
    if hasKey(details, "exception") and hasKey(details["exception"], "description"):
      message = getStr(details["exception"]["description"])
    handler(message)
  on(tab.session, "Runtime.exceptionThrown", onThrown)

# -----------------------------------------------------------------
# Диагностика страницы
# -----------------------------------------------------------------

proc installDiagnostics*(tab: Tab) {.async.} =
  ## Внедряет в страницу лёгкий перехватчик, копящий журнал: необработанные
  ## исключения и отклонения промисов, неуспешные fetch/XHR-запросы
  ## (статус 0 или >=400), а также каждый click/keydown, дошедший до
  ## window (с целевым узлом, keyCode и defaultPrevented) — позволяет
  ## отличить "событие не долетело" от "долетело, но отменено обработчиком".
  ## Забрать накопленное можно в любой момент через fetchDiagnostics().
  ## Безопасно вызывать повторно. Журнал ограничен последними 500 записями.
  discard await evalJS(tab, """(function () {
    if (window.__childtearDiag) { return 'already-installed'; }
    var log = [];
    var MAX = 500;
    function push(kind, detail) {
      log.push({ t: Date.now(), kind: kind, detail: String(detail).slice(0, 500) });
      if (log.length > MAX) { log.shift(); }
    }
    window.addEventListener('error', function (e) {
      push('js-error', (e && e.message) || e);
    });
    window.addEventListener('unhandledrejection', function (e) {
      push('promise-rejection', (e && e.reason) || e);
    });
    function describeTarget(t) {
      if (!t || !t.tagName) { return String(t); }
      var cls = (t.className && t.className.toString) ? t.className.toString() : '';
      return t.tagName.toLowerCase() +
        (t.id ? '#' + t.id : '') +
        (cls ? '.' + cls.trim().replace(/\s+/g, '.') : '');
    }
    window.addEventListener('click', function (e) {
      push('click', describeTarget(e.target) + ' defaultPrevented=' + e.defaultPrevented);
    }, true);
    window.addEventListener('keydown', function (e) {
      push('keydown', 'key=' + e.key + ' keyCode=' + e.keyCode + ' on ' + describeTarget(e.target) +
        ' defaultPrevented=' + e.defaultPrevented);
    }, true);
    var origFetch = window.fetch;
    if (origFetch) {
      window.fetch = function () {
        var args = arguments;
        return origFetch.apply(this, args).then(function (resp) {
          if (!resp.ok) { push('fetch-failed', args[0] + ' -> ' + resp.status); }
          return resp;
        }).catch(function (err) {
          push('fetch-error', args[0] + ' -> ' + err);
          throw err;
        });
      };
    }
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__childtearUrl = url;
      return origOpen.apply(this, arguments);
    };
    var origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var xhr = this;
      xhr.addEventListener('loadend', function () {
        if (xhr.status === 0 || xhr.status >= 400) {
          push('xhr-failed', xhr.__childtearUrl + ' -> ' + xhr.status);
        }
      });
      return origSend.apply(this, arguments);
    };
    window.__childtearDiag = { log: log };
    return 'installed';
  })()""")

proc fetchDiagnostics*(tab: Tab): Future[JsonNode] {.async.} =
  ## Забирает журнал, накопленный installDiagnostics() с момента
  ## установки. Если она не вызывалась — возвращает пустой массив, а не
  ## ошибку.
  result = await evalJS(tab, "window.__childtearDiag ? window.__childtearDiag.log : []")

proc dumpDebugInfo*(tab: Tab, prefix = "debug"): Future[JsonNode] {.async.} =
  ## Связка для разбора сбоя: сохраняет скриншот (<prefix>.png), HTML
  ## (<prefix>.html) и, если была installDiagnostics(), журнал диагностики
  ## (<prefix>-console.json), который и возвращает (иначе пустой JArray).
  ## Ошибки сохранения не выбрасываются.
  ##
  ## Если была installNetworkFailureLog() и tab.netFailures непуст,
  ## дополнительно пишет <prefix>-network.json — сбои уровня CDP Network
  ## (включая <script>/<link>, невидимые для -console.json). Без событий
  ## файл не создаётся.
  try:
    await screenshot(tab, prefix & ".png", fullPage = true)
    writeFile(prefix & ".html", await content(tab))
    let diag = await fetchDiagnostics(tab)
    writeFile(prefix & "-console.json", pretty(diag))
    if len(tab.netFailures) > 0:
      writeFile(prefix & "-network.json", pretty(%tab.netFailures))
    result = diag
  except CatchableError:
    result = newJArray()

# -----------------------------------------------------------------
# Сеть: ожидание конкретных ответов
# -----------------------------------------------------------------

proc waitForResponse*(tab: Tab, urlSubstring: string, timeoutMs = 30_000): Future[JsonNode] {.async.} =
  ## Ждёт HTTP-ответ, чей URL содержит urlSubstring (домен Network
  ## включается автоматически, если ещё не был, через enableNetwork()).
  ## Возвращает полный объект события "Network.responseReceived" —
  ## {"requestId", "response": {"url", "status", "headers", ...}, ...};
  ## requestId нужен для последующего responseBody(). В отличие от
  ## waitForNavigation(), реагирует на конкретный сетевой запрос, а не
  ## на загрузку страницы целиком — удобно ждать конкретный XHR/fetch.
  await enableNetwork(tab)
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  while true:
    let remaining = deadline - epochTime()
    if remaining <= 0:
      raise newException(ChildTearError, &"таймаут ожидания ответа сети, содержащего: {urlSubstring}")
    let params = await waitForEvent(tab.session, "Network.responseReceived", int(remaining * 1000.0))
    if urlSubstring in getStr(params["response"]["url"]):
      return params

proc responseBody*(tab: Tab, requestId: string): Future[tuple[body: string, base64Encoded: bool]] {.async.} =
  ## Тело конкретного сетевого ответа по requestId (см. waitForResponse()).
  ## Доступно только пока Chromium ещё не вытолкнул данные запроса из
  ## памяти — вызывать нужно вскоре после получения ответа.
  result = await networkApi.getResponseBody(tab.session, requestId)

# -----------------------------------------------------------------
# Фреймы
# -----------------------------------------------------------------

proc frames*(tab: Tab): Future[seq[JsonNode]] {.async.} =
  ## Возвращает список всех фреймов (включая вложенные iframe) текущей
  ## страницы — плоский список объектов {"id", "url", "name", ...} из
  ## Page.getFrameTree. Чтобы работать с содержимым конкретного iframe
  ## (клики, чтение текста и т.п.), не обязательно разбирать этот
  ## список вручную — обычно удобнее frame() ниже, находящий нужный
  ## iframe сразу по CSS-селектору самого тега <iframe>.
  let tree = await pageApi.getFrameTree(tab.session)
  result = @[]
  proc collect(node: JsonNode) =
    add(result, node["frame"])
    if hasKey(node, "childFrames"):
      for child in getElems(node["childFrames"]):
        collect(child)
  collect(tree["frameTree"])

proc frame*(tab: Tab, iframeSelector: string): Future[Frame] {.async.} =
  ## Находит <iframe> по CSS-селектору в главном документе вкладки
  ## (вложенные iframe не ищутся) и возвращает Frame — отдельный вход в его
  ## содержимое со своими click()/hover()/getText()/fill()/evalJS()/exists().
  ##
  ## DOM.describeNode(pierce = true) отдаёт узел <iframe> вместе с
  ## contentDocument и frameId: nodeId документа становится корнем для
  ## querySelector() внутри Frame, а frameId создаёт изолированный
  ## execution context (Page.createIsolatedWorld) при первом
  ## evalJS()/getText()/fill().
  let
    ownerNodeId = await findNode(tab, iframeSelector)
    described = await domApi.describeNode(tab.session, ownerNodeId, depth = 1, pierce = true)
  if not hasKey(described, "frameId") or not hasKey(described, "contentDocument"):
    raise newException(ChildTearError,
      &"элемент по селектору {iframeSelector} не является iframe/frame с доступным содержимым")
  result = Frame(
    tab: tab,
    frameId: getStr(described["frameId"]),
    docNodeId: getInt(described["contentDocument"]["nodeId"]),
    contextId: 0,
  )

proc frameContext(frame: Frame): Future[int] {.async.} =
  ## Возвращает изолированный execution context этого iframe, создавая
  ## его при первом обращении (Page.createIsolatedWorld) и переиспользуя
  ## дальше — нужен всем процедурам Frame, исполняющим JS (evalJS(),
  ## getText(), fill() и т.п.), но не нужен тем, что работают только
  ## через домен DOM по nodeId (click(), hover()).
  if frame.contextId == 0:
    frame.contextId = await pageApi.createIsolatedWorld(
      frame.tab.session, frame.frameId, "childtear", grantUniversalAccess = true)
  result = frame.contextId

proc findFrameNode(frame: Frame, selector: string): Future[int] {.async.} =
  ## Аналог findNode(tab, selector), но ищет внутри документа этого
  ## iframe (frame.docNodeId), а не главного документа вкладки.
  let nodeId = await domApi.querySelector(frame.tab.session, frame.docNodeId, selector)
  if nodeId == 0:
    raise newException(ChildTearError, &"элемент не найден внутри iframe по селектору: {selector}")
  result = nodeId

proc click*(frame: Frame, selector: string) {.async.} =
  ## Как Tab.click(), но ищет и кликает элемент внутри содержимого
  ## этого iframe, а не в главном документе страницы.
  let nodeId = await findFrameNode(frame, selector)
  let (centerX, centerY) = await nodeCenter(frame.tab, nodeId)
  await inputApi.click(frame.tab.session, centerX, centerY)

proc hover*(frame: Frame, selector: string) {.async.} =
  ## Как Tab.hover(), но для элемента внутри содержимого этого iframe.
  let nodeId = await findFrameNode(frame, selector)
  let (centerX, centerY) = await nodeCenter(frame.tab, nodeId)
  await inputApi.moveMouse(frame.tab.session, centerX, centerY)

proc session*(frame: Frame): CDPSession =
  ## CDP-сессия вкладки, которой принадлежит iframe: события мыши/клавиатуры
  ## в Chromium всегда уходят во вкладку целиком (см. dragBy()).
  frame.tab.session

proc boundingBox*(frame: Frame, selector: string): Future[tuple[x, y, width, height: float]] {.async.} =
  ## Как Tab.boundingBox(), но для элемента внутри iframe. DOM.getBoxModel
  ## возвращает координаты относительно viewport ГЛАВНОЙ страницы — смещение
  ## самого <iframe> уже учтено, складывать ничего не нужно (тем же путём
  ## идут click(frame, ...) и hover(frame, ...) через nodeCenter()).
  let nodeId = await findFrameNode(frame, selector)
  await domApi.scrollIntoViewIfNeeded(frame.tab.session, nodeId)
  let
    box = await domApi.getBoxModel(frame.tab.session, nodeId)
    quad = getElems(box["content"])
    x1 = getFloat(quad[0])
    y1 = getFloat(quad[1])
    x3 = getFloat(quad[4])
    y3 = getFloat(quad[5])
  result = (x1, y1, x3 - x1, y3 - y1)

proc dragBy*(tab: Tab, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## Зажимает левую кнопку на центре selector, ведёт курсор на (dx, dy)
  ## пикселей (dx > 0 — вправо, dy > 0 — вниз) и отпускает. Для слайдеров
  ## без элемента-цели (input[type=range], noUiSlider, «проведите для
  ## подтверждения»). Это настоящий ввод (isTrusted = true).
  ## steps — число промежуточных перемещений, stepDelayMs — пауза между
  ## ними, holdMs — пауза после нажатия до начала движения.
  ##   await dragBy(tab, "div.slider-handle", 300.0, 0.0)
  let box = await boundingBox(tab, selector)
  await dragCenterBy(tab.session, box, dx, dy, steps, stepDelayMs, holdMs)

proc dragToEnd*(tab: Tab, handleSelector, trackSelector: string,
                steps = 25, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## Тащит ручку handleSelector до правого края дорожки trackSelector;
  ## расстояние берётся из геометрии элементов, а не задаётся числом.
  ##   await dragToEnd(tab, ".slider-handle", ".slider-track")
  let
    handle = await boundingBox(tab, handleSelector)
    track = await boundingBox(tab, trackSelector)
  await dragCenterBy(tab.session, handle, toTrackEnd(handle, track), 0.0,
                     steps, stepDelayMs, holdMs)

proc dragBy*(frame: Frame, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## dragBy(tab, ...) для элемента внутри <iframe> (Frame из frame()).
  let box = await boundingBox(frame, selector)
  await dragCenterBy(session(frame), box, dx, dy, steps, stepDelayMs, holdMs)

proc dragToEnd*(frame: Frame, handleSelector, trackSelector: string,
                steps = 25, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## dragToEnd(tab, ...) для ручки и дорожки внутри <iframe>.
  let
    handle = await boundingBox(frame, handleSelector)
    track = await boundingBox(frame, trackSelector)
  await dragCenterBy(session(frame), handle, toTrackEnd(handle, track), 0.0,
                     steps, stepDelayMs, holdMs)

proc evalJS*(frame: Frame, expression: string): Future[JsonNode] {.async.} =
  ## Как Tab.evalJS(), но исполняет expression в изолированном контексте
  ## этого iframe (см. frameContext()) — document внутри выражения
  ## указывает на документ iframe, а не главной страницы.
  let ctxId = await frameContext(frame)
  result = await runtimeApi.evaluateValue(frame.tab.session, expression, contextId = ctxId)

proc getText*(frame: Frame, selector: string): Future[string] {.async.} =
  ## Как Tab.getText(), но читает текст элемента внутри содержимого
  ## этого iframe.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return null;
      return (el.innerText !== undefined) ? el.innerText : el.textContent;
    }})()"""
    value = await evalJS(frame, js)
  if value.kind == JNull:
    raise newException(ChildTearError, &"элемент не найден внутри iframe: {selector}")
  result = getStr(value)

proc getAllText*(frame: Frame, selector: string): Future[seq[string]] {.async.} =
  ## Как Tab.getAllText(), но для элементов внутри содержимого этого iframe.
  let
    sel = jsStringLiteral(selector)
    js = &"""(function() {{
      var list = document.querySelectorAll({sel});
      var out = [];
      for (var i = 0; i < list.length; i++) {{
        var el = list[i];
        out.push((el.innerText !== undefined) ? el.innerText : el.textContent);
      }}
      return out;
    }})()"""
    value = await evalJS(frame, js)
  result = @[]
  for item in getElems(value):
    add(result, getStr(item))

proc fill*(frame: Frame, selector: string, text: string) {.async.} =
  ## Как Tab.fill(), но заполняет поле внутри содержимого этого iframe.
  ## Использует Input.insertText в текущий фокус вкладки (см. Tab.fill()) —
  ## поэтому сначала фокусирует поле через JS в контексте iframe.
  let
    sel = jsStringLiteral(selector)
    focusAndSelectJs = &"""(function() {{
      var el = document.querySelector({sel});
      if (!el) return false;
      el.focus();
      if (typeof el.select === 'function') el.select();
      return true;
    }})()"""
    found = await evalJS(frame, focusAndSelectJs)
  if found.kind != JBool or not getBool(found):
    raise newException(ChildTearError, &"элемент для заполнения не найден внутри iframe: {selector}")
  await inputApi.insertText(frame.tab.session, text)

proc exists*(frame: Frame, selector: string): Future[bool] {.async.} =
  ## Как Tab.exists(), но проверяет наличие элемента внутри содержимого
  ## этого iframe.
  let
    sel = jsStringLiteral(selector)
    value = await evalJS(frame, &"document.querySelector({sel}) !== null")
  result = value.kind == JBool and getBool(value)

# -----------------------------------------------------------------
# Скриншот отдельного элемента
# -----------------------------------------------------------------

proc screenshotElement*(tab: Tab, selector, path: string, format = "png", quality = 100) {.async.} =
  ## Скриншот одного элемента (а не всей вкладки целиком) — сначала
  ## прокручивает его в видимую область (см. boundingBox()), затем
  ## снимает только его прямоугольник.
  let (x, y, width, height) = await boundingBox(tab, selector)
  let
    clip = %*{"x": x, "y": y, "width": width, "height": height, "scale": 1}
    dataBase64 = await pageApi.captureScreenshot(tab.session, format, quality, clip)
  writeFile(path, base64.decode(dataBase64))


