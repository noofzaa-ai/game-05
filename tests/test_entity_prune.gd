extends RefCounted
## Dead/despawned entities (monster killed, projectile-backed id removed) used to leak
## forever: neither the authority (server/rooms/netfox/service.gd) nor the client
## (client/session/netfox_session.gd) ever freed a replicated Entity once its id dropped
## out of the live simulation, so its RemoteState synchronizer kept broadcasting/
## interpolating a frozen position for the rest of the room/epoch - confirmed from a real
## Lag Report where the client reported 37-42 "entities" while the worker's own sim had
## only 5-6 live fighters. See runtime/netfox/entity_prune.gd and
## docs/tech/lag_analysis_20261101_TH.md.
const Prune := preload("res://runtime/netfox/entity_prune.gd")

class FakeSynchronizer:
	extends RefCounted
	var suspended := false

class FakeEntity:
	extends RefCounted
	var synchronizer := FakeSynchronizer.new()
	var freed := false
	func queue_free() -> void: freed = true


func run(ctx) -> void:
	var a := FakeEntity.new()
	var b := FakeEntity.new()
	var c := FakeEntity.new()
	var entities := {1: a, 2: b, 3: c}

	Prune.prune(entities, {1: true, 3: true})
	ctx.check("M4 an id missing from live_ids is removed from the entities dict", not entities.has(2))
	ctx.check("M4 ids still present in live_ids are left in the entities dict", entities.has(1) and entities.has(3))
	ctx.check("M4 the removed entity's node is freed", b.freed)
	ctx.check("M4 the removed entity's synchronizer is suspended before freeing", b.synchronizer.suspended)
	ctx.check("M4 surviving entities are never freed or suspended", not a.freed and not a.synchronizer.suspended and not c.freed and not c.synchronizer.suspended)

	# Idempotent: pruning again with the same live set touches nothing further.
	Prune.prune(entities, {1: true, 3: true})
	ctx.check("M4 pruning again with the same live set is a no-op", entities.size() == 2 and entities.has(1) and entities.has(3))

	# Everything gone (room emptied / all enemies cleared).
	var d := FakeEntity.new()
	var all_gone := {4: d}
	Prune.prune(all_gone, {})
	ctx.check("M4 every entity is removed once none are in live_ids", all_gone.is_empty() and d.freed)

	# Nothing to prune: an empty entities dict is always a no-op, regardless of live_ids.
	var empty := {}
	Prune.prune(empty, {1: true})
	ctx.check("M4 pruning an empty dict never errors or adds anything", empty.is_empty())

	# live_ids keys matter, not values - this must work the same whether called with
	# room.sim.bodies (server, id -> SimBody) or state.entities (client, id -> [body, fighter] row).
	var e := FakeEntity.new()
	var mixed := {5: e, 6: FakeEntity.new()}
	Prune.prune(mixed, {5: "anything, only presence is checked"})
	ctx.check("M4 only key presence in live_ids matters, not the value", mixed.has(5) and not mixed.has(6))
