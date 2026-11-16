#!/bin/bash
# (Re)start the local profile worker and room worker from the CURRENT checkout (native Godot, after up.py).
# Logs: build/localstack/worker.log, build/localstack/rooms.log. Local only: throwaway keys from build/localstack/state.json.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
G="${GODOT_BIN:-/c/Users/wanwi/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
ST=build/localstack/state.json
test -f "$ST" || { echo "run python tools/localstack/up.py first"; exit 1; }
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'Godot%'\" | Where-Object { \$_.CommandLine -like '*server/names/worker.gd*' -or \$_.CommandLine -like '*server/rooms/worker.gd*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"
TOK=$(python -c "import json;print(json.load(open('$ST'))['worker_token'])")
HK=$(python -c "import json;print(json.load(open('$ST'))['http_key'])")
# Python and Godot need a Windows path here (a Git Bash /c/... path became C:\c\... for Python).
ROOMS="$(cygpath -w "$ROOT/build/localstack/roomproj")"
rm -rf "$ROOT/build/localstack/roomproj"
python -c "import runpy,pathlib;runpy.run_path('server/rooms/smoke.py')['prepare'](pathlib.Path(r'$ROOMS'))" || exit 1
ZORX_NAMES_TOKEN=$TOK nohup "$G" --headless --path . --script res://server/names/worker.gd > build/localstack/worker.log 2>&1 &
ZORX_WORKER_TOKEN=$TOK ZORX_ROOM_HTTP_KEY=$HK ZORX_ROOM_NAKAMA_URL=http://127.0.0.1:7350 ZORX_WORKER_PORT=8052 ZORX_WORKER_BIND=127.0.0.1 ZORX_SQUAD_ROOMS=1 \
  nohup "$G" --headless --path "$ROOMS" --script res://server/rooms/worker.gd > build/localstack/rooms.log 2>&1 &
for i in $(seq 1 60); do
  grep -q "ready" build/localstack/worker.log 2>/dev/null && grep -q "ready" build/localstack/rooms.log 2>/dev/null && { echo "workers ready"; exit 0; }
  sleep 1
done
echo "workers did not start; see build/localstack/*.log"; exit 1
