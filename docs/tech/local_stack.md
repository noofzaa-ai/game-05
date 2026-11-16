# Local online stack and jump-to-state testing

Boss 2026-11-16: test mostly on this machine, on a copy of the staging server. Never play to a state: load it.
The staging web is only a short smoke after a release.

## Start the stack (once per boot)

```sh
python tools/localstack/up.py          # Postgres + Nakama (staging image, current runtime) on 127.0.0.1:7350
bash tools/localstack/workers.sh       # profile worker + room worker from the CURRENT checkout (re-run after code changes)
```

Throwaway local keys live in `build/localstack/state.json` (git-ignored). Nothing here touches staging or production.
The room server needs the runtime built first: `cd server/names/runtime && npm run build`.

## Jump to a game state

```sh
godot --path . --script res://tools/localstack/scenario.gd -- --fixture unlock_ceremony [--open map] [--size 844x390] [--shot out.png]
```

The script signs in a fresh account, puts it into `tools/localstack/fixtures/<name>.json`, and opens the screen.
Without `--shot` the window stays open so you can click around. About 10 s, against minutes of play.

| Fixture | State |
|---|---|
| `new_player` | brand new account (tutorial welcome) |
| `tutorial_alliance` | races picked, tutorial on Alliance |
| `tutorial_tour` | first fight done, tutorial on the Equipment tour |
| `unlock_ceremony` | Goblin Chief just beaten, Magic seal-break ceremony |
| `veteran` | tutorial done, Magic Runeborn, level 10 cards, 500k gold, Chief beaten |
| `old_account` | a pre-tutorial save (migration) |

`--open`: `hub` (default), `map`, `character:<class>`, `storage`, `shop`, `blacksmith`, `tailor`, `fight`.

A new state means a new JSON file. A fixture is a partial profile: dictionaries merge, everything else replaces, and
`_remove` drops top-level keys. `tests/test_localstack_fixtures.gd` checks that every fixture still loads and lands its
state.

To put an existing local account into a state: `python tools/localstack/fixture.py apply <user_id> <fixture>`.

## Whole-flow walks and hard cases

- `tools/localstack/walk.gd`: plays the whole tutorial on the local stack, checking each step on the server too.
  Options: `--fps 24` (web-like frame rate). For latency, run `tools/localstack/lagproxy.py` between Nakama and the
  room worker.
- Timing and network edge cases (busy replies, slow sends, rooms closing, oversized events) are unit tests with fake
  transports: see tests/test_tutorial_ui.gd and tests/test_event_stream.gd.
