#!/usr/bin/env bash
# Installs the pinned Flutter (same as CI) into a fresh cloud container, then
# resolves packages. Run once per container from the repo root:
#   bash tool/setup_flutter.sh
set -e
FLUTTER_DIR=/opt/flutter
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 -b 3.47.4 https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
git config --global --add safe.directory "$FLUTTER_DIR"
ln -sf "$FLUTTER_DIR/bin/flutter" /usr/local/bin/flutter
ln -sf "$FLUTTER_DIR/bin/dart" /usr/local/bin/dart
flutter config --no-analytics >/dev/null
flutter --version
flutter pub get
