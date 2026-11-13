extends SceneTree
## Race starter outfits on the Studio body (docs/art/race_gear_handoff.md): every race x class, through the real
## renderer (client/card_portrait.gd hub framing + client/characters/studio05_character_model.gd), front and back;
## a battle 3/4 view (party camera angle) standing and mid-run; two mixed-race bodies; and 192x192 piece icons
## rendered from the meshes. Run windowed (needs a GPU):
##   godot --path . --script res://tools/shots/race_outfit_shots.gd
## Output: build/race_outfits/ (PNG per shot; contact sheets are put together by tools/shots/race_outfit_sheet.py).
## ZORX_ICONS=1 also writes the icons to art/armor/race_shared/icon-<race>_<slot>.png.

const Portrait := preload("res://client/card_portrait.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const SLOTS := ["shirt", "pants", "armband", "shoes"]
const OUT := "res://build/race_outfits/"


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(vp: SubViewport, name: String) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await _frames(3)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + name)
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _outfit(race_by_slot: Dictionary) -> Dictionary:
	var looks := {}
	for slot in SLOTS:
		looks[slot] = "res://art/armor/race_shared/%s_%s.glb" % [race_by_slot[slot], slot]
	return looks


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if OS.get_environment("ZORX_POKE") == "1":
		await _poke()
	elif OS.get_environment("ZORX_ONLY") == "weapons":
		await _weapon_shots()
		await _icons()
	else:
		await _weapon_shots()
		await _portraits()
		await _battle()
		await _icons()
	print("RACE_OUTFIT_SHOTS DONE")
	quit()


## Hub card portrait (the real CardPortrait, "hub" framing, ink outline on), front and back, 4 races x 4 classes,
## plus the class suit (no race armour) as the reference and two mixed-race bodies.
func _portraits() -> void:
	var holder := Control.new()
	root.add_child(holder)
	var portrait: Control = Portrait.new()
	portrait.size = Vector2(300, 450)
	holder.add_child(portrait)
	await _frames(2)
	portrait.viewport.size = Vector2i(300, 450)
	portrait.set_framing("hub")
	portrait.set_render_mode(Portrait.Mode.ONCE)
	var mixes := {
		"mix_viking_elf": {"shirt": "viking", "pants": "elf", "armband": "viking", "shoes": "elf"},
		"mix_human_runeborn": {"shirt": "runeborn", "pants": "human", "armband": "human", "shoes": "runeborn"},
	}
	for cls in CLASSES:
		portrait.set_class(cls)
		await _frames(2)
		var looks_list := {"suit": {}}
		for race in RACES:
			looks_list[race] = _outfit({"shirt": race, "pants": race, "armband": race, "shoes": race})
		for mix in mixes:
			looks_list[mix] = _outfit(mixes[mix])
		for key in looks_list:
			var looks: Dictionary = looks_list[key].duplicate()
			if key == "suit":
				for slot in SLOTS:
					looks[slot] = ""
			portrait.model.dress(looks)
			portrait._fit_camera()
			for side in ["front", "back"]:
				portrait._pivot.rotation.y = 0.0 if side == "front" else PI
				portrait._turn = portrait._pivot.rotation.y
				portrait._turn_target = portrait._turn
				portrait.model.apply_pose(0.0)
				await _save(portrait.viewport, "card_%s_%s_%s.png" % [cls, key, side])
	holder.queue_free()
	await _frames(2)


func _stage(size: Vector2i) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = CardTokens.PORTRAIT_AMBIENT
	env.ambient_light_energy = CardTokens.PORTRAIT_AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	CharacterLight.light_scene(vp, env, CardTokens.PORTRAIT_KEY_ENERGY, CardTokens.PORTRAIT_RIM_ENERGY)
	var cam := Camera3D.new()
	vp.add_child(cam)
	return {"vp": vp, "cam": cam, "env": env}


## Battle 3/4 view: the party camera's angle (offset (0, 3, 7) at fov 45, client/party_camera.gd) brought closer,
## the body turned 35 degrees; standing idle and mid-run, front and back.
func _battle() -> void:
	var stage := _stage(Vector2i(360, 480))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	cam.fov = 45.0
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	for cls in CLASSES:
		model.dress({"class": cls, "weapon": {"path": "", "family": str(CardDeck.class_data(cls).get("weapon", "")), "style": str(CardDeck.class_data(cls).get("weapon", ""))}})
		for race in ["suit"] + RACES:
			var looks := {}
			if race == "suit":
				for slot in SLOTS:
					looks[slot] = ""
			else:
				looks = _outfit({"shirt": race, "pants": race, "armband": race, "shoes": race})
			model.dress(looks)
			for pose in ["idle", "run"]:
				for side in ["front", "back"]:
					model.rotation.y = deg_to_rad(35.0) + (PI if side == "back" else 0.0)
					cam.position = Vector3(0.0, 1.35, 2.35)
					cam.look_at(Vector3(0.0, 0.68, 0.0))
					model.set_pose(pose, 1.0 if pose == "run" else 0.0, 4.0 if pose == "run" else 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
					for i in 3:
						model.apply_pose(0.11)
					await _save(vp, "battle_%s_%s_%s_%s.png" % [cls, race, pose, side])
	vp.queue_free()
	await _frames(2)


## Icons: each race piece alone (body, head, hair, class gear hidden) in the bind pose, ONE fixed camera and light per
## piece type for every race (so a slot looks the same across races): armour front 3/4, the sword from above (its
## full length), the shield from its outer face 3/4. 1024 transparent frames; tools/shots/race_outfit_sheet.py crops,
## lays the sword diagonal, adds the rim and makes the 96x96 icons.
const ICON_VIEWS := {  # skeleton space (+Z = the body's front, +X = its left): [view direction, up]
	"armour": [Vector3(-0.42, 0.21, 0.88), Vector3.UP],
	"sword": [Vector3(0.0, 1.0, 0.25), Vector3(0.0, 0.0, -1.0)],
	"shield": [Vector3(0.92, 0.18, 0.36), Vector3.UP],
}


func _icons() -> void:
	var stage := _stage(Vector2i(1024, 1024))
	var vp: SubViewport = stage["vp"]
	vp.transparent_bg = true
	(stage["env"] as Environment).background_mode = Environment.BG_CLEAR_COLOR
	var cam: Camera3D = stage["cam"]
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	model.dress({"class": "sword_shield", "weapon": {"path": "", "family": "", "style": ""}})
	var jobs := []
	for race in RACES:
		for slot in SLOTS:
			jobs.append([race, slot, "armour", "res://art/armor/race_shared/%s_%s.glb" % [race, slot]])
		jobs.append([race, "sword", "sword", "res://art/weapons/race_%s/sword_shield.glb" % race])
		jobs.append([race, "shield", "shield", "res://art/weapons/race_%s/shield.glb" % race])
	for job in jobs:
		var looks := {"offhand": {}, "weapon": {"path": "", "family": "", "style": ""}}
		for s in SLOTS:
			looks[s] = ""
		match job[2]:
			"armour":
				looks[job[1]] = job[3]
			"sword":
				looks["weapon"] = {"path": job[3], "family": "blade", "style": "blade"}
			"shield":
				looks["offhand"] = {"item_id": "icon", "asset_id": "", "procedural": false, "path": job[3], "refine_level": 0}
		model.dress(looks)
		model._skeleton.reset_bone_poses()  # bind pose: the piece as authored
		var piece_meshes: Array = []
		match job[2]:
			"armour":
				piece_meshes = model._worn.get(job[1], {}).get("meshes", [])
			"sword":
				piece_meshes = model._race_weapon_meshes
			"shield":
				piece_meshes = model._race_shield_meshes
		for mesh in model._skeleton.find_children("*", "MeshInstance3D", true, false):
			var keep := false
			for piece in piece_meshes:
				keep = keep or mesh == piece or piece.is_ancestor_of(mesh)
			mesh.visible = keep
		if piece_meshes.is_empty():
			push_warning("icon: nothing to draw for %s" % [job])
			continue
		# Two passes: a wide view of the whole body finds the piece on screen (skinned meshes: their AABB is not the
		# drawn shape), then the camera closes in on it. Same view direction for every race of a piece type.
		var basis: Basis = model._skeleton.global_transform.basis.orthonormalized()
		var view: Array = ICON_VIEWS[job[2]]
		var center: Vector3 = model._skeleton.global_position + Vector3(0.0, 0.68, 0.0)
		cam.size = 2.4
		for attempt in 2:
			cam.position = center + (basis * (view[0] as Vector3).normalized()) * 6.0
			cam.look_at(center, basis * (view[1] as Vector3))
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await _frames(3)
			await RenderingServer.frame_post_draw
			var used: Rect2i = vp.get_texture().get_image().get_used_rect()
			if used.size.x <= 0:
				break
			var px := cam.size / float(vp.size.y)
			var mid := Vector2(used.position) + Vector2(used.size) * 0.5 - Vector2(vp.size) * 0.5
			center += cam.global_basis.x * mid.x * px - cam.global_basis.y * mid.y * px
			cam.size = maxf(float(used.size.x), float(used.size.y)) * px * 1.15
		await _save(vp, "iconraw-%s_%s.png" % [job[0], job[1]])
	vp.queue_free()


## Poke-through check: the base body's skin shader is flat magenta, so any skin showing through a worn race piece is
## obvious. Idle and mid-run, front / side / back, every race on every class.
func _poke() -> void:
	var stage := _stage(Vector2i(320, 420))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	cam.fov = 30.0
	var model = CharacterModel.new()
	vp.add_child(model)
	model.load_model()
	for cls in CLASSES:
		model.dress({"class": cls, "weapon": {"path": "", "family": "", "style": ""}})
		for race in RACES:
			model.dress(_outfit({"shirt": race, "pants": race, "armband": race, "shoes": race}))
			model.set_weapon_visible(false)
			for mesh in model._body_meshes:
				if str(mesh.name) == "Base_Body":
					for i in mesh.get_surface_override_material_count():
						var m = mesh.get_surface_override_material(i)
						if m is ShaderMaterial:
							m.set_shader_parameter("base_color_linear", Vector3(1.0, 0.0, 1.0))
			for pose in ["idle", "run"]:
				for side in [["front", 0.0], ["side", 90.0], ["back", 180.0]]:
					model.rotation.y = deg_to_rad(side[1])
					cam.position = Vector3(0.0, 0.75, 3.2)
					cam.look_at(Vector3(0.0, 0.66, 0.0))
					model.set_pose(pose, 1.0 if pose == "run" else 0.0, 4.0 if pose == "run" else 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
					for i in 3:
						model.apply_pose(0.11)
					await _save(vp, "poke_%s_%s_%s_%s.png" % [cls, race, pose, side[0]])
	vp.queue_free()


## Race sword & shield (art/weapons/race_<race>/sword_shield.glb + shield.glb) with the race outfit on the Sword &
## Shield body: idle, an attack frame (slash at 45%: the swing) and a block frame (block_idle), front 3/4 and back.
## build/race_outfits/weapons/ss_<race>_<frame>_<side>.png.
func _weapon_shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "weapons"))
	var stage := _stage(Vector2i(450, 600))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	cam.fov = 40.0
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	model.dress({"class": "sword_shield"})
	var lib = model._library
	for race in RACES:
		var looks := _outfit({"shirt": race, "pants": race, "armband": race, "shoes": race})
		looks["weapon"] = {"path": "res://art/weapons/race_%s/sword_shield.glb" % race, "family": "blade", "style": "blade"}
		looks["offhand"] = {"item_id": "race_%s_shield" % race, "asset_id": "procedural_round_shield", "procedural": true, "path": "res://art/weapons/race_%s/shield.glb" % race, "refine_level": 0}
		model.dress(looks)
		for frame in [["idle", "idle", 0.4], ["attack", "slash", 0.45], ["block", "block_idle", 0.3]]:
			var clip: String = frame[1]
			model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", "blade")
			model.show_class_skill_frame({"clip": clip, "time": float(frame[2]) * lib.length(clip)})
			for i in 30:
				model.apply_pose(0.1)  # (the joints ease toward the clip frame; the turn settles facing the camera)
			for side in [["front", 30.0], ["back", 210.0]]:
				model.rotation.y = deg_to_rad(side[1])
				cam.position = Vector3(0.0, 1.2, 2.6)
				cam.look_at(Vector3(0.0, 0.66, 0.0))
				await _save(vp, "weapons/ss_%s_%s_%s.png" % [race, frame[0], side[0]])
		model.clear_class_skill_frame()
	vp.queue_free()
