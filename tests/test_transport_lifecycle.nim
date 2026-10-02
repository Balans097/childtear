## tests/test_transport_lifecycle.nim
##
## Поведение cdp/transport.nim при сбоях: обрыв соединения не оставляет
## зависших команд, исключение в обработчике события не обрывает сессию.

import std/[asyncdispatch, json]
import ../cdp/transport
import ./mock_cdp_server

const testPort = 9335

proc raisesCDPError[T](fut: Future[T]): Future[bool] {.async.} =
  ## true, если fut завершилась CDPError (а не зависла и не вернула значение).
  try:
    discard await fut
  except CDPError:
    return true
  return false

proc runTest() {.async.} =
  asyncCheck serve(testPort)
  await sleepAsync(200)
  let url = "ws://127.0.0.1:" & $testPort & "/devtools/page/L"

  # 1. Исключение в одном обработчике не мешает другим и не рушит сессию.
  block:
    let session = await newCDPSession(url)
    var secondCalled = false
    on(session, "Page.loadEventFired", proc(params: JsonNode) =
      raise newException(ValueError, "ошибка в обработчике"))
    on(session, "Page.loadEventFired", proc(params: JsonNode) =
      secondCalled = true)
    discard await call(session, "Page.navigate", %*{"url": "http://example.com"})
    await sleepAsync(200)
    doAssert secondCalled, "второй обработчик не был вызван"
    doAssert isAlive(session), "сессия должна пережить исключение в обработчике"
    let res = await call(session, "Foo.bar")
    doAssert res["echo"].getStr() == "Foo.bar"
    await close(session)
    echo "OK: исключение в обработчике изолировано"

  # 2. Обрыв во время ожидания ответа: команда завершается CDPError,
  #    а не висит; следующие вызовы тоже падают сразу.
  block:
    let session = await newCDPSession(url)
    doAssert await raisesCDPError(call(session, "Test.drop")),
      "call() при обрыве должен завершиться CDPError"
    doAssert not isAlive(session), "сессия должна считаться мёртвой после обрыва"
    doAssert await raisesCDPError(call(session, "Foo.bar")),
      "call() на мёртвой сессии должен падать сразу"
    doAssert await raisesCDPError(waitForEvent(session, "Page.loadEventFired", 500)),
      "waitForEvent() на мёртвой сессии должен падать сразу"
    echo "OK: обрыв соединения не оставляет зависших команд"

  # 3. waitForEvent по таймауту бросает CDPError и снимает свой обработчик.
  block:
    let session = await newCDPSession(url)
    doAssert await raisesCDPError(waitForEvent(session, "Never.happens", 200)),
      "waitForEvent() по таймауту должен бросать CDPError"
    doAssert isAlive(session)
    await close(session)
    echo "OK: таймаут waitForEvent()"

  echo "Все проверки жизненного цикла транспорта пройдены успешно."

waitFor runTest()
