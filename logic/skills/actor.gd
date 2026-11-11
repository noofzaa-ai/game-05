class_name ZorxSkillActor
extends RefCounted

var position := Vector3.ZERO
var base_max_hp := 100.0

signal died
signal attacked(amount: float, source: ZorxSkillTarget)
signal shield_broken(context: Dictionary)
signal parried(source: ZorxSkillTarget)
var max_hp: float = 100.0
var hp: float = 70.0
var shield: float = 0.0
var buffs: Array[Dictionary] = []
var parry_left: float = 0.0
var invulnerable: bool = false
var passive_stats: Dictionary = {}

func configure_passives(stats: Dictionary) -> void:
 passive_stats=stats
 max_hp=base_max_hp*float(stats.get("hp_max_mul",1))
 hp=minf(hp,max_hp)

func advance(delta: float) -> void:
 parry_left = maxf(0.0,parry_left-delta)
 for i in range(buffs.size()-1,-1,-1):
  var buff: Dictionary = buffs[i]
  var active := minf(delta,float(buff["left"]))
  buff["left"] -= delta
  if float(buff.get("regen",0.0))>0.0: heal(max_hp*float(buff["regen"])*active)
  if float(buff["left"])<=0.000001:
   if buff["id"]=="shield": shield=0.0
   buffs.remove_at(i)

func add_buff(id: String, duration: float, context: Dictionary) -> void:
 buffs = buffs.filter(func(b: Dictionary) -> bool: return b["id"]!=id)
 var buff := context.duplicate(true)
 buff["id"] = id
 buff["left"] = duration
 buffs.append(buff)

func multiplier(stat: String) -> float:
 var value := float(passive_stats.get(stat,1.0))
 for buff in buffs: value *= float(buff.get(stat,1.0))
 return value

func heal(amount: float) -> void:
 if hp>0 and float(passive_stats.get("heal_allowed",1))>0: hp = minf(max_hp,hp+maxf(amount,0))

func receive_attack(amount: float, source: ZorxSkillTarget = null, melee: bool = true) -> float:
 if hp<=0 or invulnerable: return 0.0
 if parry_left>0:
  parry_left=0.0
  parried.emit(source)
  return 0.0
 var incoming := maxf(0,amount)*multiplier("damage_taken_mul")
 for buff in buffs.duplicate():
  if melee and is_instance_valid(source) and not source.dead:
   if buff["id"]=="armor": source.apply_status("chill",{})
   if float(buff.get("thorns",0))>0: source.take_damage(incoming*float(buff["thorns"]),"reflect",{})
 var absorbed := minf(shield,incoming)
 shield -= absorbed
 var lost := minf(hp,incoming-absorbed)
 hp -= lost
 if absorbed>0 and shield<=0:
  for buff in buffs.duplicate():
   if buff["id"]=="shield":
    shield_broken.emit(buff)
  buffs = buffs.filter(func(b: Dictionary) -> bool: return b["id"]!="shield")
 if hp<=0: died.emit()
 attacked.emit(lost,source)
 return lost

func reset_combat() -> void:
 hp=70
 shield=0
 buffs.clear()
 invulnerable=false
 parry_left=0

