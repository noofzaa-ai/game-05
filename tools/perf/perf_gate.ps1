# Fight performance gate (tech-artist 2026-11-27). Windowed (needs a GPU), gl_compatibility like the web build.
# Boss wave of every zone, desktop (1920x987, scale 0.75, MSAA 2x, drawn style on) and phone (932x430, scale 0.5,
# no MSAA, drawn style on) profiles, against data/perf/budgets.json. Exit 1 when any row fails.
#   powershell -ExecutionPolicy Bypass -File tools\perf\perf_gate.ps1
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) { $godot = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v*_console.exe" | Select-Object -First 1).FullName }
$failed = 0
foreach ($journey in @("goblin_waves", "mummy_waves", "orc_waves")) {
    foreach ($p in @(@("--size=1920x987", "--scale=0.75", "--aa=2", "--style=on"), @("--device=phone", "--size=932x430", "--scale=0.5", "--aa=0", "--style=on", "--cap=0"))) {
        $out = & $godot --path $root --rendering-driver opengl3 "res://client/perf/fight_bench.tscn" -- "--journey=$journey" "--frames=120" "--gate" @p 2>&1 | Select-String "^GATE"
        Write-Host $out
        if (-not $out -or "$out" -notmatch "GATE PASS") { $failed++ }
    }
}
if ($failed -gt 0) { Write-Host "perf gate: $failed row(s) failed"; exit 1 }
Write-Host "perf gate: all rows pass"
