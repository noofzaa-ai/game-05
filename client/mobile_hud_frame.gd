extends Control
const UiArt := preload("res://client/mobile_ui_art.gd")
var frame_key := "trip"
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	UiArt.draw_frame(self, frame_key, Rect2(Vector2.ZERO, size))
