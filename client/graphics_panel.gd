extends CanvasLayer
## Non-pausing overlay: online combat continues while this panel is open.
const Options := preload("res://client/graphics_options.gd")
var dock_right_of := Rect2()

const Ink := preload("res://client/ink_ui.gd")

static func contents(two_columns: bool = false) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var quality := Label.new()
	var names := ["Normal · 50%", "High · 75%", "Ultra · 100%"]
	var selected := Options.SCALES.find(Options.value("render_scale"))
	quality.text = "ความละเอียด 3D · " + names[selected]
	box.add_child(quality)
	var resolution := HSlider.new()
	resolution.min_value = 0
	resolution.max_value = 2
	resolution.step = 1
	resolution.tick_count = 3
	resolution.ticks_on_borders = true
	resolution.custom_minimum_size = Vector2(260, 36)
	resolution.value = selected
	resolution.value_changed.connect(func(index: float):
		var choice := int(index)
		Options.set_value("render_scale", Options.SCALES[choice])
		quality.text = "ความละเอียด 3D · " + names[choice])
	box.add_child(resolution)
	var stops := HBoxContainer.new()
	for text in ["Normal", "High", "Ultra"]:
		var label := Label.new()
		label.text = text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stops.add_child(label)
	box.add_child(stops)
	for entry in [["outline", "เส้นขอบโมเดล (Outline)"], ["ultimate_vfx", "เอฟเฟกต์อัลติ"], ["combat_vfx", "เอฟเฟกต์ต่อสู้ / ริ้วอาวุธ"], ["ultimate_camera", "กล้องอัลติ"], ["shadows", "เงาฉาก"], ["decorative_lights", "แสงตกแต่ง"], ["fog", "หมอก"], ["glow", "แสงฟุ้ง"]]:
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.button_pressed = Options.enabled(entry[0])
		toggle.toggled.connect(func(value: bool): Options.set_enabled(entry[0], value))
		box.add_child(toggle)
	var aa_names := ["ปิด", "2×", "4×"]
	var aa_values := [0, 2, 4]
	var aa_title := Label.new()
	aa_title.text = "ลบรอยหยัก · " + aa_names[aa_values.find(Options.value("antialiasing"))]
	box.add_child(aa_title)
	var aa := HSlider.new()
	aa.min_value = 0
	aa.max_value = 2
	aa.step = 1
	aa.tick_count = 3
	aa.ticks_on_borders = true
	aa.custom_minimum_size = Vector2(260, 36)
	aa.value = aa_values.find(Options.value("antialiasing"))
	aa.value_changed.connect(func(index: float):
		var choice := int(index)
		Options.set_value("antialiasing", aa_values[choice])
		aa_title.text = "ลบรอยหยัก · " + aa_names[choice])
	box.add_child(aa)
	var aa_stops := HBoxContainer.new()
	for text in aa_names:
		var label := Label.new()
		label.text = text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		aa_stops.add_child(label)
	box.add_child(aa_stops)
	var hint := Label.new()
	hint.text = "ลดความละเอียดเฉพาะฉาก 3D · UI เท่าเดิม"
	box.add_child(hint)
	if two_columns:
		var controls := box.get_children()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		box.add_child(row)
		box.move_child(row, 0)
		var left := VBoxContainer.new()
		var right := VBoxContainer.new()
		for column in [left, right]:
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_theme_constant_override("separation", 10)
			row.add_child(column)
		# Each column starts with a slider, then four effect switches.
		for index in [0, 1, 2, 3, 4, 5, 6]: controls[index].reparent(left)
		for index in [11, 12, 13, 7, 8, 9, 10]: controls[index].reparent(right)
	return box

func _ready() -> void:
	layer = 30
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme = Ink.make_theme(Ink.FONT_BODY)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "กราฟิก"
	var header := HBoxContainer.new()
	header.add_child(title)
	box.add_child(header)
	Ink.add_close(header, queue_free)
	var settings := contents(true)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(settings)
	var note := Label.new()
	note.text = "จำค่าบนอุปกรณ์นี้ · เกมยังดำเนินต่อ"
	box.add_child(note)
	_fit_overlay.call_deferred(panel)
	get_viewport().size_changed.connect(func(): _fit_overlay.call_deferred(panel))
	if dock_right_of.size != Vector2.ZERO:
		_dock.call_deferred(panel, center)

func _fit_overlay(panel: PanelContainer) -> void:
	if not is_instance_valid(panel): return
	var area := get_viewport().get_visible_rect().size - Vector2(24, 24)
	var minimum := panel.get_combined_minimum_size()
	var fit := minf(1.0, minf(area.x / maxf(1, minimum.x), area.y / maxf(1, minimum.y)))
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * fit

func _dock(panel: PanelContainer, center: CenterContainer) -> void:
	var area := get_viewport().get_visible_rect().size
	var width := panel.get_combined_minimum_size().x
	var x := dock_right_of.end.x + 12.0
	if x + width + 12.0 > area.x: return
	panel.reparent(self)
	panel.position = Vector2(x, clampf(dock_right_of.position.y, 12.0, maxf(12.0, area.y - panel.size.y - 12.0)))
	center.queue_free()
