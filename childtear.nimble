# Package

version       = "0.1.0"
author        = "Balans097"
description   = "Высокоуровневая обёртка над Chrome DevTools Protocol для управления headless Chromium"
license       = "MIT"
srcDir        = "."
installExt    = @["nim"]
installDirs   = @["cdp", "siteworkers"]

# Dependencies

requires "nim >= 2.0.0"
requires "checksums"

task test, "Запуск автономных тестов (Chromium не нужен)":
  exec "sh tests/run_tests.sh"
