extends SceneTree
const Fold=preload("res://client/skills/native_flipbook.gd")
var report: Array=[]
func _initialize():
 walk("res://art/skill_system")
 var file=FileAccess.open("res://build/skill-flipbook-report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
 for row in report:print("FOLD ",row)
 quit()
func walk(path: String):
 var directory=DirAccess.open(path)
 for name in directory.get_files():
  if name!="effect.glb":continue
  var source: String=path+"/"+name
  var packed: PackedScene=load(source)
  var node=packed.instantiate()
  var result: Dictionary=Fold.fold(node)
  result.path=source
  if result.groups>0:
   Fold.own(node,node)
   var output=PackedScene.new();var error=output.pack(node)
   if error==OK:error=ResourceSaver.save(output,path+"/runtime.scn")
   result.error=error
  if result.groups==0 and FileAccess.file_exists(path+"/runtime.scn"):DirAccess.remove_absolute(path+"/runtime.scn")
  if result.get("error",OK)!=OK:push_error("Failed native flipbook derivative: "+source);quit(1);return
  report.append(result);node.free()
 for name in directory.get_directories():walk(path+"/"+name)
