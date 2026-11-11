extends RefCounted
## Shared owner transition for netfox. Full skill runtime, no economy/AI/persistence tick.
## Context targets are a private prediction copy, never the authoritative game world.
static func advance(sim,id:int,frame)->void:
 if sim.skill_system!=null:sim.skill_system.before_tick()
 sim.set_input(id,frame)
 sim.tick(id)
 if sim.skill_system!=null:sim.skill_system.advance()
