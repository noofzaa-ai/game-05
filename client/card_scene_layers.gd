extends Control
## Painted 3-layer depth scene inside a class card window (Boss 2026-11-13; art/ui/class_cards/scene/,
## from art_source/ui/class_cards/v11/card_scene). Back to front: far (opaque), mid, the soft contact shadow,
## [the live 3D character, drawn by the caller], near. One instance draws Part.BACK (far + mid + shadow), a
## second one Part.FRONT (near) above the character. Both are plain canvas draws inside the card's existing
## window clip: no viewport, no shader of their own; they redraw only when the tilt or the size changes, so a
## card that is not tilting costs three static textured quads.
## API: setup(class_id, part) -> bool (false = no art: the caller keeps its flat backdrop), set_depth(tilt,
## figure_shift), set_feet(y), set_locked(on), set_clip(mat).

const CardTokens := preload("res://client/card_tokens.gd")

enum Part { BACK, FRONT }

var part := Part.BACK
var class_id := ""
var tilt := Vector2.ZERO  ## -1..1 (x right, y down)
var figure_shift := Vector2.ZERO  ## px: how far the character is shifted (the shadow stays under its feet)
var feet_y := 0.9  ## where the character's feet stand, fraction of the window height
var locked := false
var _far: Texture2D
var _mid: Texture2D
var _near: Texture2D
var _clip: Material


## The painted layers of `id` exist (all three).
static func has_scene(id: String) -> bool:
	for layer in ["far", "mid", "near"]:
		if not ResourceLoader.exists(_path(id, layer)):
			return false
	return true


static func _path(id: String, layer: String) -> String:
	return CardTokens.SCENE_ART_DIR + id + "_" + layer + ".png"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func setup(id: String, p_part: Part) -> bool:
	part = p_part
	class_id = id
	var ok := has_scene(id)
	_far = load(_path(id, "far")) as Texture2D if ok and part == Part.BACK else null
	_mid = load(_path(id, "mid")) as Texture2D if ok and part == Part.BACK else null
	_near = load(_path(id, "near")) as Texture2D if ok and part == Part.FRONT else null
	visible = ok
	queue_redraw()
	return ok


func set_depth(p_tilt: Vector2, p_figure_shift: Vector2) -> void:
	if p_tilt.is_equal_approx(tilt) and p_figure_shift.is_equal_approx(figure_shift):
		return
	tilt = p_tilt
	figure_shift = p_figure_shift
	queue_redraw()


func set_feet(y: float) -> void:
	feet_y = y
	queue_redraw()


## Locked card: greyed and darkened like the character.
func set_locked(on: bool) -> void:
	locked = on
	modulate = CardTokens.HUB_LOCKED if on else CardTokens.HUB_WHITE
	_apply_material()


## The card's window clip material while it is tilted (client/card_tilt_clip.gdshader), null when flat.
func set_clip(mat: Material) -> void:
	_clip = mat
	_apply_material()


func _apply_material() -> void:
	material = _clip if _clip != null else (CardTokens.grey_material() if locked else null)


## Layer scale: the art covers the reference window (CardTokens.SCENE_WINDOW on the 1000x1460 layer) at any
## window size or aspect, the overscan left over hides the edges during the parallax.
func _layer_rect(shift: Vector2, raise: float) -> Rect2:
	var k := maxf(size.x / CardTokens.SCENE_WINDOW.x, size.y / CardTokens.SCENE_WINDOW.y)
	var layer := CardTokens.SCENE_LAYER * k
	var at := (size - layer) * 0.5 + shift * size - Vector2(0.0, raise * k)
	return Rect2(at, layer)


func _draw() -> void:
	if part == Part.BACK:
		if _far == null:
			return
		draw_texture_rect(_far, _layer_rect(-tilt * CardTokens.SCENE_FAR_PARALLAX, 0.0), false)
		draw_texture_rect(_mid, _layer_rect(-tilt * CardTokens.SCENE_MID_PARALLAX, 0.0), false)
		var shadow_size := size * CardTokens.SCENE_SHADOW_SIZE
		var centre := Vector2(size.x * 0.5, size.y * feet_y) + figure_shift
		draw_texture_rect(CardTokens.scene_shadow(), Rect2(centre - shadow_size * 0.5, shadow_size), false)
		return
	if _near == null:
		return
	# Near: raised above the frame's bottom plate; its bottom row is opaque ground, so the source rect runs past
	# the texture (clamped edge row) to keep the ground under the plate at any tilt.
	var rect := _layer_rect(tilt * CardTokens.SCENE_NEAR_PARALLAX, CardTokens.SCENE_NEAR_RAISE)
	var extend := CardTokens.SCENE_NEAR_EXTEND
	rect.size.y *= 1.0 + extend
	var tex_size := _near.get_size()
	draw_texture_rect_region(_near, rect, Rect2(Vector2.ZERO, Vector2(tex_size.x, tex_size.y * (1.0 + extend))))
