extends RefCounted
## Cross-class combo UI helpers (client/combo_ui.gd, Boss 2026-11-25): state colours/shapes, Sets / Pays off badge
## mapping, squad link counting ("Combos in squad: N pairs"), "Works with" text, the fight popup and summary lines,
## th + en text. Uses a small fixture in the combos.json contract so it runs before combat ships the real file.
const ComboUi := preload("res://client/combo_ui.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const Lang := preload("res://client/language_options.gd")
const ComboFight := preload("res://client/combo_fight.gd")
const SkillTreeTab := preload("res://client/skill_tree_tab.gd")
const JourneyScreen := preload("res://client/journey_screen.gd")

const FIXTURE := {
	"states": {
		"stagger": {"name_th": "เซ", "name_en": "Stagger", "color": "#F2C230", "icon": "stagger", "duration": 2.0},
		"cluster": {"name_th": "รวมกลุ่ม", "name_en": "Cluster", "color": "#9B5DE5", "icon": "cluster", "duration": 2.0},
		"mark": {"name_th": "หมายหัว", "name_en": "Mark", "color": "#E5383B", "icon": "mark", "duration": 4.0},
	},
	"skills": {
		"shield_rush": {"sets": ["stagger"], "payoffs": []},
		"hook_sweep": {"sets": ["cluster"], "payoffs": [{"needs": ["stagger"], "effect_th": "ดึงไกลขึ้น", "effect_en": "Pulls further"}]},
		"pinning_shot": {"sets": ["mark"], "payoffs": []},
		"starfall": {"sets": [], "payoffs": [{"needs": ["cluster"], "effect_th": "x2", "effect_en": "Double damage"}, {"needs": ["stagger", "mark"], "effect_th": "คริ", "effect_en": "Crits"}]},
	},
}


func run(ctx) -> void:
	var lang := CardTokens.language
	CardTokens.language = "en"
	# states: data colour wins, unknown fields fall back, every state of the 8 has a distinct colour AND shape
	var stagger := ComboUi.state_info("stagger", FIXTURE)
	ctx.check("combo ui: state colour from data", (stagger["color"] as Color).is_equal_approx(Color("F2C230")))
	ctx.check("combo ui: state name from data", stagger["name"] == "Stagger")
	var colors := {}
	var shapes := {}
	for st in ComboUi.ORDER:
		var info := ComboUi.state_info(st, FIXTURE)
		colors[(info["color"] as Color).to_html()] = true
		shapes[info["shape"]] = true
	ctx.check("combo ui: 8 states, 8 distinct colours", colors.size() == 8)
	ctx.check("combo ui: shapes tell states apart without colour (>= 7 shapes)", shapes.size() >= 7)
	# badges
	var b := ComboUi.badges_for("hook_sweep", FIXTURE)
	ctx.check("combo ui: sets badges", b["sets"] == ["cluster"])
	ctx.check("combo ui: payoff text in English", b["payoffs"][0]["effect"] == "Pulls further")
	ctx.check("combo ui: payoff states unique in order", ComboUi.payoff_states("starfall", FIXTURE) == ["stagger", "cluster", "mark"])
	ctx.check("combo ui: unknown skill has no badges", ComboUi.badges_for("nope", FIXTURE)["sets"].is_empty())
	# squad links: S&S rush sets stagger -> GS hook, magic starfall; GS hook sets cluster -> starfall; bow pin sets mark -> starfall
	var squad := {"sword_shield": ["shield_rush"], "greatsword": ["hook_sweep"], "magic": ["starfall"]}
	var links := ComboUi.squad_links(squad, FIXTURE)
	ctx.check("combo ui: 3 pairs in S&S + GS + Magic", ComboUi.pair_count(links) == 3)
	ctx.check("combo ui: pairs text", ComboUi.pairs_text(links, 3) == "Combos in squad: 3 pairs")
	ctx.check("combo ui: same-card skills never link", ComboUi.squad_links({"magic": ["starfall", "arcane_orb"]}, FIXTURE).is_empty())
	ctx.check("combo ui: one card -> pick hint", ComboUi.pairs_text([], 1) == ComboUi.t("squad_need"))
	ctx.check("combo ui: no pair text", ComboUi.pairs_text([], 3) == ComboUi.t("squad_none"))
	var two := ComboUi.squad_links({"longbow": ["pinning_shot"], "magic": ["starfall"]}, FIXTURE)
	ctx.check("combo ui: 1 pair singular", ComboUi.pairs_text(two, 2) == "Combos in squad: 1 pair" and two[0]["states"] == ["mark"])
	var works := ComboUi.works_with_text("starfall", links)
	ctx.check("combo ui: works-with lists both partners", works.begins_with("Works with: ") and works.contains("Shield Rush") and works.contains("Hook Sweep"))
	ctx.check("combo ui: works-with none", ComboUi.works_with_text("pinning_shot", links) == ComboUi.t("works_none"))
	# fight + summary
	ctx.check("combo ui: popup text", ComboUi.popup_text({"skill": "starfall", "states": ["cluster", "stagger"]}) == "STARFALL x2!")
	ctx.check("combo ui: popup single", ComboUi.popup_text({"skill": "starfall", "states": ["cluster"]}) == "STARFALL!")
	ctx.check("combo ui: summary text", ComboUi.summary_text(7, 0.234) == "Combos 7, combo damage 23%")
	ctx.check("combo ui: summary none", ComboUi.summary_text(0, 0.0) == ComboUi.t("summary_none"))
	ctx.check("combo ui: summary share from tally", is_equal_approx(JourneyScreen.combo_share({"combo_damage": 50.0, "team_damage": 200.0}), 0.25))
	ctx.check("combo ui: summary share prefers sim field", is_equal_approx(JourneyScreen.combo_share({"combo_damage_share": 0.4, "combo_damage": 1.0, "team_damage": 2.0}), 0.4))
	var fight := ComboFight.new()
	var tally := {}
	fight.run_tally = tally
	fight.on_combo({"type": "combo", "attacker": 1, "target": 9, "skill": "starfall", "states": ["cluster"], "damage": 30.0})
	fight.on_combo({"type": "combo", "attacker": 1, "target": 9, "skill": "starfall", "states": ["stagger", "mark"], "damage": 20.0})
	fight.on_team_damage(200.0)
	ctx.check("combo ui: fight counter + tally", fight.counter() == 2 and int(tally["combo_count"]) == 2 and is_equal_approx(JourneyScreen.combo_share(tally), 0.25))
	fight.free()
	# fighter state icons read the effects dictionary (fallback until combat names its own field)
	var f := preload("res://logic/fighter.gd").new()
	f.effects = {"mark": {"left": 10}, "slow": {"left": 5}, "stagger": {"left": 3}}
	ctx.check("combo ui: fighter states in order, non-combo effects ignored", ComboUi.fighter_states(f) == ["stagger", "mark"])
	# skill tree node -> skill
	ctx.check("combo ui: tree node maps to its skill", SkillTreeTab.node_skill({"effects": [{"type": "skill_upgrade", "skill": "starfall"}]}) == "starfall")
	# Thai text exists for every key
	CardTokens.language = "th"
	var desc_lang := Lang.value()
	Lang._value = "th"  # state names / payoff effects follow the description language (client/language_options.gd)
	var th_ok := true
	for key in ComboUi.TEXT:
		th_ok = th_ok and not str(ComboUi.TEXT[key][0]).is_empty()
	ctx.check("combo ui: Thai strings", th_ok and ComboUi.state_info("mark", FIXTURE)["name"] == "หมายหัว" and ComboUi.badges_for("hook_sweep", FIXTURE)["payoffs"][0]["effect"] == "ดึงไกลขึ้น")
	Lang._value = desc_lang
	CardTokens.language = lang
