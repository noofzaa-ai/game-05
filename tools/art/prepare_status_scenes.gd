extends SceneTree
const Fold=preload("res://client/skills/native_flipbook.gd")
func _initialize()->void:
 for status in ["burn","bleed","freeze","chill","shock","stun"]:
  var path: String="res://art/skill_system/status_vfx/"+status
  var node: Node=load(path+"/effect.glb").instantiate()
  var report:=Fold.fold(node)
  Fold.own(node,node)
  var packed:=PackedScene.new()
  assert(packed.pack(node)==OK)
  assert(ResourceSaver.save(packed,path+"/runtime.scn")==OK)
  print(status," ",report)
  node.free()
 quit()
