extends SceneTree
## Windowed screenshots of the combo UI (fixture data until data/combat/combos.json exists):
## godot --path . --script res://tools/ui/combo_shots.gd -- <out dir> <w> <h>
const ComboUi := preload("res://client/combo_ui.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const FIX := {"states": {}, "skills": {
	"shield_rush": {"sets": ["stagger"], "payoffs": []},
	"iron_guard": {"sets": ["taunt", "guarded"], "payoffs": []},
	"intercept": {"sets": ["guarded"], "payoffs": [{"needs": ["mark"], "effect_en": "Leaps to the mark"}]},
	"breaker_slam": {"sets": ["sunder"], "payoffs": [{"needs": ["stagger"], "effect_en": "x2 damage"}]},
	"reaping_arc": {"sets": [], "payoffs": [{"needs": ["sunder"], "effect_en": "+50%"}]},
	"crater_leap": {"sets": ["airborne"], "payoffs": [{"needs": ["cluster"], "effect_en": "Bigger"}]},
	"hook_sweep": {"sets": ["cluster"], "payoffs": [{"needs": ["stagger"], "effect_en": "Pulls further"}]},
	"battle_trance": {"sets": ["hasted"], "payoffs": []},
	"heartseeker_shot": {"sets": [], "payoffs": [{"needs": ["mark"], "effect_en": "Crit"}]},
	"pinning_shot": {"sets": ["mark"], "payoffs": [{"needs": ["airborne"], "effect_en": "Pins"}]},
	"rapid_fire": {"sets": [], "payoffs": [{"needs": ["sunder"], "effect_en": "Pierce"}]},
	"vault_shot": {"sets": ["hasted"], "payoffs": []},
	"arcane_orb": {"sets": ["mark"], "payoffs": []},
	"repulse_nova": {"sets": ["airborne"], "payoffs": [{"needs": ["guarded"], "effect_en": "Shield"}]},
	"starfall": {"sets": ["stagger"], "payoffs": [{"needs": ["cluster", "stagger"], "effect_en": "x2"}]},
	"warding_veil": {"sets": ["guarded"], "payoffs": [{"needs": ["taunt"], "effect_en": "Bigger veil"}]}}}

var out := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var size := Vector2i(int(a[1]), int(a[2]))
	DisplayServer.window_set_size(size)
	root.size = size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	ComboUi._default = FIX
	_run.call_deferred(size)

func _bg() -> Control:
	var bg := CardTokens.art_rect(CardTokens.HUB_BG)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	return bg

func _snap(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")

func _clear() -> void:
	for c in root.get_children(): c.queue_free()
	await process_frame

func _run(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	# 1 squad combos board
	_bg()
	var board = preload("res://client/squad_combos.gd").new()
	root.add_child(board)
	board.open(["sword_shield", "greatsword", "magic"])
	await _snap("squad_" + tag)
	board.select_skill("starfall")
	await _snap("squad_tap_" + tag)
	await _clear()
	# 2 skill detail
	_bg()
	var tab = preload("res://client/skill_tree_tab.gd").new()
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.phone = CardTokens.is_phone(Vector2(size))
	tab.s = CardTokens.scale_for(Vector2(size))
	root.add_child(tab)
	var deck: Dictionary = preload("res://logic/card_deck.gd").initial()
	tab.show_card("magic", deck, 0)
	await process_frame
	tab.layout_tab()
	tab.select("mg_t1_strike")
	await _snap("skill_detail_" + tag)
	await _clear()
	# 3 fight overlay (over a still background; heads at fixed points)
	_bg()
	var heads := {1: Vector2(size) * Vector2(0.35, 0.45), 2: Vector2(size) * Vector2(0.55, 0.5), 3: Vector2(size) * Vector2(0.7, 0.4)}
	var fighters := {}
	for id in heads:
		var f := preload("res://logic/fighter.gd").new()
		fighters[id] = f
	fighters[1].effects = {"stagger": {}, "mark": {}}
	fighters[2].effects = {"cluster": {}, "stagger": {}, "sunder": {}, "airborne": {}}
	fighters[3].effects = {"guarded": {}}
	var fight = preload("res://client/combo_fight.gd").new()
	fight.fighter_ids = func(): return heads.keys()
	fight.fighter_of = func(id): return fighters[id]
	fight.head_point = func(id): return heads.get(id)
	root.add_child(fight)
	fight.on_combo({"target": 2, "skill": "starfall", "states": ["cluster", "stagger"]})
	fight.on_combo({"target": 1, "skill": "heartseeker_shot", "states": ["mark"]})
	await _snap("fight_" + tag)
	await _clear()
	# 4 summary line on parchment (the real summary needs a finished journey; this shows the line itself)
	_bg()
	var s := CardTokens.scale_for(Vector2(size))
	var pc := PanelContainer.new()
	CardTokens.panel(pc, preload("res://client/hub_look.gd").parchment(s))
	pc.position = Vector2(size) * 0.2
	pc.size = Vector2(size) * Vector2(0.6, 0.3)
	root.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(CardTokens.hub_label("Victory", CardTokens.FONT_SUMMARY_TITLE, CardTokens.HUB_INK, s))
	v.add_child(CardTokens.hub_label(ComboUi.summary_text(14, 0.31), CardTokens.FONT_SUMMARY_LINE, CardTokens.HUB_SUBTEXT, s, 0, "medium"))
	await _snap("summary_" + tag)
	quit()
