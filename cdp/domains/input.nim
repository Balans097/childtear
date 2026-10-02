## cdp/domains/input.nim
##
## Обёртка над доменом Input:
## https://chromedevtools.github.io/devtools-protocol/tot/Input/
##
## Эмулирует настоящие события мыши и клавиатуры на уровне движка браузера
## (а не JS-вызовы вроде el.click()), как у реального пользователя.

import std/[asyncdispatch, json]
import ../transport

proc dispatchMouseEvent*(session: CDPSession, kind: string, x, y: float,
                          button = "left", clickCount = 1,
                          deltaX = 0.0, deltaY = 0.0, buttons = 0) {.async.} =
  ## kind: "mousePressed" | "mouseReleased" | "mouseMoved" | "mouseWheel".
  ## deltaX/deltaY используются только для "mouseWheel".
  ## buttons — битовая маска удерживаемых кнопок (левая = 1, правая = 2,
  ## средняя = 4). Для перетаскивания её нужно передавать в каждом
  ## "mouseMoved" между нажатием и отпусканием: обработчики
  ## pointermove/mousemove у слайдеров и списков с drag-and-drop
  ## проверяют event.buttons и без единицы считают кнопку отпущенной.
  var params = %*{
    "type": kind,
    "x": x,
    "y": y,
    "button": button,
    "clickCount": clickCount,
  }
  if buttons != 0:
    params["buttons"] = %buttons
  if kind == "mouseWheel":
    params["deltaX"] = %deltaX
    params["deltaY"] = %deltaY
  discard await call(session, "Input.dispatchMouseEvent", params)

proc click*(session: CDPSession, x, y: float, holdMs = 70) {.async.} =
  ## Полный клик: перемещение курсора, нажатие и отпускание в
  ## viewport-координатах страницы.
  ##
  ## holdMs — пауза между mousePressed и mouseReleased: живое нажатие не
  ## бывает нулевой длительности, а некоторые страницы (защита от
  ## кликджекинга, обработчики pointerdown+pointerup) отфильтровывают клики
  ## без задержки, и обработчик молча не срабатывает, хотя курсор в цели.
  ## Задержка включена для любого click(), а не под конкретный сайт.
  await dispatchMouseEvent(session, "mouseMoved", x, y)
  await dispatchMouseEvent(session, "mousePressed", x, y)
  if holdMs > 0:
    await sleepAsync(holdMs)
  await dispatchMouseEvent(session, "mouseReleased", x, y)

proc moveMouse*(session: CDPSession, x, y: float) {.async.} =
  ## Только перемещение курсора, без клика — основа hover().
  await dispatchMouseEvent(session, "mouseMoved", x, y)

proc scroll*(session: CDPSession, x, y, deltaX, deltaY: float) {.async.} =
  ## Эмулирует прокрутку колесом мыши в точке (x, y).
  await dispatchMouseEvent(session, "mouseWheel", x, y, deltaX = deltaX, deltaY = deltaY)

proc insertText*(session: CDPSession, text: string) {.async.} =
  ## Вставляет текст в текущий сфокусированный элемент одним куском —
  ## быстрее и надёжнее посимвольной эмуляции нажатий клавиш.
  discard await call(session, "Input.insertText", %*{"text": text})

proc dispatchKeyEvent*(session: CDPSession, kind: string, key: string, code = "",
                        text = "", modifiers = 0, windowsVirtualKeyCode = 0) {.async.} =
  ## kind: "keyDown" | "keyUp" | "rawKeyDown" | "char".
  ## modifiers — маска CDP: Alt=1, Ctrl=2, Meta=4, Shift=8.
  ## text — печатаемый символ (для kind == "char"), иначе Chromium может не
  ## породить input-событие.
  ## windowsVirtualKeyCode — числовой код клавиши (13 для Enter). Без него
  ## event.keyCode/event.which остаются нулевыми, а многие обработчики
  ## "отправить по Enter" проверяют именно keyCode и молча не срабатывают.
  var params = %*{"type": kind, "key": key, "modifiers": modifiers}
  if len(code) > 0:
    params["code"] = %code
  if len(text) > 0:
    params["text"] = %text
  if windowsVirtualKeyCode != 0:
    params["windowsVirtualKeyCode"] = %windowsVirtualKeyCode
    params["nativeVirtualKeyCode"] = %windowsVirtualKeyCode
  discard await call(session, "Input.dispatchKeyEvent", params)

proc pressKey*(session: CDPSession, key: string, code = "", modifiers = 0,
               windowsVirtualKeyCode = 0) {.async.} =
  ## Нажатие и отпускание одной клавиши (например, "Enter", "Tab").
  ## Для клавиш, чей numeric keyCode важен странице (Enter=13, Tab=9 и
  ## т.п.), передавайте windowsVirtualKeyCode явно — см. dispatchKeyEvent().
  await dispatchKeyEvent(session, "keyDown", key, code, modifiers = modifiers,
                          windowsVirtualKeyCode = windowsVirtualKeyCode)
  await dispatchKeyEvent(session, "keyUp", key, code, modifiers = modifiers,
                          windowsVirtualKeyCode = windowsVirtualKeyCode)

proc typeChar*(session: CDPSession, ch: string) {.async.} =
  ## Печатает один символ событием клавиатуры "char" — в отличие от
  ## insertText(), обработчики keydown/keypress/input видят его отдельно.
  ## Используется в typeText() для эмуляции живого набора.
  ##
  ## text передаётся только в "char": "keyDown" с непустым text Chromium
  ## считает печатающим нажатием и вставляет символ сам, поэтому второй
  ## "char" с тем же text задвоил бы ввод ("ППрреессттаавв..."). "keyUp"
  ## text не нужен.
  await dispatchKeyEvent(session, "keyDown", ch)
  await dispatchKeyEvent(session, "char", ch, text = ch)
  await dispatchKeyEvent(session, "keyUp", ch)

proc dispatchTouchEvent*(session: CDPSession, kind: string, touchPoints: seq[JsonNode]) {.async.} =
  ## kind: "touchStart" | "touchEnd" | "touchMove" | "touchCancel".
  ## touchPoints — например @[%*{"x": 10.0, "y": 20.0}].
  var pointsArr = newJArray()
  for p in touchPoints:
    add(pointsArr, p)
  discard await call(session, "Input.dispatchTouchEvent", %*{"type": kind, "touchPoints": pointsArr})

proc setIgnoreInputEvents*(session: CDPSession, ignore = true) {.async.} =
  ## Заставляет браузер игнорировать весь пользовательский ввод —
  ## полезно, чтобы фоновая автоматизация не смешивалась с реальными
  ## событиями мыши/клавиатуры на этой же машине.
  discard await call(session, "Input.setIgnoreInputEvents", %*{"ignore": ignore})

proc cancelDragging*(session: CDPSession) {.async.} =
  ## Отменяет драг, начатый через Input.dispatchDragEvent (низкоуровневый
  ## API нативного HTML5 drag-and-drop через сам Input-домен, здесь не
  ## обёрнутый — childtear.nim эмулирует HTML5 DnD не им, а прямой
  ## JS-симуляцией DragEvent/DataTransfer, см. dragAndDrop(native=true)
  ## в childtear.nim). Полезно как аварийный сброс "зависшего" состояния
  ## перетаскивания страницы.
  discard await call(session, "Input.cancelDragging")
