# Goblin waves release — 2026-11-01

Deployed public Web build `9b77e80430dc`, based on scenery build `ac9b485d31c4`. Goblin Journey now enables the single-arena wave controller by default: waves 1–11, knight miniboss and one server-owned chest at 3/6/9, rest following wave 11, then existing separate final boss room. Chest rewards are per surviving party member, with server range check and phase/idempotency guards. Dead fighters are retired between waves after 150 simulation ticks. Scenery reduction from the previous release is retained; Goblin monster geometry optimization is still unfinished.

- Web: `wiyazard:30500/zorx-web:goblin-waves-20261101-1@sha256:c3b06b6ace9386e351ec8e4235e5f18383991ebba5b3909f1fcb117ecee6516a`
- Rooms: `wiyazard:30500/zorx-room-worker:goblin-waves-20261101-1@sha256:de35a950f59979c7895a83ba10e5250ec1ec572ddd8b19305833410ffb3d88d5`

Both deployments Ready, imageIDs verified. Remote game.yaml/headless.yaml image references synchronized with backups. Public core bytes match tested candidate. Scoped Web overlay preserves deployed source inheritance and prior assets; worker room.gd differs from live baseline only by wave integration plus two new logic scripts.

Validation: Godot room flow check passes solo 1–11, rest-to-boss, co-op milestone reward, repeat/range rejection. The same synthetic check passed inside deployed Godot 4.7.2 Linux worker without account/database writes. Shipped Web StageView script parsed in extracted production project. Real browser combat/latency acceptance is pending user testing, not claimed complete. Worker crash-resume remains unsupported as before.

Evidence and builders: `/tmp/zorx-wave-release2/`, `/tmp/build-zorx-wave-release.py`. Rollback Web is scenery image `37dc2e4d974a703308bded796f29e69f64e15fea90d5ea7ee981889598de48b9`; Rooms is flight image `f0dfa6ee3675493a62ef3537847af1b952e3204c642447c137622371e0b1fd09`.
