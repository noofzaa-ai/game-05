extends "res://logic/skills/system.gd"
## Training uses body-clearance movement queries; damage/skill rules remain the normal system.
func before_tick()->void:
 super.before_tick()
 for caster in casters.values():
  var clearance:Array[AABB]=[]
  for box in caster.obstacles:
   # Runtime sweeps a point at feet +0.5m. Expand XZ by the real body footprint,
   # preserving Y so the floor is not interpreted as an impassable wall.
   clearance.append(AABB(box.position-Vector3(.401,0,.401),box.size+Vector3(.802,0,.802)))
  caster.obstacles=clearance
