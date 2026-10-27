#!/bin/bash
# Сборка игры для игрока (вопрос Q01, Huzzah 2026-10-24): экспорт в AmberWorld.exe + AmberWorld.pck,
# рендерер Compatibility (Q11), без редактора _runtime, без исходников, атласов и Preview (Q13; tests остаются в .pck).
# Нужны: Godot 4.7.2 (GODOT) и шаблоны экспорта windows_release_x86_64*.exe в ~/.local/share/godot/export_templates/4.7.2.stable
# Запуск: tools/build_release.sh <папка результата> [имя сборки]
#   <папка результата>/<имя сборки>/ — AmberWorld.exe, AmberWorld.pck, ЧИТАТЬ.txt, CHECKLIST.txt
set -e
GODOT="${GODOT:-godot}"
GAME="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$1/${2:-Amber Game}"
rm -rf "$OUT" && mkdir -p "$OUT"
# Импорт: без него экспорт возьмёт старые .ctex и кэш классов
"$GODOT" --headless --path "$GAME" --import
"$GODOT" --headless --path "$GAME" --export-release "Windows Desktop" "$OUT/AmberWorld.exe"
test -s "$OUT/AmberWorld.exe" && test -s "$OUT/AmberWorld.pck"
cp "$GAME/tools/release/ЧИТАТЬ.txt" "$GAME/tools/release/CHECKLIST.txt" "$OUT/"
cp "$GAME/audio/ЗВУКИ_CC0.txt" "$OUT/"
# Проверка: пакет запускается и проходит сквозной тест пути игрока (Q22)
"$GODOT" --main-pack "$OUT/AmberWorld.pck" --headless -s res://tests/player_path_checks.gd
echo "ok: $OUT"
