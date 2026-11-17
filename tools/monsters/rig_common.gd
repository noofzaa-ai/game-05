extends RefCounted
## Shared helpers of the monster rigging tools (Godot scripts, run headless).
## The donor is the player's longbow body: art/characters/studio05/split/body_longbow.glb (102 joints, READ ONLY).

const DONOR := "res://art/characters/studio05/split/body_longbow.glb"
const DONOR_ARMOR := "res://art/characters/studio05/v1111/outfits/armor_longbow.glb"
const FPS := 30.0
const ROT_TOL := deg_to_rad(0.35)  ## a key within this angle of the interpolation of its neighbours is dropped
const POS_TOL := 0.0005  ## metres (rig units)


static func load_donor() -> Node:
	return (load(DONOR) as PackedScene).instantiate()


static func donor_skeleton(root: Node) -> Skeleton3D:
	return root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


static func donor_player(root: Node) -> AnimationPlayer:
	return root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer


## Bone name -> {"rot": track index, "pos": track index or -1} of a donor clip.
static func clip_tracks(anim: Animation) -> Dictionary:
	var out := {}
	for t in anim.get_track_count():
		var bone := String(anim.track_get_path(t).get_concatenated_subnames())
		if not out.has(bone):
			out[bone] = {"rot": -1, "pos": -1}
		match anim.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				out[bone]["rot"] = t
			Animation.TYPE_POSITION_3D:
				out[bone]["pos"] = t
	return out


## A new Skeleton3D with the donor's bones (name, parent, rest), in the donor's order.
static func copy_skeleton(src: Skeleton3D) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for i in src.get_bone_count():
		skeleton.add_bone(src.get_bone_name(i))
	for i in src.get_bone_count():
		skeleton.set_bone_parent(i, src.get_bone_parent(i))
		skeleton.set_bone_rest(i, src.get_bone_rest(i))
	skeleton.reset_bone_poses()
	return skeleton


## Drops keys a straight (slerp / lerp) line between their kept neighbours reproduces. times/values are parallel.
static func reduce_keys(times: Array, values: Array, is_rotation: bool) -> Array:
	var n := times.size()
	if n <= 2:
		return [times, values]
	var kept_t := [times[0]]
	var kept_v := [values[0]]
	var start := 0
	var end := 2
	while end < n:
		var ok := true
		for mid in range(start + 1, end):
			var w: float = (times[mid] - times[start]) / (times[end] - times[start])
			if is_rotation:
				var q: Quaternion = (values[start] as Quaternion).slerp(values[end], w)
				if q.angle_to(values[mid]) > ROT_TOL:
					ok = false
					break
			else:
				var p: Vector3 = (values[start] as Vector3).lerp(values[end], w)
				if p.distance_to(values[mid]) > POS_TOL:
					ok = false
					break
		if not ok:
			kept_t.append(times[end - 1])
			kept_v.append(values[end - 1])
			start = end - 1
		end += 1
	kept_t.append(times[n - 1])
	kept_v.append(values[n - 1])
	return [kept_t, kept_v]


## The bone's global rest-relative pose of `clip` at `time` on a skeleton copy (for measuring only).
static func pose_at(skeleton: Skeleton3D, anim: Animation, tracks: Dictionary, time: float) -> void:
	skeleton.reset_bone_poses()
	for bone in tracks:
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		if tracks[bone]["rot"] >= 0:
			skeleton.set_bone_pose_rotation(index, anim.rotation_track_interpolate(tracks[bone]["rot"], time))
		if tracks[bone]["pos"] >= 0:
			skeleton.set_bone_pose_position(index, anim.position_track_interpolate(tracks[bone]["pos"], time))


## Godot writes the glTF JSON chunk indented: re-pack the file with a compact JSON chunk (same data, much smaller).
static func minify_glb(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	var json_len := bytes.decode_u32(12)
	var lines := bytes.slice(20, 20 + json_len).get_string_from_utf8().split("
")
	var compact := ""
	for line in lines:
		compact += line.strip_edges()
	var text := compact.to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var rest := bytes.slice(20 + json_len)  # the BIN chunk (header + data)
	var out := PackedByteArray()
	out.append_array(bytes.slice(0, 12))
	out.resize(20)
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(text)
	out.append_array(rest)
	out.encode_u32(8, out.size())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(out)
	file.close()
