extends RefCounted
## Keep reference geometry independent from the atlas sprite sizes/padding.
const UiArt := preload("res://client/mobile_ui_art.gd")

static func texture(action: String) -> Texture2D:
	return UiArt.texture(action)

static func texture_rect(action: String, body_size: Vector2) -> Rect2:
	var region: Rect2 = UiArt.REGIONS[action]
	var body: Rect2 = UiArt.BODIES[action]
	return Rect2(-(body.position-region.position) / body.size * body_size, region.size / body.size * body_size)
