extends Control
## The journey's route screen. Since the exit portals (Boss 2026-10-13) the player picks the next stage
## by walking into a portal in the stage itself, so this screen is no longer shown between stages: it is
## the end-of-journey summary (won / fell / went home / left) and the fallback route list (Esc after a
## clear or at a rest camp): where the player is ("Stage 4/12"), health and bag, one button per next
## choice, the camp window, bag banking, and leaving the journey.
## Every rule is in logic/journey.gd; this only shows it and passes the player's picks on.

const CardTokens := preload("res://client/card_tokens.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const InkUi := preload("res://client/ink_ui.gd")
const Journey := preload("res://logic/journey.gd")
const MapLoader := preload("res://logic/map_loader.gd")

const TYPE_TEXT := {
	"combat": ["Combat", "A fight at this stage's strength."],
	"challenge": ["Challenge", "A harder fight. Better loot."],
	"treasure": ["Treasure", "No fight. A rare (or better) piece of gear."],
	"camp": ["Camp", "Heal fully, sort and wear your gear."],
	"boss": ["BOSS", "The last stage."],
}

var _box: VBoxContainer
var _center: CenterContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	if _is_wave_summary():
		_build_wave_summary()
		return
	theme = InkUi.make_theme(InkUi.FONT_SECTION)
	var back := ColorRect.new()
	back.color = InkUi.INK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_center = CenterContainer.new()  # scaled to the screen like the camp window (InkUi.layout_for())
	add_child(_center)
	var window := PanelContainer.new()  # the route sits in the same brass window as the camp
	InkUi.panel(window, InkUi.window_style())
	_center.add_child(window)
	_box = VBoxContainer.new()
	InkUi.gap(_box, InkUi.GAP_XXL)
	window.add_child(_box)
	get_viewport().size_changed.connect(_fit)
	# Wrapped labels report a very tall minimum before their first layout, which grows the centre past the
	# screen (the route ended up below the window); fit again once the real minimum is known.
	_center.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_fit()
	_refresh()
	if GameState.remote_session != null:
		GameState.remote_session.command_completed.connect(_online_changed)
		GameState.remote_session.ownership_changed.connect(_refresh)
		GameState.remote_session.route_changed.connect(_refresh)


## Scales the route to the screen: phones get fewer, bigger units (readable and touchable).
func _fit() -> void:
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		window_size = logical
	var layout := InkUi.layout_for(window_size, logical, DisplayServer.screen_get_scale())
	_box.custom_minimum_size = Vector2(minf(760.0, layout["size"].x - 64.0), 0.0)  # (first: the centre cannot shrink below it)
	_center.scale = Vector2.ONE * float(layout["scale"])
	_center.size = layout["size"]
	_center.set_deferred("size", layout["size"])


func journey():
	return GameState.journey


func _refresh() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_buttons.clear()
	var j = journey()
	if GameState.remote_session != null and GameState.remote_session.is_lobby():
		_box.add_child(InkUi.brush_title("แคมป์ปาร์ตี้", InkUi.FONT_TITLE))
		_add_button("กลับเข้าแคมป์ปาร์ตี้", func(): get_tree().change_scene_to_file(GameState.STAGE_SCENE))
		_add_button("ออกจากปาร์ตี้ กลับแคมป์หลัก", func(): GameState.remote_session.command({"type": "party_leave"}))
		return
	if j == null:
		_box.add_child(_label("No journey in progress.", InkUi.MUTED))
		_add_button("Back to the cards", GameState.go_card_deck)
		return
	var over: bool = j.state in [Journey.WON, Journey.LOST, Journey.RETREATED, Journey.ABANDONED]
	# The fight is over: the title is the stage alone (no "Wave 1/12"), and no bag/gold/path line (the auto-battler has no bag).
	_box.add_child(InkUi.brush_title(str(j.data.display_name) if over else "%s   -   %s" % [j.data.display_name, j.progress_text()], InkUi.FONT_TITLE))
	if not over:
		_box.add_child(_label(_status_text(j), InkUi.PAPER))
		_box.add_child(_label(_path_text(j), InkUi.MUTED))
	match j.state:
		Journey.CHOOSING:
			_box.add_child(_label("Choose the next stage:", InkUi.PAPER))
			var row := HBoxContainer.new()
			InkUi.gap(row, InkUi.GAP_XL)
			_box.add_child(row)
			var options: Array = j.choices()
			for index in options.size():
				var button := _choice_button(options[index])
				button.pressed.connect(_choose.bind(index))
				row.add_child(button)
				_buttons.append(button)
			_buttons[0].grab_focus.call_deferred()
			_add_button("Leave the journey (the bag is lost)", _abandon)
		Journey.AT_NODE:
			if str(j.current["kind"]) == "treasure":
				if GameState.remote_session == null:
					GameState.get_session().command({"type": "journey_treasure"})
				elif j.treasure_pending:
					_add_button("Open the treasure", _open_online_treasure)
				_box.add_child(_label("Treasure: " + _reward_text(j.last_reward), InkUi.GOLD))
			else:
				_box.add_child(_label("You rest at the camp. Health restored.", InkUi.GOOD))
				if j.can_bank_bag():
					_add_button("Store the bag in the stash (safe from death)", _bank)
			_add_button("Continue", _leave).grab_focus.call_deferred()
			if not j.is_at_camp():
				_add_button("Leave the journey (the bag is lost)", _abandon)
		_:
			var ending := {Journey.WON: "ชนะ! บอสล้มแล้ว", Journey.LOST: "พ่ายแพ้ — ทัพล้มก่อนจบเวฟ", Journey.RETREATED: "ถอนทัพกลับแล้ว", Journey.ABANDONED: "ออกจากด่านกลางทาง"}
			_box.add_child(_label(str(ending.get(j.state, "")), InkUi.GOLD if j.state == Journey.WON else InkUi.BAD))
			if GameState.remote_session != null and not GameState.remote_session.saved:
				_box.add_child(_label("กำลังบันทึกผลรอบบนเซิร์ฟเวอร์…", InkUi.MUTED))
			var back := _add_button("กลับหน้าการ์ด", GameState.end_journey)
			if GameState.remote_session != null and not GameState.remote_session.can_return_to_hub():
				back.disabled = true
				back.text = "กำลังบันทึกผล…"
			else: back.grab_focus.call_deferred()


func _status_text(j) -> String:
	if j.state == Journey.LOST:
		return "ของที่เก็บได้ยังอยู่ครบ ตรวจดูได้ที่คลังในแคมป์หลัก"
	var text := "Health %d%%    Bag %d/%d    Gold %d" % [roundi(j.hp_fraction * 100.0), j.run.bag.slots_used(), j.run.bag.capacity, j.run.bag.gold]
	if not j.last_reward.is_empty() and j.state == Journey.CHOOSING:
		text += "\nChallenge reward: " + _reward_text(j.last_reward)
	return text


func _path_text(j) -> String:
	var marks: Array[String] = []
	for stage in j.data.stage_count:
		if stage < j.path.size():
			marks.append(str(TYPE_TEXT.get(j.path[stage], [j.path[stage]])[0]).substr(0, 2).to_upper())
		else:
			marks.append("..")
	return "Path:  " + "  ".join(marks)


func _reward_text(reward: Dictionary) -> String:
	if reward.is_empty():
		return "nothing"
	var parts: Array[String] = []
	for item in reward.get("items", []):
		parts.append("%s %s" % [str(GameState.item_rules.tiers[item.tier]["id"]).capitalize(), item.slot])
	if int(reward.get("gold", 0)) > 0:
		parts.append("%d gold" % int(reward["gold"]))
	for id in reward.get("materials", {}):
		parts.append("%d %s" % [int(reward["materials"][id]), id])
	if not reward.get("lost_items", []).is_empty():
		parts.append("(%d left behind: bag full)" % reward["lost_items"].size())
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _choice_button(node: Dictionary) -> Button:
	var type := str(node["kind"])
	var info: Array = TYPE_TEXT.get(type, [type, ""])
	var button := Button.new()
	var where := ""
	if not str(node.get("map", "")).is_empty():
		where = "\n" + MapLoader.load_by_id(str(node["map"])).display_name.get_slice(" (", 0)
	button.text = "%s\nStage %d%s\n\n%s" % [info[0], int(node["stage"]), where, info[1]]
	button.custom_minimum_size = Vector2(230.0, 170.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	InkUi.style_text(button, _type_color(type))
	InkUi.icon_button(button, type, 36)  # the stage kind as a brass icon above its word
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button


func _choose(index: int) -> void:
	var node: Dictionary = GameState.enter_journey_choice(index)  # (a fight or a camp loads its map)
	if node.is_empty():
		return
	Audio.play_ui("select")
	if journey().state == Journey.AT_NODE and not journey().is_at_camp():
		_refresh()  # a treasure: show what it gave


func _leave() -> void:
	Audio.play_ui("click")
	GameState.get_session().command({"type": "journey_leave"})
	_refresh()


func _abandon() -> void:
	Audio.play_ui("click")
	GameState.get_session().command({"type": "journey_abandon"})
	_refresh()


func _bank() -> void:
	GameState.last_trip = GameState.get_session().command({"type": "bank_bag"}).get("result", {})
	_refresh()


func _add_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320.0, 52.0)
	button.pressed.connect(callback)
	_box.add_child(button)
	return button


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	InkUi.style_text(label, color)
	return label


## Each stage kind has its own color (and always its own word on the button).
static func _type_color(type: String) -> Color:
	return {"combat": InkUi.STAGE_COMBAT, "challenge": InkUi.STAGE_CHALLENGE, "treasure": InkUi.STAGE_TREASURE, "camp": InkUi.STAGE_CAMP, "boss": InkUi.STAGE_BOSS}.get(type, InkUi.PAPER)


func _online_changed(_id: int, _result: Dictionary) -> void:
	_refresh.call_deferred()

func _open_online_treasure() -> void:
	GameState.get_session().command({"type": "journey_treasure"})


## The auto-battler's end screen uses the class card look (cartoon sky, paper panel, orange button) instead of
## the old brass route window.
func _is_wave_summary() -> bool:
	var j = journey()
	return j != null and GameState.remote_session == null and bool(j.data.wave_mode) 		and j.state in [Journey.WON, Journey.LOST, Journey.RETREATED, Journey.ABANDONED]


func _build_wave_summary() -> void:
	var j = journey()
	var s := CardTokens.scale_for(get_viewport().get_visible_rect().size)
	var sky := TextureRect.new()
	sky.texture = CardTokens.tex("bg_sky") if CardTokens.tex("bg_sky") != null else CardTokens.sky_gradient()
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	CardTokens.panel(panel, CardTokens.panel_paper(s))
	center.add_child(panel)
	var pad := MarginContainer.new()
	CardTokens.margin(pad, 48.0, s)
	panel.add_child(pad)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	CardTokens.gap(_box, 28.0, s)
	pad.add_child(_box)
	var won: bool = j.state == Journey.WON
	var headline := {Journey.WON: "ชนะ!", Journey.LOST: "พ่ายแพ้", Journey.RETREATED: "ถอนทัพ", Journey.ABANDONED: "ออกจากด่าน"}
	var detail := {Journey.WON: "บอสล้มแล้ว", Journey.LOST: "ทัพล้มก่อนจบเวฟ", Journey.RETREATED: "ถอนทัพกลับแล้ว", Journey.ABANDONED: "ออกจากด่านกลางทาง"}
	var title := CardTokens.label(str(headline.get(j.state, "")), CardTokens.FONT_SCREEN_TITLE * 2, CardTokens.FRAME if won else CardTokens.ERROR, s, CardTokens.OUTLINE_FRAME)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var stage := CardTokens.label(str(j.data.display_name), CardTokens.FONT_EDITOR_NAME, CardTokens.TEXT_DARK, s, 0, "medium")
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(stage)
	var line := CardTokens.label(str(detail.get(j.state, "")), CardTokens.FONT_TAB, CardTokens.SLATE, s, 0, "body")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(line)
	var back := Button.new()
	back.text = "กลับหน้าการ์ด"
	back.custom_minimum_size = Vector2(420.0, 96.0) * s
	CardTokens.button_skin(back, "primary", s)
	CardTokens.style_text(back, CardTokens.FONT_FIGHT, CardTokens.TEXT_LIGHT, s, CardTokens.OUTLINE_PRIMARY)
	back.pressed.connect(GameState.end_journey)
	_box.add_child(back)
	_buttons.append(back)
	back.grab_focus.call_deferred()

