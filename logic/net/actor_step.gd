extends RefCounted
## Shared owner transition for netfox. No economy/AI/persistence tick.
## Context targets are a private prediction copy, never the authoritative game world.
static func advance(sim,id:int,frame)->void:
 sim.set_input(id,frame)
 sim.tick(id)
