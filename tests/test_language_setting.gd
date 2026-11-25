extends RefCounted
## Language setting (Boss 2026-11-25): a device-local "Language: EN / TH" row in Settings that switches ONLY the
## descriptions (skills, skill tree, race passives/ultimates, combos, item set/relic/boss option text, quest text).
## Menus stay English. Every description source has non-empty Thai.
const Lang := preload("res://client/language_options.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const ComboUi := preload("res://client/combo_ui.gd")
const GraphicsPanel := preload("res://client/graphics_panel.gd")


func _json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func run(ctx) -> void:
	var saved_desc := Lang.value()
	var saved_menu := CardTokens.language
	# persistence + flip
	Lang.set_value("th")
	Lang.reload_settings()
	ctx.check("language: TH persists in user://", Lang.value() == "th" and CardTokens.desc_language() == "th")
	Lang.set_value("xx")
	ctx.check("language: unknown value ignored", Lang.value() == "th")
	Lang.set_value("en")
	Lang.reload_settings()
	ctx.check("language: EN persists", Lang.value() == "en")
	ctx.check("language: default is en", Lang.DEFAULT == "en")
	var cfg := ConfigFile.new()
	ctx.check("language: saved to its own file", cfg.load(Lang.PATH) == OK and cfg.get_value("language", "descriptions", "") == "en")

	# the settings row exists, pressing TH flips the description language, menus stay English
	var panel := GraphicsPanel.contents(true, 0.6, false)
	var th_btn: Button = panel.find_child("language_th", true, false)
	var row_labels: Array = []
	ctx.check("language: Settings has an EN / TH row", th_btn != null and panel.find_child("language_en", true, false) != null)
	if th_btn != null:
		th_btn.pressed.emit()
		ctx.check("language: TH plate sets Thai descriptions", Lang.value() == "th")
		ctx.check("language: TH plate is marked", th_btn.text.begins_with("✓"))
	ctx.check("language: menus stay English in TH", CardTokens.language == "en")
	for key in ["gfx_sec_quality", "gfx_shadows", "close", "lang_row", "lang_hint"]:
		ctx.check("language: menu word %s English in TH" % key, CardTokens.t(key) == CardTokens.STRINGS[key][1])
	ctx.check("language: menu word stays English (combo title)", ComboUi.t("title") == "Squad combos")
	panel.free()

	# descriptions are Thai in TH
	var desc := CardTokens.desc({"text": "A", "text_th": "ก"})
	ctx.check("language: desc() picks text_th", desc == "ก" and CardTokens.desc({"text": "A"}) == "A")
	ctx.check("language: combo state name Thai", ComboUi.state_info("stagger")["name"] == "เซ")
	ctx.check("language: works-with line Thai", ComboUi.works_with_text("x", []) == ComboUi.TEXT["works_none"][0])
	var tree = preload("res://logic/skill_tree_data.gd").load_default()
	ctx.check("language: skill tree description Thai", tree.description("ss_t1_storm", CardTokens.desc_language()).contains("ยั่ว"))
	Lang.set_value("en")
	ctx.check("language: EN back to English", ComboUi.state_info("stagger")["name"] == "Stagger" and CardTokens.desc({"text": "A", "text_th": "ก"}) == "A")

	# coverage: every description source has non-empty Thai
	var texts: Dictionary = _json("res://data/skill_tree/texts.json")
	var missing: Array = []
	for id in texts["en"]:
		if str(texts.get("th", {}).get(id, "")).strip_edges().is_empty(): missing.append(id)
	ctx.check("language: every skill tree node has Thai (%s)" % str(missing), missing.is_empty() and texts["en"].size() > 100)
	var combos: Dictionary = _json("res://data/combat/combos.json")
	missing = []
	for st in combos["states"]:
		if str(combos["states"][st].get("name_th", "")).is_empty(): missing.append(st)
	var class_skills: Dictionary = _json("res://data/class_skills/class_skills.json")
	for skill in class_skills["skills"]:
		if not combos["skills"].has(skill): missing.append("no combo row " + skill); continue
		for p in combos["skills"][skill].get("payoffs", []):
			if str(p.get("effect_th", "")).is_empty(): missing.append(skill)
	ctx.check("language: every combo state / class skill payoff has Thai (%s)" % str(missing), missing.is_empty())
	missing = []
	for race in ["human", "viking", "elf", "runeborn"]:
		var r: Dictionary = _json("res://data/races/%s.json" % race)
		var blocks: Array = [r["default_class"]]
		for c in r["classes"]: blocks.append(r["classes"][c])
		for b in blocks:
			for k in ["passive", "ultimate"]:
				if b.has(k) and str(b[k].get("text_th", "")).is_empty(): missing.append("%s %s" % [race, k])
		for n in r["synergy"]:
			if str(r["synergy"][n].get("text_th", "")).is_empty(): missing.append("%s synergy %s" % [race, n])
	if str(_json("res://data/races/rules.json")["alliance"].get("text_th", "")).is_empty(): missing.append("alliance")
	ctx.check("language: every race passive / ultimate / synergy has Thai (%s)" % str(missing), missing.is_empty())
	missing = []
	var sets: Dictionary = _json("res://data/items/sets.json")["sets"]
	for set_id in sets:
		for step in sets[set_id].get("steps", []):
			if step.has("text") and str(step.get("text_th", "")).is_empty(): missing.append(set_id)
			for c in step.get("by_class", {}):
				if str(step["by_class"][c].get("text_th", "")).is_empty(): missing.append("%s %s" % [set_id, c])
	var relics: Dictionary = _json("res://data/items/catalog.json")["relics"]
	for id in relics:
		if str(relics[id].get("text_th", "")).is_empty(): missing.append(id)
	var procs: Dictionary = _json("res://data/items/boss_options.json")
	for status in procs.get("status_names", {}):
		if str(procs["status_names"][status][0]).is_empty(): missing.append("status " + status)
	ctx.check("language: every item set / relic / boss option text has Thai (%s)" % str(missing), missing.is_empty())

	Lang.set_value(saved_desc)
	CardTokens.language = saved_menu
