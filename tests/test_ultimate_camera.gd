extends RefCounted
## Tests the ultimates' own cameras (the "camera" block per skill in data/combat/ultimates.json,
## played by client/ultimate_camera.gd through the camera rig): every pack has a block that parses,
## the packs that bring a camera keep the pack's own timings, the rest get the small default shake,
## a shot never sits behind the caster and never loses the caster off screen, and a cast's override
## begins, ends, and always gives the player back the angle they chose (also when the caster dies,
## the stage goes away, or PvP rules are on).

const CameraRig := preload("res://client/camera_rig.gd")
const Fighter := preload("res://logic/fighter.gd")
const SkillVfx := preload("res://client/vfx/skill_vfx.gd")
const UltimateCamera := preload("res://client/ultimate_camera.gd")

const ULTIMATES := "res://data/combat/ultimates.json"
const WEAPON_TYPES := ["blade", "dagger", "spear", "hammer"]
## The packs whose skill.json / demo scripts carry a camera (the rest use the default shake).
const PACK_CAMERAS := [
	"blade_earth_slam_ultimate", "blade_solar_slam_ultimate", "blade_thunder_slam_ultimate", "blade_tidal_slam_ultimate",
]

var _ultimates: Dictionary = {}
var _manifests: Dictionary = {}  ## pack folder -> its skill.json


func run(ctx) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ULTIMATES))
	_ultimates = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	ctx.check("ultimates.json is readable", not _ultimates.is_empty())
	if _ultimates.is_empty():
		return
	_test_blocks_parse(ctx)
	_test_pack_timings(ctx)
	_test_parse_rejects_bad_blocks(ctx)
	_test_shots_stay_in_front_and_on_screen(ctx)
	await _test_rig_override(ctx)


func _test_blocks_parse(ctx) -> void:
	var skills: Dictionary = _ultimates["skills"]
	var bad: Array = []
	var pack_sources: Array = []
	var default_ok := true
	var knob: Dictionary = _ultimates.get("camera_default", {})
	for id in skills:
		var skill: Dictionary = skills[id]
		var camera := UltimateCamera.parse(skill.get("camera"), id)
		if not camera["errors"].is_empty():
			bad.append("%s: %s" % [id, camera["errors"]])
			continue
		if camera["source"] == "pack":
			pack_sources.append(id)
		else:
			var last := float(skill["events"][skill["events"].size() - 1]["time_s"])
			default_ok = default_ok and camera["keys"].is_empty() and camera["shakes"].size() == 1 \
				and is_equal_approx(camera["shakes"][0]["time_s"], last) \
				and is_equal_approx(camera["shakes"][0]["strength"], float(knob.get("shake_strength_m", -1.0)))
		for key in camera["keys"]:
			if float(key["time_s"]) > float(skill["duration_s"]):
				bad.append("%s: a camera key after the clip ends" % id)
		for shake in camera["shakes"]:
			if float(shake["time_s"]) > float(skill["duration_s"]):
				bad.append("%s: a shake after the clip ends" % id)
	ctx.check("every one of the %d packs has a camera block that parses %s" % [skills.size(), bad], bad.is_empty() and skills.size() == 9)
	pack_sources.sort()
	var expected := PACK_CAMERAS.duplicate()
	expected.sort()
	ctx.check("the 4 packs with a camera of their own are the ones marked source=pack %s" % [pack_sources], pack_sources == expected)
	ctx.check("the other 21 get the default: one small shake (camera_default) on their last hit", default_ok)
	for weapon_type in WEAPON_TYPES:
		var pack := SkillVfx.pack_for(weapon_type + "_ultimate")
		ctx.check("%s's ultimate (%s) brings its camera to the client" % [weapon_type, pack.get("id", "?")],
			typeof(pack.get("camera")) == TYPE_DICTIONARY and not pack["camera"].is_empty() and float(pack.get("body_m", 0.0)) > 0.0)


## The numbers come from the packs themselves (skill.json), not typed in again.
func _test_pack_timings(ctx) -> void:
	var skills: Dictionary = _ultimates["skills"]
	for id in ["blade_earth_slam_ultimate", "dagger_shadow_extraction_ultimate"]:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(skills[id]["folder"]) + "skill.json"))
		var source: Dictionary = manifest["camera"]
		var keys: Array = skills[id]["camera"]["keys"]
		var first_key := float(source.get("enter_start_s", 0.0))
		ctx.check("%s: the shot starts and is back at the player's angle when the pack says (%.2f..%.2f s)" % [id, first_key, float(source["return_end_s"])],
			is_equal_approx(float(keys[0]["time_s"]), first_key) and keys[0]["shot"] == "game"
			and is_equal_approx(float(keys[keys.size() - 1]["time_s"]), float(source["return_end_s"])) and keys[keys.size() - 1]["shot"] == "game")
	var slam: Dictionary = skills["blade_earth_slam_ultimate"]["camera"]
	ctx.check("blade slam: the close shot uses the pack's field of view (42 deg) and the impact shakes at the landing (1.86 s)",
		is_equal_approx(float(slam["keys"][1]["fov_deg"]), 42.0) and is_equal_approx(float(slam["shakes"][0]["time_s"]), 1.86))
	var shadow: Dictionary = skills["dagger_shadow_extraction_ultimate"]["camera"]
	ctx.check("shadow extraction: the view darkens as the pack asks (brightness 0.7, saturation 0.83, contrast 1.08)",
		is_equal_approx(float(shadow["tone"]["brightness"]), 0.7) and is_equal_approx(float(shadow["tone"]["saturation"]), 0.83) and is_equal_approx(float(shadow["tone"]["contrast"]), 1.08))
	var throw: Dictionary = skills["spear_water_sky_throw_ultimate"]["camera"]
	var throw_keys: Array = throw["keys"]
	ctx.check("sky throw: pose (orbit) to wide (58 deg) to the catch, back at 2.96 s, shake on the spear's landing (1.66 s)",
		throw_keys[1]["shot"] == "orbit" and is_equal_approx(float(throw_keys[3]["fov_deg"]), 58.0)
		and is_equal_approx(float(throw_keys[throw_keys.size() - 1]["time_s"]), 2.96) and is_equal_approx(float(throw["shakes"][0]["time_s"]), 1.66))


func _test_parse_rejects_bad_blocks(ctx) -> void:
	ctx.check("a camera that is not an object is an error", not UltimateCamera.parse(3)["errors"].is_empty())
	ctx.check("keys out of time order are an error", not UltimateCamera.parse({"keys": [{"time_s": 1.0, "shot": "game"}, {"time_s": 0.5, "shot": "game"}]})["errors"].is_empty())
	ctx.check("an unknown shot is an error", not UltimateCamera.parse({"keys": [{"time_s": 1.0, "shot": "spin"}]})["errors"].is_empty())
	ctx.check("a frame shot under the ground is an error", not UltimateCamera.parse({"keys": [{"time_s": 1.0, "shot": "frame", "position_m": [0, -1, 2], "look_m": [0, 1, 0], "fov_deg": 40}]})["errors"].is_empty())
	ctx.check("a huge shake is an error", not UltimateCamera.parse({"shakes": [{"time_s": 1.0, "strength_m": 2.0, "seconds": 0.2}]})["errors"].is_empty())


## Every pack, every facing, every one of the player's angles, every 1/30 s: the shot is never
## behind the caster (seen from the player's side) and the caster's feet and body stay in frame.
func _test_shots_stay_in_front_and_on_screen(ctx) -> void:
	var skills: Dictionary = _ultimates["skills"]
	var scale := float(_ultimates.get("body_length_m", 1.7)) / 1.506733
	var behind: Array = []
	var lost: Array = []
	var samples := 0
	var pulls := 0
	var raw_misses := 0
	for id in skills:
		var camera := UltimateCamera.parse(skills[id]["camera"], id)
		if camera["keys"].is_empty():
			continue
		var duration := float(skills[id]["duration_s"])
		for d in 8:
			var facing := Vector2.RIGHT.rotated(TAU * d / 8.0)
			var frame := UltimateCamera.frame_for(facing)
			for preset_key in CameraRig.PRESETS:
				var chosen: Dictionary = CameraRig.PRESETS[preset_key]
				var t := 0.0
				while t < duration:
					var shot := UltimateCamera.sample(camera, t, chosen, frame, scale, Vector3.ZERO)
					if shot["special"]:
						samples += 1
						if shot["offset"].z < -0.001:
							behind.append("%s %s %.2f" % [id, facing, t])
						# The shown body: hips at 0.85 m standing, lifted by the pack's own visual jump.
						var points := UltimateCamera.body_points(Vector3(0.0, _hips_height(skills[id], t, scale), 0.0))
						if not UltimateCamera._sees_all(shot, points):
							raw_misses += 1
						var kept := UltimateCamera.keep_in_view(shot, chosen, points)
						if kept.get("pulled", false):
							pulls += 1
						if not UltimateCamera._sees_all(kept, points):
							lost.append("%s %s %.2f %s" % [id, facing, t, chosen["name"]])
					t += 1.0 / 30.0
	ctx.check("no shot puts the camera behind the caster (%d samples) %s" % [samples, behind.slice(0, 5)], behind.is_empty() and samples > 1000)
	ctx.check("the caster never leaves the frame (%d of %d samples needed the pull toward the chosen angle) %s" % [pulls, samples, lost.slice(0, 5)], lost.is_empty())
	ctx.check("the packs' own shots already frame the caster almost always (%d of %d needed a pull)" % [raw_misses, samples], raw_misses * 10 <= samples)
	for preset_key in CameraRig.PRESETS:
		var chosen: Dictionary = CameraRig.PRESETS[preset_key]
		var game := UltimateCamera.sample({}, 1.0, chosen, Basis.IDENTITY, 1.0, Vector3.ZERO)
		ctx.check("with no keys the shot is the player's own angle %s" % chosen["name"], not game["special"] and game["offset"] == chosen["offset"])


## The height of the shown hips at `t`: 0.85 m standing, plus the pack's visual jump (body_motion in
## its skill.json: up from launch to apex, held until hover end, down by the impact/landing).
func _hips_height(skill: Dictionary, t: float, scale: float) -> float:
	var manifest: Dictionary = _manifests.get(skill["folder"], {})
	if manifest.is_empty():
		manifest = JSON.parse_string(FileAccess.get_file_as_string(str(skill["folder"]) + "skill.json"))
		_manifests[skill["folder"]] = manifest
	var body: Dictionary = manifest.get("body_motion", {}) if typeof(manifest.get("body_motion")) == TYPE_DICTIONARY else {}
	var jump := float(body.get("visual_jump_height_m", 0.0)) * scale
	if jump <= 0.0 or not body.has("apex_time_s"):
		return 0.85
	var landing := maxf(float(manifest.get("flight", {}).get("arrival_time_s", 0.0)), float(body["hover_end_time_s"]) + 0.16)
	var up := smoothstep(float(body["launch_time_s"]), float(body["apex_time_s"]), t)
	var down := smoothstep(float(body["hover_end_time_s"]), landing, t)
	return 0.85 + jump * up * (1.0 - down)


func _fighter(move_id: String) -> Fighter:
	var fighter := Fighter.new()
	fighter.hp = 100.0
	fighter.state = Fighter.State.ATTACK
	fighter.move_id = move_id
	fighter.move_frame = 0.0
	fighter.direction = Vector2i(1, 0)
	return fighter


## Runs the cast for `seconds` of move time, a tick at a time, pumping the rig as the frame would.
func _cast(rig, camera, fighter: Fighter, player: Node3D, from_s: float, to_s: float) -> void:
	fighter.move_frame = from_s * 60.0
	while fighter.move_frame <= to_s * 60.0:
		camera.update(fighter, player.position, player.position + Vector3(0.0, 0.85, 0.0))
		rig._process(1.0 / 60.0)
		fighter.move_frame += 1.0


func _settle(rig) -> void:
	for i in 180:
		rig._process(1.0 / 60.0)


func _test_rig_override(ctx) -> void:
	var player := Node3D.new()
	ctx.root.add_child(player)
	var rig := CameraRig.new()
	rig.target = player
	ctx.root.add_child(rig)
	var camera := UltimateCamera.new()
	camera.rig = rig
	ctx.root.add_child(camera)
	var chosen_name: String = rig.chosen["name"]
	ctx.check("the player's angle is camera 8 to begin with", chosen_name == "8: High")
	var home: Vector3 = rig.view()["position"]

	# The spear's sky throw: its own camera from the pose (0.40 s) to the catch, then home.
	var spear := _fighter("spear_ultimate")
	_cast(rig, camera, spear, player, 0.0, 0.1)
	ctx.check("before its first shot the cast leaves the camera alone", not rig.has_override())
	_cast(rig, camera, spear, player, 0.1, 1.9)
	ctx.check("during the throw the ultimate's camera is the active override", rig.has_override() and rig.override_name() == "Ultimate")
	ctx.check("and it really moved the camera (%.1f m from the player's angle)" % rig.view()["position"].distance_to(home), rig.view()["position"].distance_to(home) > 2.0)
	ctx.check("the spear's landing shook the camera", rig._shake_left > 0.0 or rig._shake_strength > 0.0)
	ctx.check("the player's own choice is untouched while it plays", rig.chosen["name"] == chosen_name)
	spear.state = Fighter.State.IDLE  # the move ends (before the pack's 2.96 s return: the hold is 2.74 s)
	camera.update(spear, player.position, player.position)
	ctx.check("when the move ends the override is released", not rig.has_override())
	_settle(rig)
	ctx.check("and the camera blends back to the player's angle", rig.view()["position"].distance_to(home) < 0.05 and absf(rig.view()["fov"] - float(rig.chosen["fov"])) < 0.05)

	# Dying in the middle of the cast.
	var dying := _fighter("spear_ultimate")
	_cast(rig, camera, dying, player, 0.0, 1.0)
	ctx.check("a second cast takes the camera again", rig.has_override())
	dying.state = Fighter.State.DEAD
	dying.hp = 0.0
	camera.update(dying, player.position, player.position)
	ctx.check("the caster dying mid-skill releases it", not rig.has_override())
	_settle(rig)
	ctx.check("and the camera is home again", rig.view()["position"].distance_to(home) < 0.05)

	# The dagger's shadow extraction darkens the view (needs a world environment to copy).
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	ctx.root.add_child(world)
	var dagger := _fighter("dagger_ultimate")
	_cast(rig, camera, dagger, player, 0.0, 0.8)
	var toned: Environment = rig._camera.environment
	ctx.check("shadow extraction: its own camera and a darker view tone", rig.has_override() and toned != null and toned.adjustment_brightness < 0.95)
	_cast(rig, camera, dagger, player, 0.8, 1.7)
	ctx.check("the tone is gone again when its shot returns (1.64 s)", rig._camera.environment == null)
	dagger.state = Fighter.State.IDLE
	camera.update(dagger, player.position, player.position)

	# The stage going away mid-cast (the camera node is freed with it).
	var leaving := _fighter("dagger_ultimate")
	_cast(rig, camera, leaving, player, 0.0, 0.6)
	ctx.check("a cast in progress holds the override", rig.has_override() and rig._camera.environment != null)
	ctx.root.remove_child(camera)
	camera.free()
	ctx.check("freeing the ultimate camera mid-cast releases the override and the tone", not rig.has_override() and rig._camera.environment == null)
	_settle(rig)
	ctx.check("and the player's angle is back", rig.view()["position"].distance_to(home) < 0.05)

	# PvP rules: no special camera at all, the impact shake stays (it is hit feedback).
	camera = UltimateCamera.new()
	camera.rig = rig
	ctx.root.add_child(camera)
	rig.special_enabled = false
	var pvp := _fighter("dagger_ultimate")
	_cast(rig, camera, pvp, player, 0.0, 1.0)
	ctx.check("PvP: the ultimate's camera does not move the view", not rig.has_override() and rig._camera.environment == null and rig.view()["position"].distance_to(home) < 0.05)
	rig.special_enabled = true
	pvp.state = Fighter.State.IDLE
	camera.update(pvp, player.position, player.position)

	# A pack with only the default camera: no override, one small shake on its last hit.
	var hammer := _fighter("hammer_ultimate")
	rig._shake_left = 0.0
	rig._shake_strength = 0.0
	_cast(rig, camera, hammer, player, 0.0, 1.0)
	ctx.check("hammer drag owns a low tracking shot", rig.has_override() and rig._shake_strength == 0.0)
	_cast(rig, camera, hammer, player, 1.0, 3.1)
	ctx.check("hammer shakes only at actual ground contact", rig._shake_strength > 0.0)
	_cast(rig, camera, hammer, player, 3.1, 3.3)
	ctx.check("hammer returns to gameplay after the strike", not rig.has_override())
	hammer.state = Fighter.State.IDLE
	camera.update(hammer, player.position, player.position)
	ctx.check("after every cast the player's choice is still camera 8", rig.chosen["name"] == "8: High")

	for node in [camera, world, rig, player]:
		node.queue_free()
	await ctx.process_frame
