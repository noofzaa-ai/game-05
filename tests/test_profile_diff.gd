extends RefCounted
## Protocol 3: the viewer's own profile block is omitted (sentinel {"v":0}) from a snapshot
## when it is unchanged since the last one sent to that peer, instead of resending ~12-16KB
## of stash/loadout data 20x/second. See runtime/netfox/profile_diff.gd and
## docs/tech/lag_analysis_20261101_TH.md.
const Diff := preload("res://runtime/netfox/profile_diff.gd")
const Manager := preload("res://server/rooms/manager.gd")
const F := preload("res://tests/online_fixture.gd")

func run(ctx) -> void:
	_test_authority_against_real_room(ctx)
	_test_client_rehydration(ctx)
	_test_edge_cases(ctx)


## Exercises the authority side against an actual Room.public_state() - not a mock - so a
## future change to what belongs in a profile dict is covered automatically.
func _test_authority_against_real_room(ctx) -> void:
	var manager := Manager.new()
	var f := F.make(77)
	manager.create("profile-diff-room", 77, [{"id": 1, "profile": f.profile.to_dict()}, {"id": 2, "profile": F.make(78).profile.to_dict()}])
	var room = manager.rooms["profile-diff-room"].room

	var cache := {}
	var first: Dictionary = room.public_state(1)
	var first_profile: Dictionary = first.meta.profiles[1].duplicate(true)
	Diff.send_only_on_change(first.meta.profiles, 1, cache)
	ctx.check("M4 first snapshot to a peer always sends the real profile", first.meta.profiles[1] == first_profile and not first.meta.profiles[1].has("v") or first.meta.profiles[1].v != 0 or first.meta.profiles[1].size() != 1)

	var second: Dictionary = room.public_state(1)
	ctx.check("M4 nothing changed server-side between snapshots", second.meta.profiles[1] == first_profile)
	Diff.send_only_on_change(second.meta.profiles, 1, cache)
	ctx.check("M4 unchanged profile is replaced by the sentinel on the next snapshot", second.meta.profiles[1] == {"v": 0})
	ctx.check("M4 the sentinel never collides with a real profile shape", first_profile.size() != 1 or not first_profile.has("v") or first_profile.v != 0)

	var third: Dictionary = room.public_state(1)
	Diff.send_only_on_change(third.meta.profiles, 1, cache)
	ctx.check("M4 still-unchanged profile keeps sending the sentinel", third.meta.profiles[1] == {"v": 0})

	# Mutate the authoritative profile through a real command, same as a player buying/moving gear.
	# public_state() caches per (clock_tick, epoch); advance a tick so it recomputes.
	room.trip_for(1).profile.stash.gold += 500
	manager.advance(1.0 / 60.0)
	var changed: Dictionary = room.public_state(1)
	var changed_profile: Dictionary = changed.meta.profiles[1].duplicate(true)
	ctx.check("M4 a real change produces a different profile dict", changed_profile != first_profile)
	Diff.send_only_on_change(changed.meta.profiles, 1, cache)
	ctx.check("M4 a real change sends the full profile again, not the sentinel", changed.meta.profiles[1] == changed_profile)

	var settled: Dictionary = room.public_state(1)
	Diff.send_only_on_change(settled.meta.profiles, 1, cache)
	ctx.check("M4 it goes quiet again once the new value stabilizes", settled.meta.profiles[1] == {"v": 0})

	# A second peer has its own independent cache; the same room tick must not cross-pollute.
	var cache2 := {}
	var peer2_first: Dictionary = room.public_state(2)
	var peer2_profile: Dictionary = peer2_first.meta.profiles[2].duplicate(true)
	Diff.send_only_on_change(peer2_first.meta.profiles, 2, cache2)
	ctx.check("M4 a second peer's first snapshot is unaffected by peer 1's cache", peer2_first.meta.profiles[2] == peer2_profile)
	ctx.check("M4 the room's own profiles cache is untouched by the sentinel swap (no aliasing)", room.public_state(1).meta.profiles[1] == changed_profile)


## The client side is deliberately a pure, side-effect-free function so it is testable
## without a live connection; netfox_session.gd calls it as the very first thing in
## _accept_metadata(), before `ownership` is computed from state.meta.profiles.
func _test_client_rehydration(ctx) -> void:
	var real_profile := {"v": 1, "stash": {"gold": "100"}}
	var profiles := {1: real_profile.duplicate(true), 2: {"v": 1, "stash": {"gold": "0"}}}
	var previous := {}
	ctx.check("M4 the real first packet passes through rehydration unchanged", Diff.restore_cached(profiles, 1, previous) and profiles[1] == real_profile)

	var sentinel_packet := {1: {"v": 0}, 2: {"v": 1, "stash": {"gold": "0"}}}
	var previous_with_real := {1: real_profile.duplicate(true), 2: profiles[2]}
	ctx.check("M4 a sentinel is restored to the last cached real profile", Diff.restore_cached(sentinel_packet, 1, previous_with_real) and sentinel_packet[1] == real_profile)
	ctx.check("M4 restoring the sentinel never mutates the cache it reads from", previous_with_real[1] == real_profile)

	var other_player_untouched := {1: {"v": 0}, 2: {"v": 1, "stash": {"gold": "77"}}}
	Diff.restore_cached(other_player_untouched, 1, previous_with_real)
	ctx.check("M4 another player's profile entry is never touched", other_player_untouched[2] == {"v": 1, "stash": {"gold": "77"}})

	var updated_profile := {"v": 1, "stash": {"gold": "250"}}
	var real_packet := {1: updated_profile.duplicate(true)}
	ctx.check("M4 a real (non-sentinel) profile is never mistaken for a sentinel", Diff.restore_cached(real_packet, 1, previous_with_real) and real_packet[1] == updated_profile)


func _test_edge_cases(ctx) -> void:
	var sentinel_no_cache := {1: {"v": 0}}
	ctx.check("M4 a sentinel with nothing cached yet fails closed (wait for the next real snapshot)", not Diff.restore_cached(sentinel_no_cache, 1, {}))
	ctx.check("M4 failing closed never invents or clears the sentinel in place", sentinel_no_cache[1] == {"v": 0})

	var missing_player := {2: {"v": 1}}
	ctx.check("M4 a missing player id is left alone (not a sentinel, nothing to restore)", Diff.restore_cached(missing_player, 1, {}))

	ctx.check("M4 the sentinel constant matches what the authority actually sends", Diff.SENTINEL == {"v": 0})

	# A profile dict that happens to be size 1 but is not the sentinel (schema drift guard):
	# real Profile.to_dict() always has 19 keys (see logic/profile.gd), so size==1 with a
	# "v" key other than 0 should never occur in practice, but must not be swallowed if it did.
	var almost := {1: {"v": 1}}
	ctx.check("M4 a size-1 dict that is not literally {v:0} is treated as real data", Diff.restore_cached(almost, 1, {}) and almost[1] == {"v": 1})
