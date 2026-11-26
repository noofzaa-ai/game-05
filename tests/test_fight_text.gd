extends RefCounted
## Fight-screen text rules (client/fight_text_rules.gd + data/ui/fight_text.json, Boss 2026-11-25 "clean fight screen"):
## merge of the same word, the per-fighter lane cap, the phone/desktop screen budget, suppressed categories, the
## single top combo lane, the damage-number filter and status icons for every effect in data/combat/effects.json.
const Rules := preload("res://client/fight_text_rules.gd")
const ComboFight := preload("res://client/combo_fight.gd")


func run(ctx) -> void:
	var data := Rules.load_default()
	ctx.check("fight text: data file loads", not data.is_empty() and data.has("budget") and data.has("categories"))
	var r = Rules.new()
	# merge: same word within merge_seconds -> one line "x3"
	r.push(1, "info", "+FORTIFY")
	r.tick(0.4)
	r.push(1, "info", "+FORTIFY")
	r.tick(0.4)
	ctx.check("fight text: merge returns merged", r.push(1, "info", "+FORTIFY") == "merged")
	ctx.check("fight text: merged into one line x3", r.lanes[1].size() == 1 and r.lanes[1][0]["text"] == "+FORTIFY x3")
	r.tick(float(data["merge_seconds"]) + 0.1)
	ctx.check("fight text: after the window it expires (no ghost)", not r.lanes.has(1) or r.lanes[1].size() == 0)
	# lane cap
	var c = Rules.new()
	for w in ["A", "B", "C", "D"]:
		c.push(5, "info", w)
	ctx.check("fight text: lane keeps max lane_lines, newest kept", c.lanes[5].size() == int(data["lane_lines"]) and c.lanes[5][-1]["text"] == "D")
	# screen budget phone vs desktop
	var p = Rules.new()
	p.phone = true
	for id in range(10):
		p.push(id, "info", "W%d" % id)
	ctx.check("fight text: phone budget", p.line_count() == int(data["budget"]["phone"]))
	var d = Rules.new()
	for id in range(10):
		d.push(id, "info", "W%d" % id)
	ctx.check("fight text: desktop budget", d.line_count() == int(data["budget"]["desktop"]))
	# suppressed categories
	var s = Rules.new()
	ctx.check("fight text: our buff -> icon, no text", s.push(1, "buff_ours", "+HASTE") == "icon" and s.line_count() == 0)
	ctx.check("fight text: enemy debuff -> icon", s.push(100, "debuff_enemy", "BURN") == "icon")
	ctx.check("fight text: resist hidden", s.push(100, "resist", "RESIST") == "hide")
	ctx.check("fight text: boss label hidden", s.category_action("boss_label") == "hide")
	ctx.check("fight text: class skill bubble hidden", s.category_action("class_skill") == "hide")
	ctx.check("fight text: loot goes to the feed", s.push(1, "loot", "+1") == "feed" and s.line_count() == 0)
	ctx.check("fight text: ultimates keep a line", s.category_action("ultimate") == "lane")
	# big control once
	var o = Rules.new()
	ctx.check("fight text: stun shows once", o.push(100, "control", "STUN") == "lane")
	o.tick(1.5)
	ctx.check("fight text: stun again soon is skipped", o.push(100, "control", "STUN") == "once_skipped")
	ctx.check("fight text: control category from effect", Rules.effect_category({"kind": "debuff", "control": "stun"}, false) == "control" and Rules.effect_category({"kind": "buff"}, true) == "buff_ours" and Rules.effect_category({"kind": "debuff"}, false) == "debuff_enemy")
	# top lane: one combo at a time
	var t = Rules.new()
	t.push(100, "combo", "STARFALL!")
	t.push(101, "combo", "REAPING ARC x2!")
	ctx.check("fight text: one combo popup, newest", t.top["text"] == "REAPING ARC x2!" and t.line_count() == 0)
	var fight := ComboFight.new()
	fight.run_tally = {}
	fight.on_combo({"type": "combo", "target": 9, "skill": "starfall", "states": ["cluster"]})
	fight.on_combo({"type": "combo", "target": 9, "skill": "starfall", "states": ["mark"]})
	ctx.check("fight text: combo fight keeps one popup", fight.popup_count() == 1)
	fight.free()
	# numbers
	var n = Rules.new()
	ctx.check("fight text: normal small hit no number", not n.shows_number(10.0, 540.0, false))
	ctx.check("fight text: crit shows", n.shows_number(10.0, 540.0, true))
	ctx.check("fight text: combo payoff shows", n.shows_number(5.0, 0.0, false, true))
	ctx.check("fight text: big hit shows", n.shows_number(60.0, 540.0, false))
	ctx.check("fight text: small heal hidden, big heal shown", not n.shows_heal(5.0, 500.0) and n.shows_heal(80.0, 500.0))
	# every effect has an icon
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/effects.json"))
	effects = effects.get("effects", effects)
	var missing: Array = []
	for id in effects:
		if effects[id] is Dictionary and n.status_icon(id).is_empty():
			missing.append(id)
	ctx.check("fight text: every status effect has an icon %s" % [missing], missing.is_empty())
	ctx.check("fight text: statuses_of reads effects", n.statuses_of({"burn": {}, "fortify": {}, "zzz": {}}).size() == 2)
