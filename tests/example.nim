## example.nim
##
## Развёрнутая демонстрация childtear.nim на самодостаточной странице
## (без обращения к внешним сайтам, чтобы пример не зависел от их
## разметки и был воспроизводим где угодно): форма логина, нативный
## HTML5 drag-and-drop и iframe с собственной кнопкой — по одному
## примеру на каждую высокоуровневую возможность библиотеки.
##
## Перед запуском нужно поднять браузер:
##
##   chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox &
##
## (порт 9222 — DefaultDebuggingPort из childtear.nim; если браузер
## запущен на другом порту, передайте его вторым аргументом в newBrowser()).
##
## Затем:
##
##   nim c -d:release example.nim
##   ./example
##
## Отдельный пример извлечения статьи с настоящего сайта —
## в bbc_article_example.nim.

import std/[asyncdispatch, uri, json]
import ../childtear

const demoPage = """
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>childtear demo</title></head>
<body>
  <h1 id="heading">childtear demo page</h1>

  <!-- 1. Обычная форма -->
  <form id="login-form">
    <input id="username" name="username" placeholder="имя пользователя">
    <input id="password" name="password" type="password" placeholder="пароль">
    <button type="submit">Войти</button>
  </form>
  <p id="result" style="display:none">Добро пожаловать, <span id="result-name"></span>!</p>
  <script>
    document.getElementById('login-form').addEventListener('submit', function(e) {
      e.preventDefault();
      document.getElementById('result-name').textContent = document.getElementById('username').value;
      document.getElementById('result').style.display = 'block';
    });
  </script>

  <!-- 2. Нативный HTML5 drag-and-drop (не сработал бы через "честную мышь" —
       нужны настоящие события dragstart/dragover/drop) -->
  <h2>Перетаскивание</h2>
  <div id="drag-item" draggable="true" style="width:120px; padding:8px; background:#def;">Перетащи меня</div>
  <div id="drop-zone" style="border:2px dashed #888; width:200px; height:60px; margin-top:8px;">Зона для сброса</div>
  <p id="drop-result" style="display:none">Элемент был сброшен!</p>
  <script>
    var item = document.getElementById('drag-item');
    var zone = document.getElementById('drop-zone');
    item.addEventListener('dragstart', function(e) { e.dataTransfer.setData('text/plain', 'dropped'); });
    zone.addEventListener('dragover', function(e) { e.preventDefault(); });
    zone.addEventListener('drop', function(e) {
      e.preventDefault();
      document.getElementById('drop-result').style.display = 'block';
    });
  </script>

  <!-- 3. iframe со своим собственным документом -->
  <h2>Содержимое iframe</h2>
  <iframe id="inner-frame" style="width:300px; height:80px; border:1px solid #ccc;"></iframe>
</body></html>
"""

const iframeContent = """
<button id="iframe-btn" onclick="document.getElementById('iframe-result').textContent = 'нажато внутри iframe'">
  Кнопка внутри iframe
</button>
<p id="iframe-result">ещё не нажато</p>
"""

proc main() {.async.} =
  ## Демонстрационный сценарий: открывает встроенную демо-страницу,
  ## заполняет и отправляет форму, работает с iframe и делает
  ## скриншот — показывает основные приёмы использования childtear.
  let
    browser = newBrowser() # 127.0.0.1:9222 по умолчанию
    tab = await newPage(browser)
  await setViewport(tab, 1280, 800)

  # data:-URL вместо реального сайта — страница целиком известна заранее
  # и не изменится между запусками примера.
  await goto(tab, "data:text/html," & encodeUrl(demoPage))
  echo "Заголовок вкладки: ", await title(tab)

  # 1. Заполнение и отправка формы одним вызовом, чтение результата.
  await fillForm(tab, @{"#username": "andy", "#password": "secret"})
  await click(tab, "#login-form button[type=submit]")
  discard await waitForSelector(tab, "#result")
  echo "Форма отправлена, ответ страницы: ", await getText(tab, "#result")

  # 2. iframe получает содержимое уже после загрузки основной страницы
  # (например, как это обычно и бывает — виджет чата, встроенное видео
  # и т.п. подгружают себя сами) — здесь для простоты примера просто
  # проставляем его через evalJS().
  discard await evalJS(tab, "document.getElementById('inner-frame').srcdoc = " &
    $(%iframeContent))
  discard await waitForFunction(tab,
    "document.getElementById('inner-frame').contentDocument && " &
    "document.getElementById('inner-frame').contentDocument.readyState === 'complete'")

  # Клик и чтение текста ВНУТРИ iframe — отдельный execution context,
  # получаемый через frame():
  let innerFrame = await frame(tab, "#inner-frame")
  await click(innerFrame, "#iframe-btn")
  echo "Текст внутри iframe после клика: ", await getText(innerFrame, "#iframe-result")

  # 3. Нативный HTML5 drag-and-drop (native = true — настоящие
  # dragstart/dragover/drop, а не эмуляция мышью):
  await dragAndDrop(tab, "#drag-item", "#drop-zone", native = true)
  echo "Перетаскивание сработало: ", await isVisible(tab, "#drop-result")

  await screenshot(tab, "/tmp/example.png", fullPage = true)
  echo "Скриншот сохранён в /tmp/example.png"

  await close(tab)
  # await close(browser)  # закрыть браузер целиком, а не только эту вкладку

waitFor main()
