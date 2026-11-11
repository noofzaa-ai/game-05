class_name ZorxSkillBuildTransfer
extends RefCounted
## ID-only Studio handoff. Never load paths supplied in imported JSON.
const SCHEMA="skill-lab-build/1"
const WEAPONS={"katana":"fast","dagger":"fast","hammer":"heavy","spear":"mid","bow":"ranged","staff":"ranged"}
static func decode(input: Variant,tree: ZorxPassiveTreeData) -> Dictionary:
 var d: Variant=JSON.parse_string(input) if input is String else input
 if not d is Dictionary or d.get("schema")!=SCHEMA:return {"error":"Unsupported build schema"}
 if not WEAPONS.has(d.get("weapon")):return {"error":"Unknown weapon"}
 if not d.get("allocated") is Array or d.allocated.is_empty() or d.allocated.size()>13 or d.allocated[0]!="start_"+d.weapon:return {"error":"Invalid tree start/points"}
 if not d.get("skills") is Array or d.skills.size()!=4:return {"error":"Four skill slots required"}
 var active: Variant=d.get("active_slot")
 if not (active is float or active is int) or not is_finite(float(active)) or active!=floor(float(active)) or active<0 or active>3:return {"error":"Invalid active slot"}
 var weapon:=ZorxWeaponData.new();weapon.id=d.weapon;weapon.start_node="start_"+d.weapon;weapon.pattern=WEAPONS[d.weapon]
 var run:=ZorxRunState.new();var error:=run.start(weapon,tree,12)
 if not error.is_empty():return {"error":error}
 for id in d.allocated.slice(1):
  if not id is String:return {"error":"Invalid node ID"}
  error=run.allocate(tree,id)
  if not error.is_empty():return {"error":"Tree "+id+": "+error}
 var owned: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_system/catalog.json"))
 var used: Array=[]
 for row in d.skills:
  if not row is Dictionary or not row.get("skill") in owned or row.get("skill") in used:return {"error":"Unknown/duplicate skill"}
  var eq:=ZorxEquippedSkill.new();eq.skill=load("res://data/skill_system/skills/"+row.skill+".tres");used.append(row.skill)
  for slot in ["shape","effect"]:
   if not row.get(slot) is String:return {"error":"Invalid Gem ID"}
   var id: String=row[slot]
   if id.is_empty():continue
   # Strict catalog lookup prevents arbitrary Resource path injection.
   var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_system/studio_catalog.json"))
   if not catalog.gems.any(func(g: Dictionary)->bool:return g.id==id):return {"error":"Unknown Gem"}
   error=eq.equip(load("res://data/skill_system/gems/"+id+".tres"),slot)
   if not error.is_empty():return {"error":error}
  run.skills.append(eq)
 return {"run":run,"active_slot":int(active),"error":""}
static func encode(run: ZorxRunState,active_slot: int=0) -> Dictionary:
 var skills: Array=[]
 for eq in run.skills:skills.append({"skill":eq.skill.id,"shape":eq.shape_gem.id if eq.shape_gem else "","effect":eq.effect_gem.id if eq.effect_gem else ""})
 return {"schema":SCHEMA,"version":"3.1","weapon":run.weapon.id,"allocated":run.allocated.duplicate(),"skills":skills,"active_slot":active_slot}
