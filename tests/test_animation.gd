extends RefCounted
## Tests the player's animation: the test05 Studio character's own clips (art/characters/studio05), their
## timing marks (clips.json), sampling, and how the model picks a clip for each pose.
## (Run `godot --headless --path . --import` once after changing a .glb.)

const AnimationSet := preload("res://client/animation_set.gd")
const StudioModel := preload("res://client/characters/studio05_character_model.gd")
const FOLDER := "res://art/characters/studio05/"


func run(ctx) -> void:
	AnimationSet.clear_cache()
	var spec: Dictionary = StudioModel.class_data("sword_shield")
	ctx.check("the sword and shield class file loads", spec.get("weapon") == "blade" and spec.has("moves") and spec.has("states"))
	var library = AnimationSet.load_file(str(spec.animations), str(spec.clip_marks))
	ctx.check("the studio character's clips load", library != null)
	if library == null:
		return
	for clip in ["idle", "run", "walk", "slash", "slash_3", "slash_5", "attack_2", "attack_4", "kick", "block_idle", "impact", "impact_2", "jump", "crouching", "attack_2", "slash_2", "slash_4"]:
		ctx.check("the source has a '%s' clip" % clip, library.has_clip(clip))
	ctx.check("idle and run loop; a slash does not", library.is_looping("idle") and library.is_looping("run") and not library.is_looping("slash"))
	for move in spec.moves.values():
		ctx.check("move clip '%s' exists" % move, library.has_clip(move))
		var meta: Dictionary = library._clips[move]["meta"]
		ctx.check("attack clip '%s' has ordered marks" % move, not meta.has("windup_end") or (float(meta["windup_end"]) < float(meta["strike_end"]) and float(meta["strike_end"]) <= library.length(move)))
	var sample: Dictionary = library.sample("run", 0.3)
	ctx.check("a sample moves the hips and the hair chains", sample.has("mixamorig_Hips") and sample.has("hair_CB_1"))
	ctx.check("loading twice gives the same cached object", AnimationSet.load_file(str(spec.animations), str(spec.clip_marks)) == library)
	for hair in StudioModel.HAIR_STYLES:
		for silver in [false, true]:
			ctx.check("variant %s%s exists" % [hair, " silver" if silver else ""], ResourceLoader.exists(StudioModel.variant_path(hair, silver)))
	ctx.check("the ultimate and the heavy hit use different clips", spec.moves["ultimate"] == "attack_2" and spec.moves["heavy"] != "attack_2")
	ctx.check("hair ids map to a stable file", StudioModel.hair_for("anything") == StudioModel.hair_for("anything") and StudioModel.hair_for("c") == "c")

	for class_id in ["sword_shield", "greatsword", "longbow", "magic"]:
		var class_spec: Dictionary = StudioModel.class_data(class_id)
		var class_library = AnimationSet.load_file(str(class_spec.get("animations", "")), str(class_spec.get("clip_marks", "")))
		ctx.check("class %s loads its clips" % class_id, class_library != null)
		if class_library == null:
			continue
		var missing := []
		for clip in class_spec.moves.values() + class_spec.states.values():
			if not class_library.has_clip(str(clip)):
				missing.append(clip)
		ctx.check("class %s maps every move and state onto a real clip %s" % [class_id, missing], missing.is_empty())

	var model := StudioModel.new()
	ctx.check("the model loads", model.load_model())
	if model.bone_count() == 0:
		return
	ctx.check("the rig keeps the 102 source joints plus two weapon sockets", model.bone_count() == 104 and model.has_bone("attach_weapon.R") and model.has_bone("attach_weapon.L"))
	ctx.check("the body is at most 135cm", model.model_height() <= 1.351)
	model.set_pose("idle", 0.0, 0.0, true, 1, false)
	ctx.check("standing plays the idle clip", model.current_clip().get("clip") == "idle")
	model.set_pose("run", 0.0, 1.0, true, 1, false)
	ctx.check("running plays the run clip", model.current_clip().get("clip") == "run")
	model.set_pose("guard", 1.0, 0.0, true, 1, false)
	ctx.check("guarding plays the block clip", model.current_clip().get("clip") == "block_idle")
	model.set_pose("punch_r", 0.5, 0.0, true, 1, false, "strike", "light_1", "blade")
	var strike: Dictionary = model.current_clip()
	var meta: Dictionary = library._clips["slash"]["meta"]
	ctx.check("a sword strike plays the slash clip inside its strike window", strike.get("clip") == "slash" and strike["time"] >= float(meta["windup_end"]) and strike["time"] <= float(meta["strike_end"]))
	model.set_pose("punch_r", 0.0, 0.0, true, 1, false, "windup", "light_1", "blade")
	var windup_time: float = model.current_clip()["time"]
	model.set_pose("punch_r", 1.0, 0.0, true, 1, false, "recover", "light_1", "blade")
	ctx.check("windup comes before recovery in the clip", windup_time < model.current_clip()["time"])
	model.set_pose("hurt", 0.5, 0.0, true, 1, false)
	ctx.check("being hit plays an impact clip", str(model.current_clip().get("clip")).begins_with("impact"))
	model.set_pose("idle", 0.0, 0.0, false, 1, false)
	ctx.check("in the air plays the jump clip", model.current_clip().get("clip") == "jump")
	model.free()
