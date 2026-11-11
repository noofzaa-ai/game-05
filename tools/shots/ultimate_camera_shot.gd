extends SceneTree
## Renders the ultimates' own cameras the way the game plays them: a real map (its scenery and
## atmosphere), our chibi with the pack's own clip and effect, and the real camera rig driven tick by
## tick by client/ultimate_camera.gd from a stand-in Fighter casting the move (the simulation itself
## is not run; the move frame advances 1 per tick). Needs a window (run WITHOUT --headless):
##
##   godot --path . --script res://tools/shots/ultimate_camera_shot.gd -- <out_dir> [map_id]
##
## Writes <out_dir>/<weapon>_<skill>_<t>s.png (1024x576), the first frame of each at t=0 (the
## player's own angle, camera 8) for comparison.

const CameraRig := preload("res://client/camera_rig.gd")
const CharacterModel := preload("res://client/character_model.gd")
const Fighter := preload("res://logic/fighter.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const SkillVfx := preload("res://client/vfx/skill_vfx.gd")
const StageProps := preload("res://client/stage_props.gd")
const UltimateCamera := preload("res://client/ultimate_camera.gd")

const SIZE := Vector2i(1024, 576)
## weapon type -> [skill id, the moments to show]; the default packs and one blade slam (a blade
## pack with a camera of its own; the blade's default, the Inferno, has none).
const SHOTS := [
	["blade", "blade_earth_slam_ultimate", [0.0, 0.62, 1.2, 1.9]],
	["blade", "blade_inferno_ultimate", [1.91]],
	["dagger", "dagger_shadow_extraction_ultimate", [0.0, 0.3, 1.0, 1.5]],
	["spear", "spear_water_sky_throw_ultimate", [0.0, 0.9, 1.95, 2.45]],
	["hammer", "hammer_quake_leap_ultimate", [1.7]],
]

var _viewport: SubViewport
var _anchor: Node3D  ## where the caster stands (the rig follows it)
var _model: CharacterModel
var _rig: Node
var _camera: Node
var _effect: SkillVfx


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if not args.is_empty() else "user://shots"
	var map_id: String = args[1] if args.size() > 1 else "goblin_arena_a"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/ultimates.json"))
	var ultimates: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_build_scene(MapLoader.load_by_id(map_id))
	await process_frame  # (the rig makes its Camera3D when it is ready)
	for entry in SHOTS:
		await _render(out_dir, str(entry[0]), str(entry[1]), entry[2], ultimates)
	quit()


func _build_scene(map) -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var stage := Node3D.new()
	_viewport.add_child(stage)
	var atmosphere := Node3D.new()
	atmosphere.set_script(load("res://client/atmosphere.gd"))
	atmosphere.set("style", map.atmosphere)
	stage.add_child(atmosphere)
	StageProps.build(stage, map.props, map.atmosphere == "ink")
	for solid in map.solids:
		var box: AABB = solid["box"]
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = box.size
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.36, 0.40, 0.33)
		box_mesh.material = material
		mesh.mesh = box_mesh
		mesh.position = box.get_center()
		stage.add_child(mesh)
	_anchor = Node3D.new()
	_anchor.position = Vector3(map.spawn.x, 0.0, map.spawn.z - 2.0)
	stage.add_child(_anchor)
	_model = CharacterModel.new()
	_anchor.add_child(_model)
	_model.load_model()
	_rig = CameraRig.new()
	_rig.target = _anchor
	_rig.follow_depth = true
	_rig.min_x = -100.0
	_rig.max_x = 100.0
	_rig.min_z = -100.0
	_rig.max_z = 100.0
	stage.add_child(_rig)
	_rig.set_process(false)  # driven tick by tick below


## The caster faces right-and-toward-the-viewer (a three-quarter facing, as in a real fight).
func _render(out_dir: String, weapon_type: String, skill_id: String, times: Array, ultimates: Dictionary) -> void:
	var skill: Dictionary = ultimates["skills"][skill_id]
	var move_id := weapon_type + "_ultimate"
	SkillVfx.clear_cache()
	var pack := SkillVfx.pack_for(move_id)
	if pack.get("id", "") != skill_id:  # show a pack that is not the weapon's default
		pack = pack.duplicate()
		pack["id"] = skill_id
		pack["folder"] = str(skill["folder"])
		pack["animation"] = str(skill.get("animation", ""))
		pack["duration_s"] = float(skill["duration_s"])
		pack["vfx_end_s"] = float(skill.get("vfx_end_s", skill["duration_s"]))
		pack["events"] = skill["events"]
		pack["throw"] = skill.get("throw", {})
		pack["camera"] = skill["camera"]
		SkillVfx._packs[move_id] = pack
	_model.set_weapon(weapon_type)
	if _camera != null:
		_camera.queue_free()
	_camera = UltimateCamera.new()
	_camera.rig = _rig
	_rig.add_sibling(_camera)
	var fighter := Fighter.new()
	fighter.hp = 100.0
	fighter.state = Fighter.State.ATTACK
	fighter.move_id = move_id
	fighter.direction = Vector2i(1, 1)
	var facing := Vector2(1.0, 1.0).normalized()
	_model.set_pose("idle", 0.0, 0.0, true, facing, false, "", "", weapon_type)
	if _effect != null:
		_effect.queue_free()
	_effect = SkillVfx.new()
	_anchor.get_parent().add_child(_effect)
	_effect.setup(pack, _anchor.position, facing, _model.model_scale())
	for i in 120:
		_model.apply_pose(1.0 / 60.0)  # turn to the facing
		_rig._process(1.0 / 60.0)  # settle on the player's angle (camera 8)
	var motion := SkillVfx.motion_for(pack)
	var frame := 0
	var wanted := times.duplicate()
	while not wanted.is_empty():
		var t := frame / 60.0
		fighter.move_frame = float(frame)
		if not motion.is_empty():
			_model.show_skill_clip(motion["set"], motion["clip"], t)
		_model.apply_pose(1.0 / 60.0)
		_effect.show_at(t)
		var hips := _hips()
		_camera.update(fighter, _anchor.position, hips)
		_rig._process(1.0 / 60.0)
		if t + 0.0001 >= float(wanted[0]):
			var img := await _grab()
			var path := out_dir.path_join("%s_%s_%.2fs.png" % [weapon_type, skill_id.replace("_ultimate", ""), t])
			img.save_png(path)
			print("saved %s  (override: %s)" % [path, _rig.has_override()])
			wanted.pop_front()
		frame += 1
	fighter.state = Fighter.State.IDLE
	_camera.update(fighter, _anchor.position, _hips())
	_model.clear_skill_clip()


func _hips() -> Vector3:
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return _anchor.position + Vector3(0.0, 0.85, 0.0)
	var skeleton: Skeleton3D = found[0]
	var bone := skeleton.find_bone("Hips")
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin if bone >= 0 else _anchor.position + Vector3(0.0, 0.85, 0.0)


func _grab() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()
