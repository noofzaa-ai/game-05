extends SceneTree
## Windowed shots of the Thai description language (Boss 2026-11-25): settings row, skill detail, item details,
## squad combos board, fight combo popup. Real data. Restores the saved language at the end.
## godot --path . --script res://tools/ui/language_shots.gd -- <out dir> <w> <h>
const CardTokens := preload("res://client/card_tokens.gd")
const Lang := preload("res://client/language_options.gd")
var out := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var size := Vector2i(int(a[1]), int(a[2]))
	DisplayServer.window_set_size(size)
	root.size = size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_run.call_deferred(size)

func _bg() -> void:
	var bg := CardTokens.art_rect(CardTokens.HUB_BG)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

func _snap(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("SHOT ", out + "/" + name + ".png")

var _keep: Array = []

func _clear() -> void:
	for c in root.get_children():
		if not _keep.has(c): c.queue_free()
	await process_frame
	await process_frame

func _run(size: Vector2i) -> void:
	_keep = root.get_children()
	var saved := Lang.value()
	Lang.set_value("th")
	var tag := "%dx%d" % [size.x, size.y]
	var s := CardTokens.scale_for(Vector2(size))
	# 1 settings
	_bg()
	var panel = load("res://client/graphics_panel.gd").new()
	root.add_child(panel)
	for i in 6: await process_frame
	var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
	var row: Control = panel.find_child("Row_language", true, false)
	if scroll != null and row != null:
		scroll.ensure_control_visible(row)
	await _snap("settings_" + tag)
	await _clear()
	# 2 skill detail (real data)
	_bg()
	var tab = preload("res://client/skill_tree_tab.gd").new()
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.phone = CardTokens.is_phone(Vector2(size))
	tab.s = s
	root.add_child(tab)
	tab.show_card("sword_shield", preload("res://logic/card_deck.gd").initial(), 0)
	await process_frame
	tab.layout_tab()
	tab.select("ss_t2_storm_b")
	await _snap("skill_detail_" + tag)
	await _clear()
	# 3 item details: boss weapon (boss option) with a socketed relic + the boss set lines below
	_bg()
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var item = preload("res://logic/item_system.gd").create_item(rules, "shot-1", "weapon", 2, RandomNumberGenerator.new(), "", "boss_mummy_high_wizard_staff")
	item.relic = "relic_mummy_high_wizard"
	var details = preload("res://client/hub_item_details.gd").new()
	details.cell.card_race = "human"
	details.cell.card_level = 30
	root.add_child(details)
	var w := minf(size.x - 32.0, 900.0 * s * 1.4)
	details.position = Vector2(16, 16)
	details.layout_box(w, size.y * 0.62, 56.0 * s, s, size.x > size.y * 1.5)
	details.show_item(item, rules)
	details.show_socket(item, rules)
	var set_box := VBoxContainer.new()
	set_box.position = Vector2(16, size.y * 0.66)
	set_box.size = Vector2(w, size.y * 0.3)
	root.add_child(set_box)
	for line in preload("res://client/item_text.gd").boss_set_lines(item, rules, []):
		var l := CardTokens.hub_label(str(line["text"]), CardTokens.FONT_CHAR_STAT, CardTokens.HUB_INK, s, 0, "medium")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = w
		set_box.add_child(l)
	await _snap("item_details_" + tag)
	await _clear()
	# 4 squad combos board (real combos.json)
	_bg()
	var board = preload("res://client/squad_combos.gd").new()
	root.add_child(board)
	board.open(["sword_shield", "greatsword", "magic"])
	board.select_skill("starfall")
	await _snap("squad_combos_" + tag)
	await _clear()
	# 5 fight popup
	_bg()
	var heads := {1: Vector2(size) * Vector2(0.35, 0.45), 2: Vector2(size) * Vector2(0.55, 0.5), 3: Vector2(size) * Vector2(0.7, 0.4)}
	var fighters := {}
	for id in heads: fighters[id] = preload("res://logic/fighter.gd").new()
	fighters[1].effects = {"stagger": {}, "mark": {}}
	fighters[2].effects = {"cluster": {}, "stagger": {}, "sunder": {}, "airborne": {}}
	fighters[3].effects = {"guarded": {}}
	var fight = preload("res://client/combo_fight.gd").new()
	fight.fighter_ids = func(): return heads.keys()
	fight.fighter_of = func(id): return fighters[id]
	fight.head_point = func(id): return heads.get(id)
	root.add_child(fight)
	fight.on_combo({"target": 2, "skill": "starfall", "states": ["cluster", "stagger"]})
	fight.on_combo({"target": 1, "skill": "heartseeker_shot", "states": ["sunder"]})
	await _snap("fight_" + tag)
	Lang.set_value(saved)
	quit()
