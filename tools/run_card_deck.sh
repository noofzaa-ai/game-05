#!/usr/bin/env bash
# Opens the class card screen in a live Godot window (hover = tilt + holo, click a card = editor, FIGHT = summon).
# Usage: bash tools/run_card_deck.sh        (optional: GODOT=/path/to/godot bash tools/run_card_deck.sh)
set -e
cd "$(dirname "$0")/.."

find_godot() {
  if [ -n "$GODOT" ] && [ -x "$GODOT" ]; then echo "$GODOT"; return; fi
  for c in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64.exe" \
    "$(command -v godot 2>/dev/null)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return; fi
  done
  for c in "$LOCALAPPDATA"/Microsoft/WinGet/Packages/GodotEngine*/Godot_v*_win64.exe; do
    if [ -x "$c" ]; then echo "$c"; return; fi
  done
  return 1
}

G="$(find_godot)" || { echo "Godot not found. Set GODOT=/path/to/godot and run again."; exit 1; }
echo "Using: $G"
# First run after a fresh clone needs the import once:  "$G" --headless --path . --import
exec "$G" --path . --resolution 1280x720 --script res://tools/shots/card_deck_live.gd
