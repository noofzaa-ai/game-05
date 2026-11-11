extends CanvasLayer
## The player's heads-up display: health, stamina and ultimate bars, status chips, skill icons with
## cooldowns, the trip line (enemies, bag, gold), the combo counter, the skill-name banner, the
## stage banner, help lines and screen flashes.
## Built from plain rectangles and labels so it needs no art; it only displays what the
## simulation says.
##
## Layout: everything sits in one root control that is scaled by `ui_scale`. On a small screen
## (phone) the HUD switches to a "compact" layout that is bigger relative to the screen, hides the
## keyboard help and moves the skill banner off the top. `_layout()` places every piece from the
## current screen size, so it adapts when the window is resized.
## EXTENDING: a new bar or icon is one more call to _bar()/_skill_icon() in _ready() and a line
## in _layout(). Player-facing words are in TEXT (one place, for translation).

const Capsule := preload("res://client/hud_capsule.gd")
const Combat := preload("res://logic/combat.gd")
const CombatData := preload("res://logic/combat_data.gd")
const Fighter := preload("res://logic/fighter.gd")
const InkUi := preload("res://client/ink_ui.gd")
const InputReader := preload("res://client/input_reader.gd")

## Every word the HUD shows, so it can be translated in one place.
const TEXT := {
	"hp": "HP  %d / %d",
	"stamina": "STAMINA  %d / %d",
	"no_stamina": "NOT ENOUGH STAMINA",
	"ultimate": "ULT  %d%%",
	"ultimate_ready": "ULT READY  [%s]",
	"guard": "Guard", "dodge": "Dodge", "special": "Skill", "ultimate_icon": "Ultimate",
	"enemies": "Enemies  %d",
	"hit_combo": "HIT COMBO",
	"combo_damage": "%s DMG",
	"buff_mark": "+ ", "debuff_mark": "- ",
	"boss": "%s   %d%%",
}

const ICON_SIZE := Vector2(64.0, 64.0)
const ICON_GAP := 8.0
const CHIP_SIZE := Vector2(124.0, 24.0)  ## one buff/debuff chip under the bars
const CHIPS_PER_ROW := 3
const HP_BAR_WIDTH := 360.0
const ENERGY_BAR_WIDTH := 260.0  ## width of the stamina bar at the base 100 STAMINA
const ENERGY_SCALE_MAX := 1.4  ## the bar grows with STAMINA up to this many times (stays clear of the banner)
const GAUGE_BAR_WIDTH := 260.0
const MARGIN := 24.0
const BANNER_SIZE := Vector2(480.0, 106.0)
const BOSS_BAR_WIDTH := 440.0
## Screens shorter than this many real pixels get the compact (phone) layout.
const COMPACT_HEIGHT := 560
const COMPACT_SCALE := 1.8
const SKILL_KEYS := ["guard", "dodge", "special", "ultimate"]
const SKILL_FALLBACK_KEYS := {"guard": "F", "dodge": "C", "special": "1", "ultimate": "2"}

## Set above zero to force a HUD scale (a future "HUD size" setting); 0 = automatic.
var ui_scale_override := 0.0
## Force the compact layout on or off (-1 = automatic from the screen size). Mainly for tests.
var compact_override := -1

var compact := false
var ui_scale := 1.0

const LOOT_SECONDS := 4.5  ## how long a loot line stays
const LOOT_FADE_SECONDS := 1.0  ## ... the last part of it fading out
const LOOT_LINES := 6
const LOOT_FEED_WIDTH := 420.0

var _new_skills: CanvasLayer
var _root: Control
var _hp: Dictionary
var _energy: Dictionary
var _gauge: Dictionary
var _chips: Dictionary = {}  ## effect id -> {"root", "label"}: the player's buffs and debuffs
var _chip_order: Array = []
var _mobile_feedback := {}
var _icons: Dictionary = {}  ## skill name -> {"root", "cover", "time", "fill", "key"}
var _combo_box: Control
var _combo_count: Label
var _combo_hits: Label
var _combo_damage: Label
var _combo_timer: ColorRect
var _banner: Label
var _flash: ColorRect
var _help: Label
var _help_plate: ColorRect
var _help_wanted := true
var _info: Label
var _trip: Label  ## top right: enemies left, bag and gold
var _trip_art: Control
var _trip_plate: ColorRect  ## (themes with an ornament frame only) a plate under the trip line
## Auto-battler (Boss 2026-11-10): nobody steers, so the player-fighter bars, skill icons, key help, buffs and
## the combo counter are hidden; a squad panel (client/squad_panel.gd) shows the fighters instead.
var auto_battle := false:
	set(value):
		auto_battle = value
		_layout()
var _boss: Dictionary = {}  ## the boss bar (a bar dictionary plus "name"), hidden while there is no boss
var _boss_name: Label

var _warning: Label
var _skill_banner: Control  ## the brush-stroke banner that names a special skill or ultimate when it is used
var _skill_label: Label
var _skill_tween: Tween
var _prompt: Label  ## "Q = rest point": what the player can do where they stand
var _loot_feed: VBoxContainer  ## right side: what the last kills put in the bag, newest at the bottom
var _warning_left := 0.0

var _hp_shown := 1.0
var _hp_trail := 1.0
var _combo_alpha := 0.0
var _last_combo := 0
var _clock := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_hp = _bar(Vector2(HP_BAR_WIDTH, 28.0), InkUi.HP, true, "hp")
	_energy = _bar(Vector2(ENERGY_BAR_WIDTH, 18.0), InkUi.STAMINA, false, "bar")
	_gauge = _bar(Vector2(GAUGE_BAR_WIDTH, 16.0), InkUi.ULT, false, "bar_small")
	_boss = _bar(Vector2(BOSS_BAR_WIDTH, 16.0), InkUi.HP, true, "bar_small", 20)
	_boss_name = _text("boss", InkUi.HUD_TEXT, 5)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_boss_name)
	set_boss("", 0.0)
	for key in SKILL_KEYS:
		var name_key: String = "ultimate_icon" if key == "ultimate" else key
		_skill_icon(key, InputReader.key_label(key, SKILL_FALLBACK_KEYS[key]), TEXT[name_key])
	_build_combo()
	_build_overlays()
	_loot_feed = VBoxContainer.new()
	_loot_feed.alignment = BoxContainer.ALIGNMENT_END
	_loot_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	InkUi.gap(_loot_feed, InkUi.GAP_XS)
	_root.add_child(_loot_feed)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_clock += delta
	_hp_trail = move_toward(_hp_trail, _hp_shown, delta * 0.35)
	var low := 0.0
	if _hp_shown > 0.0 and _hp_shown < InkUi.LOW_HP:  # low HP: the frame pulses (and its cap shows "!")
		low = 0.55 + 0.45 * sin(_clock * 7.0)
	_set_bar(_hp, _hp_shown, _hp_trail, low)
	_combo_alpha = move_toward(_combo_alpha, 0.0 if _last_combo == 0 else 1.0, delta * 6.0)
	_combo_box.modulate.a = _combo_alpha
	var pulse := 0.65 + 0.35 * sin(_clock * 8.0)
	_gauge["fill"].color = InkUi.ULT.lerp(InkUi.HUD_TEXT, 0.5 * pulse) if _gauge["full"] else InkUi.ULT
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 2.5)
	for line in _loot_feed.get_children():
		var left: float = line.get_meta("left") - delta
		line.set_meta("left", left)
		line.modulate.a = clampf(left / LOOT_FADE_SECONDS, 0.0, 1.0)
		if left <= 0.0:
			line.queue_free()
	_warning_left = maxf(0.0, _warning_left - delta)
	_warning.visible = _warning_left > 0.0 and not auto_battle
	_energy["label"].visible = not _warning.visible and not auto_battle  # the warning takes the stamina bar's text spot
	if _warning_left > 0.0 and int(_warning_left * 14.0) % 2 == 0:
		_energy["fill"].color = InkUi.STAMINA_BLINK  # blink red: not enough stamina


## Adds a line to the loot feed: what just went into the bag ("+ Golden Blossom Katana  Rare"), in the
## item's tier color, with its picture when it has one. Old lines fade; at most LOOT_LINES stay.
func add_loot(text: String, color: Color, icon: Texture2D = null) -> void:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.alignment = BoxContainer.ALIGNMENT_END
	InkUi.gap(line, InkUi.GAP_M)
	var label := InkUi.hud_text("loot", color, 5, InkUi.LOOT_OUTLINE)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(label)
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(36.0, 36.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = icon
	picture.visible = icon != null
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(picture)
	line.set_meta("left", LOOT_SECONDS)
	if InkUi.FRAME_STYLE == "engraved":  # a dark plate behind the line: readable on light and busy ground
		var plate := InkUi.hud_plate_style()
		line.draw.connect(func() -> void:
			var from := label.position.x - 10.0
			plate.draw(line.get_canvas_item(), Rect2(from, -2.0, line.size.x - from + 6.0, line.size.y + 4.0)))
		line.sort_children.connect(line.queue_redraw)  # (the label moves when the line is laid out)
	_loot_feed.add_child(line)
	while _loot_feed.get_child_count() > LOOT_LINES:
		var oldest := _loot_feed.get_child(0)
		_loot_feed.remove_child(oldest)
		oldest.queue_free()


## The loot feed's lines now (for tests): Array of their texts.
func loot_lines() -> Array[String]:
	var texts: Array[String] = []
	for line in _loot_feed.get_children():
		if not line.is_queued_for_deletion():
			texts.append((line.get_child(0) as Label).text)
	return texts


## Called every simulation tick with the local player's fighter. `trip_text` is the bag and gold.
func update_from(fighter: Fighter, data: CombatData, enemies_left: int, camera_text: String, trip_text: String = "") -> void:
	_hp_shown = clampf(fighter.hp / fighter.max_hp(), 0.0, 1.0)
	_hp["label"].text = TEXT["hp"] % [int(ceilf(fighter.hp)), int(fighter.max_hp())]

	# More STAMINA from gear makes the bar itself longer, so a bigger pool is visible at a glance.
	var energy_max := fighter.max_energy()
	var bar_width := minf(280.0, 260.0 * clampf(energy_max / 100.0, 0.5, ENERGY_SCALE_MAX)) / ui_scale if compact else ENERGY_BAR_WIDTH * clampf(energy_max / 100.0, 0.5, ENERGY_SCALE_MAX)
	if not is_equal_approx(bar_width, float(_energy["width"])):
		_energy["width"] = bar_width
		_energy["back"].size.x = bar_width
		if _energy["frame"] != null:
			_energy["frame"].size.x = bar_width
		if _energy["decor"] != null:
			_energy["decor"].size.x = bar_width
			_energy["decor"].ticks = maxi(2, int(roundf(energy_max / 10.0)))  # one segment per 10 stamina
		_place_bar_label(_energy)
	var energy_ratio := clampf(fighter.energy / energy_max, 0.0, 1.0)
	_set_bar(_energy, energy_ratio, energy_ratio)
	_energy["fill"].color = InkUi.STAMINA_EXHAUSTED if fighter.exhausted else InkUi.STAMINA
	_energy["label"].text = TEXT["stamina"] % [int(fighter.energy), int(energy_max)]

	var gauge_max := float(data.rules["ultimate_gauge_max"])
	var gauge_ratio := clampf(fighter.gauge / gauge_max, 0.0, 1.0)
	_gauge["full"] = fighter.gauge >= gauge_max
	_set_bar(_gauge, gauge_ratio, gauge_ratio)
	_gauge["label"].text = TEXT["ultimate_ready"] % _icons["ultimate"]["key"].text if _gauge["full"] else TEXT["ultimate"] % int(gauge_ratio * 100.0)
	InkUi.style_text(_gauge["label"], InkUi.ULT_READY_TEXT if _gauge["full"] else InkUi.HUD_TEXT)

	var style: Dictionary = data.styles.get(fighter.style, data.styles["fists"])
	_set_icon("guard", 0.0, "", fighter.state == Fighter.State.GUARD, true)
	var dodge_total := float(data.rules["dodge_cooldown"])
	var dodge_ok := fighter.energy >= float(data.rules["dodge_energy"])
	_set_icon("dodge", float(fighter.dodge_cooldown) / dodge_total, _seconds(fighter.dodge_cooldown), fighter.state == Fighter.State.DODGE, dodge_ok)
	var special_move: Dictionary = data.moves[style["special"]]
	var special_left := Combat.special_cooldown_left(fighter, data)
	var special_ok := fighter.energy >= float(special_move["energy_cost"])
	_set_icon("special", float(special_left) / maxf(1.0, float(special_move["cooldown"])), _seconds(special_left), false, special_ok)
	_set_icon("ultimate", 0.0, "", false, true, not _gauge["full"])
	_mobile_feedback["ultimate"]["gauge"] = gauge_ratio
	if _gauge["full"]:
		_icons["ultimate"]["root"].color = InkUi.ULT_ICON_PULSE_A.lerp(InkUi.ULT_ICON_PULSE_B, 0.5 + 0.5 * sin(_clock * 8.0))
	_icons["ultimate"]["fill"].size.y = ICON_SIZE.y * gauge_ratio
	_icons["ultimate"]["fill"].position.y = ICON_SIZE.y - _icons["ultimate"]["fill"].size.y

	_update_effects(fighter, data)
	_update_combo(fighter, data)
	if auto_battle:
		_apply_auto_battle()
	var weapon_name := str(data.weapons.get(fighter.style, {}).get("name", fighter.style))
	_info.text = "%s    %s" % [weapon_name, camera_text]
	_trip.text = (TEXT["enemies"] % enemies_left) + ("    " + trip_text if not trip_text.is_empty() else "")
	_place_trip_plate()
	if _new_skills != null:
		_new_skills.update_from(fighter)
		for key in ["back","trail","fill","frame","decor","label","pill"]:
			if _gauge.get(key) is CanvasItem: _gauge[key].visible = false
		for key in ["special","ultimate"]:
			for value in _icons[key].values():
				if value is CanvasItem: value.visible = false


## One chip per buff and debuff on the player: a +/- mark (not only color), its name, stacks and
## seconds left. Buffs come first.
func _update_effects(fighter: Fighter, data: CombatData) -> void:
	for id in _chips.keys():
		if not fighter.effects.has(id):
			_chips[id]["root"].queue_free()
			_chips.erase(id)
	var ids := fighter.effects.keys()
	ids.sort_custom(func(a, b) -> bool:
		var a_buff: bool = data.effects[a]["kind"] == "buff"
		var b_buff: bool = data.effects[b]["kind"] == "buff"
		return a < b if a_buff == b_buff else a_buff)
	for id in ids:
		var definition: Dictionary = data.effects[id]
		if not _chips.has(id):
			_chips[id] = _make_chip(definition)
		var instance: Dictionary = fighter.effects[id]
		var stacks := int(instance["stacks"])
		var mark: String = TEXT["buff_mark"] if definition["kind"] == "buff" else TEXT["debuff_mark"]
		_chips[id]["label"].text = "%s%s%s  %.1f" % [mark, definition["name"], (" x%d" % stacks) if stacks > 1 else "", float(instance["left"]) / 60.0]
	_chip_order = ids
	_place_chips()


func _place_chips() -> void:
	var top: float = _gauge["back"].position.y + _gauge["back"].size.y + 12.0
	var chip_scale := 1.0 / ui_scale if compact else 1.0
	var column := 0
	for id in _chip_order:
		if _chips.has(id):
			_chips[id]["root"].scale = Vector2.ONE * chip_scale
			_chips[id]["root"].position = Vector2((16.0 / ui_scale if compact else MARGIN) + float(column % CHIPS_PER_ROW) * (CHIP_SIZE.x + 4.0) * chip_scale, top + float(column / CHIPS_PER_ROW) * (CHIP_SIZE.y + 4.0) * chip_scale)
			column += 1


func _make_chip(definition: Dictionary) -> Dictionary:
	var root := ColorRect.new()
	var color: Color = definition["color"]
	root.color = Color(InkUi.CHIP_BASE.lerp(color, InkUi.CHIP_TINT), InkUi.CHIP_ALPHA)
	root.size = CHIP_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(root)
	var edge := ColorRect.new()  # a bright strip on the left: green = buff, red = debuff (plus the +/- mark)
	edge.color = InkUi.BUFF if definition["kind"] == "buff" else InkUi.DEBUFF
	edge.size = Vector2(4.0, CHIP_SIZE.y)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(edge)
	var label := _text("chip", InkUi.HUD_TEXT, 3)
	label.position = Vector2(8.0, 2.0)
	root.add_child(label)
	var frame := InkUi.hud_ornament(CHIP_SIZE, false, false)
	if frame != null:
		root.add_child(frame)
	return {"root": root, "label": label}


## The player tried an action without enough stamina: blink the stamina bar and say so.
func flash_stamina() -> void:
	_warning_left = 0.7


func flash(color: Color, _seconds: float) -> void:
	_flash.color = color  # fades out on its own in _process


## A black brush stroke with the skill's name in it, popping in and fading. It sits at the top
## centre (compact layout: low, left of the skill icons) so it does not cover the fight around the
## player, who is in the middle of the screen.
func show_skill_banner(text: String) -> void:
	_skill_label.text = text
	_skill_banner.visible = true
	_skill_banner.modulate.a = 0.0
	_skill_banner.pivot_offset = BANNER_SIZE * 0.5
	_skill_banner.scale = Vector2(1.3, 1.3)
	if _skill_tween != null:
		_skill_tween.kill()
	_skill_tween = create_tween()
	_skill_tween.tween_property(_skill_banner, "modulate:a", 1.0, 0.08)
	_skill_tween.parallel().tween_property(_skill_banner, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_OUT)
	_skill_tween.tween_interval(0.9)
	_skill_tween.tween_property(_skill_banner, "modulate:a", 0.0, 0.4)
	_skill_tween.tween_callback(func() -> void: _skill_banner.visible = false)


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_banner(text: String) -> void:
	_banner.text = text


func set_help(text: String) -> void:
	_help.text = text
	_layout()


## Shows or hides the keyboard help lines (F1 in a stage). The compact layout never shows them.
func toggle_help() -> void:
	_help_wanted = not _help_wanted
	_layout()


func help_visible() -> bool:
	return _help.visible


## The combo counter: a big number that pops on every hit and a bar showing how long it lasts.
func _update_combo(fighter: Fighter, data: CombatData) -> void:
	_last_combo = fighter.combo_dealt
	if fighter.combo_dealt <= 0:
		return
	_combo_count.text = str(fighter.combo_dealt)
	_combo_damage.text = TEXT["combo_damage"] % _thousands(fighter.combo_damage)
	_combo_timer.size.x = (_combo_box.size.x - 16.0) * clampf(float(fighter.combo_timer) / float(data.rules["combo_window_ticks"]), 0.0, 1.0)
	_combo_timer.position.x = _combo_box.size.x - _combo_timer.size.x  # shrinks toward the right edge
	if fighter.combo_dealt != _combo_box.get_meta("shown", 0):
		_combo_box.set_meta("shown", fighter.combo_dealt)
		# Pop from the right edge so the bigger number never runs off the screen.
		_combo_count.pivot_offset = Vector2(_combo_count.size.x, _combo_count.size.y * 0.5)
		_combo_count.scale = Vector2.ONE * 1.4
		create_tween().tween_property(_combo_count, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_OUT)
		var heat := clampf(float(fighter.combo_dealt) / 12.0, 0.0, 1.0)
		InkUi.style_text(_combo_count, InkUi.COMBO_COOL.lerp(InkUi.COMBO_HOT, heat))


# ---------------------------------------------------------------- layout

## True when the screen is small in real pixels (a phone), or on a mobile device.
func _wants_compact() -> bool:
	if compact_override >= 0:
		return compact_override == 1
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return get_window().size.y < COMPACT_HEIGHT


## Places every piece for the current screen size.
func _layout() -> void:
	if _root == null:
		return
	compact = _wants_compact()
	ui_scale = ui_scale_override if ui_scale_override > 0.0 else (COMPACT_SCALE if compact else 1.0)
	var screen := get_viewport().get_visible_rect().size
	var area := screen / ui_scale  # the HUD's own coordinate space
	_root.scale = Vector2(ui_scale, ui_scale)
	_root.position = Vector2.ZERO
	_root.size = area

	# Top left: the three bars, then the status chips.
	var hp_width := HP_BAR_WIDTH if not compact else 300.0
	_hp["width"] = hp_width
	_place_bar(_hp, Vector2(MARGIN, 18.0), Vector2(hp_width, 28.0))
	_place_bar(_energy, Vector2(MARGIN, 52.0), Vector2(float(_energy["width"]), 18.0))
	_place_bar(_gauge, Vector2(MARGIN, 74.0), Vector2(GAUGE_BAR_WIDTH, 16.0))
	if compact:
		_place_bar(_hp, Vector2(16, 16) / ui_scale, Vector2(300, 24) / ui_scale)
		_place_bar(_energy, Vector2(16, 44) / ui_scale, Vector2(minf(float(_energy["width"]) * ui_scale, 280), 19) / ui_scale)
		_place_bar(_gauge, Vector2(16, 67) / ui_scale, Vector2(230, 17) / ui_scale)
		for bar in [_hp, _energy, _gauge]:
			InkUi.text_size(bar["label"], maxi(8, roundi(InkUi.FONT_BODY / ui_scale)))
			_place_bar_label(bar)
	_place_chips()

	# The boss bar: top centre (the skill banner moves under it); compact: under the player's bars.
	var boss_at := Vector2((area.x - BOSS_BAR_WIDTH) * 0.5, 40.0)
	var boss_width := BOSS_BAR_WIDTH
	if compact:
		boss_width = hp_width
		boss_at = Vector2(MARGIN, 162.0)
	_place_bar(_boss, boss_at, Vector2(boss_width, 16.0))
	_boss_name.size = Vector2(boss_width, 24.0)
	_boss_name.position = boss_at - Vector2(0.0, 28.0)

	# Bottom right: the skill icons (where the touch buttons will be on a phone).
	var row_width := ICON_SIZE.x * SKILL_KEYS.size() + ICON_GAP * (SKILL_KEYS.size() - 1)
	for i in SKILL_KEYS.size():
		_icons[SKILL_KEYS[i]]["root"].visible = true
		_icons[SKILL_KEYS[i]]["root"].position = Vector2(area.x - MARGIN - row_width + float(i) * (ICON_SIZE.x + ICON_GAP), area.y - MARGIN - ICON_SIZE.y)

	# Top right: the trip line, with the combo counter under it.
	_trip.position = Vector2(area.x - MARGIN - 340.0, 16.0)
	_trip.size = Vector2(340.0, 26.0)
	_place_trip_plate()
	var combo_width := 236.0
	_combo_box.position = Vector2(area.x - MARGIN - combo_width, 90.0 if GameState.remote_session != null else 46.0)
	_combo_box.size = Vector2(combo_width, 160.0)
	InkUi.text_size(_combo_count, InkUi.HUD_FONT["combo_compact"] if compact else InkUi.HUD_FONT["combo"])
	var count_height := 76.0 if compact else 92.0
	_combo_count.size = Vector2(combo_width, count_height)
	_combo_hits.position = Vector2(0.0, count_height - 4.0)
	_combo_damage.position = Vector2(0.0, count_height + 22.0)
	_combo_timer.position.y = count_height + 52.0

	# The skill banner: top centre; compact: low, centred in the space left of the skill icons.
	if compact:
		var free_width := area.x - MARGIN - row_width
		if free_width >= BANNER_SIZE.x + MARGIN:
			_skill_banner.position = Vector2(maxf(MARGIN, (free_width - BANNER_SIZE.x) * 0.5), area.y - MARGIN - BANNER_SIZE.y)
		else:  # a narrow (portrait) screen: above the skill icons instead
			_skill_banner.position = Vector2((area.x - BANNER_SIZE.x) * 0.5, area.y - MARGIN - ICON_SIZE.y - 12.0 - BANNER_SIZE.y)
	else:
		_skill_banner.position = Vector2((area.x - BANNER_SIZE.x) * 0.5, 8.0 + (60.0 if _boss_name.visible else 0.0))
	_skill_banner.size = BANNER_SIZE

	# Bottom left: weapon and camera, and the help lines (keyboard only, hidden on a phone).
	var help_on := _help_wanted and not compact and not _help.text.is_empty()
	_help.visible = help_on
	_help_plate.visible = help_on
	var help_height := _help.get_minimum_size().y if help_on else 0.0
	_help.position = Vector2(MARGIN, area.y - 14.0 - help_height)
	_help_plate.position = _help.position - Vector2(8.0, 4.0)
	_help_plate.size = _help.get_minimum_size() + Vector2(16.0, 8.0)
	_info.visible = not compact
	_info.position = Vector2(MARGIN, area.y - 14.0 - help_height - (10.0 if help_on else 0.0) - 20.0)

	# Right side, above the skill icons: the loot feed grows upward.
	_loot_feed.size = Vector2(LOOT_FEED_WIDTH, 44.0 * LOOT_LINES)
	_loot_feed.position = Vector2(area.x - MARGIN - LOOT_FEED_WIDTH, area.y - MARGIN - ICON_SIZE.y - 16.0 - _loot_feed.size.y)

	_apply_auto_battle()
	_prompt.position = Vector2(area.x * 0.5 - 300.0, area.y - (150.0 if compact else 120.0))
	_prompt.size = Vector2(600.0, 30.0)
	_banner.position = Vector2(area.x * 0.5 - 400.0, area.y * 0.5 - 80.0)
	_banner.size = Vector2(800.0, 160.0)


func _apply_auto_battle() -> void:
	if not auto_battle:
		return
	for bar in [_hp, _energy, _gauge]:
		for key in ["back", "trail", "fill", "frame", "decor", "label", "pill"]:
			if bar.get(key) is CanvasItem:
				bar[key].visible = false
	for key in _icons:
		_icons[key]["root"].visible = false
	for chip in _chips.values():
		chip["root"].visible = false
	_help.visible = false
	_help_plate.visible = false
	_info.visible = false
	_combo_box.visible = false
	if _new_skills != null:
		_new_skills.visible = false


## The plate fits the trip line's text, right-aligned with it.
func _place_trip_plate() -> void:
	if _trip_plate == null:
		return
	var width := _trip.get_minimum_size().x + 28.0
	_trip_plate.size = Vector2(width, 32.0)
	_trip_plate.position = Vector2(_trip.position.x + _trip.size.x - width + 12.0, _trip.position.y - 3.0)
	_trip_plate.get_child(0).size = _trip_plate.size
	_trip_plate.get_child(0).visible = not compact
	_trip_plate.color = InkUi.CLEAR if compact else InkUi.HELP_PLATE
	if _trip_art != null:
		_trip_art.visible = compact
		_trip_art.size = _trip_plate.size


func _place_bar(bar: Dictionary, position: Vector2, size: Vector2) -> void:
	for part in ["back", "trail", "fill"]:
		bar[part].position = position
		bar[part].size.y = size.y
	bar["back"].size.x = size.x
	bar["width"] = size.x
	if bar["frame"] != null:  # (the theme's ornament line)
		bar["frame"].position = position
		bar["frame"].size = size
	if bar["decor"] != null:
		bar["decor"].position = position
		bar["decor"].size = size
	var rounded: bool = compact and bar != _boss
	bar["pill"].visible = rounded
	bar["pill"].position = position
	bar["pill"].size = size
	if bar != _boss:
		for part in ["back", "fill", "trail"]:
			bar[part].visible = not rounded and (part != "trail" or bar[part].get_meta("with_trail", false))
		for part in ["decor", "frame"]:
			if bar[part] != null:
				bar[part].visible = not rounded
	InkUi.text_size(bar["label"], int(InkUi.HUD_FONT[bar["font_role"]]))
	_place_bar_label(bar)


## Every bar has its text inside, on the left, with a black outline (the fills are dark enough
## for white text). Nothing sticks out to the right, where the skill banner appears.
func _place_bar_label(bar: Dictionary) -> void:
	var back: ColorRect = bar["back"]
	var label: Label = bar["label"]
	label.position = back.position + Vector2(back.size.y * 1.2 + 4.0 if compact and bar != _boss else (8.0 if bar.get("decor") == null else 12.0), (back.size.y - label.get_minimum_size().y) * 0.5)
	if not _energy.is_empty() and back == _energy["back"] and _warning != null:
		_warning.position = back.position + Vector2(8.0, (back.size.y - _warning.get_minimum_size().y) * 0.5)


# ---------------------------------------------------------------- widgets

## A HUD text: `role` is its size in InkUi.HUD_FONT.
func _text(role: String, color: Color = InkUi.HUD_TEXT, outline: int = 4) -> Label:
	return InkUi.hud_text(role, color, outline)


func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the HUD never takes clicks (they are attacks)
	return rect


func _bar(size: Vector2, color: Color, with_trail: bool, font_role: String, ticks: int = 10) -> Dictionary:
	var back := _rect(InkUi.HUD_PANEL)
	back.size = size
	_root.add_child(back)
	var trail := _rect(InkUi.HP_TRAIL)
	trail.size = size
	trail.set_meta("with_trail", with_trail)
	trail.visible = with_trail
	_root.add_child(trail)
	var fill := _rect(color)
	fill.size = size
	_root.add_child(fill)
	var decor := InkUi.bar_decor(size, ticks)  # gloss, ticks, hatched trail, frame and caps (null = flat bars)
	var frame: Control = null
	if decor != null:
		_root.add_child(decor)
	else:
		frame = InkUi.hud_ornament(size)  # null unless the theme draws one
		if frame != null:
			_root.add_child(frame)
	var pill := Capsule.new()
	pill.visible = false
	_root.add_child(pill)
	var label := _text(font_role, InkUi.HUD_TEXT, 5)
	_root.add_child(label)
	var bar := {"width": size.x, "back": back, "trail": trail, "fill": fill, "frame": frame, "decor": decor, "label": label, "full": false, "pill": pill, "font_role": font_role}
	pill.source = bar
	return bar


func _set_bar(bar: Dictionary, ratio: float, trail_ratio: float, low: float = 0.0) -> void:
	bar["low"] = low
	bar["fill"].size.x = bar["width"] * ratio
	bar["trail"].size.x = bar["width"] * trail_ratio
	if bar["decor"] != null:
		bar["decor"].set_values(ratio, trail_ratio if bar["trail"].visible else ratio, low)


## Styles the boss bar to match the map (client/enemy_bars.gd resolves the look). `style` is a
## resolved enemy-bar style (fill, fill_low, trail, back, outline, frame, low_flash); an empty
## dictionary keeps the default Night Brass HP look. Called before the boss bar is shown so the
## Chief's bar matches its floating goblin bar.
func set_boss_style(style: Dictionary) -> void:
	if style.is_empty():
		return
	_boss["fill"].color = style.get("fill", InkUi.HP)
	_boss["trail"].color = style.get("trail", InkUi.HP_TRAIL)
	_boss["back"].color = style.get("back", InkUi.HUD_PANEL)
	var decor = _boss["decor"]
	if decor != null:  # the brass bar decoration: frame, caps, low-HP pulse
		decor.line = style.get("frame", InkUi.ORNAMENT)
		decor.low_color = style.get("low_flash", InkUi.HP_LOW)
		decor.dark = style.get("outline", InkUi.HUD_OUTLINE)
		decor.queue_redraw()


## The boss's bar (top centre; compact: under the player's bars). An empty name hides it.
func set_boss(boss_name: String, ratio: float) -> void:
	var on := not boss_name.is_empty()
	var relayout: bool = _boss_name.visible != on and _loot_feed != null  # (not while the HUD is being built)
	for part in ["back", "trail", "fill", "label"]:
		_boss[part].visible = on and (part != "trail" or ratio > 0.0)
	if _boss["decor"] != null:
		_boss["decor"].visible = on
	_boss_name.visible = on
	if relayout:
		_layout()  # (the skill banner makes room for the boss bar)
	if not on:
		return
	_boss_name.text = TEXT["boss"] % [boss_name, int(ceilf(ratio * 100.0))]
	_boss["label"].visible = false  # (the name line says it all)
	var trail: float = maxf(ratio, _boss.get("shown_trail", ratio) - 0.004)
	_boss["shown_trail"] = trail
	_set_bar(_boss, ratio, trail)


func _skill_icon(key: String, key_text: String, name_text: String) -> void:
	var root := _rect(InkUi.HUD_PANEL)
	root.size = ICON_SIZE
	_root.add_child(root)
	var fill := _rect(Color(InkUi.ULT, InkUi.ULT_ICON_FILL_ALPHA))  # fills from the bottom: the ultimate gauge
	fill.size = Vector2(ICON_SIZE.x, 0.0)
	fill.position = Vector2(0.0, ICON_SIZE.y)
	root.add_child(fill)
	var badge := _rect(InkUi.KEY_BADGE)  # the key, on a dark badge in the corner
	badge.position = Vector2(2.0, 2.0)
	root.add_child(badge)
	var key_label := _text("key", InkUi.KEY_TEXT, 3)
	key_label.text = key_text
	key_label.position = Vector2(6.0, 2.0)
	root.add_child(key_label)
	badge.size = Vector2(key_label.get_minimum_size().x + 8.0, 22.0)
	var picture := InkUi.icon(key, 30, InkUi.ICON_TINT)  # the action's brass icon (null = no icons)
	if picture != null:
		var art := TextureRect.new()
		art.texture = picture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.size = Vector2(30.0, 30.0)
		art.position = Vector2(ICON_SIZE.x - 36.0, 8.0)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(art)
		root.move_child(art, fill.get_index() + 1)
	if InkUi.FRAME_STYLE == "engraved":  # the key on a diamond, ringed in the ornament line
		badge.size = Vector2(24.0, 24.0)
		badge.pivot_offset = badge.size * 0.5
		badge.rotation_degrees = 45.0
		badge.position = Vector2(3.0, 3.0)
		badge.add_child(InkUi.hud_ornament(badge.size, false, false))
		key_label.size = Vector2(30.0, 30.0)
		key_label.position = Vector2(0.0, 0.0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var title := _text("icon", InkUi.ICON_LABEL, 3)
	title.text = name_text
	title.size = Vector2(ICON_SIZE.x, 20.0)
	title.position = Vector2(0.0, ICON_SIZE.y - 21.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var cover := _rect(InkUi.COOLDOWN_COVER)  # dark overlay that shrinks as the cooldown runs out
	cover.size = ICON_SIZE
	cover.visible = false
	root.add_child(cover)
	var time := _text("cooldown", InkUi.HUD_TEXT, 5)
	time.size = Vector2(ICON_SIZE.x, 30.0)
	time.position = Vector2(0.0, 18.0)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(time)
	var frame := InkUi.hud_ornament(ICON_SIZE, true)
	if frame != null:
		root.add_child(frame)
		root.move_child(badge, -1)  # the key stays on top, readable under the cooldown cover
		root.move_child(key_label, -1)
	_icons[key] = {"root": root, "cover": cover, "time": time, "fill": fill, "key": key_label}


## `usable` false = the player cannot afford it (red); `charging` = not ready yet but nothing is
## wrong (dim, e.g. the ultimate filling up).
func _set_icon(key: String, cooldown_ratio: float, time_text: String, active: bool, usable: bool, charging: bool = false) -> void:
	_mobile_feedback[key] = {"ratio": cooldown_ratio, "time": time_text, "active": active, "usable": usable, "charging": charging}
	var icon: Dictionary = _icons[key]
	icon["cover"].visible = cooldown_ratio > 0.0
	icon["cover"].size.y = ICON_SIZE.y * clampf(cooldown_ratio, 0.0, 1.0)
	icon["time"].text = time_text
	var tint := InkUi.HUD_PANEL
	if active:
		tint = InkUi.ICON_ACTIVE
	elif not usable:
		tint = InkUi.ICON_UNAFFORDABLE
	elif charging:
		tint = InkUi.ICON_CHARGING
	icon["root"].color = tint
	icon["key"].modulate.a = InkUi.ICON_DIM_ALPHA if (charging or not usable) else 1.0


func _build_combo() -> void:
	_combo_box = Control.new()
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_box.modulate.a = 0.0
	_root.add_child(_combo_box)

	_combo_count = InkUi.hud_text("combo", InkUi.COMBO_COOL, 12, InkUi.COMBO_OUTLINE)
	_combo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_box.add_child(_combo_count)

	_combo_hits = _text("combo_label", InkUi.COMBO_LABEL, 6)
	_combo_hits.text = TEXT["hit_combo"]
	_combo_hits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_hits.size = Vector2(236.0, 30.0)
	_combo_box.add_child(_combo_hits)

	_combo_damage = _text("combo_damage", InkUi.HUD_TEXT, 5)
	_combo_damage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_damage.size = Vector2(236.0, 26.0)
	_combo_box.add_child(_combo_damage)

	_combo_timer = _rect(InkUi.COMBO_TIMER)
	_combo_timer.size = Vector2(220.0, 5.0)
	_combo_box.add_child(_combo_timer)


func _build_overlays() -> void:
	_banner = _text("banner", InkUi.HUD_TEXT, 10)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_banner)

	_warning = _text("warning", InkUi.WARNING_TEXT, 5)
	_warning.text = TEXT["no_stamina"]
	_warning.visible = false
	_root.add_child(_warning)

	var trip_frame := InkUi.hud_ornament(Vector2(100.0, 32.0))
	if trip_frame != null:
		_trip_plate = _rect(InkUi.HELP_PLATE)
		_trip_plate.add_child(trip_frame)
		_root.add_child(_trip_plate)
		_trip_art = preload("res://client/mobile_hud_frame.gd").new()
		_trip_plate.add_child(_trip_art)
	_trip = _text("trip", InkUi.TRIP_TEXT, 5)
	_trip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_trip)

	_skill_banner = Control.new()
	_skill_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_banner.visible = false
	_root.add_child(_skill_banner)
	var stroke := Polygon2D.new()
	stroke.color = InkUi.SKILL_BANNER_BG
	var shape := [Vector2(6, 34), Vector2(40, 12), Vector2(130, 24), Vector2(260, 6), Vector2(390, 26), Vector2(480, 8), Vector2(534, 34),
			Vector2(512, 78), Vector2(470, 104), Vector2(340, 88), Vector2(230, 112), Vector2(120, 92), Vector2(34, 106), Vector2(2, 70)]
	var engraved := InkUi.FRAME_STYLE == "engraved"
	if engraved:  # a pointed plate instead of a brush stroke
		shape = [Vector2(60, 18), Vector2(480, 18), Vector2(536, 60), Vector2(480, 102), Vector2(60, 102), Vector2(4, 60)]
	var points := PackedVector2Array()
	for point in shape:
		points.append(point * Vector2(BANNER_SIZE.x / 540.0, BANNER_SIZE.y / 120.0))  # (drawn for 540x120)
	stroke.polygon = points
	_skill_banner.add_child(stroke)
	if engraved:  # its ornament lines: the edge, and a second one inset
		for inset in [0.0, 6.0]:
			var edge := Line2D.new()
			edge.width = 1.5 if inset == 0.0 else 1.0
			edge.default_color = Color(InkUi.ORNAMENT, 1.0 if inset == 0.0 else 0.5)
			edge.closed = true
			var center := BANNER_SIZE * 0.5
			for point in points:
				edge.add_point(point + (center - point).normalized() * inset * Vector2(1.6, 1.0))
			_skill_banner.add_child(edge)
	_skill_label = _text("skill", InkUi.SKILL_BANNER_TEXT, 8)
	_skill_label.size = BANNER_SIZE
	_skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_banner.add_child(_skill_label)

	_prompt = _text("prompt", InkUi.PROMPT_TEXT, 6)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)

	_info = _text("info", InkUi.INFO_TEXT, 4)
	_root.add_child(_info)

	_help_plate = _rect(InkUi.HELP_PLATE)  # keeps the small text readable over world labels and light ground
	_root.add_child(_help_plate)
	_help = _text("help", InkUi.HELP_TEXT, 4)
	_root.add_child(_help)

	_flash = _rect(InkUi.CLEAR)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


static func _seconds(ticks: int) -> String:
	return "" if ticks <= 0 else "%.1f" % (float(ticks) / 60.0)


static func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			out += ","
		out += text[i]
	return out


func mobile_feedback() -> Dictionary:
	return _mobile_feedback


## Position a physical-pixel network readout below the scaled trip row.
func network_readout_position(width: float) -> Vector2:
	var bounds := _trip.get_global_rect()
	return Vector2(maxf(8.0, bounds.end.x - width), bounds.end.y + 6.0)


func lag_report_position() -> Vector2:
	var bounds: Rect2 = _gauge["back"].get_global_rect()
	return Vector2(bounds.end.x + 8.0, bounds.get_center().y - 14.0)
