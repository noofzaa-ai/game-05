extends Node3D
## Root anchor shared by every stage: pixel (128,240) in a 256px canvas.
const ROOT := "res://art/props/farm_crops/"
const PIXEL_SIZE := .0048
static var _textures: Dictionary = {}
static func texture(crop: String, stage: int) -> Texture2D:
	if crop not in ["carrot", "potato", "herb"] or stage not in [1,2,3]: return null
	var path := ROOT + "%s_stage_%d.png" % [crop,stage]
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]
static func icon(crop: String) -> Texture2D:
	if crop not in ["carrot", "potato", "herb"]: return null
	var path := ROOT + crop + "_icon.png"
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]
func setup(crop: String, stage: int) -> void:
	var image := texture(crop,stage)
	if image == null: return
	var sprite := Sprite3D.new()
	sprite.name = "PlantSprite"
	sprite.texture = image
	sprite.pixel_size = PIXEL_SIZE
	# The ground is y=.15. Raise the image centre so pixel240 lands at the root.
	sprite.position.y = (240.0-128.0)*PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = true
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = .25
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
