extends Node2D
## Compact A-style pickups: existing icons, rounded text, no panel or per-pickup Tween.
const InkUi = preload("res://client/ink_ui.gd")
const FACE = preload("res://art/fonts/ChangaOne-Italic.ttf")
const CAP := 20
const LIFE := 1.5
var slots: Array = []
var sequence := 0
var face: Font

func _ready() -> void:
	face = FACE.duplicate()
	face.fallbacks = [InkUi.font()] # Existing Thai UI face; never show missing-glyph squares.
	for i in range(CAP):
		var row := Control.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(24,24)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var label := Label.new()
		label.add_theme_font_override("font",face)
		label.add_theme_font_size_override("font_size",18)
		label.add_theme_constant_override("outline_size",3)
		label.add_theme_color_override("font_outline_color",Color("211611"))
		label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.65))
		label.add_theme_constant_override("shadow_offset_y",2)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		row.hide()
		slots.append({"row":row,"icon":icon,"label":label,"age":LIFE})

func show_pickup(at: Vector3, text: String, color: Color, icon: Texture2D = null, line: int = 0) -> void:
	var selected := 0
	var oldest := -1.0
	for i in range(CAP):
		if slots[i].age >= LIFE: selected=i;break
		if slots[i].age>oldest:oldest=slots[i].age;selected=i
	var slot: Dictionary=slots[selected]
	sequence+=1
	slot.age=0.0;slot.at=at+Vector3(0,0.6,0);slot.line=mini(line,4);slot.sequence=sequence
	slot.icon.texture=icon;slot.icon.visible=icon!=null
	slot.label.text=text
	slot.label.add_theme_color_override("font_color",color)
	var icon_room := 28.0 if icon!=null else 0.0
	var text_width := minf(face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+7.0,220.0)
	slot.label.position=Vector2(icon_room,-1)
	slot.label.size=Vector2(text_width,26)
	slot.width=icon_room+text_width
	slot.row.modulate=Color.WHITE
	slot.row.show()

static func responsive_scale(viewport_size: Vector2) -> float:
	return clampf(viewport_size.y/720.0,0.9,1.15)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var area := get_viewport_rect().size
	var factor := responsive_scale(area)
	for slot in slots:
		if slot.age>=LIFE:continue
		slot.age+=delta
		if slot.age>=LIFE:slot.row.hide();continue
		if camera==null or camera.is_position_behind(slot.at):slot.row.hide();continue
		slot.row.show()
		var width: float=slot.width
		var point := camera.unproject_position(slot.at)
		point+=Vector2(-width*factor*0.5,-slot.age*24.0-slot.line*27.0*factor)
		slot.row.scale=Vector2.ONE*factor
		# Pickups remain legible at screen edges, without entering touch UI hit testing.
		slot.row.position=Vector2(clampf(point.x,8,maxf(8,area.x-width*factor-8)),clampf(point.y,8,maxf(8,area.y-28*factor-8)))
		slot.row.modulate.a=1.0-smoothstep(0.8,LIFE,float(slot.age))
