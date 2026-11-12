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
			_box.add_child(_label(HubLook.t(str(SUMMARY_TITLES.get(j.state, "summary_lost"))), InkUi.GOLD if j.state == Journey.WON else InkUi.BAD))
			if GameState.remote_session != null and not GameState.remote_session.saved:
				_box.add_child(_label(HubLook.t("summary_saving"), InkUi.MUTED))
			var back := _add_button(HubLook.t("summary_back"), GameState.end_journey)
			if GameState.remote_session != null and not GameState.remote_session.can_return_to_hub():
				back.disabled = true
				back.text = HubLook.t("summary_saving")
			else: back.grab_focus.call_deferred()


func _status_text(j) -> String:
	if j.state == Journey.LOST:
		return HubLook.t("summary_safe")
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


## The auto-battler's end screen in the approved hub look (Boss 2026-11-12): a leather / parchment panel over the
## dimmed ruins background with the outcome, the stage, waves cleared and what this run picked up (items in their
## tier colours, gold, materials), and a leather "Back to Cards" button. Display only: the loot list is
## GameState.run_loot (noted from the fight's loot events); the bag itself was already settled by the rules.
func _is_wave_summary() -> bool:
	var j = journey()
	return j != null and GameState.remote_session == null and bool(j.data.wave_mode) \
		and j.state in [Journey.WON, Journey.LOST, Journey.RETREATED, Journey.ABANDONED]


const HubLook := preload("res://client/hub_look.gd")
const HubItemCell := preload("res://client/hub_item_cell.gd")
const Item := preload("res://logic/item.gd")
const SUMMARY_TITLES := {Journey.WON: "summary_won", Journey.LOST: "summary_lost", Journey.RETREATED: "summary_retreated", Journey.ABANDONED: "summary_abandoned"}


## Waves the squad got through: all of them on a win, else every wave before the one it fell / left on.
static func waves_cleared(state: String, wave_reached: int, total: int) -> int:
	if state == Journey.WON:
		return total
	return clampi(wave_reached - 1, 0, total)


func _build_wave_summary() -> void:
	var j = journey()
	var screen := get_viewport().get_visible_rect().size
	var s := CardTokens.scale_for(screen)
	var back_art := CardTokens.art_rect(CardTokens.HUB_BG)
	back_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back_art)
	var dim := Panel.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.panel(dim, CardTokens.hub_shade(CardTokens.HUB_DIM))
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var leather := PanelContainer.new()
	CardTokens.panel(leather, HubLook.leather(s))
	center.add_child(leather)
	var rim := MarginContainer.new()
	CardTokens.margin(rim, CardTokens.SVC_LEATHER, s)
	leather.add_child(rim)
	var paper := PanelContainer.new()
	CardTokens.panel(paper, HubLook.parchment(s))
	rim.add_child(paper)
	var pad := MarginContainer.new()
	CardTokens.margin(pad, CardTokens.SUMMARY_PAD, s)
	paper.add_child(pad)
	var width := minf(CardTokens.SUMMARY_PANEL_W * s, screen.x - (CardTokens.SVC_LEATHER + CardTokens.SUMMARY_PAD) * 2.0 * s - CardTokens.hub_safe_x(screen, s) * 2.0)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.custom_minimum_size = Vector2(width, 0.0)
	CardTokens.gap(_box, CardTokens.SUMMARY_GAP, s)
	pad.add_child(_box)
	var won: bool = j.state == Journey.WON
	_box.add_child(CardTokens.hub_label(HubLook.t(str(SUMMARY_TITLES.get(j.state, "summary_lost"))), CardTokens.FONT_SUMMARY_TITLE, CardTokens.HUB_INK if won else CardTokens.HUB_BAD, s))
	_box.add_child(CardTokens.hub_label(str(j.data.display_name), CardTokens.FONT_SUMMARY_STAGE, CardTokens.HUB_INK, s))
	var loot: Dictionary = GameState.run_loot
	var total: int = j.wave_total() if j.has_method("wave_total") else int(j.data.stage_count)
	var cleared := waves_cleared(j.state, int(loot.get("wave", 1)), total)
	_box.add_child(CardTokens.hub_label(HubLook.t("summary_waves") % [cleared, total], CardTokens.FONT_SUMMARY_LINE, CardTokens.HUB_SUBTEXT, s, 0, "medium"))
	var line := Panel.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(width, CardTokens.SUMMARY_DIVIDER_H * s)
	CardTokens.panel(line, CardTokens.hub_line(CardTokens.HUB_DIVIDER))
	_box.add_child(line)
	_box.add_child(CardTokens.hub_label(HubLook.t("summary_loot"), CardTokens.FONT_SUMMARY_STAGE, CardTokens.HUB_INK, s))
	_add_loot(loot, width, s)
	if not _loot_empty(loot):
		var lost: bool = j.state == Journey.ABANDONED
		_box.add_child(CardTokens.hub_label(HubLook.t("summary_left_lost" if lost else "summary_safe"), CardTokens.FONT_SUMMARY_LINE, CardTokens.HUB_BAD if lost else CardTokens.HUB_GOOD, s, 0, "medium"))
	var row := CenterContainer.new()
	_box.add_child(row)
	var back := Button.new()
	back.text = HubLook.t("summary_back")
	back.focus_mode = Control.FOCUS_ALL
	back.custom_minimum_size = Vector2(CardTokens.SUMMARY_BUTTON.x * s, CardTokens.tap(CardTokens.SUMMARY_BUTTON.y, CardTokens.is_phone(screen)) * s)
	CardTokens.hub_plate_button(back, s)
	CardTokens.hub_fit(back, back.text, CardTokens.FONT_SUMMARY_BUTTON, back.custom_minimum_size.x - (CardTokens.HUB_PLATE_MARGINS[0] + CardTokens.HUB_PLATE_MARGINS[2]), CardTokens.HUB_INK, s)
	back.pressed.connect(_back_to_cards)
	row.add_child(back)
	_buttons.append(back)
	back.grab_focus.call_deferred()


func _back_to_cards() -> void:
	Audio.play_ui("click")
	GameState.end_journey()


static func _loot_empty(loot: Dictionary) -> bool:
	return loot.get("items", []).is_empty() and int(loot.get("gold", 0)) <= 0 and loot.get("materials", {}).is_empty()


## Gold and materials on one line (icon + count), then the items as hub cells (real icon, tier pips), then a
## per-tier count line (the tier word and pips as well as the colour).
func _add_loot(loot: Dictionary, width: float, s: float) -> void:
	if _loot_empty(loot):
		_box.add_child(CardTokens.hub_label(HubLook.t("summary_loot_none"), CardTokens.FONT_SUMMARY_LINE, CardTokens.HUB_TAB_IDLE, s, 0, "medium"))
		return
	var money := _flow(width, CardTokens.SUMMARY_GAP * 1.5, s)
	if int(loot.get("gold", 0)) > 0:
		money.add_child(_amount(CardTokens.tex(CardTokens.HUB_SYS_PREFIX + "gold"), HubLook.t("summary_gold") % int(loot["gold"]), s))
	for id in loot.get("materials", {}):
		var name := str(GameState.camp_data.materials.get(id, {}).get("name", id)) if GameState.camp_data != null else str(id)
		money.add_child(_amount(InkUi.icon(str(id), int(CardTokens.SUMMARY_ICON)), HubLook.t("summary_material") % [int(loot["materials"][id]), name], s))
	if money.get_child_count() == 0:
		money.queue_free()
	var items: Array = loot.get("items", [])
	if items.is_empty():
		return
	var sorted := items.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return int(a["tier"]) > int(b["tier"]))
	var grid := _flow(width, CardTokens.SUMMARY_CELL_GAP, s)
	var cell_px := CardTokens.SUMMARY_CELL * s
	for index in mini(sorted.size(), CardTokens.SUMMARY_MAX_ITEMS):
		var entry: Dictionary = sorted[index]
		var piece := Item.new()
		piece.item_id = str(entry["item_id"])
		piece.tier = int(entry["tier"])
		piece.slot = str(entry["slot"])
		var cell := HubItemCell.new()
		cell.setup()
		cell.s = s
		cell.focus_mode = Control.FOCUS_NONE
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.custom_minimum_size = Vector2(cell_px, cell_px)
		cell.show_item(piece, GameState.item_rules, "")
		cell.tooltip_text = str(GameState.item_rules.catalog.entry(piece.item_id).get("name", CardTokens.slot_name(piece.slot)))
		grid.add_child(cell)
	if sorted.size() > CardTokens.SUMMARY_MAX_ITEMS:
		var more := CardTokens.label(HubLook.t("summary_more") % (sorted.size() - CardTokens.SUMMARY_MAX_ITEMS), CardTokens.FONT_SUMMARY_LINE, CardTokens.HUB_INK, s, 0, "medium")
		more.custom_minimum_size = Vector2(0.0, cell_px)
		grid.add_child(more)
	var counts := {}
	for entry in sorted:
		counts[int(entry["tier"])] = int(counts.get(int(entry["tier"]), 0)) + 1
	var tiers := _flow(width, CardTokens.SUMMARY_GAP * 1.5, s)
	var order := counts.keys()
	order.sort()
	order.reverse()
	for tier in order:
		var tier_id := str(GameState.item_rules.tiers[tier]["id"]) if tier < GameState.item_rules.tiers.size() else "normal"
		var words := "%s %s" % ["◆".repeat(tier + 1), HubLook.t("summary_tiers") % [counts[tier], CardTokens.t("tier_" + tier_id)]]
		tiers.add_child(CardTokens.label(words, CardTokens.FONT_SUMMARY_LINE, HubLook.tier_color(tier), s, CardTokens.OUTLINE_HUB, "medium", CardTokens.HUB_OUTLINE))


func _flow(width: float, gap: float, s: float) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.custom_minimum_size = Vector2(width, 0.0)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardTokens.flow_gap(flow, gap, s)
	_box.add_child(flow)
	return flow


func _amount(icon: Texture2D, text: String, s: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardTokens.gap(row, 8.0, s)
	if icon != null:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2.ONE * CardTokens.SUMMARY_ICON * s
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
	row.add_child(CardTokens.label(text, CardTokens.FONT_SUMMARY_LINE, CardTokens.HUB_INK, s))
	return row
