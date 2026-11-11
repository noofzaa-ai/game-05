extends Node3D
## Materials and eye accents only. The guardians/burst move in their GLB.
const GUARDIAN := preload("res://art/skills/shared/shaders/shadow_attack_guardian.gdshader")
const AURA := preload("res://art/skills/shared/shaders/shadow_attack_aura.gdshader")
const GROUND := preload("res://art/skills/shared/shaders/shadow_ink_ground.gdshader")
const EYE := preload("res://art/skills/shared/shaders/shadow_eye.gdshader")
const GLINT := preload("res://art/skills/shared/shaders/shadow_eye_glint.gdshader")
var config: Dictionary
var receiver_skeleton: Skeleton3D
var hero_root: Node3D
var _materials: Array[Dictionary] = []
var _eyes: Array[Dictionary] = []
var _accents: Array[Dictionary] = []
var _eye_material: ShaderMaterial
var _eye_root: Node3D
var _eye_strength := 0.0
var _time := 0.0
var _light: OmniLight3D

func _ready() -> void:
	_adapt(get_parent())
	_eye_material = ShaderMaterial.new()
	_eye_material.shader = EYE
	if is_instance_valid(hero_root) and is_instance_valid(receiver_skeleton):
		_eye_root = Node3D.new()
		_eye_root.name = "ShadowEyeAccents"
		hero_root.add_child(_eye_root)
		_find_eyes(hero_root)
	_light = OmniLight3D.new()
	_light.position = Vector3(0,1.25,float(config["attack"]["range_m"]))
	_light.light_color = Color(.45,.10,.85)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	add_child(_light)

func _adapt(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(index)
			var tag := original.resource_name if original else ""
			var mat := ShaderMaterial.new()
			var group := "guardian"
			if tag.begins_with("ShadowBurst") or tag.begins_with("ShadowRush") or tag.begins_with("ShadowFlame") or tag.begins_with("ShadowSmoke") or tag.begins_with("ShadowChip"):
				mat.shader = AURA
				mat.set_shader_parameter("kind",2.0 if "Chip" in tag else 1.0 if "Smoke" in tag else 0.0)
				mat.set_shader_parameter("flake_tint",float(absi(String(node.name).hash())%5)/4.0)
				group = "burst" if tag.begins_with("ShadowBurst") else "rush" if tag.begins_with("ShadowRush") else "pose"
			elif tag.begins_with("ShadowGround"):
				mat.shader = GROUND
				mat.render_priority = -10
				group = "ground"
			else:
				mat.shader = GUARDIAN
				mat.set_shader_parameter("is_double",true)
				mat.set_shader_parameter("is_eye",tag.begins_with("ShadowEye"))
				mat.set_shader_parameter("is_seam",tag.begins_with("ShadowArmorEdge"))
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.set_surface_override_material(index,mat)
			_materials.append({"mat":mat,"group":group})
	for child in node.get_children():
		if child != self:_adapt(child)

# Fitted New v1 faces are rigid socket attachments with a shared eye-white surface.
# Split that surface into two temporary eye overlays; leave the face asset unchanged.
func _new_v1_eyes(node: MeshInstance3D) -> void:
	for surface in node.mesh.get_surface_count():
		var material := node.mesh.surface_get_material(surface)
		if material == null or material.resource_name != "Relief teeth and eye whites":
			continue
		var arrays := node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for side in [-1.0, 1.0]:
			var points := PackedVector3Array()
			for j in range(0, indices.size(), 3):
				var a := vertices[indices[j]]
				var b := vertices[indices[j + 1]]
				var c := vertices[indices[j + 2]]
				if a.x * side > 0.02 and b.x * side > 0.02 and c.x * side > 0.02:
					for point in [a, b, c]:
						points.append(point + Vector3(0, 0, 0.002))
			if points.is_empty():
				continue
			var data := []
			data.resize(Mesh.ARRAY_MAX)
			data[Mesh.ARRAY_VERTEX] = points
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
			var eye := MeshInstance3D.new()
			eye.name = "Eye inset NewV1"
			eye.mesh = mesh
			eye.set_meta("temporary_shadow_eye", true)
			eye.visible = false
			node.add_child(eye)

func _find_eyes(node: Node) -> void:
	if node is Node3D and not node.visible and not node.has_meta("temporary_shadow_eye"):
		return  # hidden embedded eyes must not duplicate a selected face
	if node is MeshInstance3D and node.mesh and not node.has_meta("temporary_shadow_eye"):
		_new_v1_eyes(node)
	if node is MeshInstance3D and (String(node.name).begins_with("Eye inset") or String(node.name).begins_with("Sharp turquoise eye")) and node.mesh:
		var bone := _receiver_bone("Head")
		var rest_point: Vector3 = node.mesh.get_aabb().get_center()
		# Skinned vertices are in bind space. Mesh node origins are not eye sockets.
		var head_pose := receiver_skeleton.get_bone_global_pose(bone) if node.has_meta("temporary_shadow_eye") else receiver_skeleton.get_bone_global_rest(bone)
		var local_eye: Vector3 = head_pose.affine_inverse() * (receiver_skeleton.global_transform.affine_inverse() * (node.global_transform * rest_point))
		var originals: Array = []
		for surface in node.mesh.get_surface_count():originals.append(node.get_surface_override_material(surface))
		_eyes.append({"node":node,"original":originals,"anchor":local_eye,"bone":bone})
		var rng := RandomNumberGenerator.new()
		rng.seed = 81 + _eyes.size()
		for i in 15:
			var card := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(.040,.13) if i<3 else Vector2(.009,.019)
			card.mesh = quad
			card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = GLINT
			mat.set_shader_parameter("kind",0.0 if i<3 else 2.0)
			mat.render_priority = 10
			card.material_override = mat
			_eye_root.add_child(card)
			_accents.append({"node":card,"mat":mat,"eye":_eyes.size()-1,"index":i,"seed":rng.randf(),"small":i>=3})
	for child in node.get_children():_find_eyes(child)

func advance(time_s: float) -> void:
	_time = time_s
	var visual: Dictionary = config["visual"]
	_eye_strength = smoothstep(float(visual["eye_ignite_start_s"]),float(visual["eye_ignite_full_s"]),time_s)*(1.0-smoothstep(float(visual["eye_fade_start_s"]),float(visual["eye_fade_end_s"]),time_s))
	_eye_material.set_shader_parameter("strength",_eye_strength)
	for row in _eyes:
		var eye: MeshInstance3D = row["node"]
		if not is_instance_valid(eye):continue
		if eye.has_meta("temporary_shadow_eye"):
			eye.visible = _eye_strength > .005
		for s in eye.mesh.get_surface_count():eye.set_surface_override_material(s,_eye_material if _eye_strength>.005 else row["original"][s])
	for row in _accents:
		var card: MeshInstance3D = row["node"]
		var eye: Dictionary = _eyes[row["eye"]]
		var basis: Transform3D = receiver_skeleton.global_transform * receiver_skeleton.get_bone_global_pose(eye["bone"])
		var phase := fmod(time_s*2.6+float(row["seed"]),1.0)
		var offset := Vector3((float(row["seed"])-.5)*.075,phase*.13,.012) if row["small"] else Vector3((int(row["index"])-1)*.024,.025,.012)
		card.global_transform = basis * Transform3D(Basis.IDENTITY,eye["anchor"]+offset)
		card.rotate_object_local(Vector3.FORWARD,(float(row["seed"])-.5)*.7)
		card.visible = _eye_strength>.005
		row["mat"].set_shader_parameter("cast_time",time_s)
		row["mat"].set_shader_parameter("visibility_factor",_eye_strength*(1.0-phase if row["small"] else .85))
	for row in _materials:
		var mat: ShaderMaterial = row["mat"]
		mat.set_shader_parameter("cast_time",time_s)
		var fade := 1.0
		match row["group"]:
			"burst":fade = smoothstep(1.82,1.91,time_s)*(1.0-smoothstep(2.55,3.80,time_s))
			"rush":fade = 1.0-smoothstep(1.82,2.10,time_s)
			"pose":fade = 1.0-smoothstep(1.40,2.05,time_s)
			"guardian":fade = 1.0-smoothstep(1.82,2.18,time_s)
		if row["group"]!="ground":mat.set_shader_parameter("visibility_factor",fade)
	_light.light_energy = smoothstep(1.82,1.93,time_s)*(1.0-smoothstep(2.20,3.10,time_s))*1.9

func snapshot() -> Dictionary:
	var guardians: Array = []
	for name in ["ShadowDouble_1","ShadowDouble_2"]:
		var node := get_parent().find_child(name,true,false) as Node3D
		if node:guardians.append({"name":name,"position_world_m":[node.global_position.x,node.global_position.y,node.global_position.z]})
	return {"eye_strength":_eye_strength,"eye_meshes_found":_eyes.size(),"eyes_restored":_eye_strength<=.005,"runtime_triangles":_accents.size()*2,"guardians":guardians,"burst_center_local_m":config["visual"]["blast_center_gltf_m"]}

func restore_eyes() -> void:
	for row in _eyes:
		var eye: MeshInstance3D = row["node"]
		if is_instance_valid(eye):
			if eye.has_meta("temporary_shadow_eye"):
				eye.queue_free()
				continue
			for s in eye.mesh.get_surface_count():eye.set_surface_override_material(s,row["original"][s])
	_eyes.clear()
	if is_instance_valid(_eye_root):_eye_root.queue_free()
	_eye_root = null

func _exit_tree() -> void:restore_eyes()

func _receiver_bone(short_name: String) -> int:
	for candidate in [short_name, "mixamorig:" + short_name, "mixamorig_" + short_name, "mixamorig" + short_name]:
		var index := receiver_skeleton.find_bone(candidate)
		if index >= 0: return index
	return -1
