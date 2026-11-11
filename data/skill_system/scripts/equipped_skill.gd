class_name ZorxEquippedSkill
extends Resource

@export var skill: ZorxSkillData
@export var shape_gem: ZorxGemData
@export var effect_gem: ZorxGemData

func equip(gem: ZorxGemData, slot: String) -> String:
 var error := ZorxBuildCalc.can_equip(skill, gem, slot)
 if not error.is_empty():
  return error
 if slot == "shape":
  shape_gem = gem
 else:
  effect_gem = gem
 return ""

func unequip(slot: String) -> void:
 if slot == "shape":
  shape_gem = null
 elif slot == "effect":
  effect_gem = null

func gems() -> Array[ZorxGemData]:
 var result: Array[ZorxGemData] = []
 if shape_gem != null:
  result.append(shape_gem)
 if effect_gem != null:
  result.append(effect_gem)
 return result

