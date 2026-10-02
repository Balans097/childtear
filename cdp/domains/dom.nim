## cdp/domains/dom.nim
##
## Обёртка над доменом DOM:
## https://chromedevtools.github.io/devtools-protocol/tot/DOM/
##
## DOM в CDP работает через nodeId — числовые идентификаторы узлов
## внутри снятого браузером "слепка" дерева документа. Поэтому
## querySelector в CDP — это не "верните мне элемент", а "найдите
## nodeId внутри поддерева другого nodeId".

import std/[asyncdispatch, json]
import ../transport

proc enable*(session: CDPSession) {.async.} =
  ## Формально требуется спецификацией перед использованием остальных
  ## команд домена (в актуальном headless-Chromium многие команды
  ## прощают его отсутствие, но полагаться на это не стоит).
  discard await call(session, "DOM.enable")

proc disable*(session: CDPSession) {.async.} =
  ## Отключает домен DOM — на практике почти никогда не вызывается
  ## явно: домен живёт, пока жива сама сессия вкладки.
  discard await call(session, "DOM.disable")

proc getDocument*(session: CDPSession, depth = 1): Future[JsonNode] {.async.} =
  ## Возвращает корневой узел документа (обычно нужен только его "nodeId").
  result = await call(session, "DOM.getDocument", %*{"depth": depth})

proc querySelector*(session: CDPSession, nodeId: int, selector: string): Future[int] {.async.} =
  ## Ищет первый узел, соответствующий CSS-селектору, внутри поддерева
  ## nodeId. Возвращает 0, если ничего не найдено.
  let res = await call(session, "DOM.querySelector", %*{"nodeId": nodeId, "selector": selector})
  result = getInt(res["nodeId"])

proc querySelectorAll*(session: CDPSession, nodeId: int, selector: string): Future[seq[int]] {.async.} =
  ## Как querySelector(), но возвращает nodeId ВСЕХ узлов, подходящих
  ## под селектор, внутри поддерева nodeId, а не только первого.
  let res = await call(session, "DOM.querySelectorAll", %*{"nodeId": nodeId, "selector": selector})
  result = @[]
  for idNode in getElems(res["nodeIds"]):
    add(result, getInt(idNode))

proc getBoxModel*(session: CDPSession, nodeId: int): Future[JsonNode] {.async.} =
  ## Геометрия узла на странице (нужна, чтобы навести курсор в его центр).
  let res = await call(session, "DOM.getBoxModel", %*{"nodeId": nodeId})
  result = res["model"]

proc getContentQuads*(session: CDPSession, nodeId: int): Future[seq[JsonNode]] {.async.} =
  ## В отличие от getBoxModel, работает и для узлов, у которых
  ## несколько прямоугольников на экране (например, инлайновые элементы,
  ## разбитые переносом строки на несколько строк).
  let res = await call(session, "DOM.getContentQuads", %*{"nodeId": nodeId})
  result = getElems(res["quads"])

proc focus*(session: CDPSession, nodeId: int) {.async.} =
  ## Программно фокусирует узел (аналог el.focus() из JS, но через DOM,
  ## а не Runtime) — узел должен быть фокусируемым (input, [tabindex] и т.п.).
  discard await call(session, "DOM.focus", %*{"nodeId": nodeId})

proc setAttributeValue*(session: CDPSession, nodeId: int, name, value: string) {.async.} =
  ## Устанавливает значение HTML-атрибута узла (Element.setAttribute).
  discard await call(session, "DOM.setAttributeValue", %*{"nodeId": nodeId, "name": name, "value": value})

proc removeAttribute*(session: CDPSession, nodeId: int, name: string) {.async.} =
  ## Удаляет HTML-атрибут узла (Element.removeAttribute); не ошибается,
  ## если атрибута и так не было.
  discard await call(session, "DOM.removeAttribute", %*{"nodeId": nodeId, "name": name})

proc getAttributes*(session: CDPSession, nodeId: int): Future[seq[(string, string)]] {.async.} =
  ## DOM.getAttributes отдаёт плоский массив ["имя1","значение1","имя2",...] —
  ## здесь он уже разложен в пары (имя, значение) для удобства.
  let
    res = await call(session, "DOM.getAttributes", %*{"nodeId": nodeId})
    flat = getElems(res["attributes"])
  result = @[]
  var i = 0
  while i + 1 < len(flat):
    add(result, (getStr(flat[i]), getStr(flat[i + 1])))
    i += 2

proc resolveNode*(session: CDPSession, nodeId: int): Future[JsonNode] {.async.} =
  ## Возвращает Runtime.RemoteObject для узла — используется, когда
  ## нужно передать узел в Runtime.callFunctionOn.
  let res = await call(session, "DOM.resolveNode", %*{"nodeId": nodeId})
  result = res["object"]

proc requestNode*(session: CDPSession, objectId: string): Future[int] {.async.} =
  ## Обратная операция к resolveNode: получить nodeId по RemoteObject.objectId.
  let res = await call(session, "DOM.requestNode", %*{"objectId": objectId})
  result = getInt(res["nodeId"])

proc describeNode*(session: CDPSession, nodeId: int, depth = 1, pierce = false): Future[JsonNode] {.async.} =
  ## Возвращает описание узла (Node) — тег, атрибуты, дочерние узлы (на
  ## глубину depth; -1 — целиком) и, для <iframe>/<frame>, поля
  ## "frameId" и, при pierce = true, вложенный узел "contentDocument"
  ## (корневой документ внутри фрейма). Именно pierce = true и есть тот
  ## способ, которым childtear.frame() находит документ внутри iframe,
  ## чтобы искать в нём элементы через querySelector().
  let res = await call(session, "DOM.describeNode", %*{"nodeId": nodeId, "depth": depth, "pierce": pierce})
  result = res["node"]

proc getOuterHTML*(session: CDPSession, nodeId: int): Future[string] {.async.} =
  ## HTML-разметка самого узла вместе с ним самим (Element.outerHTML).
  let res = await call(session, "DOM.getOuterHTML", %*{"nodeId": nodeId})
  result = getStr(res["outerHTML"])

proc setOuterHTML*(session: CDPSession, nodeId: int, outerHTML: string) {.async.} =
  ## Заменяет узел целиком на разобранный из outerHTML фрагмент разметки
  ## (Element.outerHTML =). После вызова исходный nodeId недействителен —
  ## узел на его месте нужно искать заново.
  discard await call(session, "DOM.setOuterHTML", %*{"nodeId": nodeId, "outerHTML": outerHTML})

proc setNodeValue*(session: CDPSession, nodeId: int, value: string) {.async.} =
  ## Меняет значение текстового узла (Node.nodeValue), а не атрибута.
  discard await call(session, "DOM.setNodeValue", %*{"nodeId": nodeId, "value": value})

proc removeNode*(session: CDPSession, nodeId: int) {.async.} =
  ## Удаляет узел из документа (аналог el.remove()).
  discard await call(session, "DOM.removeNode", %*{"nodeId": nodeId})

proc requestChildNodes*(session: CDPSession, nodeId: int, depth = 1, pierce = false) {.async.} =
  ## "Прогревает" узел на нужную глубину — после этого дочерние узлы
  ## доступны в DOM.getDocument/событиях без отдельного getDocument.
  discard await call(session, "DOM.requestChildNodes", %*{"nodeId": nodeId, "depth": depth, "pierce": pierce})

proc scrollIntoViewIfNeeded*(session: CDPSession, nodeId: int) {.async.} =
  ## Прокручивает страницу так, чтобы узел оказался в видимой области —
  ## настоящий пользователь не может кликнуть на то, что вне экрана,
  ## поэтому click()/hover() в childtear.nim вызывают это перед кликом.
  discard await call(session, "DOM.scrollIntoViewIfNeeded", %*{"nodeId": nodeId})

proc setFileInputFiles*(session: CDPSession, nodeId: int, files: seq[string]) {.async.} =
  ## Назначает файлы элементу <input type="file"> напрямую, без
  ## системного диалога выбора файла — files: полные пути на диске,
  ## где выполняется сам браузер.
  var filesArr = newJArray()
  for f in files:
    add(filesArr, %f)
  discard await call(session, "DOM.setFileInputFiles", %*{"nodeId": nodeId, "files": filesArr})

proc getNodeForLocation*(session: CDPSession, x, y: int): Future[JsonNode] {.async.} =
  ## Возвращает узел под указанной точкой экрана (аналог document.elementFromPoint).
  result = await call(session, "DOM.getNodeForLocation", %*{"x": x, "y": y})
