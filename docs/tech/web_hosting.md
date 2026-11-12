# Web build: packs and hosting

How the web build is split, how it boots, and what a server or CDN must do to host it.
Build it with `powershell -ExecutionPolicy Bypass -File tools\web\build_web.ps1` (add `-SkipTests` to skip the test suite,
`-PackBase "https://cdn.example.com/zorx/"` to put the packs on another origin).

## Files in `build/web/`

| File | What | Cache |
|---|---|---|
| `play.html` | the page (from `tools/web/play_template.html`) | `no-cache` |
| `packs.json` | the manifest: build id, engine, core and content pack file names, sizes, load order | `no-cache` (the page also fetches it with `cache: 'no-store'`) |
| `engine.<hash>.wasm` | Godot engine, gzip-wrapped | immutable, 1 year |
| `core.<hash>.pck.wasm` | core pack: all scripts, scenes, shaders, `data/`, JSON, audio, project settings | immutable, 1 year |
| `<pack>.<hash>.pck.wasm` | content packs (art only), gzip-wrapped | immutable, 1 year |
| `<pack>.<format>.<hash>.pck.wasm` | that pack's GPU textures for one format (`s3tc` desktop, `etc2` mobile); a device downloads only one | immutable, 1 year |
| `index.js` | Godot's loader (the page loads `index.js?v=<build>`) | `no-cache` or short |
| `index.audio.worklet.js`, `index.audio.position.worklet.js` | audio worklets, fetched by `index.js` under fixed names | `no-cache` or short |
| `index.png`, `index.icon.png`, `index.apple-touch-icon.png` | icons | any |

`<hash>` is the first 12 hex digits of the SHA-256 of the file's uncompressed content, so a changed file always
gets a new name and an unchanged pack keeps its name (and its cached copy) across builds. Only `play.html`,
`packs.json`, `index.js` and the worklets have fixed names; keep those short-cached.

The `.wasm` suffix on packs and the gzip wrapping exist for the claude.ai artifact host (15 MB per binary file, a
limited set of file types). A normal server can serve them as they are; see "Compression" below.

## Pack layout

Defined in `tools/web/pack_layout.json`; the longest matching path prefix decides the pack. Whatever the folder,
scripts (`.gd`/`.gdc`), shaders, scenes (`.tscn`/`.scn`), `.json`/`.cfg`, `data/` and project files always stay
in core, so `class_name` scripts and the script class cache never split across packs. Audio is in core because
the `Audio` autoload preloads its cues at startup, before any content pack can load (move it to its own pack only
after `audio_director.gd` can reload its cues when packs arrive).

The build exports the "Web" preset to one `.pck` as before, then `tools/web/pck_split.gd` regroups the exported
entries. Each imported file (`.godot/imported/...`) goes with the `.import`/`.remap` file that names it; in content
packs the `path.s3tc` / `path.etc2` textures go to the `<pack>.s3tc` / `<pack>.etc2` packs.
`build_web.ps1` fails if any file is 15 MB or more and warns at 12 MB. To split a pack that grows, add an entry with
a longer prefix to `pack_layout.json` (for example `res://art/items/weapons/hammer` as its own pack).

## Boot flow

1. `play.html` fetches `packs.json` from the pack base (no-store) and stores `window.zorxBoot = {base, manifest}`.
2. Godot's `index.js` asks for `index.wasm` and `index.pck`; the page's fetch hook serves `manifest.engine` and
   `manifest.core` from the pack base and un-gzips them.
3. The engine starts the main scene `scenes/boot.tscn` (`client/pack_loader.gd`). It reads `window.zorxBoot`,
   chooses the content packs (plain packs plus one texture format: the first format, in the manifest's order,
   that `OS.has_feature` reports; this is the same rule Godot's importer uses to pick `path.<format>`), and
   splits them by `stage`. The **boot** packs (`client/pack_fetcher.gd`) download in parallel with `HTTPRequest`
   (3 tries each), are un-gzipped, written to the in-memory `/tmp/zorx_packs/` and mounted with
   `ProjectSettings.load_resource_pack` in manifest order.
4. Then it opens the class card screen. The page keeps its loading card up (one progress bar for engine + core +
   boot packs only) until the game calls `window.zorxBootDone()`; `window.zorxBootFail(msg)` shows an error.
5. The **battle** packs (maps, battle props, monsters, skill VFX, monster clips) start downloading in the
   background in the persistent `/root/BattlePacks` node as soon as the card screen opens. FIGHT checks
   `PackFetcher.battle_ready()`: if they are in it starts at once; if not, FIGHT shows "Loading battle NN%" and
   starts by itself when they arrive. A failed battle download shows "Load failed, tap to retry" on FIGHT.

No manifest (desktop, editor, headless tests, `--script` runs): the boot scene opens the hub at once and
everything loads from the project folder.

Two-stage loading (Boss 2026-11-13): each pack in `tools/web/pack_layout.json` has `"stage": "boot"` or
`"battle"` (missing = boot), copied into `packs.json`. Only FIGHT on the card screen enters a stage today; any new
way into a stage (online rooms, previews) must also wait for `PackFetcher.battle_ready()`.
Scenes (`.tscn`) always stay in core, so a map's `.tscn` is in core but its meshes/textures are in the battle pack.

## Pack base URL (CDN)

The packs, the engine and `packs.json` are fetched from `window.ZORX_PACK_BASE`, default `''` = next to the page.
Set it at build time: `build_web.ps1 -PackBase "https://cdn.example.com/zorx/"` (written into `play.html`).
It deliberately cannot be set from the page URL: the core pack carries the game's code, so a link that pointed
the page at another server would run that server's code on our origin.
Upload every file except `play.html` to the base (`play.html` may be uploaded too; it is unused there).

## Server requirements

- **CORS** (only when the pack base is another origin than the page): the pack host must send
  `Access-Control-Allow-Origin: <page origin>` (or `*`) on `packs.json`, `engine.*.wasm` and `*.pck.wasm`.
  Requests are plain GETs without credentials, so no preflight and no `Allow-Credentials` are needed.
  (Tested: page on one port, packs on another with `Access-Control-Allow-Origin: *`.)
- **MIME types**: `.wasm` as `application/wasm` (needed for streaming compilation on a real server; our fetch hook
  re-wraps it anyway), `.json` as `application/json`, `.js` as `text/javascript`, `.html` as
  `text/html; charset=utf-8`. Pack files may also be `application/octet-stream`.
- **Compression**: our files are already gzip-wrapped and the game unwraps them itself (it checks the gzip magic
  bytes), so do not let the server compress them again. If you prefer server-side compression, upload the raw
  files with the same names and serve them with `Content-Encoding: br` or `gzip`; the browser unpacks them before
  the game sees them and the game then gets plain bytes, which it also accepts. Compress `index.js`, the worklets,
  `play.html` and `packs.json` normally.
- **Cache headers**: hashed files `Cache-Control: public, max-age=31536000, immutable`; `play.html`,
  `packs.json`, `index.js`, the worklets `Cache-Control: no-cache`.
- **Cross-origin isolation**: not needed. The export has no threads (`variant/thread_support=false`), so no
  `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers and no service worker
  (`ensureCrossOriginIsolationHeaders` is turned off in the page). If threads are ever turned on, both headers
  become mandatory on the page and every pack host must also send `Cross-Origin-Resource-Policy: cross-origin`.
- **HTTPS** in production (WebAssembly, audio worklets and `DecompressionStream` work on `localhost` without it).

## Local test

```
python -m http.server 8060 --directory build/web      (then open http://127.0.0.1:8060/play.html)
```
For a cross-origin test, serve `build/web` with an `Access-Control-Allow-Origin: *` header on a second port and
build with `-PackBase "http://127.0.0.1:<second port>/"`.
