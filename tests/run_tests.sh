#!/bin/sh
# Запуск всех автономных тестов (не требуют Chromium).
# Использование: ./tests/run_tests.sh   (из корня проекта)
set -e
cd "$(dirname "$0")/.."
for t in test_transport test_wsclient test_transport_lifecycle test_browser_http; do
  echo "=== $t"
  nim c -r --hints:off --out:"/tmp/childtear_$t" "tests/$t.nim"
done
echo "Все тесты пройдены."
