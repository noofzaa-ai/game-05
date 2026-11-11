extends RefCounted
## Tests the data-driven enemy health-bar styles (data/ui/enemy_bars.json via client/enemy_bars.gd):
## the file loads, every map resolves to a style, the goblin maps get the goblin style with its
## elite/boss richer frames, other maps fall back to brass, null colours become InkUi tokens, and
## the floating bar in fighter_view still shrinks with HP while drawing the data-driven look.

const EnemyBars := preload("res://client/enemy_bars.gd")
const FighterView := preload("res://client/fighter_view.gd")
const InkUi := preload("res://client/ink_ui.gd")
const MapLoader := preload("res://logic/map_loader.gd")

## Every map file that must resolve to a style (the index plus the journey boss arena).
const MAPS := ["sunward_valley", "ink_garden", "shrine_wall", "brush_ring", "practice_field", "goblin_arena_a", "goblin_arena_b", "goblin_rest_camp"]
## The goblin-family maps (Boss 2026-10-12: enemy bars match the map theme; the goblin stages first).
const GOBLIN_MAPS := ["ink_garden", "shrine_wall", "brush_ring", "sunward_valley", "goblin_arena_a", "goblin_arena_b", "goblin_rest_camp"]


func run(ctx) -> void:
	var bars = EnemyBars.new().load_default()
	ctx.check("the enemy bar file loads with no errors (%s)" % str(bars.errors), bars.is_valid())

	# 1. Every map resolves to a usable style with every key present.
	var all_resolve := true
	var missing := ""
	for map_id in MAPS:
		var map := MapLoader.load_by_id(map_id)
		for tier in ["base", "elite", "boss"]:
			var style: Dictionary = bars.resolve(map.id, map.atmosphere, tier)
			for key in EnemyBars.KEYS:
				if not style.has(key):
					all_resolve = false
					missing = "%s/%s missing %s" % [map_id, tier, key]
			if not (style["fill"] is Color) or not (style["frame"] is Color):
				all_resolve = false
				missing = "%s/%s colours not Color" % [map_id, tier]
	ctx.check("every map resolves to a full style for base/elite/boss (%s)" % missing, all_resolve)

	# 2. The goblin maps get the goblin style: a crude frame and a mossy (greenish) fill, not the red HP.
	var goblin_ok := true
	for map_id in GOBLIN_MAPS:
		var map := MapLoader.load_by_id(map_id)
		var style: Dictionary = bars.resolve(map.id, map.atmosphere, "base")
		var fill: Color = style["fill"]
		var mossy := fill.g > fill.r  # mossy green-yellow: green channel above red (the HP red is the opposite)
		goblin_ok = goblin_ok and style["frame_shape"] == "crude" and style["mark"] == "fang" and mossy
	ctx.check("goblin maps use the crude goblin bar: a fang mark and a mossy fill, not the player's red", goblin_ok)

	# 3. The elite and the Chief get a richer frame (not the grunt's crude one) and their own marks.
	var garden := MapLoader.load_by_id("ink_garden")
	var elite: Dictionary = bars.resolve(garden.id, garden.atmosphere, "elite")
	var chief: Dictionary = bars.resolve(garden.id, garden.atmosphere, "boss")
	ctx.check("the goblin elite (knight) gets a richer studded frame and a double fang",
		elite["frame_shape"] == "studded" and elite["mark"] == "fang_double")
	ctx.check("the Goblin Chief gets the richest frame and a skull mark", chief["frame_shape"] == "chief" and chief["mark"] == "skull")

	# 4. The enemy type -> tier mapping is data-driven (knight = elite, chief = boss, grunt = base).
	ctx.check("tier_for maps the goblin types: grunt base, knight elite, chief boss",
		bars.tier_for("goblin") == "base" and bars.tier_for("goblin_knight") == "elite"
		and bars.tier_for("goblin_chief") == "boss" and bars.tier_for("goblin", true) == "boss")

	# 5. A non-goblin / unknown map falls back to the plain brass style, whose null colours become
	#    the live InkUi tokens (so a chosen theme still drives the default bar).
	var brass: Dictionary = bars.resolve("some_unlisted_map", "golden", "base")
	ctx.check("an unlisted map falls back to brass (plain frame)", brass["frame_shape"] == "plain")
	ctx.check("brass null colours resolve to the InkUi HP / HP_TRAIL tokens",
		brass["fill"].is_equal_approx(InkUi.HP) and brass["trail"].is_equal_approx(InkUi.HP_TRAIL))

	# 6. The floating bar in fighter_view draws the style and still shrinks with HP.
	var view := FighterView.new()
	view.show_health_bar = true
	view.monster_model_path = ""  # a capsule, so _ready does not need a model file
	view.bar_style = bars.resolve(garden.id, garden.atmosphere, "base")
	ctx.root.add_child(view)
	await ctx.process_frame
	ctx.check("the floating bar is built with its frame and fill", view._bar_fill != null and view._bar_frame != null)
	var full: float = view._bar_fill.scale.x
	# drop the fighter to half HP through a hand-made state and check the bar follows
	var fighter = _hurt_fighter(0.5)
	var body = _body(Vector3(0.0, 0.05, 0.0))
	view.show_state(body, fighter)
	var half: float = view._bar_fill.scale.x
	fighter = _hurt_fighter(0.1)  # below the low-HP threshold: the fill recolours toward low/flash
	view.show_state(body, fighter)
	ctx.check("the floating bar shrinks with HP (full %.2f, half %.2f, low %.2f)" % [full, half, view._bar_fill.scale.x],
		full > half and half > view._bar_fill.scale.x and view._bar_fill.scale.x < 0.2)
	var low_color: Color = view._bar_fill_material.albedo_color
	var base_color: Color = view.bar_style["fill"]
	ctx.check("a near-dead goblin bar leaves its base fill colour (low-HP warning)", not low_color.is_equal_approx(base_color))
	view.queue_free()
	await ctx.process_frame


## A fighter at `ratio` of its max HP, built without the sim (enough for the bar's show_state).
func _hurt_fighter(ratio: float):
	var Fighter := load("res://logic/fighter.gd")
	var fighter = Fighter.new()
	fighter.stats = {"HP": 100.0}
	fighter.hp = fighter.max_hp() * ratio
	return fighter


func _body(at: Vector3):
	var SimBody := load("res://logic/sim_body.gd")
	var body = SimBody.new()
	body.position = at
	return body
