extends SceneTree
## Renders the imported ultimate skill packs (art/skills/, 30 of them) the way the game shows them:
## the pack's OWN character clip on our chibi rig and its vfx.glb frozen at the cast origin, facing
## +x (right). A translucent red bar on the ground is the logic's forward hit box (combat_data), so
## the picture and the rules can be compared. Needs a window (run WITHOUT --headless):
##
##   godot --path . --script res://tools/shots/ultimate_shot.gd -- <out_dir>
##   godot --path . --script res://tools/shots/ultimate_shot.gd -- <out_dir> --all
##
## Default: each weapon type's DEFAULT ultimate (data/combat/ultimates.json) in 3 frames
##   <weapon>_<skill>_1_windup / _2_hit / _3_fade  -> <out_dir>/<weapon>/
## --all: every one of the 30 packs at its hit time, saved as <skill>_hit.png, then stitched into
##   one contact sheet contact_sheet_all30.png.

const CharacterModel := preload("res://client/character_model.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")
const SkillVfx := preload("res://client/vfx/skill_vfx.gd")

const WEAPON_TYPES := ["blade", "dagger", "spear", "hammer"]
const SIZE := Vector2i(900, 600)
const CELL := Vector2i(300, 200)  ## one tile of the contact sheet
const COLS := 5  ## 30 packs -> 6 rows of 5

var _rules
var _combat
var _ultimates: Dictionary = {}
var _viewport: SubViewport
var _box: MeshInstance3D
var _model: CharacterModel
var _effect: SkillVfx
var _loaded_weapon := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if not args.is_empty() else "user://shots"
	var all := args.has("--all")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_rules = ItemRulesLoader.load_default()
	_combat = CombatDataLoader.load_default()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/ultimates.json"))
	_ultimates = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_build_scene()
	if all:
		await _render_all(out_dir)
	else:
		await _render_defaults(out_dir)
	quit()


func _build_scene() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_viewport.add_child(light)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.17, 0.19, 0.23)
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	environment.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = environment
	_viewport.add_child(we)
	var camera := Camera3D.new()
	camera.fov = 48.0
	# Centred on the forward corridor (~1.7 m ahead) and pulled back/up so a sky-throw's apex and a
	# wide burst are not clipped; the whole 2-body-length lane stays in frame for every pack.
	camera.position = Vector3(1.7, 7.6, 9.2)
	camera.rotation_degrees = Vector3(-39.0, 0.0, 0.0)
	_viewport.add_child(camera)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(24, 24)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.24, 0.27)
	floor.material_override = floor_mat
	_viewport.add_child(floor)
	_box = MeshInstance3D.new()
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.33)
	box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box.material_override = box_mat
	_viewport.add_child(_box)
	_model = CharacterModel.new()
	_viewport.add_child(_model)
	_model.load_model()


## Equips a weapon-type stand-in on the model (once per type) and points the red bar at that
## weapon's ultimate hit box.
func _dress(weapon_type: String) -> void:
	if _loaded_weapon != weapon_type:
		_loaded_weapon = weapon_type
		var loadout := Loadout.new(_rules)
		loadout.equip(ItemSystem.create_item(_rules, weapon_type + "_01", "weapon", 0, RandomNumberGenerator.new(), "", weapon_type + "_01"))
		_model.dress(ItemAssets.looks(loadout, _rules.catalog, weapon_type))
	var move: Dictionary = _combat.moves[weapon_type + "_ultimate"]
	var plane := BoxMesh.new()
	plane.size = Vector3(maxf(0.05, move["hit_size"].x), 0.02, move["hit_size"].z)
	_box.mesh = plane
	_box.position = Vector3(move["hit_offset"].x, 0.01, 0.0)


## Poses the model with a pack's own motion clip and places its effect, both at `time` seconds.
func _pose_pack(pack: Dictionary, time: float) -> void:
	if _effect != null:
		_effect.queue_free()
		_effect = null
	_effect = SkillVfx.new()
	_viewport.add_child(_effect)
	_effect.setup(pack, Vector3.ZERO, Vector2(1.0, 0.0), _model.model_scale())
	var motion := SkillVfx.motion_for(pack)
	# The skill clip wins over any code pose and is applied last, so re-assert it after each
	# apply_pose settles the rig (as fighter_view does on its tick).
	for i in 20:
		if motion.is_empty():
			_model.set_pose("heavy", 1.0, 0.0, true, Vector2(1.0, 0.0), false, "strike", "ultimate", _loaded_weapon)
		else:
			_model.show_skill_clip(motion["set"], motion["clip"], time)
		_model.apply_pose(1.0 / 60.0)
	_effect.show_at(time)


func _grab() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


## The three moments to show a pack at: half of the first hit (wind-up), the climax (its last hit
## event = full-range burst), and near the end of the effect (fade).
func _phases(skill: Dictionary) -> Array:
	var events: Array = skill.get("events", [])
	var first := float(events[0]["time_s"]) if not events.is_empty() else 0.3
	var last := float(events[events.size() - 1]["time_s"]) if not events.is_empty() else first
	var fade := minf(float(skill.get("vfx_end_s", skill.get("duration_s", last))), float(skill.get("duration_s", last))) * 0.92
	return [["1_windup", first * 0.5], ["2_hit", last], ["3_fade", maxf(fade, last + 0.1)]]


func _render_defaults(out_dir: String) -> void:
	for weapon_type in WEAPON_TYPES:
		var skill_id := str(_combat.weapons[weapon_type].get("ultimate_skill", ""))
		var skill: Dictionary = _ultimates.get("skills", {}).get(skill_id, {})
		var pack := SkillVfx.pack_for(weapon_type + "_ultimate")
		if skill.is_empty() or pack.is_empty():
			push_warning("no pack for %s" % weapon_type)
			continue
		_dress(weapon_type)
		var dir := out_dir.path_join(weapon_type)
		DirAccess.make_dir_recursive_absolute(dir)
		for phase in _phases(skill):
			_pose_pack(pack, float(phase[1]))
			var img := await _grab()
			img.save_png(dir.path_join("%s_%s.png" % [skill_id, phase[0]]))
			print("saved %s %s @ %.2fs" % [weapon_type, phase[0], phase[1]])


func _render_all(out_dir: String) -> void:
	var ids: Array = _ultimates.get("skills", {}).keys()
	ids.sort()
	var tiles: Array[Image] = []
	for id in ids:
		var skill: Dictionary = _ultimates["skills"][id]
		_dress(str(skill["weapon_type"]))
		var pack := {
			"id": id, "folder": str(skill["folder"]), "animation": str(skill.get("animation", "")),
			"duration_s": float(skill.get("duration_s", 0.0)), "vfx_end_s": float(skill.get("vfx_end_s", 0.0)),
			"events": skill.get("events", []), "throw": skill.get("throw", {}),
		}
		var events: Array = skill.get("events", [])
		var hit := float(events[events.size() - 1]["time_s"]) if not events.is_empty() else float(skill.get("duration_s", 1.0)) * 0.5
		_pose_pack(pack, hit)
		var img := await _grab()
		img.save_png(out_dir.path_join("%s_hit.png" % id))
		var tile := img.duplicate()
		tile.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_label(tile, id)
		tiles.append(tile)
		print("saved %s @ %.2fs" % [id, hit])
	var rows := int(ceil(float(tiles.size()) / float(COLS)))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.11))
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % COLS) * CELL.x, (i / COLS) * CELL.y))
	sheet.save_png(out_dir.path_join("contact_sheet_all30.png"))
	print("contact sheet: %d packs -> %s" % [tiles.size(), out_dir.path_join("contact_sheet_all30.png")])


## Burns the pack id into the top-left of a tile (a few blocky glyphs; just enough to tell them apart).
func _label(img: Image, text: String) -> void:
	var short := text.replace("_ultimate", "")
	var bar := Image.create(img.get_width(), 16, false, Image.FORMAT_RGBA8)
	bar.fill(Color(0, 0, 0, 0.55))
	img.blend_rect(bar, Rect2i(Vector2i.ZERO, bar.get_size()), Vector2i.ZERO)
	# A tiny 3x5 pixel font would be a lot of code; the file name carries the exact id, and the row/
	# column order matches the sorted id list printed to the console, so the sheet stays legible.
	var tag := Image.create(mini(img.get_width(), short.length() * 4 + 2), 7, false, Image.FORMAT_RGBA8)
	tag.fill(Color(1, 1, 1, 0.9))
	img.blit_rect(tag, Rect2i(Vector2i.ZERO, tag.get_size()), Vector2i(2, 4))
