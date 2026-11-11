class_name ZorxSkillCaster
extends RefCounted

signal visual_requested(event: Dictionary)

signal released(position: Vector3, damage: float, pulse: int)
signal healed(amount: float)
signal explosion(position: Vector3)
var targets: Array[ZorxSkillTarget] = []
var visuals_enabled: bool = true
var clock: float = 0.0
var ready_at: float = 0.0
var pending: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var cast_serial: int = 0
var cast_until: float = 0.0



func remaining_cooldown() -> float:
 return maxf(0.0, ready_at - clock)

func is_casting() -> bool:
 return clock < cast_until

func request_cast(skill: ZorxSkillData, stats: Dictionary, origin: Vector3, aim: Vector3) -> String:
 if stats.has("error"):
  return str(stats["error"])
 if skill == null or skill.authored_radius_m <= 0.0:
  return "Missing VFX or authored radius"
 if remaining_cooldown() > 0.000001:
  return "กำลังร่าย / คูลดาวน์"
 var point := origin
 if stats["origin"] == "target":
  var direction := aim - origin
  direction.y = 0.0
  point += direction.limit_length(float(stats["target_range"]))
 var snapshot := stats.duplicate(true)
 cast_until = clock + float(snapshot["cast_time"])
 ready_at = cast_until + float(snapshot["cooldown"])
 cast_serial += 1
 for i in range(int(snapshot["repeat"])):
  pending.append({"cast_id":cast_serial,"started":false,"time":cast_until + i * float(snapshot["repeat_delay"]),"point":point,"stats":snapshot,"pulse":i,"skill":skill})
 return ""

func advance(delta: float) -> void:
 clock += maxf(delta, 0.0)
 # Remove a due event before dispatch: deaths can synchronously emit more events.
 while not pending.is_empty() and float(pending[0]["time"]) <= clock + 0.000001:
  var event: Dictionary = pending.pop_front()
  if int(event["pulse"])==0:
   for queued in pending:
    if queued["cast_id"]==event["cast_id"]: queued["started"]=true
  var stats: Dictionary = event["stats"]
  var amount := float(stats["damage"]) * (float(stats["repeat_damage_mul"]) if int(event["pulse"]) > 0 else 1.0)
  _spawn_visual(event["skill"], event["point"], float(stats["radius"]))
  _area_hit(event["point"], float(stats["radius"]), amount, stats["statuses"], stats)
  released.emit(event["point"], amount, int(event["pulse"]))

func _area_hit(point: Vector3, radius: float, damage: float, status_ids: Array, context: Dictionary) -> void:
 for target: ZorxSkillTarget in targets.duplicate():
  if not is_instance_valid(target) or target.dead:
   continue
  var offset: Vector3 = target.global_position - point
  if absf(offset.y) > float(context.get("hit_height", 2.5)) or Vector2(offset.x,offset.z).length() > radius + 0.000001:
   continue
  var actual: float = target.receive_hit(damage, status_ids, context)
  if float(context.get("leech", 0.0)) > 0.0:
   healed.emit(actual * float(context["leech"]))

func connect_target(target: ZorxSkillTarget) -> void:
 targets.append(target)
 target.died.connect(_on_target_died)

func _on_target_died(target: ZorxSkillTarget, context: Dictionary) -> void:
 if not bool(context.get("burning", false)) or not "burn_death_explosion" in context.get("events", []):
  return
 var point := target.global_position
 # Corpse explosion is its own hit: no gem/echo/leech/status propagation.
 # Already-burning victims retain their burn context for further corpse explosions.
 explosion.emit(point)
 if visuals_enabled:
  _spawn_visual(load("res://data/skill_system/skills/fire_ring.tres"), point, 2.0)
 _area_hit(point, 2.0, 15.0, [], {"hit_height":2.5})

func _spawn_visual(skill: ZorxSkillData, point: Vector3, radius: float) -> void:
 visual_requested.emit({"kind":"burst","skill":skill.id,"position":point,"radius":radius})

func reset() -> void:
 pending.clear()
 clock = 0.0
 ready_at = 0.0
 cast_until = 0.0
 effects.clear()
 for target in targets:
  if is_instance_valid(target) and target.died.is_connected(_on_target_died):
   target.died.disconnect(_on_target_died)
 targets.clear()




