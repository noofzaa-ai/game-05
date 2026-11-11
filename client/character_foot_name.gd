extends Label3D
## Shared readable name below a character's feet, outside the body silhouette.
func _init() -> void:
	font = preload("res://art/fonts/Sarabun-Regular.woff2")
	position = Vector3(0.0, 0.06, 0.65)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	font_size = 48
	pixel_size = .0055
	modulate = Color("f4dfa9")
	outline_modulate = Color("101a22")
	outline_size = 8
	no_depth_test = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
