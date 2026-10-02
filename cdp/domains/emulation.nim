## cdp/domains/emulation.nim
##
## Обёртка над доменом Emulation:
## https://chromedevtools.github.io/devtools-protocol/tot/Emulation/
##
## Позволяет подделывать характеристики устройства (размер экрана,
## deviceScaleFactor, мобильный режим), геолокацию, часовой пояс,
## media-фичи (prefers-color-scheme и т.п.) и троттлинг CPU — то, на
## чём построены page.setViewport()/emulate() в Puppeteer.

import std/[asyncdispatch, json]
import ../transport

proc setDeviceMetricsOverride*(session: CDPSession, width, height: int,
                                deviceScaleFactor = 1.0, mobile = false) {.async.} =
  ## Подделывает размеры вьюпорта и плотность пикселей — основа
  ## page.setViewport() в Puppeteer. width/height = 0 сбрасывает
  ## override на реальный размер окна.
  discard await call(session, "Emulation.setDeviceMetricsOverride", %*{
    "width": width,
    "height": height,
    "deviceScaleFactor": deviceScaleFactor,
    "mobile": mobile,
  })

proc clearDeviceMetricsOverride*(session: CDPSession) {.async.} =
  ## Сбрасывает override, сделанный setDeviceMetricsOverride(), — размер
  ## вьюпорта и deviceScaleFactor снова определяются реальным окном браузера.
  discard await call(session, "Emulation.clearDeviceMetricsOverride")

proc setUserAgentOverride*(session: CDPSession, userAgent: string,
                            acceptLanguage = "", platform = "") {.async.} =
  ## Актуальный (не-deprecated) способ подменить User-Agent — в отличие
  ## от Network.setUserAgentOverride, также умеет acceptLanguage/platform
  ## (влияет на navigator.language и navigator.platform).
  var params = %*{"userAgent": userAgent}
  if len(acceptLanguage) > 0:
    params["acceptLanguage"] = %acceptLanguage
  if len(platform) > 0:
    params["platform"] = %platform
  discard await call(session, "Emulation.setUserAgentOverride", params)

proc setGeolocationOverride*(session: CDPSession, latitude, longitude: float, accuracy = 1.0) {.async.} =
  ## Подделывает координаты navigator.geolocation — страница получает их
  ## как настоящий ответ геолокации, без системного диалога разрешения
  ## (в headless-режиме такого диалога и так нет).
  discard await call(session, "Emulation.setGeolocationOverride", %*{
    "latitude": latitude,
    "longitude": longitude,
    "accuracy": accuracy,
  })

proc clearGeolocationOverride*(session: CDPSession) {.async.} =
  ## Сбрасывает override, сделанный setGeolocationOverride() — geolocation
  ## после этого либо недоступна, либо использует реальное окружение браузера.
  discard await call(session, "Emulation.clearGeolocationOverride")

proc setTimezoneOverride*(session: CDPSession, timezoneId: string) {.async.} =
  ## timezoneId — IANA-имя, например "Europe/Amsterdam".
  discard await call(session, "Emulation.setTimezoneOverride", %*{"timezoneId": timezoneId})

proc setLocaleOverride*(session: CDPSession, locale = "") {.async.} =
  ## Пустая строка сбрасывает override на системную локаль.
  discard await call(session, "Emulation.setLocaleOverride", %*{"locale": locale})

proc setScriptExecutionDisabled*(session: CDPSession, disabled = true) {.async.} =
  ## Полностью включает/выключает выполнение JS на странице (аналог
  ## настройки браузера "разрешить JavaScript"); полезно, чтобы проверить,
  ## как выглядит/работает страница без скриптов (progressive enhancement).
  discard await call(session, "Emulation.setScriptExecutionDisabled", %*{"value": disabled})

proc setEmulatedMedia*(session: CDPSession, media = "", features: JsonNode = newJArray()) {.async.} =
  ## media: "screen"/"print"/"" (сбросить). features — массив вида
  ## [{"name": "prefers-color-scheme", "value": "dark"}].
  var params = newJObject()
  if len(media) > 0:
    params["media"] = %media
  params["features"] = features
  discard await call(session, "Emulation.setEmulatedMedia", params)

proc setCPUThrottlingRate*(session: CDPSession, rate: float) {.async.} =
  ## rate = 1 — без замедления, rate = 4 — CPU в 4 раза "медленнее".
  discard await call(session, "Emulation.setCPUThrottlingRate", %*{"rate": rate})

proc setDefaultBackgroundColorOverride*(session: CDPSession, r, g, b: int, a = 1.0) {.async.} =
  ## Полезно для скриншотов с прозрачным фоном: a = 0.
  discard await call(session, "Emulation.setDefaultBackgroundColorOverride", %*{
    "color": {"r": r, "g": g, "b": b, "a": a}
  })

proc clearDefaultBackgroundColorOverride*(session: CDPSession) {.async.} =
  ## Сбрасывает override фона, сделанный setDefaultBackgroundColorOverride().
  ## У CDP нет отдельной команды "clear" для этого override — по
  ## спецификации протокола, вызов Emulation.setDefaultBackgroundColorOverride
  ## вовсе без параметра "color" как раз и означает "снять override",
  ## поэтому здесь сознательно вызывается та же самая команда, но без
  ## параметров, а не другой метод.
  discard await call(session, "Emulation.setDefaultBackgroundColorOverride")

proc setTouchEmulationEnabled*(session: CDPSession, enabled = true, maxTouchPoints = 1) {.async.} =
  ## Подделывает поддержку сенсорного ввода (navigator.maxTouchPoints,
  ## 'ontouchstart' in window и т.п.) — не эмулирует сами тач-события,
  ## только признаки их поддержки; сами события шлются через
  ## Input.dispatchTouchEvent (см. input.nim).
  discard await call(session, "Emulation.setTouchEmulationEnabled", %*{
    "enabled": enabled,
    "maxTouchPoints": maxTouchPoints,
  })
