extends "res://client/hub_skill_baseline.gd"
## Add only the training sandbox to the exact shipped hub; preserve every existing panel flow.
var _training
var _training_view:Node3D
func _ready()->void:
 super._ready()
 _training_view=preload("res://client/training_arena.gd").new();add_child(_training_view)
 _training_view.setup(_training,_training_looks())
func _exit_tree()->void:
 if _training!=null:_training.dispose()
func _build_menu()->void:
 super._build_menu()
 preload("res://client/skill_menu_icon.gd").apply(_skill_button)
func _build_camera()->void:
 super._build_camera()
 _rig.min_x=-25
func refresh_character()->void:
 super.refresh_character()
 if is_instance_valid(_rig):_rig.min_x=-25
 if _training==null or not GameState.ensure_profile():return
 _training.configure(preload("res://logic/stats.gd").totals(GameState.item_rules,GameState.profile.loadout.items()),_style,GameState.profile.skill_build)
 if is_instance_valid(_training_view):_training_view.refresh(_training_looks())
func _update_near()->void:
 if _training!=null and _training.enabled:
  _near={}
  if _prompt!=null:_prompt.hide()
  return
 super._update_near()

func training_combat_active()->bool:
 return _training!=null and _training.enabled and can_walk()

func _training_looks()->Dictionary:
 var looks:=ItemAssets.looks(GameState.profile.loadout,GameState.item_rules.catalog,_style)
 looks["appearance"]=ItemAssets.appearance(GameState.profile.appearance)
 return looks

func _aim_training(input)->void:
 var origin:Vector3=player_position()
 var camera:=get_viewport().get_camera_3d()
 var mobile:bool=is_instance_valid(GameState.mobile_controls) and GameState.mobile_controls.enabled
 if not mobile and camera!=null and get_viewport().gui_get_hovered_control()==null:
  var mouse:=get_viewport().get_mouse_position()
  var point=Plane(Vector3.UP,origin.y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
  if point is Vector3:
   var delta:=Vector2(point.x-origin.x,point.z-origin.z)
   input.aim=delta.normalized();input.aim_distance=minf(25.5,delta.length());return
 var nearest:=INF
 for id in preload("res://logic/training_ground.gd").DUMMY_IDS:
  var delta:Vector3=_sim.bodies[id].position-origin
  if delta.length()<nearest:
   nearest=delta.length();input.aim=Vector2(delta.x,delta.z).normalized();input.aim_distance=nearest


## Moves the player (tests and screenshots).

func _build_simulation() -> void:
 var sim_world := SimWorld.new()
 sim_world.half_width = world.half_extents.x
 sim_world.half_depth = world.half_extents.y
 sim_world.add_solid(AABB(Vector3(-60.0, -1.0, -60.0), Vector3(120.0, 1.0, 120.0)))  # the ground
 for box in world.farm_boundaries(): sim_world.add_solid(box)
 for box in world.solids:
  sim_world.add_solid(box)
 _sim = GameSim.new(sim_world)
 _combat=CombatDataLoader.load_default()
 _training=preload("res://logic/training_ground.gd").new(sim_world,_combat,world.spot("spawn",Vector3(0,0,3.6)))
 _sim=_training.sim
 _sim.bodies[PLAYER_ID].grounded = true


## The player's own character, wearing their gear and looks (refresh_character()).

func _physics_process(_delta: float) -> void:
 var input := SimInput.new()
 if can_walk():
  var read: SimInput = InputReader.read(get_viewport())
  input.move = _touch.vector if _touch != null and _touch.vector != Vector2.ZERO else read.move
  if _rig.has_method("movement_from_screen"):input.move = _rig.movement_from_screen(input.move)
  input.run = read.run
  if _training.enabled:
   input=read
   if _rig.has_method("movement_from_screen"):input.move=_rig.movement_from_screen(read.move)
   _aim_training(input)
 elif _touch != null:
  _touch.release()
 _training.step(input)
 if _touch!=null:
  _touch.enabled=not _training.enabled
  if _training.enabled:_touch.release()
 if is_instance_valid(_training_view):
  _training_view.update()
  _character.visible=not _training.enabled
  _rig.target=_training_view.player if _training.enabled else _character
  _shortcut_root.visible=not _training.enabled
 _show_player()
 _update_near()
 _check_gate()


## The player may walk: no menu or screen is open.
