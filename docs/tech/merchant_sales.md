# Merchant sales

2026-10-21 side-conversation request. Boss approved deployment of exact source `5dea16a` (see release record below).

Merchant opens a Storage-derived two-column panel: sale target left, backpack right. Mouse drop/touch horizontal drag stages items locally on the left, with a summed Gold quote. Drag left-to-right to remove, or tap and use Add/Return; Return all clears selection. Nothing is sold or removed from authoritative ownership while staging. Sell entire basket opens one whole-batch confirmation. Sale is irreversible after authoritative success. Bag contents remain unchanged on the client until authority refresh; pending/ambiguous failures lock further commands until refresh. Equipped/vault items must first be moved to the backpack. Merchant purchase stock remains empty.

`data/items/shop.json.sell`: equipment_by_tier = [100,200,400,800] for Normal/Rare/Epic/Legendary (provisional figures; Boss chose tier pricing), material_per_unit =1. Refine/Upgrade/durability do not change sale prices. Material sales transfer the selected stack (up to the configured material stack size), not the entire material inventory. This JSON is build-owned currently; live ConfigMap price edits are not implemented.

`shop_sell_batch` accepts entries (maximum64 unique item/material rows) + expected_price. Nested records have exact schema; duplicates, fractional/negative/excess material counts, foreign ownership, non-bag items, price mismatch and Gold overflow reject the entire batch before any mutation. Aggregate material amounts may cover several stacks. The client caps encoded command size3400bytes to reserve room under the existing4096char RPC envelope. Full batch validates first, then removes bag items/materials and credits Gold once. Profile refresh prunes stale local selections; rejection preserves remaining valid selections. Legacy single-item sale commands remain compatible.

`shop_sell` accepts only item instance ID + expected_price. `shop_sell_material` accepts material/count + expected_price. Commands validate shape/integral numbers, camp-only location, ownership and container. Server recomputes prices; expected_price only rejects stale quotes. Validate all conditions and Gold cap before removing ownership/crediting Gold together; inherited profile CAS/revision/request receipts and room command receipts prevent repeat credits. Profile command allowlist and security command labeling include both commands. Starter kits have existing once-only version flags; selling starter pieces does not regenerate them.

Implementation touches: logic/shop.gd + commands.gd; server/profile/runner.gd; client/merchant_sell_panel.gd inherits Storage; small virtual labels in Storage; CampScreen delegates merchant setup while retaining Hub lifecycle (no Hub edits by this task); online text + guide content. Existing unrelated plaza/chat work in the shared working tree is left alone.

Compiler/import status: new Merchant panel and profile runner check-only compilation pass; TypeScript build passes. Standalone CampScreen check-only lacks the existing Audio autoload context; no game suite or purchase/sale transaction tests run. Normal editor import has no GDScript parse errors but cannot save editor preferences outside sandbox. No interactive mobile acceptance performed. Boss subsequently requested commit/push to develop. Deployment was subsequently requested for exact commit `5dea16a`; no additional tests requested.

Deployment requires coordinated web + profile-worker builds and room-worker build (for online camp lobby), and apply updated NPC guide ConfigMap. Nakama needs its security label update when next deployed; this is telemetry only. No admin permission/configuration changes.

## Release 2026-10-21

Deployed `merchant-sales-20261021-1` from clean detached source `5dea16a765a81c5ece955c9c2cfb69a898befafe`. Web build `0c427be0f0ea`; public manifest exactly matches release. Profile worker,room worker,Nakama and web rollouts successful;workers report ready and Nakama RPC registration logged. Merchant-only NPC ConfigMap update applied with resource-version guard;other guide entries preserved. Public Merchant guide now matches source; ConfigMap propagation confirmed. No sale against real player inventories,live interactive acceptance or automated tests performed.

Images:

- Web `sha256:71c6b4b30bf197cf8135899df7acfb7aa61fec8d767426c9f48cf80fef9f3081`
- Profiles `sha256:1d30907df2b4a11be0bcfaa3b7302220d9b87cea6829e518c4987dc8c0c8920c`
- Rooms `sha256:bea320e4ef1f92e6cbf15a5d9861d132c42135754da20d25c7db5e779729e757`
- Nakama `sha256:5bd01f35abfa6e2e2867d97359280f5c2e9c950a9a902f72847944bdcfc26604`

2026-10-21 follow-up: batch staging replaces immediate single-item drag sales. Merchant panel and profile runner check-only compilation pass; no transaction tests or native/mobile interactive acceptance run. Scoped follow-up prepared for push to develop under existing Merchant push authorization. No deployment for this follow-up.

## Basket release 2026-10-21

Boss requested exact source `ae8fe96b59dd4853c21c9f2b4d6ac227c1c49dbe`. Built from clean detached snapshot,tag `merchant-basket-20261021-1`,public web build `d99529e4d07a`. Web/profile/room/Nakama rollouts successful;workers ready,Nakama RPCs registered,public manifest matches release. Merchant-only guide update applied with resource-version check;public Merchant guide projection confirmed. Existing public-only SDK connection configuration retained. No automated tests,real-player inventory sale or interactive acceptance performed.

- Web `sha256:fe355ff3dae078f8fb4e6fb44eb892e245f4680229b364ed099e4dcbbf9c939a`
- Profiles `sha256:b2fd2a5a1f4387ba214de188dbec1284170c95150026e069edee848370db234d`
- Rooms `sha256:2d417e2e9279ecbd468a0c9f1db68fbe7597ee83cfb815cc8f0873b423c2e491`
- Nakama `sha256:fb9460ea877307139f0b402dc4322d24358fe148573a0c45a782068687b6e4c6`
