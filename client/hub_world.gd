extends Node3D
## The camp hub's world: the Blender-built clearing (art/maps/camp_hub/camp_hub.glb, made by
## tools/blender/build_camp_hub.py) plus what moves in it - the campfire's flames and flicker, the warp
## gate's cyan swirl, embers, fireflies - the night environment and the few real lights.
## Gameplay spots and colliders come from the glb's named empties (see the Blender script):
##   spots       name -> Vector3 (spawn, campfire, warp_gate, npc_<role>, light_forge, lantern_<n>)
##   solids      AABBs from the col_<name> empties (centre = position, half extents = scale)
##   half_extents the walkable rectangle from the `bounds` empty (x, z)
## Cheap for phones (GL Compatibility): 3 static meshes (one per material), 3 omni lights without
## shadows, CPU particles. Raw colours here are 3D world colours (not UI).

const SCENE := "res://art/maps/camp_hub/camp_training.glb"
const STORAGE_STATION_SCENE := "res://art/props/storage_station/storage_station.glb"
const MERCHANT_SHOP_SCENE := "res://art/props/merchant_shop/merchant_shop.glb"
const TAILOR_HOUSE_SCENE := "res://art/props/tailor_house/tailor_house.glb"
const FORGE_SCENE := "res://art/props/blacksmith_forge/blacksmith_forge.glb"
const FIRE_COLOR := Color(1.0, 0.56, 0.22)
const FIRE_ENERGY := 2.6
const GATE_COLOR := Color(0.3, 0.92, 1.0)
const GATE_ARCH_HEIGHT := 2.25  ## the portal disc's centre above the ground (the stone ring in the glb)
const GATE_ARCH_BACK := 1.3  ## how far north of the warp_gate spot the stone ring stands
const GATE_DISC_RADIUS := 1.78

var spots := {}
var solids: Array[AABB] = []
var half_extents := Vector2(12.5, 10.5)
var environment: Environment
var loaded := false

var _campfire_props: Node3D
var _refine_props: Node3D
var _upgrade_props: Node3D
var _visual_key := ""
var _farm_boundary_trees: Node3D
var _farm_extension: Node3D
var _base_half_extents := Vector2.ZERO
var _farm_plants: Node3D
var _farm_growth_key := ""
var _farm_check := 0.0
var _time := 0.0
var _fire_light: OmniLight3D
var _forge_light: OmniLight3D
var _gate_light: OmniLight3D
var _gate_disc: MeshInstance3D
var _gate_ring: MeshInstance3D


func _ready() -> void:
	_build_environment()
	loaded = _load_scene()
	spots["npc_relic_master"] = Vector3(-4.5,0,-6.0)
	solids.append(AABB(Vector3(-4.95,0,-6.4),Vector3(0.9,1.8,0.8)))
	solids.append_array(preload("res://client/modular_fence.gd").collision_boxes(preload("res://client/modular_fence.gd").training_segments()))
	var training_trees:=find_child("TrainingBoundaryTrees",true,false)
	if training_trees!=null:training_trees.hide()
	if not loaded:
		_fallback_ground()
	_build_campfire(spots.get("campfire", Vector3.ZERO))
	_build_plaza_sign()
	_build_gate(spots.get("warp_gate", Vector3(0.0, 0.0, -8.7)))
	_build_storage_station()
	_build_merchant_shop()
	_build_tailor_house()
	refresh_facilities()
	half_extents.x=maxf(half_extents.x,25.5)
	_build_forge_light(spots.get("light_forge", Vector3.INF))
	_build_fireflies()


func _process(delta: float) -> void:
	_time += delta
	_farm_check += delta
	if _farm_check >= 1.0:
		_farm_check = 0.0
		_update_farm_plants()
	if _fire_light != null:
		_fire_light.light_energy = FIRE_ENERGY + 0.45 * sin(_time * 11.0) + 0.3 * sin(_time * 17.3)
	if _forge_light != null:
		_forge_light.light_energy = 0.9 + 0.25 * sin(_time * 7.1) + 0.15 * sin(_time * 13.7)
	if _gate_light != null:
		_gate_light.light_energy = 1.3 + 0.35 * sin(_time * 1.6)
	if _gate_ring != null:
		var pulse := 0.5 + 0.5 * sin(_time * 2.2)
		_gate_ring.scale = Vector3(1.0 + 0.04 * pulse, 0.2, 1.0 + 0.04 * pulse)


## A position on the ground for a named spot (`fallback` if the glb has no such empty).
func spot(name: String, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return spots.get(name, fallback)


func _load_scene() -> bool:
	if not ResourceLoader.exists(SCENE):
		push_error("camp hub scenery is missing: " + SCENE)
		return false
	var packed := load(SCENE) as PackedScene
	if packed == null:
		return false
	var scene: Node3D = packed.instantiate()
	add_child(scene)
	for node in scene.get_children():
		var name := str(node.name)
		if node is MeshInstance3D:
			if name=="FarmBoundaryTrees": _farm_boundary_trees=node
			_prepare_mesh(node as MeshInstance3D)
		elif node is Node3D:
			var xf: Transform3D = (node as Node3D).transform
			if name == "bounds":
				var s := xf.basis.get_scale()
				half_extents = Vector2(s.x, s.z)
			elif name.begins_with("col_"):
				var half := xf.basis.get_scale()
				if name not in ["col_forge", "col_anvil", "col_counter", "col_weapon_rack"]:
					solids.append(AABB(xf.origin - half, half * 2.0))
			else:
				spots[name] = xf.origin
	return true


## The glTF import leaves vertex colours off (they would render white); the glow materials glow.
func _prepare_mesh(mesh: MeshInstance3D) -> void:
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mesh.mesh.get_surface_count():
		var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
		if source == null:
			continue
		var material := source.duplicate() as StandardMaterial3D
		material.metallic = 0.0
		material.roughness = 1.0
		material.metallic_specular = 0.0
		if str(mesh.name).contains("glow"):
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.vertex_color_use_as_albedo = false
			material.albedo_color = material.emission * 1.15
			material.emission_enabled = false
		else:
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = false
			material.albedo_color = Color.WHITE
		mesh.set_surface_override_material(i, material)


func _fallback_ground() -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.2, 0.1)
	plane.material = material
	mesh.mesh = plane
	add_child(mesh)
	spots = {"spawn": Vector3(0.0, 0.0, 3.6), "campfire": Vector3.ZERO, "warp_gate": Vector3(0.0, 0.0, -8.7)}


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.03, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.5, 0.78)
	environment.ambient_light_energy = 1.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.05, 0.07, 0.12)
	environment.fog_density = 0.028
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.9
	var holder := WorldEnvironment.new()
	holder.environment = environment
	add_child(holder)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.7
	moon.shadow_enabled = false
	add_child(moon)


func _additive(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	return material


func _build_campfire(at: Vector3) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	gradient.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.16
	flame_mesh.height = 0.32
	flame_mesh.radial_segments = 8
	flame_mesh.rings = 4
	flame_mesh.material = _additive(Color.WHITE)
	var flames := CPUParticles3D.new()
	flames.mesh = flame_mesh
	flames.amount = 40
	flames.lifetime = 0.85
	flames.direction = Vector3.UP
	flames.spread = 14.0
	flames.initial_velocity_min = 0.9
	flames.initial_velocity_max = 1.7
	flames.gravity = Vector3.ZERO
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.5
	flames.color_ramp = gradient
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.35
	flames.position = at + Vector3(0.0, 0.25, 0.0)
	add_child(flames)
	# embers drifting up past the camera's view of the fire
	var ember_mesh := QuadMesh.new()
	ember_mesh.size = Vector2(0.05, 0.05)
	var ember_material := _additive(Color(1.0, 0.6, 0.25))
	ember_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_mesh.material = ember_material
	var embers := CPUParticles3D.new()
	embers.mesh = ember_mesh
	embers.amount = 18
	embers.lifetime = 2.6
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 1.6
	embers.gravity = Vector3(0.3, 0.2, 0.0)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.4
	embers.position = at + Vector3(0.0, 0.6, 0.0)
	add_child(embers)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = FIRE_COLOR
	_fire_light.omni_range = 9.5
	_fire_light.omni_attenuation = 1.3
	_fire_light.shadow_enabled = false
	_fire_light.position = at + Vector3(0.0, 1.1, 0.0)
	add_child(_fire_light)


## The warp gate: a cyan swirl filling the stone ring, a glowing ring on the ground (walk into it),
## motes rising and a cyan light.
func _build_gate(at: Vector3) -> void:
	var portal := preload("res://client/warp_crystal.gd").new()
	portal.position = at
	add_child(portal)
	_gate_light = OmniLight3D.new()
	_gate_light.light_color = GATE_COLOR
	_gate_light.omni_range = 6.0
	_gate_light.light_energy = 1.3
	_gate_light.shadow_enabled = false
	_gate_light.position = at + Vector3(0, 2.0, -.8)
	add_child(_gate_light)


func _build_legacy_gate(at: Vector3) -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.3, 0.92, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * 2.4);
	float rim = smoothstep(0.62, 0.98, r) * (1.0 - smoothstep(0.98, 1.0, r));
	float core = (1.0 - smoothstep(0.0, 1.0, r)) * (0.35 + 0.45 * swirl);
	float alpha = clamp(core + rim * 1.2, 0.0, 1.0) * (1.0 - step(1.0, r));
	ALBEDO = tint.rgb * (0.6 + 0.8 * swirl * (1.0 - r * 0.5));
	ALPHA = alpha * 0.85;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", GATE_COLOR)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * GATE_DISC_RADIUS * 2.0
	quad.material = material
	_gate_disc = MeshInstance3D.new()
	_gate_disc.mesh = quad
	_gate_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate_disc.position = at + Vector3(0.0, GATE_ARCH_HEIGHT, -GATE_ARCH_BACK + 0.05)
	add_child(_gate_disc)

	var torus := TorusMesh.new()
	torus.inner_radius = 1.32
	torus.outer_radius = 1.5
	torus.rings = 32
	torus.ring_segments = 4
	torus.material = _additive(Color(0.35, 0.95, 1.0, 0.9))
	_gate_ring = MeshInstance3D.new()
	_gate_ring.mesh = torus
	_gate_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate_ring.position = at + Vector3(0.0, 0.06, 0.0)
	_gate_ring.scale = Vector3(1.0, 0.2, 1.0)
	add_child(_gate_ring)

	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2(0.07, 0.07)
	var mote_material := _additive(Color(0.5, 1.0, 1.0))
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mesh.material = mote_material
	var motes := CPUParticles3D.new()
	motes.mesh = mote_mesh
	motes.amount = 24
	motes.lifetime = 2.2
	motes.direction = Vector3.UP
	motes.spread = 8.0
	motes.initial_velocity_min = 0.5
	motes.initial_velocity_max = 1.1
	motes.gravity = Vector3.ZERO
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 1.4
	motes.emission_ring_inner_radius = 1.2
	motes.emission_ring_height = 0.05
	motes.position = at + Vector3(0.0, 0.1, 0.0)
	add_child(motes)

	_gate_light = OmniLight3D.new()
	_gate_light.light_color = GATE_COLOR
	_gate_light.omni_range = 6.0
	_gate_light.omni_attenuation = 1.4
	_gate_light.shadow_enabled = false
	_gate_light.position = at + Vector3(0.0, 1.6, -0.6)
	add_child(_gate_light)


func _build_plaza_sign() -> void:
	var sign := Label3D.new()
	sign.text = "ลานรวมพล · Gathering Plaza"
	sign.font = preload("res://art/fonts/Sarabun-Regular.woff2")
	sign.position = spots.get("plaza_entry", Vector3(0, 0, -12.5)) + Vector3(0, 2.5, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 40
	sign.pixel_size = .006
	sign.modulate = Color("e9c577")
	add_child(sign)


func _build_storage_station() -> void:
	if not ResourceLoader.exists(STORAGE_STATION_SCENE): return
	var packed := load(STORAGE_STATION_SCENE) as PackedScene
	if packed == null: return
	var station := packed.instantiate() as Node3D
	station.name = "StorageStation"
	station.position = spots.get("storage_station", Vector3(-4.2, 0, 7.6))
	add_child(station)
	for mesh in station.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_merchant_shop() -> void:
	if not ResourceLoader.exists(MERCHANT_SHOP_SCENE): return
	var packed := load(MERCHANT_SHOP_SCENE) as PackedScene
	if packed == null: return
	var shop := packed.instantiate() as Node3D
	shop.name = "MerchantShop"
	shop.position = spots.get("merchant_shop", Vector3(9.4, 0, 4.4))
	add_child(shop)
	for mesh in shop.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_tailor_house() -> void:
	if not ResourceLoader.exists(TAILOR_HOUSE_SCENE): return
	var packed := load(TAILOR_HOUSE_SCENE) as PackedScene
	if packed == null: return
	var house := packed.instantiate() as Node3D
	house.name = "TailorHouse"
	house.position = spots.get("tailor_house", Vector3(-8.6, 0, -4.6))
	add_child(house)
	for mesh in house.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func refresh_facilities() -> void:
	var profile = GameState.profile
	var camp_level := clampi(int(profile.camp_level) if profile != null else 1, 1, 3)
	var refine_level := clampi(int(profile.facility_levels.get("workbench", 1)) if profile != null else 1, 1, 3)
	var upgrade_level := clampi(int(profile.facility_levels.get("armory", 1)) if profile != null else 1, 1, 3)
	var key := "%d/%d/%d" % [camp_level, refine_level, upgrade_level]
	if key == _visual_key: return
	_visual_key = key
	_refresh_farm(camp_level)
	for old in [_campfire_props, _refine_props, _upgrade_props]:
		if is_instance_valid(old): remove_child(old); old.queue_free()
	_campfire_props = _facility_model("res://art/props/campfire_workshop/campfire_level_%d.glb" % camp_level, spot("campfire"))
	_refine_props = _facility_model("res://art/props/camp_modular/workshops/refine_lv%d.glb" % refine_level, Vector3(8, 0, -6.2))
	_upgrade_props = _facility_model("res://art/props/camp_modular/workshops/upgrade_lv%d.glb" % upgrade_level, Vector3(8, 0, -0.4))
	spots["npc_bs_refine"] = Vector3(8, 0, -3.2)
	spots["npc_bs_upgrade"] = Vector3(8, 0, 2.6)
	if not spots.has("workshop_collisions"):
		spots["workshop_collisions"] = Vector3.ZERO
		for box in [AABB(Vector3(6.5, 0, -7.2), Vector3(3, 2.8, 1.7)), AABB(Vector3(6.7, 0, -4.3), Vector3(2.6, 0.9, 0.5)), AABB(Vector3(6.7, 0, 1.2), Vector3(2.6, 0.9, 0.5))]: solids.append(box)

func _facility_model(path: String, at: Vector3) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null: return null
	var model := packed.instantiate() as Node3D
	model.position = at
	add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


func _build_forge_effects(forge: Node3D) -> void:
	# Soft procedural texture: no external images, very few billboard particles.
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = fade
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var fire_material := StandardMaterial3D.new()
	fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_material.vertex_color_use_as_albedo = true
	fire_material.albedo_texture = texture
	fire_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.25, 0.45)
	flame_mesh.material = fire_material
	var flames := CPUParticles3D.new()
	flames.name = "FurnaceFlames"
	flames.mesh = flame_mesh
	flames.amount = 18
	flames.lifetime = 0.8
	flames.preprocess = 0.8
	flames.position = Vector3(-0.29, 0.77, -0.90)
	flames.direction = Vector3.UP
	flames.spread = 12
	flames.initial_velocity_min = 0.25
	flames.initial_velocity_max = 0.65
	flames.gravity = Vector3.ZERO
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.28, 0.03, 0.08)
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.3
	var fire_colors := Gradient.new()
	fire_colors.offsets = PackedFloat32Array([0, 0.25, 0.75, 1])
	fire_colors.colors = PackedColorArray([Color(1, 0.85, 0.3, 0), Color(1, 0.65, 0.12, 0.85), Color(1, 0.19, 0.025, 0.45), Color(0.8, 0.08, 0.01, 0)])
	flames.color_ramp = fire_colors
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	forge.add_child(flames)
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_material.vertex_color_use_as_albedo = true
	smoke_material.albedo_texture = texture
	smoke_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(0.65, 0.65)
	smoke_mesh.material = smoke_material
	var smoke := CPUParticles3D.new()
	smoke.name = "ChimneySmoke"
	smoke.mesh = smoke_mesh
	smoke.amount = 12
	smoke.lifetime = 3.4
	smoke.preprocess = 3.4
	# Measured from the supplied model's chimney rim in normalized game coordinates.
	smoke.position = Vector3(-0.306, 2.66, -0.803)
	smoke.direction = Vector3.UP
	smoke.spread = 8
	smoke.initial_velocity_min = 0.45
	smoke.initial_velocity_max = 0.7
	smoke.gravity = Vector3(0.05, 0.04, -0.025)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.08
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.0
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.35))
	growth.add_point(Vector2(1, 1.8))
	smoke.scale_amount_curve = growth
	var smoke_colors := Gradient.new()
	smoke_colors.offsets = PackedFloat32Array([0, 0.15, 0.65, 1])
	smoke_colors.colors = PackedColorArray([Color(0.22, 0.24, 0.27, 0), Color(0.35, 0.37, 0.4, 0.4), Color(0.42, 0.44, 0.47, 0.22), Color(0.5, 0.52, 0.55, 0)])
	smoke.color_ramp = smoke_colors
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	forge.add_child(smoke)


func _build_forge_light(at: Vector3) -> void:
	if at == Vector3.INF:
		return
	_forge_light = OmniLight3D.new()
	_forge_light.light_color = Color(1.0, 0.5, 0.2)
	_forge_light.omni_range = 4.0
	_forge_light.shadow_enabled = false
	_forge_light.position = at + Vector3(-0.29, 1.1, -0.85)
	add_child(_forge_light)


func _build_fireflies() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	var material := _additive(Color(0.85, 1.0, 0.55))
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = material
	var flies := CPUParticles3D.new()
	flies.mesh = mesh
	flies.amount = 36
	flies.lifetime = 5.0
	flies.preprocess = 5.0
	flies.direction = Vector3.UP
	flies.spread = 180.0
	flies.initial_velocity_min = 0.1
	flies.initial_velocity_max = 0.35
	flies.gravity = Vector3.ZERO
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(half_extents.x + 1.0, 0.8, half_extents.y + 1.0)
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.3, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.7, Color(1.0, 1.0, 1.0, 0.8))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	flies.color_ramp = fade
	flies.position = Vector3(0.0, 1.2, 0.0)
	add_child(flies)


func _refresh_farm(level: int) -> void:
	if is_instance_valid(_farm_boundary_trees): _farm_boundary_trees.visible=level<2
	if _base_half_extents == Vector2.ZERO: _base_half_extents = half_extents
	half_extents = _base_half_extents
	half_extents.x=maxf(half_extents.x,25.5)
	if is_instance_valid(_farm_extension):
		remove_child(_farm_extension)
		_farm_extension.queue_free()
		_farm_extension = null
	if level < 2: return
	_farm_extension = Node3D.new()
	_farm_extension.name = "CampVegetableFarm"
	add_child(_farm_extension)
	var edge := _base_half_extents.x
	half_extents.x=maxf(half_extents.x,_base_half_extents.x+9.0)
	_farm_box(Vector3(edge + 4.0, -.12, -3.3), Vector3(10, .2, 11), Color("344936"))
	# Plot IDs and crop positions share this function; rows follow the two shops.
	for index in range(4):
		var at:=farm_plot_position(index)
		_farm_box(at+Vector3(0,.04,0),Vector3(2.6,.12,2.6),Color("503c2b"))
		for row in range(4):
			_farm_box(at+Vector3(0,.12,-.85+row*.55),Vector3(2.2,.08,.16),Color("705039"))
	for z in [-6.2,-.4]:
		_farm_box(Vector3(edge+3.0,.005,z+1.85),Vector3(9,.03,.8),Color("8b7955"))
	_farm_box(Vector3(edge+.3,.005,-3.3),Vector3(.8,.03,6.6),Color("8b7955"))
	preload("res://client/modular_fence.gd").build(_farm_extension,preload("res://client/modular_fence.gd").farm_segments(edge))
	var label := Label3D.new()
	label.text = "พื้นที่ฟาร์ม · ปลดล็อกกองไฟ Lv.2"
	label.position = Vector3(edge + 4, 1.5, -8.0)
	label.font_size = 38
	label.pixel_size = .012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_farm_extension.add_child(label)

func _farm_box(at: Vector3, dimensions: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	visual.mesh = box
	visual.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_farm_extension.add_child(visual)

func farm_boundaries() -> Array[AABB]:
	var result: Array[AABB] = []
	if _base_half_extents == Vector2.ZERO: return result
	var edge := _base_half_extents.x
	# West training clearing is always open; other forest edges remain blocked.
	result.append(AABB(Vector3(-edge-20,-1,-60),Vector3(20,8,58)))
	result.append(AABB(Vector3(-edge-20,-1,11),Vector3(20,8,49)))
	if is_instance_valid(_farm_extension):
		result.append_array(preload("res://client/modular_fence.gd").collision_boxes(preload("res://client/modular_fence.gd").farm_segments(edge)))
		result.append(AABB(Vector3(edge, -1, -60), Vector3(12, 8, 51.5)))
		result.append(AABB(Vector3(edge, -1, 2.5), Vector3(12, 8, 66)))
	else:result.append(AABB(Vector3(edge,-1,-60),Vector3(20,8,120)))
	return result

func farm_plot_position(index:int)->Vector3:
	return Vector3(_base_half_extents.x + (2.0 if index%2==0 else 5.5),0,-6.2 if index<2 else -.4)

func _update_farm_plants() -> void:
	if not is_instance_valid(_farm_extension) or GameState.profile == null: return
	var planted: Dictionary = GameState.profile.farm.get("plots",{})
	var crops: Dictionary = preload("res://logic/farm.gd").config().crops
	var stages := {}
	for key in planted:
		var row: Dictionary = planted[key]
		if not crops.has(row.crop): continue
		var progress := clampf((Time.get_unix_time_from_system()-float(row.planted_at))/float(crops[row.crop].seconds),0,1)
		stages[key] = {"crop":row.crop,"stage":mini(3,int(progress*4))}
	var signature := str(stages)
	if signature == _farm_growth_key and is_instance_valid(_farm_plants): return
	_farm_growth_key = signature
	if is_instance_valid(_farm_plants): _farm_plants.queue_free()
	_farm_plants = Node3D.new();_farm_extension.add_child(_farm_plants)
	for key in stages:
		var row: Dictionary = stages[key]
		var stage := int(row.stage)
		if stage == 0: continue
		for offset in [Vector3(-.6,0,-.6),Vector3(.6,0,-.6),Vector3(-.6,0,.6),Vector3(.6,0,.6)]:
			var at: Vector3 = farm_plot_position(int(key))+Vector3(offset)
			var plant := preload("res://client/farm_crop_sprite.gd").new()
			plant.name = "Plant_%s_%d" % [key,_farm_plants.get_child_count()]
			plant.position = at + Vector3(0,.15,0)
			plant.setup(str(row.crop),stage)
			_farm_plants.add_child(plant)
