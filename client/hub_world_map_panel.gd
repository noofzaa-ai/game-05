extends "res://client/hub_service_panel.gd"
## World map (Boss 2026-11-16, boss-farming game): the zones of data/world/zones.json on the archipelago map
## (logic/world_zones.gd). An open zone is lit and tappable, a locked one sits under the fog with a padlock, a
## zone with no journey yet reads "coming soon". The details on the right name the zone, its boss and how it
## opens. Display only: which zone is open comes from the server-set boss flags in the profile.

const Zones := preload("res://logic/world_zones.gd")

var selected := ""
var _map_frame: Panel
var _map: TextureRect
var _mat: ShaderMaterial
var _markers := {}  ## zone id -> Button
var _info: Label
var _info_title: Label
var _go: Button


func _init() -> void:
	service = "map"
	full_screen = true  # the map needs the room (phones especially)


func build() -> void:
	_map_frame = Panel.new()
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_map_frame)
	_map = TextureRect.new()
	_map.texture = load(str(Zones.data().get("image", "res://art/ui/world_map/archipelago.png")))
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://client/world_map.gdshader")
	_map.material = _mat
	_map_frame.add_child(_map)
	for z in Zones.zones():
		var b := Button.new()
		b.name = "Zone_" + str(z.id)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(select_zone.bind(str(z.id)))
		_map_frame.add_child(b)
		_markers[str(z.id)] = b
	_info_title = CardTokens.label("", CardTokens.FONT_HUB_PANEL_TITLE, CardTokens.HUB_INK, 1.0)
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_child(_info_title)
	_info = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_child(_info)
	_go = plate(CardTokens.t("map_go"), _go_pressed)
	body.add_child(_go)


func open() -> void:
	if selected.is_empty():
		selected = str(Zones.current_zone(_profile()).get("id", ""))
	super.open()


func first_focus() -> Control:
	return _markers.get(selected, _close)


func select_zone(id: String) -> void:
	selected = id
	_layout()  # (marker widths follow their text; _layout ends with refresh())


func _zone_name(z: Dictionary) -> String:
	return str(z.get("name_th" if CardTokens.language == "th" else "name_en", z.get("id", "")))


func _boss_name(z: Dictionary) -> String:
	return str(z.get("boss_th" if CardTokens.language == "th" else "boss_en", ""))


var _refreshing := false  ## (restyling a marker can resize it, which lays the panel out and refreshes again)
func refresh() -> void:
	super.refresh()
	if _info == null or _refreshing:
		return
	_refreshing = true
	var p = _profile()
	var lit: Array = []
	for z in Zones.zones():
		var id := str(z.id)
		var st := Zones.state(p, id)
		var b: Button = _markers[id]
		var mark := ""
		b.text = mark + _zone_name(z)
		b.modulate = Color.WHITE if st == Zones.OPEN else Color(0.78, 0.78, 0.78, 0.92)
		style_plate(b, id == selected)
		if st == Zones.OPEN:
			lit.append(Vector2(float(z.pos[0]), float(z.pos[1])))
	# the fog lifts over the open zones (up to 8 holes)
	var holes := PackedVector2Array()
	for i in 8:
		holes.append(lit[i] if i < lit.size() else Vector2(-9.0, -9.0))
	_mat.set_shader_parameter("holes", holes)
	var zone := Zones.zone(selected)
	if zone.is_empty():
		_info_title.text = ""
		_info.text = ""
		_go.visible = false
		_refreshing = false
		return
	var st := Zones.state(p, selected)
	_info_title.text = _zone_name(zone)
	var lines: Array = [CardTokens.t("map_boss") % _boss_name(zone), CardTokens.t("map_waves")]
	match st:
		Zones.OPEN:
			lines.append(CardTokens.t("map_beaten") if Zones.boss_beaten(p, selected) else CardTokens.t("map_drop"))
		Zones.LOCKED:
			var list := Zones.zones()
			var before := ""
			for i in list.size():
				if str(list[i].id) == selected and i > 0:
					before = _boss_name(list[i - 1])
			lines.append(CardTokens.t("map_locked") % before)
		_:
			lines.append(CardTokens.t("map_soon"))
	_info.text = "\n".join(lines)
	_go.visible = st == Zones.OPEN
	_refreshing = false


func _go_pressed() -> void:
	# One playable zone today (the goblin base): Go closes the map back to FIGHT. With more zones this picks the
	# journey FIGHT starts.
	close()


func layout_body(area: Vector2) -> void:
	var gap := CardTokens.CHAR_GAP * s
	var right_w := area.x * (0.28 if not phone else 0.30)
	var map_w := area.x - right_w - gap
	_map_frame.position = Vector2.ZERO
	_map_frame.size = Vector2(map_w, area.y)
	_map.position = Vector2.ZERO
	_map.size = _map_frame.size
	var image_size := Vector2(1672, 941)
	var raw = Zones.data().get("image_size", [1672, 941])
	if raw is Array and raw.size() == 2:
		image_size = Vector2(float(raw[0]), float(raw[1]))
	var k := minf(map_w / image_size.x, area.y / image_size.y)
	var shown := image_size * k
	var origin := (_map_frame.size - shown) * 0.5
	var mh := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s * 0.8
	for z in Zones.zones():
		var b: Button = _markers[str(z.id)]
		var font := maxi(int(round(CardTokens.FONT_CHAR_LINE * s * (1.15 if phone else 0.9))), CardTokens.FONT_MIN)
		b.add_theme_font_size_override("font_size", font)
		var w := CardTokens.display_font().get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font).x + 22.0 * s
		b.size = Vector2(w, mh)
		var at := origin + shown * Vector2(float(z.pos[0]), float(z.pos[1])) - b.size * 0.5
		b.position = Vector2(clampf(at.x, 0.0, map_w - w), clampf(at.y, 0.0, area.y - mh))
	var rx := map_w + gap
	_info_title.position = Vector2(rx, 0.0)
	_info_title.size = Vector2(right_w, CardTokens.FONT_HUB_PANEL_TITLE * s * 2.6)
	CardTokens.hub_text(_info_title, CardTokens.FONT_HUB_PANEL_TITLE, CardTokens.HUB_INK, s)
	_info.position = Vector2(rx, _info_title.size.y + gap * 0.5)
	var go_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	_info.size = Vector2(right_w, area.y - _info.position.y - go_h - gap)
	CardTokens.hub_text(_info, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
	_go.position = Vector2(rx, area.y - go_h)
	_go.size = Vector2(right_w, go_h)
	CarvedLook.plate_button(_go, s)
	CardTokens.hub_fit(_go, _go.text, CardTokens.FONT_CHAR_LINE, right_w - 24.0 * s, CardTokens.HUB_INK, s)
