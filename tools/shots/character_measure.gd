extends SceneTree
## Measures OUR chibi's proportions from the model itself (bone rest positions + mesh bounds), so the
## numbers are exact rather than eyeballed from a render. Headless is fine:
##   godot --headless --path . --script res://tools/shots/character_measure.gd
## Prints heads-tall, head:torso:leg split, shoulder width, hand/foot size, eye band — all as fractions
## of the body height so they compare straight to the reference's description.

const CharacterModel := preload("res://client/character_model.gd")


func _initialize() -> void:
	var model := CharacterModel.new()
	root.add_child(model)
	if not model.load_model():
		print("FAILED to load model")
		quit()
		return
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var scale := model.model_scale()
	var total := model.model_height()
	# Global rest Y of key bones (in model-local meters), scaled to game units.
	var y := func(bone: String) -> float:
		var i := skel.find_bone(bone)
		return skel.get_bone_global_rest(i).origin.y * scale if i >= 0 else -1.0
	var top := total  # feet are at 0 after load_model placed them on the origin
	var head_y: float = y.call("Head")
	var neck_y: float = y.call("Neck")
	var hips_y: float = y.call("Hips")
	var knee_y: float = y.call("LeftLowerLeg")
	# Head height = top of model minus the neck join (hair excluded: use Head..top).
	var head_h := top - head_y
	var heads_tall := total / head_h if head_h > 0.0 else 0.0
	# Shoulder width: distance between the two upper-arm bone roots.
	var sx := func(bone: String) -> float:
		var i := skel.find_bone(bone)
		return skel.get_bone_global_rest(i).origin.x * scale if i >= 0 else 0.0
	var shoulder_w := absf(sx.call("LeftUpperArm") - sx.call("RightUpperArm"))
	print("--- OUR CHIBI (base body, no gear), game units; body height = %.3f ---" % total)
	print("heads tall (crown to feet / head height): %.2f" % heads_tall)
	print("head height: %.3f (%.0f%% of body)" % [head_h, 100.0 * head_h / total])
	print("neck/shoulder line Y: %.3f (%.0f%%)" % [neck_y, 100.0 * neck_y / total])
	print("hips Y: %.3f (%.0f%%)   knee Y: %.3f (%.0f%%)" % [hips_y, 100.0 * hips_y / total, knee_y, 100.0 * knee_y / total])
	print("torso (hips->neck): %.3f (%.0f%%)   legs (feet->hips): %.3f (%.0f%%)" % [neck_y - hips_y, 100.0 * (neck_y - hips_y) / total, hips_y, 100.0 * hips_y / total])
	print("shoulder width: %.3f (%.0f%% of body height, = %.2f head widths est.)" % [shoulder_w, 100.0 * shoulder_w / total, shoulder_w / head_h])

	# Hand and foot bounding boxes (the visible mesh parts), in game units.
	var part_size := func(substr: String) -> Vector3:
		var box := AABB()
		var first := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if substr.to_lower() in str(mi.name).to_lower():
				var b: AABB = mi.get_aabb()
				b = mi.global_transform * b if false else b
				var scaled := AABB(b.position * scale, b.size * scale)
				if first:
					box = scaled
					first = false
				else:
					box = box.merge(scaled)
		return box.size
	print("hand mesh size (x,y,z): %s" % str(part_size.call("hand")))
	print("foot/base-foot mesh size: %s" % str(part_size.call("foot")))
	quit()
