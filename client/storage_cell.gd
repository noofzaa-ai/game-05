extends "res://client/item_cell.gd"
## Storage adds material-stack dragging. The payload is only a local UI reference.
var source := ""
var entry := {}
var owner_panel := 0
var locked := false

func _get_drag_data(_at_position: Vector2) -> Variant:
	if locked or not has_thing(): return null
	var preview := Control.new()
	var ghost = get_script().new()
	ghost.copy_look(self)
	ghost.size = size
	ghost.position = -size * 0.5
	ghost.modulate.a = 0.8
	preview.add_child(ghost)
	preview.scale = get_global_transform().get_scale()
	set_drag_preview(preview)
	return {"cell": self}
