# Builds the web playtest into build/web/, ready to publish as the claude.ai artifact or to put on a
# web server / CDN (docs/tech/web_hosting.md).
#
#   powershell -ExecutionPolicy Bypass -File tools\web\build_web.ps1            (tests first, then build)
#   powershell -ExecutionPolicy Bypass -File tools\web\build_web.ps1 -SkipTests
#   ... -PackBase "https://cdn.example.com/zorx/"   (packs on another origin; default: next to the page)
#
# Steps: import assets -> run the test suite (stops on a failure) -> export the "Web" preset ->
# split the exported .pck into a core pack + content packs (tools/web/pack_layout.json, pck_split.gd) ->
# gzip every big file under a content-hashed name (engine.<hash>.wasm, <pack>.<hash>.pck.wasm) ->
# write packs.json (the manifest) and play.html -> size table (fails at 15 MB per file, the artifact
# host's limit; warns at 12 MB). Publishing itself is done by Claude ("อัป artifact"), on Boss's order only.

param([switch]$SkipTests, [string]$PackBase = "")
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$out = Join-Path $root "build\web"
$limitMB = 15
$warnMB = 12

function Find-Godot {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $found = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v*_console.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Godot not found (install it or put godot on PATH)."
}

function Invoke-Godot([string[]]$arguments, [int]$timeoutSec, [string]$name) {
    $log = Join-Path $env:TEMP "zorx_$name"
    $p = Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $root -PassThru -NoNewWindow `
        -RedirectStandardOutput "$log.out.txt" -RedirectStandardError "$log.err.txt"
    if (-not $p.WaitForExit($timeoutSec * 1000)) { $p.Kill(); throw "$name timed out after $timeoutSec s (logs: $log.*.txt)" }
    return $log
}

function Compress-Gzip([string]$from, [string]$to) {
    $in = [IO.File]::OpenRead($from)
    $outStream = [IO.File]::Create($to)
    $gz = New-Object IO.Compression.GZipStream($outStream, [IO.Compression.CompressionLevel]::Optimal)
    $in.CopyTo($gz); $gz.Dispose(); $outStream.Dispose(); $in.Dispose()
}

$godot = Find-Godot
Write-Host "Godot: $godot"

# Share the same source identity with the in-game title and HTML shell.
$revision = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot read Git revision" }
$sourceFiles = & git -C $root ls-files
$sourceTime = ($sourceFiles | Where-Object { $_ -ne "data/ui/build_info.json" } | ForEach-Object { Get-Item (Join-Path $root $_) -ErrorAction SilentlyContinue } | Where-Object { -not $_.PSIsContainer } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
$sourceDate = $sourceTime.AddHours(7).ToString("yyyy-MM-dd HH:mm:ss") + " UTC+07:00"
$dirty = [bool](& git -C $root status --porcelain --untracked-files=no -- . ':(exclude)data/ui/build_info.json')
$buildInfo = @{channel="BETA-TEST"; commit=$revision; short_commit=$revision.Substring(0,12); dirty=$dirty; source_date=$sourceDate; source_modified=$sourceTime.ToString("o")}
[IO.File]::WriteAllText((Join-Path $root "data/ui/build_info.json"), ($buildInfo | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))

Write-Host "1/6 Importing assets..."
Invoke-Godot @("--headless", "--path", ".", "--import") 600 "import" | Out-Null

if (-not $SkipTests) {
    Write-Host "2/6 Running tests..."
    $log = Invoke-Godot @("--headless", "--path", ".", "--script", "res://tests/run_all.gd") 600 "tests"
    $summary = Select-String -Path "$log.out.txt" -Pattern "passed=(\d+) failed=(\d+)" | Select-Object -Last 1
    if (-not $summary) { throw "Tests did not finish (logs: $log.*.txt)" }
    $failed = [int]$summary.Matches[0].Groups[2].Value
    Write-Host "   $($summary.Line.Trim())"
    if ($failed -gt 0) {
        Select-String -Path "$log.out.txt" -Pattern "FAIL" | ForEach-Object { Write-Host "   $($_.Line.Trim())" -ForegroundColor Red }
        throw "$failed test(s) failed - not building."
    }
} else { Write-Host "2/6 Tests skipped." }

Write-Host "3/6 Exporting the Web preset..."
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -File | Remove-Item -Force   # (keeps build/web/.claude, the artifact link)
$log = Invoke-Godot @("--headless", "--path", ".", "--export-release", "Web", "build/web/index.html") 600 "export"
if (-not (Test-Path "$out\index.wasm") -or -not (Test-Path "$out\index.pck")) { throw "Export failed (logs: $log.*.txt)" }

Write-Host "4/6 Splitting the game data into packs..."
$split = Join-Path $out "_split"
New-Item -ItemType Directory -Force $split | Out-Null
$log = Invoke-Godot @("--headless", "--path", ".", "--script", "res://tools/web/pck_split.gd", "--", "$out\index.pck", "$root\tools\web\pack_layout.json", $split) 600 "split"
if (-not (Test-Path "$split\split.json") -or (Select-String -Path "$log.err.txt" -Pattern "ERROR" -Quiet)) {
    Get-Content "$log.err.txt" | Write-Host -ForegroundColor Red
    throw "Pack split failed (logs: $log.*.txt)"
}
Get-Content "$log.out.txt" | Where-Object { $_ -match "^pack " } | ForEach-Object { Write-Host "   $_" }

Write-Host "5/6 Compressing under content-hashed names..."
function Get-ShortHash([string]$path) { return (Get-FileHash $path -Algorithm SHA256).Hash.Substring(0, 12).ToLower() }
function Publish-File([string]$from, [string]$name, [string]$ext) {
    $h = Get-ShortHash $from
    $file = "$name.$h.$ext"
    Compress-Gzip $from "$out\$file"
    return [ordered]@{ file = $file; bytes = (Get-Item "$out\$file").Length; raw_bytes = (Get-Item $from).Length; hash = $h }
}
$engine = Publish-File "$out\index.wasm" "engine" "wasm"
$core = Publish-File "$split\core.pck" "core" "pck.wasm"
$packs = @()
foreach ($p in (Get-Content "$split\split.json" -Raw | ConvertFrom-Json)) {
    if ($p.name -eq "core") { continue }
    $f = Publish-File "$split\$($p.name).pck" $p.name "pck.wasm"
    $stage = if ($p.stage) { $p.stage } else { "boot" }
    $packs += [ordered]@{ name = $p.name; stage = $stage; format = $p.format; file = $f.file; bytes = $f.bytes; raw_bytes = $f.raw_bytes }
}
$buildId = (($engine.hash, $core.hash) + ($packs | ForEach-Object { $_.file }) -join "|")
$buildId = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($buildId))).Replace("-", "").Substring(0, 12).ToLower()
$manifest = [ordered]@{
    build = $buildId; built = (Get-Date -Format "yyyy-MM-dd HH:mm")
    engine = $engine.file; engine_bytes = $engine.bytes
    core = $core.file; core_bytes = $core.bytes
    packs = $packs
}
[IO.File]::WriteAllText("$out\packs.json", ($manifest | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

Write-Host "6/6 Writing play.html..."
$index = Get-Content "$out\index.html" -Raw
$match = [regex]::Match($index, "const GODOT_CONFIG = (\{.*?\});", "Singleline")
if (-not $match.Success) { throw "GODOT_CONFIG not found in the exported index.html" }
# per-device download: engine + core + plain packs + one texture format (formats are alternatives)
$formats = @($packs | Where-Object { $_.format } | ForEach-Object { $_.format } | Select-Object -Unique)
$download = $engine.bytes + $core.bytes + (Get-Item "$out\index.js").Length
# (only the boot packs: the battle packs load in the background on the card screen, client/pack_fetcher.gd)
foreach ($p in $packs) { if ($p.stage -eq "battle") { continue }; if (-not $p.format) { $download += $p.bytes } elseif ($p.format -eq $formats[0]) { $download += $p.bytes } }
$download /= 1MB
$loadingSource = "$root\assets\ui\camp_menu\farm-v1.png"
$loadingHash = (Get-FileHash $loadingSource -Algorithm SHA256).Hash.ToLower().Substring(0,12)
$loadingName = "loading.$loadingHash.png"
Copy-Item $loadingSource "$out\$loadingName"
$page = Get-Content "$root\tools\web\play_template.html" -Raw -Encoding UTF8
$page = $page.Replace("__LOADING_BACKGROUND__", $loadingName)
# (no cross-origin-isolation service worker: the build has no threads, and the artifact page cannot install one)
$config = $match.Groups[1].Value.Replace('"ensureCrossOriginIsolationHeaders":true', '"ensureCrossOriginIsolationHeaders":false')
$config = [regex]::Replace($config, '"index\.pck":\d+', '"index.pck":' + $core.raw_bytes)
$commitLabel = $buildInfo.short_commit + $(if ($dirty) { " + local changes" } else { "" })
$page = $page.Replace("__SOURCE_DATE__", $sourceDate).Replace("__COMMIT__", $commitLabel)
$page = $page.Replace("__GODOT_CONFIG__", $config).Replace("__SIZE_MB__", ("{0:N0}" -f [math]::Ceiling($download))).Replace("__BUILD_DATE__", $manifest.built)
$page = $page.Replace("__BUILD_ID__", $buildId).Replace("__PACK_BASE__", $PackBase.Replace("'", ""))
[IO.File]::WriteAllText("$out\play.html", $page, (New-Object Text.UTF8Encoding($false)))

# the raw export is only an intermediate: index.pck/index.wasm are over the limit and index.html cannot load the split packs
Remove-Item -Force "$out\index.pck", "$out\index.wasm", "$out\index.html"
Remove-Item -Recurse -Force $split

Write-Host ""
Write-Host "Size table (build $buildId):"
$over = @()
foreach ($f in Get-ChildItem $out -File | Sort-Object Length -Descending) {
    $mb = $f.Length / 1MB
    $flag = ""
    if ($mb -ge $limitMB) { $flag = "  OVER $limitMB MB LIMIT"; $over += $f.Name }
    elseif ($mb -ge $warnMB) { $flag = "  warning: over $warnMB MB" }
    $color = if ($flag -match "OVER") { "Red" } elseif ($flag) { "Yellow" } else { "Gray" }
    Write-Host ("   {0,-40} {1,8:N2} MB{2}" -f $f.Name, $mb, $flag) -ForegroundColor $color
}
if ($over.Count -gt 0) { throw "Files at or over the $limitMB MB artifact limit: $($over -join ', ')" }

Write-Host ""
Write-Host "Done. build/web/ is ready (build $buildId, download about $([math]::Ceiling($download)) MB per device)." -ForegroundColor Green
Write-Host "Files to publish: every file in build/web/ (play.html is the page; packs.json is the manifest)."
Write-Host "To put it online, tell Claude: อัป artifact"
