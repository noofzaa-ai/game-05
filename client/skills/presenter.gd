extends Node3D
## Authoritative presentation only. No damage, targeting, stamina or cooldown decisions.
const ROOT := "res://art/skill_system/"
@export var legacy_visuals: bool=false
var _active: Dictionary = {}
var _allowed: Array = []
var _scenes: Dictionary={}
var _pool: Dictionary={}
var _idle_count:=0
var _status_sync_pending:=false
static var pool_created: int=0
static var pool_reused: int=0

func _ready() -> void:
 _allowed=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_system/catalog.json"))

func _scene(id: String):
 if not id in _allowed:return null
 if not _scenes.has(id):
  var path:=ROOT+"skills/"+id+".tscn"
  _scenes[id]=load(path) if ResourceLoader.exists(path) else null
 return _scenes[id]

func _status_scene(status: String):
 var key: String="status:"+status
 if _scenes.has(key):return _scenes[key]
 if status in ["burn","bleed","freeze","chill","shock","stun"]:
  var node=preload("res://client/skills/status_effect.gd").new();node.status=status
  var packed:=PackedScene.new();packed.pack(node);node.free();_scenes[key]=packed
  return packed
 var path: String=ROOT+(status+"/effect.tscn" if status in ["burn","bleed"] else "skills/status_"+status+".tscn")
 if not ResourceLoader.exists(path):return null
 if status in ["burn","bleed"]:
  var node=preload("res://client/skills/mcp_skill_visual.gd").new();node.asset_path=path;node.preserve_materials=true
  var packed:=PackedScene.new();packed.pack(node);node.free();_scenes[key]=packed
 else:_scenes[key]=load(path)
 return _scenes[key]

func _acquire(key: String, scene: PackedScene) -> Node3D:
 var idle: Array=_pool.get(key,[])
 while not idle.is_empty():
  var cached=idle.pop_back();_idle_count-=1
  if not is_instance_valid(cached):continue
  cached.set_meta("pool_idle",false);cached.show();cached.set_process(true);cached.scale=Vector3.ONE;cached.rotation=Vector3.ZERO
  pool_reused+=1
  return cached
 pool_created+=1
 var fx: Node3D=scene.instantiate();
 if fx.get("use_folded_frames")!=null:fx.set("use_folded_frames",not legacy_visuals)
 fx.set("autoplay",false);fx.set_meta("pool_key",key);add_child(fx)
 if fx.has_signal("finished"):fx.connect("finished",_recycle.bind(fx))
 return fx

func _recycle(fx: Node3D) -> void:
 if not is_instance_valid(fx) or fx.get_meta("pool_idle",false):return
 if fx.has_method("stop_effect"):fx.call("stop_effect")
 var key: String=fx.get_meta("pool_key","")
 if not _pool.has(key):_pool[key]=[]
 if _pool[key].size()>=2 or _idle_count>=12:fx.queue_free();return
 fx.hide();fx.set_process(false);fx.set_meta("pool_idle",true);_pool[key].append(fx);_idle_count+=1

func warm_build(build: Dictionary,origin: Vector3) -> void:
 preload("res://client/animation_set.gd").load_file("res://art/skill_system/motions/skill_lab_casts.glb")
 if not preload("res://client/graphics_options.gd").enabled("combat_vfx"):return
 var jobs: Array=[]
 var seen: Dictionary={}
 for row in build.get("skills",[]):
  var id: String=row.get("skill","")
  if seen.has(id):continue
  seen[id]=true
  var scene=_scene(id)
  if scene==null:continue
  var sample: Node=scene.instantiate()
  var phases: Array=["impact"]
  if sample.get("projectile_path")!=null and not str(sample.get("projectile_path")).is_empty():phases.append("projectile")
  if sample.get("beam_path")!=null and not str(sample.get("beam_path")).is_empty():phases.append("beam")
  for phase in phases:jobs.append({"key":id+":"+phase,"scene":scene,"phase":phase})
  sample.free()
 for status in ["burn","bleed","freeze","chill","shock","stun"]:
  var scene=_status_scene(status)
  if scene!=null:jobs.append({"key":"status:"+status,"scene":scene,"phase":"persistent"})
 for job in jobs:
  var fx:=_acquire(job.key,job.scene)
  fx.set("effect_phase",job.phase);fx.set("loop_effect",false);fx.set("free_on_finish",false);fx.position=origin+Vector3.UP*.2;fx.scale=Vector3.ONE*.001;fx.set_meta("prewarm",true);fx.call("play_effect");fx.set_meta("prewarm",false)
  for fraction in [.2,.65]:
   if fx.has_method("_sample"):fx.set("elapsed",float(fx.get("duration"))*fraction);fx.call("_sample")
   await get_tree().process_frame
   if not is_inside_tree():return
  _recycle(fx)

func event(data: Dictionary) -> void:
 if not preload("res://client/graphics_options.gd").enabled("combat_vfx"):return
 if not data.get("kind","") in ["burst","beam"]:return
 var scene=_scene(str(data.get("skill","")))
 if scene==null:return
 var phase: String="beam" if data.kind=="beam" else "impact"
 var fx: Node3D=_acquire(str(data.skill)+":"+phase,scene)
 fx.set("autoplay",false);fx.set("loop_effect",false);fx.set("free_on_finish",true);fx.set("effect_phase",phase)
 if data.kind=="beam":
  fx.set("effect_phase","beam");fx.set("endpoint",data.end-data.position)
 fx.position=data.position+Vector3.UP*.025
 if data.has("radius"):
  var skill: ZorxSkillData=load("res://data/skill_system/skills/"+data.skill+".tres")
  var factor:=float(data.radius)/maxf(.001,skill.authored_radius_m);fx.scale=Vector3(factor,1,factor)
 fx.call("play_effect")

func update_from(fighters: Dictionary,bodies: Dictionary,views: Dictionary={}) -> void:
 if views.is_empty() and get_parent()!=null and get_parent().get("_views") is Dictionary:
  views=get_parent().get("_views")
  # Older deployed stages update the presenter before moving their rendered views.
  # Refresh anchors after that frame's view placement without changing simulation code.
  if not _status_sync_pending:
   _status_sync_pending=true;_sync_status_views.call_deferred(views)
 var wanted: Dictionary={}
 if preload("res://client/graphics_options.gd").enabled("combat_vfx"):
  for id in fighters:
   var view: Dictionary=fighters[id].skill_view
   for data in view.get("visuals",[]):
    var key:=str(id)+":"+str(data.id)
    wanted[key]=true
    var fx: Node3D=_active.get(key)
    if not is_instance_valid(fx):
     var scene=_scene(data.skill)
     if scene==null:continue
     fx=_acquire(str(data.skill)+":"+("impact" if str(data.phase)=="persistent" else str(data.phase)),scene);fx.set("autoplay",false);fx.set("loop_effect",true);fx.set("free_on_finish",false);fx.set("effect_phase",data.phase)
     fx.call("play_effect");_active[key]=fx
    fx.position=data.position;fx.scale=data.scale
    if data.direction.length_squared()>.00001:fx.rotation.y=atan2(data.direction.x,data.direction.z)
   for status in view.get("statuses",{}):
    var status_scene=_status_scene(status)
    if status_scene==null or not bodies.has(id):continue
    var key:=str(id)+":status:"+str(status);wanted[key]=true
    var fx: Node3D=_active.get(key)
    if not is_instance_valid(fx):
     fx=_acquire("status:"+str(status),status_scene);fx.set("autoplay",false);fx.set("loop_effect",true);fx.set("free_on_finish",false);_active[key]=fx
     if fx.has_method("fit_body"):fx.call("fit_body",bodies[id].height,.8)
     fx.call("play_effect")
    var visual=views.get(id)
    if is_instance_valid(visual) and fx.has_method("fit_body"):
     var dimensions: Vector3=_status_dimensions(visual)*visual.scale.abs()
     fx.call("fit_body",dimensions.y,maxf(dimensions.x,dimensions.z))
    fx.position=visual.position if is_instance_valid(visual) else bodies[id].position
 for key in _active.keys():
  if not wanted.has(key):
   if is_instance_valid(_active[key]):_recycle(_active[key])
   _active.erase(key)

func _status_dimensions(visual: Node3D)->Vector3:
 if visual.has_meta("status_vfx_size"):return visual.get_meta("status_vfx_size")
 var dimensions:=Vector3(.8,1.35,.8)
 if not str(visual.get("monster_model_path")).is_empty():
  var turn=visual.get("_turn")
  var bounds:=AABB();var first:=true
  if is_instance_valid(turn):
   for mesh in turn.find_children("*","MeshInstance3D",true,false):
    if mesh.name=="InkOutline":continue
    var relative: Transform3D=visual.global_transform.affine_inverse()*mesh.global_transform
    var box: AABB=relative*mesh.get_aabb()
    bounds=box if first else bounds.merge(box);first=false
  if not first:dimensions=bounds.size
  dimensions.y=float(visual.get("monster_model_height"))
 visual.set_meta("status_vfx_size",dimensions)
 return dimensions

func _sync_status_views(views: Dictionary)->void:
 _status_sync_pending=false
 if not is_inside_tree():return
 for key in _active:
  if ":status:" not in str(key):continue
  var id:=int(str(key).get_slice(":",0))
  var visual=views.get(id)
  if is_instance_valid(visual):_active[key].position=visual.position
