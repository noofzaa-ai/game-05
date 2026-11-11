class_name ZorxRunState
extends Resource

@export var weapon: ZorxWeaponData
@export var points: int = 0
@export var allocated: Array[String] = []
@export var skills: Array[ZorxEquippedSkill] = []

func start(w: ZorxWeaponData, tree: ZorxPassiveTreeData, start_points: int) -> String:
 if w == null or start_points < 0:
  return "Invalid start"
 var error := tree.build()
 if not error.is_empty():
  return error
 if not tree.by_id.has(w.start_node) or not tree.by_id[w.start_node].is_start:
  return "Invalid start node"
 weapon = w
 points = start_points
 allocated.assign([w.start_node])
 skills.clear()
 return ""

func allocate(tree: ZorxPassiveTreeData, node_id: String) -> String:
 var error := ZorxBuildCalc.can_allocate(tree, self, node_id)
 if error.is_empty():
  allocated.append(node_id)
  points -= 1
 return error

