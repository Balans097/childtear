## cdp/mouse_drag.nim
##
## Протаскивание элемента мышью на заданное смещение в пикселях — то, что
## нужно для слайдеров (<input type="range">, noUiSlider, rc-slider,
## "проведите вправо для подтверждения" и т.п.), у которых нет
## элемента-цели, на который можно бросить ручку, как в dragAndDrop().
##
## Как это устроено (последовательность событий мыши через домен Input):
##
##   mouseMoved   -> курсор в центр ручки (кнопки не нажаты)
##   mousePressed -> левая кнопка нажата (buttons = 1)
##   mouseMoved*  -> N промежуточных точек по пути (buttons = 1)
##   mouseReleased-> кнопка отпущена в конечной точке
##
## Поле buttons в mouseMoved важно: часть библиотек слайдеров проверяет
## event.buttons в обработчике pointermove/mousemove и без единицы там
## считает, что кнопку уже отпустили, — ручка «залипает» на месте.
## Обёртка dispatchMouseEvent() из cdp/domains/input.nim это поле не
## передаёт, поэтому здесь события отправляются напрямую через call().
##
## Работает и с элементами главного документа (Tab), и внутри <iframe>
## (Frame, см. Tab.frame()): boundingBox() возвращает координаты
## относительно viewport вкладки, смещение самого iframe уже учтено.
##
## События идут через Input.dispatchMouseEvent, то есть это настоящий
## браузерный ввод (isTrusted = true), а не синтетические JS-события.

import asyncdispatch, json
import ../childtear
import ./transport

const
  ButtonsNone = 0
    ## Значение CDP-поля buttons: ни одна кнопка не удерживается.
  ButtonsLeft = 1
    ## Значение CDP-поля buttons: удерживается левая кнопка (битовая маска).

proc mouseEvent(session: CDPSession, kind, button: string,
                x, y: float, buttons, clickCount: int) {.async.} =
  ## Одно событие мыши Input.dispatchMouseEvent с явным полем buttons.
  ##   kind       — "mouseMoved" | "mousePressed" | "mouseReleased"
  ##   button     — "none" | "left" (какая кнопка вызвала событие)
  ##   buttons    — битовая маска УДЕРЖИВАЕМЫХ кнопок после события
  ##   clickCount — 1 для нажатия/отпускания, 0 для перемещения
  let params = %*{
    "type": kind,
    "x": x,
    "y": y,
    "button": button,
    "buttons": buttons,
    "clickCount": clickCount,
  }
  discard await call(session, "Input.dispatchMouseEvent", params)

proc easeInOut(t: float): float =
  ## Сглаживание «smoothstep»: медленный старт, быстрая середина, мягкое
  ## торможение. t и результат — доли пути в диапазоне 0.0 .. 1.0. Живая
  ## рука не движется с постоянной скоростью, и некоторые «капчи»-слайдеры
  ## отсеивают идеально равномерное движение.
  result = t * t * (3.0 - 2.0 * t)

proc dragPath(session: CDPSession, startX, startY, endX, endY: float,
              steps, stepDelayMs, holdMs: int) {.async.} =
  ## Общая часть всех dragBy()/dragToEnd(): нажать в (startX, startY),
  ## провести курсор в (endX, endY) по кривой easeInOut и отпустить.
  ## Если посреди движения случится ошибка CDP, кнопка всё равно будет
  ## отпущена — иначе страница осталась бы в состоянии «мышь зажата».
  let n = max(1, steps)
  await mouseEvent(session, "mouseMoved", "none", startX, startY, ButtonsNone, 0)
  await mouseEvent(session, "mousePressed", "left", startX, startY, ButtonsLeft, 1)
  try:
    await sleepAsync(holdMs)
    for i in 1 .. n:
      let
        t = easeInOut(float(i) / float(n))  # доля пути, 1.0 на последнем шаге
        x = startX + (endX - startX) * t
        y = startY + (endY - startY) * t
      await mouseEvent(session, "mouseMoved", "left", x, y, ButtonsLeft, 0)
      await sleepAsync(stepDelayMs)
  except CatchableError as e:
    # Аварийное отпускание кнопки в последней достигнутой точке.
    try:
      await mouseEvent(session, "mouseReleased", "left", startX, startY, ButtonsNone, 1)
    except CatchableError:
      discard
    raise e
  await mouseEvent(session, "mouseReleased", "left", endX, endY, ButtonsNone, 1)

type Box = tuple[x, y, width, height: float]

proc dragCenterBy(session: CDPSession, handle: Box, dx, dy: float,
                  steps, stepDelayMs, holdMs: int) {.async.} =
  let
    startX = handle.x + handle.width / 2.0
    startY = handle.y + handle.height / 2.0
  await dragPath(session, startX, startY, startX + dx, startY + dy,
                 steps, stepDelayMs, holdMs)

proc toTrackEnd(handle, track: Box): float =
  ## Смещение по X, при котором правый край ручки совпадает с правым краем
  ## дорожки: «тащить до конца» без жёстко заданных пикселей — ширина
  ## дорожки может отличаться от запуска к запуску.
  (track.x + track.width) - (handle.x + handle.width)

proc dragBy*(tab: Tab, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## Зажимает левую кнопку мыши на центре элемента selector, ведёт курсор
  ## на (dx, dy) пикселей и отпускает кнопку. dx > 0 — вправо, dy > 0 —
  ## вниз (координаты экрана).
  ##
  ##   steps       — число промежуточных перемещений (больше — плавнее)
  ##   stepDelayMs — пауза между перемещениями, мс
  ##   holdMs      — пауза после нажатия, до начала движения, мс
  ##                 (страницы с pointerdown+pointermove ждут «захвата»)
  ##
  ## Пример (слайдер до упора вправо, ручка уже видна на странице):
  ##   await dragBy(tab, "div.slider-handle", 300.0, 0.0)
  let box = await boundingBox(tab, selector)  # заодно прокручивает элемент в видимую область
  await dragCenterBy(tab.session, box, dx, dy, steps, stepDelayMs, holdMs)

proc dragBy*(frame: Frame, selector: string, dx, dy: float,
             steps = 15, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## То же, что dragBy(tab, ...), но ручка находится внутри <iframe>
  ## (Frame из Tab.frame()). Пример:
  ##   let f = await frame(tab, "iframe.popup")
  ##   await dragBy(f, "#handle", 240.0, 0.0)
  let box = await boundingBox(frame, selector)
  await dragCenterBy(session(frame), box, dx, dy, steps, stepDelayMs, holdMs)

proc dragToEnd*(tab: Tab, handleSelector, trackSelector: string,
                steps = 25, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## Тащит ручку вправо до правого края дорожки (trackSelector — элемент,
  ## по которому ручка ездит). Расстояние считается по факту из геометрии
  ## обоих элементов, а не задаётся числом.
  ##   await dragToEnd(tab, ".slider-handle", ".slider-track")
  let
    handle = await boundingBox(tab, handleSelector)
    track = await boundingBox(tab, trackSelector)
  await dragCenterBy(tab.session, handle, toTrackEnd(handle, track), 0.0,
                     steps, stepDelayMs, holdMs)

proc dragToEnd*(frame: Frame, handleSelector, trackSelector: string,
                steps = 25, stepDelayMs = 16, holdMs = 80) {.async.} =
  ## То же, что dragToEnd(tab, ...), для ручки и дорожки внутри <iframe>.
  let
    handle = await boundingBox(frame, handleSelector)
    track = await boundingBox(frame, trackSelector)
  await dragCenterBy(session(frame), handle, toTrackEnd(handle, track), 0.0,
                     steps, stepDelayMs, holdMs)
