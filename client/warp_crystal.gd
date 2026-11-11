extends Node3D
## Crystal portal visual only. The hub owns warp interaction/admission.
const SCENE := preload("res://art/props/warp_crystal/warp_crystal.glb")
var rotor: Node3D

func _ready() -> void:
	var model := SCENE.instantiate()
	add_child(model)
	rotor = model.find_child("CrystalRotor", true, false) as Node3D
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if rotor != null:
		for mesh in [rotor] + rotor.find_children("*", "MeshInstance3D", true, false):
			if not mesh is MeshInstance3D: continue
			for index in mesh.mesh.get_surface_count():
				var material = mesh.mesh.surface_get_material(index).duplicate()
				if material is StandardMaterial3D:
					material.emission_enabled = true
					material.emission = Color(.12, .5, .8)
					material.emission_energy_multiplier = .65
				mesh.set_surface_override_material(index, material)
		var aura := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.4, 4.1)
		var mat := _soft_material(true)
		mat.albedo_color = Color(.2, .75, 1, .3)
		quad.material = mat
		aura.mesh = quad
		aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(aura)
		aura.global_position = rotor.global_position
	_build_sparkles()
	_build_mist()

func _process(delta: float) -> void:
	# Rotate around WORLD up, never pitch/roll or move the top point down.
	if rotor != null: rotor.global_rotate(Vector3.UP, -.42 * delta)

func _soft_material(additive: bool) -> StandardMaterial3D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1,1,1,.8))
	ramp.set_color(1, Color(1,1,1,0))
	var tex := GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.gradient = ramp
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(.5,.5)
	tex.fill_to = Vector2(1,.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _build_sparkles() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment(){
 vec2 p=UV*2.0-1.0;
 float star=exp(-length(p)*5.0)*(.2+max(exp(-abs(p.x)*28.0),exp(-abs(p.y)*28.0)));
 ALBEDO=vec3(.4,.85,1.0)*COLOR.rgb;ALPHA=star*COLOR.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# CPU particle mesh billboard needs a material vertex transform.
	shader.code = shader.code.replace("void fragment(){", "void vertex(){ MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]); }\nvoid fragment(){")
	var quad := QuadMesh.new()
	quad.size = Vector2(.14,.14)
	quad.material = mat
	var particles := CPUParticles3D.new()
	particles.name = "WarpSparkles"
	particles.mesh = quad
	particles.amount = 24
	particles.lifetime = 2.4
	particles.preprocess = 2.4
	particles.position = Vector3(0,.15,-.4)
	particles.direction = Vector3.UP
	particles.spread = 28
	particles.initial_velocity_min = .5
	particles.initial_velocity_max = 1.5
	particles.gravity = Vector3.ZERO
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = 1.8
	particles.emission_ring_inner_radius = .7
	particles.emission_ring_height = .1
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.add_point(.15,Color(.4,.9,1,1))
	fade.set_color(0,Color(.4,.9,1,0))
	fade.set_color(1,Color(.4,.9,1,0))
	particles.color_ramp = fade
	add_child(particles)

func _build_mist() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2,.8)
	quad.material = _soft_material(false)
	var mist := CPUParticles3D.new()
	mist.name = "WarpMist"
	mist.mesh = quad
	mist.amount = 20
	mist.lifetime = 2.6
	mist.preprocess = 2.6
	mist.position = Vector3(0,.15,.3)
	mist.direction = Vector3.UP
	mist.spread = 65
	mist.initial_velocity_min = .25
	mist.initial_velocity_max = .65
	mist.gravity = Vector3(0,.04,0)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	mist.emission_ring_axis = Vector3.UP
	mist.emission_ring_radius = 1.7
	mist.emission_ring_inner_radius = 1.25
	mist.emission_ring_height = .1
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.set_color(0,Color(.4,.7,.85,0))
	fade.add_point(.2,Color(.5,.8,1,.2))
	fade.set_color(1,Color(.5,.8,1,0))
	mist.color_ramp = fade
	var growth := Curve.new()
	growth.max_value = 2
	growth.add_point(Vector2(0,.45))
	growth.add_point(Vector2(1,1.8))
	mist.scale_amount_curve = growth
	add_child(mist)
