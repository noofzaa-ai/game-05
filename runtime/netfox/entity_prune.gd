extends RefCounted
## Shared cleanup for a replicated Entity (runtime/netfox/entity.gd) whose id has dropped
## out of the live simulation - a monster died or a projectile/area-backed id was removed.
## Used by both the authority (server/rooms/netfox/service.gd:_tick, comparing against
## room.sim.bodies) and the client (client/session/netfox_session.gd:_accept_metadata,
## comparing against the just-decoded state.entities). Neither side ever freed these
## before: each leaked Entity keeps its RemoteState synchronizer running - broadcasting a
## frozen position at 20Hz on the authority, interpolating it every frame on the client -
## for the rest of the room/epoch's life, compounding with every entity that has ever
## existed. See docs/tech/lag_analysis_20261101_TH.md.
static func prune(entities: Dictionary, live_ids: Dictionary) -> void:
	for id in entities.keys():
		if not live_ids.has(id):
			entities[id].synchronizer.suspended = true
			entities[id].queue_free()
			entities.erase(id)
