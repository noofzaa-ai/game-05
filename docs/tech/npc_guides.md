# NPC guide wording ConfigMap

ConfigMap `zorx-npc-guides` in zorx-staging, key `npc_guides.json`. Public wording only; never store secrets. Schema version1, guides keys blacksmith/merchant/storage/customize/world_map/default; title/body/confirm plain strings. UTF-8, body<=8000chars,title/confirm<=120.

Nginx serves `/config/npc_guides.json` from directory-mounted `/etc/zorx-public`,no subPath,no-store. Godot fetches same-origin HTTPS on each guide opening,5second timeout,64KiB response cap; validates schema and displays plain text. Bundled data/ui/npc_guides.json fallback supports native/offline/error. Changing valid ConfigMap wording requires no game rebuild or pod restart. Allow Kubernetes volume propagation (typically up to a few minutes),then reopen !. Already-open guide is not pushed live.

Edit checked-in server/k3s/npc-guides.yaml or use kubectl edit configmap zorx-npc-guides -n zorx-staging. Apply valid JSON under key; don't edit gameplay tuning or credentials. Guide content covers Repair/Refine/Upgrade, empty Merchant stock, storage transfers, appearance choices and world-map departure. Keep guidance consistent with gameplay configuration. Checked-in fallback updates on the next client build; the deployed web client reads the current ConfigMap when ! is reopened.
