#!/usr/bin/env bash
# Puts the SQLite WebAssembly build that matches the sqlite3 package into
# web/sqlite3.wasm, checked against a pinned hash. Run it again whenever
# the sqlite3 version in pubspec.lock changes (and update both pins).
set -euo pipefail
VERSION=3.9.2
SHA256=e7451780e78c56ff864fe9317a0fbcd6aeb2e8de3beba7f5efd963202f7ec3d9
cd "$(dirname "$0")/.."
tmp=$(mktemp)
curl -fsSL -o "$tmp" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$VERSION/sqlite3.wasm"
echo "$SHA256  $tmp" | sha256sum -c -
mv "$tmp" web/sqlite3.wasm
echo "web/sqlite3.wasm = sqlite3 $VERSION"
