class_name ZorxBuildCalc
extends RefCounted

static func can_equip(skill: ZorxSkillData, gem: ZorxGemData, slot: String) -> String:
 if skill == null or gem == null:
  return "Missing skill or gem"
 if not slot in skill.slots or not slot in ["shape", "effect"]:
  return "No such slot"
 if gem.slot != slot:
  return "ช่องไม่ตรง: " + gem.slot
 for tag in gem.requires_tags:
  if not tag in skill.tags:
   return "ต้องมี tag " + tag
 if not gem.status_id.is_empty() and gem.status_id in skill.built_in_statuses:
  return "สกิลทำสถานะนี้อยู่แล้ว: " + gem.status_id
 if gem.id == "pierce" and ("no_pierce" in skill.tags or float(skill.base_stats.get("pierce",0)) >= 99):
  return "การทะลุไม่มีผลกับสกิลนี้"
 if gem.id == "quickcast" and float(skill.base_stats.get("cast_time", 0.0)) <= 0.0:
  return "ไม่มีเวลาร่ายให้ลด"
 if gem.id == "charge" and skill.behavior != "parry" and float(skill.base_stats.get("cast_time", 0.0)) <= 0.0:
  return "ไม่มีเวลาร่ายเป็นต้นทุน"
 return ""

static func can_allocate(tree: ZorxPassiveTreeData, run: ZorxRunState, id: String) -> String:
 if id in run.allocated:
  return "ลงแล้ว"
 if not tree.by_id.has(id):
  return "ไม่มีโหนดนี้"
 var n: ZorxTreeNodeData = tree.by_id[id]
 if n.is_start:
  return "เลือกจุดเริ่มผ่านอาวุธเท่านั้น"
 if run.points <= 0:
  return "แต้มไม่พอ"
 if n.is_hybrid:
  if n.requires_all.is_empty():
   return "Hybrid ไม่มี prerequisites"
  for required in n.requires_all:
   if not required in run.allocated:
    return "ต้องมี " + required
  return ""
 for neighbor in tree.adjacency[id]:
  if neighbor in run.allocated:
   return ""
 return "ต้องต่อกับโหนดที่ลงแล้ว"

# Returns an independent snapshot. Invalid loadouts never reach the caster.
static func calc_skill(skill: ZorxSkillData, gems: Array[ZorxGemData], tree: ZorxPassiveTreeData = null, run: ZorxRunState = null) -> Dictionary:
 var effective_tags:=skill.tags.duplicate()
 if skill.id in ["ice_lance","shatter_smash","ice_wall","frost_armor"]:effective_tags.append("cold")
 if skill.id in ["chain_lightning","lightning_strike","blink_bolt","tesla_totem"]:effective_tags.append("lightning")
 var mods: Array[ZorxStatMod] = []
 var occupied: Array[String] = []
 var statuses := skill.built_in_statuses.duplicate()
 var events: Array[String] = []
 for gem in gems:
  var error := can_equip(skill, gem, gem.slot)
  if not error.is_empty() or gem.slot in occupied:
   return {"error": error if not error.is_empty() else "Duplicate slot"}
  occupied.append(gem.slot)
  mods.append_array(gem.mods)
  if not gem.status_id.is_empty():
   statuses.append(gem.status_id)
 if tree != null and run != null:
  for id in run.allocated:
   var n: ZorxTreeNodeData = tree.by_id[id]
   for mod in n.mods:
    if mod.scope == ZorxStatMod.Scope.SKILL and mod.scope_tags.all(func(tag: String) -> bool: return tag in effective_tags):
     mods.append(mod)
   if not n.event_id.is_empty():
    events.append(n.event_id)
 var result := {"bleed_damage_mul":1.0,"bleed_duration_mul":1.0,"bleed_stack_cap":5.0,"burn_duration_mul":1.0,"chill_effect_mul":1.0,"chill_threshold":5.0,"freeze_duration_mul":1.0,"shock_effect_mul":1.0,"shock_duration_mul":1.0,"stun_duration_mul":1.0,"hp_max_mul":1.0,"heal_allowed":1.0,"damage_taken_mul":1.0,"move_speed_mul":1.0,"dodge_cd_mul":1.0,"range_mul":1.0,"crit_chance":0.0,"crit_multiplier":1.5}
 result.merge(skill.base_stats,true)
 var assigned: Dictionary = {}
 for op in [ZorxStatMod.Op.ADD, ZorxStatMod.Op.MUL, ZorxStatMod.Op.SET]:
  for mod in mods:
   if mod.op != op:
    continue
   match op:
    ZorxStatMod.Op.ADD:
     result[mod.stat] = float(result.get(mod.stat, 0.0)) + mod.value
    ZorxStatMod.Op.MUL:
     if not result.has(mod.stat):
      return {"error": "MUL requires a base stat: " + mod.stat}
     result[mod.stat] = float(result[mod.stat]) * mod.value
    ZorxStatMod.Op.SET:
     if assigned.has(mod.stat) and not is_equal_approx(assigned[mod.stat], mod.value):
      return {"error": "Conflicting SET: " + mod.stat}
     assigned[mod.stat] = mod.value
     result[mod.stat] = mod.value
 for key in ["range","target_range"]:
  if result.has(key):result[key]*=float(result["range_mul"])
 result["player_passives"]=calc_player(tree,run)
 result["statuses"] = statuses
 result["events"] = events
 result["radius"] = float(result.get("radius", 1.0)) * sqrt(float(result.get("area_mul", 1.0)))
 result["origin"] = "target" if gems.any(func(g: ZorxGemData) -> bool: return g.behavior == "remote") else "self"
 result["skill_id"] = skill.id
 result["behavior"] = skill.behavior
 result["base_damage"] = float(skill.base_stats.get("damage",0.0))
 result["gem_ids"] = gems.map(func(g: ZorxGemData) -> String: return g.id)
 if skill.behavior == "parry" and "charge" in result["gem_ids"]:
  result["parry_window"] *= .7
 if skill.behavior == "wall" and "dense" in result["gem_ids"]:
  result["wall_hp"] *= 1.4
 return result


static func calc_player(tree: ZorxPassiveTreeData,run: ZorxRunState) -> Dictionary:
 var result: Dictionary={"hp_max_mul":1.0,"heal_allowed":1.0,"damage_taken_mul":1.0,"move_speed_mul":1.0,"dodge_cd_mul":1.0}
 if tree==null or run==null:return result
 for op in [ZorxStatMod.Op.ADD,ZorxStatMod.Op.MUL,ZorxStatMod.Op.SET]:
  for id in run.allocated:
   for mod in tree.by_id[id].mods:
    if not result.has(mod.stat) or mod.op!=op:continue
    if op==ZorxStatMod.Op.ADD:result[mod.stat]+=mod.value
    elif op==ZorxStatMod.Op.MUL:result[mod.stat]*=mod.value
    else:result[mod.stat]=mod.value
 return result
