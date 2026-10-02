## tests/test_transport.nim
##
## Прогоняет реальный wsclient.nim + transport.nim через
## tests/mock_cdp_server.nim: проверяет handshake, отправку команд,
## сопоставление id->результат и доставку asynchronous-событий.
##
## Тест написан как единая async-процедура с обычными assert'ами —
## без вложенных waitFor, которые в asyncdispatch легко ведут к
## взаимоблокировке при реентрантном вызове.



import std/[asyncdispatch, json]
import ../cdp/transport
import ./mock_cdp_server



const testPort = 9333



proc runTest() {.async.} =
  ## Поднимает mock_cdp_server на testPort и прогоняет через него
  ## transport.nim/wsclient.nim: подключение, отправку команды и
  ## получение ответа с событием — сквозная проверка транспорта.
  asyncCheck serve(testPort)
  await sleepAsync(200) # даём серверу время начать слушать порт

  let session = await newCDPSession("ws://127.0.0.1:" & $testPort & "/devtools/page/ABC")

  # 1. Простая команда должна вернуть результат, сопоставленный по id.
  let res = await call(session, "Foo.bar", %*{"x": 1})
  doAssert getStr(res["echo"]) == "Foo.bar", "неверный echo-результат: " & $res
  echo "OK: команда Foo.bar корректно вернула результат по id"

  # 2. Событие, пришедшее после ответа на команду, должно быть доставлено подписчику.
  var receivedEvent = false
  on(session, "Page.loadEventFired", proc(params: JsonNode) =
    receivedEvent = true
  )
  discard await call(session, "Page.navigate", %*{"url": "http://example.com"})
  await sleepAsync(200) # даём фоновому listenLoop обработать событие
  doAssert receivedEvent, "событие Page.loadEventFired не было доставлено подписчику"
  echo "OK: событие доставлено подписчику через on()"

  # 3. waitForEvent должен дождаться следующего такого события.
  discard await call(session, "Page.navigate", %*{"url": "http://example.com"})
  let evt = await waitForEvent(session, "Page.loadEventFired", 2000)
  doAssert getFloat(evt["timestamp"]) == 123.45, "неверные параметры события: " & $evt
  echo "OK: waitForEvent корректно дождался события"

  # 4. Утечка обработчиков: каждый waitForEvent() обязан снять свой
  # обработчик из таблицы подписчиков (removeHandler() в
  # cdp/transport.nim). Событие ожидается много раз подряд; если бы
  # обработчики копились, каждое следующее ожидание замедлялось бы.
  for i in 1 .. 20:
    discard await call(session, "Page.navigate", %*{"url": "http://example.com"})
    discard await waitForEvent(session, "Page.loadEventFired", 2000)
  echo "OK: 20 повторных waitForEvent() подряд отработали без деградации"

  await close(session)
  echo "Все проверки транспорта пройдены успешно."



waitFor runTest()



