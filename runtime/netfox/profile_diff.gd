extends RefCounted
## Protocol 3 wire saving: the viewer's own profile block (meta.profiles[slot]) is
## ~12-16KB uncompressed (stash/loadout) and almost never changes between 20Hz snapshots -
## it only moves on camp/bag commands, not combat. Resending it unchanged measured as the
## single largest share of snapshot bandwidth and compounded into visible stutter under load
## (docs/tech/lag_analysis_20261101_TH.md). The authority sends {"v":0} instead when it is
## byte-identical to the last copy sent to that peer; the client restores its own cache.
## Teammates' redacted profiles are left untouched (already small, not the cost here).
const SENTINEL := {"v": 0}

## Authority side: mutates `profiles` (state.meta.profiles) in place. `cache` is a per-peer
## scratch dict the caller owns across snapshots (e.g. lease.peers[peer]) - pass the SAME
## dict every call for a given peer so the comparison is meaningful.
static func send_only_on_change(profiles: Dictionary, slot: int, cache: Dictionary) -> void:
	var own = profiles.get(slot)
	if own == null: return
	if cache.get("sent_own_profile") == own: profiles[slot] = SENTINEL
	else: cache["sent_own_profile"] = own

## Client side: mutates `profiles` (the just-decoded state.meta.profiles) in place, restoring
## our own slot from `previous` (the last meta.profiles we actually applied) when the
## authority sent the sentinel. `previous` is {} on the very first packet, before anything is
## cached. Returns false when a sentinel arrives with nothing cached yet (should not happen -
## the authority always sends real data on a peer's first snapshot - but fails closed: the
## caller should wait for the authority's next full snapshot rather than apply this tick).
static func restore_cached(profiles: Dictionary, player_id: int, previous: Dictionary) -> bool:
	var own = profiles.get(player_id)
	if not (own is Dictionary and own.size() == 1 and own.get("v") == 0): return true
	var cached = previous.get(player_id)
	if cached == null: return false
	profiles[player_id] = cached
	return true
