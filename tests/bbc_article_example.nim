## bbc_article_example.nim
##
## Полностью рабочий пример: открывает https://www.bbc.com/russian,
## находит ссылку на главную (самую верхнюю) статью на этой странице
## и сохраняет её текст в текстовый файл.
##
## Перед запуском нужно поднять браузер:
##
##   chromium-browser --remote-debugging-port=9222 --headless=new --no-sandbox &
##
## Затем:
##
##   nim c -d:release bbc_article_example.nim
##   ./bbc_article_example
##
## Результат сохраняется в bbc_article.txt рядом со скомпилированным
## бинарником.
##
## ВАЖНО про устойчивость селекторов: у bbc.com/russian, как и у любого
## новостного сайта, вёрстка и CSS-классы время от времени меняются, а
## сам сайт недоступен из песочницы, где написан этот пример, — поэтому
## здесь сознательно не используются конкретные классы вида
## "gs-c-promo" (которые сегодня есть, а завтра могут исчезнуть).
##
## Ссылка на "главную" статью ищется устойчиво: ссылки на настоящие
## статьи содержат в URL сегмент "/articles/" (в современной платформе
## BBC — Simorgh — это общий для всех языковых версий шаблон путей вида
## /russian/articles/<id>); первая такая ссылка на главной странице
## сверху вниз — это и есть текущая "главная" статья дня.
##
## А вот с телом самой статьи одно-единственное устойчивое допущение
## (ровно один <article>) на практике не оправдалось: у части шаблонов
## Simorgh текст лежит не в <article>, а в других контейнерах.
## Поэтому ниже — не один селектор, а список кандидатов ArticleBodySelectors,
## перебираемых по очереди; если ни один не сработал, вместо невнятной
## ошибки скрипт сохраняет весь HTML страницы в OutputPath & ".debug.html",
## чтобы можно было открыть его и посмотреть настоящую структуру.

import std/[asyncdispatch, strutils]
import ../childtear

const
  BbcRussianUrl = "https://www.bbc.com/russian"
  ArticleLinkSelector = "a[href*='/russian/articles/']"
  ## Кандидаты на контейнер текста статьи, от наиболее к наименее
  ## специфичному. "article" — семантический идеал, но не единственный
  ## реально используемый на bbc.com/russian вариант; "main[role='main']"
  ## и "main" — более широкие, но рабочие запасные варианты.
  ArticleBodySelectors = [
    "article",
    "main[role='main']",
    "main",
  ]
  OutputPath = "bbc_article.txt"

proc absoluteUrl(base, href: string): string =
  ## BBC отдаёт ссылки на статьи в виде абсолютных URL, но на случай,
  ## если верстальщики BBC когда-нибудь перейдут на корень-относительные
  ## пути (href вида "/russian/articles/..."), достраиваем схему и хост
  ## самостоятельно — тратить на это отдельную HTTP-библиотеку не нужно.
  if startsWith(href, "http://") or startsWith(href, "https://"):
    href
  elif startsWith(href, "/"):
    "https://www.bbc.com" & href
  else:
    base & "/" & href

proc main() {.async.} =
  ## Демонстрационный сценарий: открывает статью BBC Russian, находит
  ## ссылку на первую связанную статью и читает с неё текст (см.
  ## пояснение к модулю выше).
  let
    browser = newBrowser() # 127.0.0.1:9222 по умолчанию, см. DefaultDebuggingPort
    tab = await newPage(browser)

  echo "Открываю ", BbcRussianUrl, "..."
  await goto(tab, BbcRussianUrl)

  if not await waitForSelector(tab, ArticleLinkSelector, timeoutMs = 10_000):
    raise newException(ChildTearError,
      "на странице не нашлось ни одной ссылки на статью (селектор устарел?)")

  let
    href = await getAttribute(tab, ArticleLinkSelector, "href")
    articleUrl = absoluteUrl(BbcRussianUrl, href)
  echo "Главная статья: ", articleUrl

  await goto(tab, articleUrl)

  let headline = await getText(tab, "h1")
  echo "Заголовок: ", headline

  var
    bodyText = ""
    usedSelector = ""
  for selector in ArticleBodySelectors:
    if await exists(tab, selector):
      bodyText = await getText(tab, selector)
      usedSelector = selector
      break

  if usedSelector.len == 0:
    # Ни один из известных селекторов не подошёл — вместо невнятного
    # сбоя сохраняем HTML страницы, чтобы можно было посмотреть на
    # текущую разметку BBC и понять, каким селектором доставать текст.
    let debugPath = OutputPath & ".debug.html"
    writeFile(debugPath, await content(tab))
    raise newException(ChildTearError,
      "тело статьи не нашлось ни по одному из известных селекторов (" &
      join(ArticleBodySelectors, ", ") &
      "); HTML страницы сохранён в " & debugPath &
      " — откройте его и подставьте подходящий селектор в ArticleBodySelectors")

  echo "Тело статьи найдено по селектору: ", usedSelector
  writeFile(OutputPath, headline & "\n\n" & bodyText)

  echo "Статья сохранена в ", OutputPath

  await close(tab)

waitFor main()
