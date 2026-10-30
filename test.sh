#!/bin/zsh
# Build and run the tests (Tests/main.swift) against the app's sources, minus its entry point.
set -euo pipefail
cd "${0:A:h}"

mkdir -p build
MIN_OS=$(plutil -extract LSMinimumSystemVersion raw Info.plist)
swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos$MIN_OS" \
  ${(f)"$(ls Sources/*.swift | grep -v '/App.swift$')"} Tests/*.swift -o build/tests
build/tests
