extends Node3D
## Authored Godot fire-wave presentation v2. Frozen cast origin and config timing.
const FLAME := preload("res://art/skills/shared/shaders/inferno_flame.gdshader")
const SLASH := preload("res://art/skills/shared/shaders/inferno_slash.gdshader")
const SMOKE := preload("res://art/skills/shared/shaders/inferno_smoke.gdshader")
const RING := preload("res://art/skills/shared/shaders/inferno_ring.gdshader")
const TEXTURE_PATH := "res://art/skills/shared/textures/inferno_flame_v2.png"
var config: Dictionary
var _wave: Node3D
var _charge: Node3D
var _slashes: Array[MeshInstance3D] = []
var _slash_materials: Array[ShaderMaterial] = []
var _plumes: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _shock: ShaderMaterial
var _light: OmniLight3D
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _flare: GPUParticles3D
var _release_time := 0.72
var _arrival_time := 1.91
var _fade_end := 2.8
var _reach := 3.01346655
var _released := false
var _arrived := false
var _flame_texture: Texture2D

func _ready() -> void:
	_release_time = float(config["flight"]["release_time_s"])
	_arrival_time = float(config["flight"]["arrival_time_s"])
	_fade_end = float(config["visual"]["vfx_fade_end_time_s"])
	_reach = float(config["attack"]["range_m"])
	_flame_texture = load(TEXTURE_PATH) as Texture2D
	_wave = Node3D.new()
	add_child(_wave)
	# Three curved sheets create a substantial flame front, rather than flat shards.
	for layer in 3:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _curtain(72,1.12-float(layer)*0.08,0.98-float(layer)*0.16)
		mesh.position = Vector3(0.0,0.025+float(layer)*0.1,-float(layer)*0.16)
		mesh.rotation.z = deg_to_rad(float(layer-1)*13.0)
		mesh.material_override = _flame_material(1.0-float(layer)*0.15,0.95-float(layer)*0.1,float(layer))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wave.add_child(mesh)
	for layer in 2:
		var slash := MeshInstance3D.new()
		slash.mesh = _crescent(96,1.12-float(layer)*0.1,0.34-float(layer)*0.08)
		var material := ShaderMaterial.new()
		material.shader = SLASH
		material.set_shader_parameter("flame_texture",_flame_texture)
		slash.material_override = material
		slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slash)
		_slashes.append(slash)
		_slash_materials.append(material)
	_charge = Node3D.new()
	_charge.position = Vector3(0.22,0.62,0.3)
	add_child(_charge)
	var charge_mesh := MeshInstance3D.new()
	charge_mesh.mesh = _curtain(32,0.42,0.52)
	charge_mesh.material_override = _flame_material(0.85,0.85,0.7)
	charge_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge.add_child(charge_mesh)
	# Short sheets fan out and curl upward at impact; front edge stays inside range.
	for index in 16:
		var mesh := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.7,1.0)
		mesh.mesh = quad
		mesh.position = Vector3(sin(float(index)*2.39996)*0.48,0.65,_reach-0.72+cos(float(index)*2.39996)*0.14)
		mesh.rotation = Vector3(-0.22,float(index)*0.53,0.2*sin(float(index)))
		mesh.material_override = _flame_material(0.36,0.5,float(index)*0.17)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		_plumes.append(mesh)
	_shock = _ground_ring()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0,0.38,0.065)
	_light.omni_range = 3.5
	_light.shadow_enabled = false
	add_child(_light)
	_sparks = _particles(160,0.95,false,false)
	_smoke = _particles(40,1.0,true,false)
	_flare = _particles(48,0.65,false,true)
	advance(0.0)

func _curtain(segments: int, width: float, height: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in segments+1:
		var u := float(index)/float(segments)
		var theta := (u-0.5)*2.65
		var x := sin(theta)*width
		var z := cos(theta)*0.42-0.17
		for side in 2:
			vertices.append(Vector3(x,float(side)*height,z+float(side)*0.16))
			uvs.append(Vector2(u,1.0-float(side)))
			normals.append(Vector3(0.0,0.0,1.0))
		if index < segments:
			var a := index*2
			indices.append_array(PackedInt32Array([a,a+3,a+1,a,a+2,a+3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _crescent(segments: int, radius: float, width: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in segments+1:
		var u := float(index)/float(segments)
		var theta := lerpf(-1.85,1.85,u)
		var taper := pow(maxf(0.001,sin(u*PI)),0.7)
		for side in 2:
			var r := radius-float(1-side)*width*taper
			vertices.append(Vector3(sin(theta)*r,0.0,cos(theta)*r))
			uvs.append(Vector2(u,float(side)))
		if index < segments:
			var a := index*2
			indices.append_array(PackedInt32Array([a,a+3,a+1,a,a+2,a+3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _flame_material(opacity: float, heat: float, variant: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLAME
	material.set_shader_parameter("flame_texture",_flame_texture)
	material.set_shader_parameter("opacity",opacity)
	material.set_shader_parameter("heat",heat)
	material.set_shader_parameter("variant",variant)
	_materials.append(material)
	return material

func _ground_ring() -> ShaderMaterial:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3,0.68)
	mesh.mesh = plane
	mesh.position = Vector3(0.0,0.035,_reach-0.4)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = RING
	material.set_shader_parameter("shock",1.0)
	mesh.material_override = material
	add_child(mesh)
	return material

func _particles(count: int, life: float, smoke: bool, flame: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = life
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-3,-1,-1),Vector3(6,5,5))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0,1.0,0.0)
	process.spread = 42.0
	process.gravity = Vector3(0,-0.5,0) if not smoke else Vector3(0,0.3,0)
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.32 if flame else 0.52
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08 if flame else 0.20
	process.scale_min = 0.12 if smoke or flame else 0.008
	process.scale_max = 0.25 if flame else (0.45 if smoke else 0.025)
	process.angular_velocity_min = -60.0
	process.angular_velocity_max = 60.0
	var ramp := Gradient.new()
	ramp.set_color(0,Color(0.14,0.08,0.045,0.0) if smoke else Color(1.0,0.8,0.3,1.0))
	ramp.add_point(0.15,Color(0.22,0.12,0.06,0.7) if smoke else Color(1.0,0.65,0.08,1.0))
	ramp.set_color(ramp.get_point_count()-1,Color(0.10,0.08,0.055,0.0) if smoke else Color(1.0,0.12,0.0,0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	particles.process_material = process
	var quad := QuadMesh.new()
	if flame:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = _flame_texture
		material.emission_enabled = true
		material.emission_texture = _flame_texture
		material.emission = Color(0.3,0.08,0.005)
		material.emission_energy_multiplier = 0.35
		quad.material = material
	elif smoke:
		var material := ShaderMaterial.new()
		material.shader = SMOKE
		quad.material = material
	else:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.vertex_color_use_as_albedo = true
		material.emission_enabled = true
		material.emission = Color(1.0,0.5,0.08)
		material.emission_energy_multiplier = 1.8
		quad.size = Vector2(0.3,1.0)
		quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles

func advance(time: float) -> void:
	var u := smoothstep(_release_time,_arrival_time,time)
	var fade := 1.0-smoothstep(_arrival_time+0.16,_fade_end,time)
	var born := smoothstep(_release_time,_release_time+0.18,time)
	var pulse := 1.0+0.045*sin(time*19.0)
	var slash_strength := born*(1.0-smoothstep(_arrival_time-0.05,_arrival_time+0.30,time))
	for index in _slashes.size():
		var slash := _slashes[index]
		slash.visible = slash_strength > 0.001
		slash.position = Vector3(0.0,0.43+float(index)*0.16,lerpf(0.28,_reach-1.23,u))
		slash.rotation = Vector3(deg_to_rad(14.0+float(index)*8.0),0.0,deg_to_rad(-15.0+float(index)*28.0))
		slash.scale = Vector3.ONE*(0.45+0.55*born)
		_slash_materials[index].set_shader_parameter("cast_clock",time)
		_slash_materials[index].set_shader_parameter("strength",slash_strength*(1.0-float(index)*0.22))
	_wave.visible = born > 0.001 and fade > 0.001
	_wave.position = Vector3(0.0,-0.08,lerpf(0.34,_reach-0.60,u))
	_wave.scale = Vector3((0.35+0.65*born)*pulse,born*fade*0.95,1.0)
	_charge.visible = time < _release_time
	var charge := smoothstep(0.08,_release_time,time)
	_charge.scale = Vector3.ONE*(0.20+0.80*charge)
	for material in _materials:
		material.set_shader_parameter("cast_clock",time)
	var impact := smoothstep(_arrival_time,_arrival_time+0.10,time)*(1.0-smoothstep(_arrival_time+0.12,_arrival_time+0.6,time))
	for index in _plumes.size():
		var plume := _plumes[index]
		plume.visible = impact > 0.001
		plume.scale = Vector3.ONE*impact*(0.65+float(index%4)*0.18)
		plume.position.y = 0.44+0.65*smoothstep(_arrival_time,_arrival_time+0.6,time)
	var shock_phase := clampf((time-_arrival_time)/0.4,0.0,1.0)
	_shock.set_shader_parameter("phase",shock_phase)
	_shock.set_shader_parameter("strength",sin(shock_phase*PI)*0.42)
	_light.position = _wave.position+Vector3(0.0,0.65,0.0)
	_light.light_energy = charge*0.15*(1.0-born)+born*fade*0.45+impact*1.3
	if time >= _release_time and not _released:
		_released = true
		_sparks.position = Vector3(0.0,0.65,0.45)
		_sparks.restart()
	if time >= _arrival_time and not _arrived:
		_arrived = true
		for particles in [_sparks,_smoke,_flare]:
			particles.position = Vector3(0.0,0.55,_reach-0.58)
			particles.restart()
