extends MeshInstance3D
## The race ground marker of a squad card in battle (design/gdd/races-and-classes.md 3.8 mockup row "Battle: ground
## marker"): a thin ring in the race colour at the fighter's feet; Runeborn gets the turning glyph ring. It reuses the
## existing ground layer shader of the effects (client/vfx/vfx_ground.gdshader, modes ring / glyph) held at a fixed
## progress, so it needs no new art. Colours come from the race file `mockup` block (client/card_tokens.gd).
## Display only: client/fighter_view.gd adds one under a squad fighter whose race_state names a race.

const CardTokens := preload("res://client/card_tokens.gd")
const GROUND_SHADER := preload("res://client/vfx/vfx_ground.gdshader")
const GROUND_MODES := ["ring", "crack", "stain", "glyph"]  ## the shader's `mode` order (client/vfx/vfx_library.gd GROUND_MODES)

var race := ""
var motion := true  ## false: the glyph does not turn (reduced motion)
var _material: ShaderMaterial
var _spin := 0.0


func setup(race_id: String) -> void:
	race = race_id
	var quad := QuadMesh.new()
	quad.size = Vector2(CardTokens.RACE_RING_SIZE, CardTokens.RACE_RING_SIZE)
	mesh = quad
	rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	position = Vector3(0.0, CardTokens.RACE_RING_LIFT, 0.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = GROUND_SHADER
	var glyph: bool = race_id in CardTokens.RACE_RING_GLYPH
	_material.set_shader_parameter("mode", GROUND_MODES.find("glyph" if glyph else "ring"))
	_material.set_shader_parameter("color", CardTokens.race_ring(race_id))
	_material.set_shader_parameter("ink", 0.0)
	_material.set_shader_parameter("seed", 0.0)
	_material.set_shader_parameter("progress", CardTokens.RACE_GLYPH_PROGRESS if glyph else CardTokens.RACE_RING_PROGRESS)
	_material.set_shader_parameter("opacity", CardTokens.RACE_GLYPH_OPACITY if glyph else CardTokens.RACE_RING_OPACITY)
	material_override = _material
	set_process(glyph)


func _process(delta: float) -> void:
	if motion:
		_spin = fmod(_spin + delta * CardTokens.RACE_GLYPH_SPIN, TAU)
		_material.set_shader_parameter("spin", _spin)
