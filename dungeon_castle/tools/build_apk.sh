#!/usr/bin/env bash
# Сборка debug-APK из командной строки.
# Нужно: Godot 4.5.1 (переменная GODOT), шаблоны экспорта 4.5.1, Android SDK (build-tools, platform-tools), JDK 17+.
# В редакторе: Editor → Editor Settings → Export → Android: пути к SDK, JDK и debug.keystore.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p ../build
"$GODOT" --headless --import || true
"$GODOT" --headless --export-debug "Android" ../build/DungeonCastle.apk
echo "Готово: build/DungeonCastle.apk"
echo "Установка: adb install -r build/DungeonCastle.apk"
