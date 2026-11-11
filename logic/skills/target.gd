class_name ZorxSkillTarget
extends RefCounted

signal died(target: ZorxSkillTarget, context: Dictionary)
signal damaged(amount: float, kind: String, context: Dictionary)
var damage_filter: Callable
var hit_allowed: Callable
signal status_applied(target: ZorxSkillTarget, id: String, context: Dictionary)
@export var max_hp: float = 100.0
var hp: float = 100.0
var statuses: Dictionary = {}
var stun_gauge: float = 0.0
var dead: bool = false
var status_visuals: Dictionary = {}
var visuals_enabled: bool = true
var entity_id: int = 0
var position := Vector3.ZERO
var global_position: Vector3:
 get: return position
const DEFINITIONS = {
 "burn":preload("res://data/skill_system/statuses/burn.tres"),
 "bleed":preload("res://data/skill_system/statuses/bleed.tres"),
 "chill":preload("res://data/skill_system/statuses/chill.tres"),
 "freeze":preload("res://data/skill_system/statuses/freeze.tres"),
 "shock":preload("res://data/skill_system/statuses/shock.tres"),
 "stun":preload("res://data/skill_system/statuses/stun.tres")
}





func status_summary() -> String:
 var names: Array[String] = []
 for id in statuses:
  if id=="bleed":
   names.append(id+" ×"+str(statuses[id].size()))
  elif id=="chill":
   names.append(id+" ×%d · %.1fs" % [int(statuses[id].get("stacks",1)),float(statuses[id].get("left",0.0))])
  else:
   names.append(id+" %.1fs" % float(statuses[id].get("left",0.0)))
 return ", ".join(names) if not names.is_empty() else "—"

func receive_hit(amount: float, status_ids: Array, context: Dictionary) -> float:
 if dead:
  return 0.0
 if hit_allowed.is_valid() and not hit_allowed.call(): return 0.0
 # Shock/stun already present affect this hit; newly applied debuffs affect later hits.
 var multiplier := _vulnerability()
 for id in status_ids:
  var stacks: int = int(context.get("status_stacks",1)) if id==context.get("intrinsic","") else 1
  var application := context.duplicate(true)
  if id=="stun" and float(context.get("stun_build",0))>0:
   application["stun_amount"] = context["stun_build"]
  for i in range(stacks): apply_status(id, application)
 return take_damage(amount * multiplier, "hit", context, true)

func consume(id: String) -> float:
 if not statuses.has(id): return 0.0
 var total := 0.0
 if id=="bleed":
  for entry in statuses[id]: total += float(entry["dps"])*maxf(0,float(entry["left"]))
 elif id=="burn":
  total = float(statuses[id]["dps"])*maxf(0,float(statuses[id]["left"]))
 else: total=1.0
 statuses.erase(id)
 _sync_status_visuals()
 return total

func remove_status(id: String) -> void:
 statuses.erase(id)
 _sync_status_visuals()

func take_damage(amount: float, kind: String, context: Dictionary, resolved: bool = false) -> float:
 if dead:
  return 0.0
 var vulnerability := 1.0 if resolved else _vulnerability()
 var incoming := maxf(amount * vulnerability, 0.0)
 if damage_filter.is_valid(): incoming = damage_filter.call(incoming, context)
 var actual := minf(hp, incoming)
 hp -= actual
 damaged.emit(actual, kind, context)
 if hp <= 0.0:
  dead = true
  var death_context := context.duplicate(true)
  if not death_context.has("events") and statuses.has("burn"):
   death_context["events"] = statuses["burn"]["context"].get("events", []).duplicate()
  var inherited: Array=death_context.get("events",[]).duplicate()
  var contexts: Array=[]
  if statuses.has("burn"):contexts.append(statuses["burn"].get("context",{}))
  if statuses.has("shock"):contexts.append(statuses["shock"].get("context",{}))
  if statuses.has("bleed"):
   for stack in statuses["bleed"]:contexts.append(stack.get("context",{}))
  for saved in contexts:
   for event in saved.get("events",[]):
    if not event in inherited:inherited.append(event)
  death_context["events"]=inherited
  death_context["burning"] = statuses.has("burn")
  death_context["bleeding"] = statuses.has("bleed")
  death_context["shocked"] = statuses.has("shock")
  death_context["status_snapshot"] = statuses.duplicate(true)
  died.emit(self, death_context)
  clear_statuses()
 return actual

func apply_status(id: String, context: Dictionary) -> void:
 if dead or not DEFINITIONS.has(id):
  return
 var definition: Resource = DEFINITIONS[id]
 match id:
  "burn":
   # Refresh to 3s; preserve the periodic tick clock so spam cannot postpone damage forever.
   var tick: float = float(statuses.get(id, {}).get("tick", definition.tick_interval_s))
   statuses[id] = {"left":definition.duration_s*float(context.get("burn_duration_mul",1)),"spread_timer":float(statuses.get(id,{}).get("spread_timer",2)),"tick":tick,"dps":definition.damage_per_tick * float(context.get("burn_damage_mul",1.0)),"context":context.duplicate(true)}
  "bleed":
   if not statuses.has(id):
    statuses[id] = []
   var stacks: Array = statuses[id]
   if stacks.size() >= int(context.get("bleed_stack_cap",definition.max_stacks)):
    stacks.pop_front()
   stacks.append({"left":definition.duration_s*float(context.get("bleed_duration_mul",1)),"tick":definition.tick_interval_s,"dps":definition.damage_per_tick*float(context.get("bleed_damage_mul",1)),"context":context.duplicate(true)})
  "chill":
   if statuses.has("freeze"):
    return
   var count: int = int(statuses.get(id, {}).get("stacks", 0)) + 1
   if count >= int(context.get("chill_threshold",definition.threshold)):
    statuses.erase(id)
    statuses["freeze"] = {"left":DEFINITIONS["freeze"].duration_s*float(context.get("freeze_duration_mul",1)),"context":context.duplicate(true)}
   else:
    # Lab-only tuning: chill expiry was not specified in the design notes.
    statuses[id] = {"left":definition.duration_s,"stacks":count,"effect_mul":float(context.get("chill_effect_mul",1)),"context":context.duplicate(true)}
  "shock":
   statuses[id] = {"left":definition.duration_s*float(context.get("shock_duration_mul",1)),"effect_mul":float(context.get("shock_effect_mul",1)),"context":context.duplicate(true)}
  "stun":
   if not statuses.has(id):
    stun_gauge += float(context.get("stun_amount",30.0))
    if stun_gauge >= definition.threshold:
     stun_gauge = 0.0
     statuses[id] = {"left":definition.duration_s*float(context.get("stun_duration_mul",1))}
 status_applied.emit(self,id,context)
 _sync_status_visuals()

func advance(delta: float) -> void:
 if dead or delta <= 0:
  return
 for id in statuses.keys():
  if not statuses.has(id) or dead:
   break
  if id in ["burn", "bleed"]:
   var entries: Array = statuses[id].duplicate() if id == "bleed" else [statuses[id]]
   for entry in entries:
    var active := minf(delta, maxf(float(entry["left"]), 0.0))
    entry["left"] -= delta
    entry["tick"] -= active
    while float(entry["tick"]) <= 0.000001 and not dead:
     entry["tick"] += DEFINITIONS[id].tick_interval_s
     take_damage(float(entry["dps"]), id, entry["context"])
    if dead:
     return
   if id == "bleed":
    statuses[id] = entries.filter(func(e: Dictionary) -> bool: return float(e["left"]) > 0.000001)
    if statuses[id].is_empty():
     statuses.erase(id)
   elif float(statuses[id]["left"]) <= 0.000001:
    statuses.erase(id)
  else:
   statuses[id]["left"] -= delta
   if float(statuses[id]["left"]) <= 0.000001:
    statuses.erase(id)
 _sync_status_visuals()

func movement_multiplier() -> float:
 if statuses.has("freeze") or statuses.has("stun") or statuses.has("root"):
  return 0.0
 return maxf(0.0,1.0 - float(DEFINITIONS["chill"].magnitude) * int(statuses.get("chill", {}).get("stacks", 0))*float(statuses.get("chill",{}).get("effect_mul",1)))

func _vulnerability() -> float:
 return (1.0 + float(DEFINITIONS["shock"].magnitude)*float(statuses["shock"].get("effect_mul",1)) if statuses.has("shock") else 1.0) * (1.0 + float(DEFINITIONS["stun"].magnitude) if statuses.has("stun") else 1.0)

func clear_statuses() -> void:
 statuses.clear()

func _sync_status_visuals() -> void:
 pass

