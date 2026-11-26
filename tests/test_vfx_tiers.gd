extends RefCounted
## VFX hierarchy + fight light (tech-artist 2026-11-25, Boss approved): tier A (boss big moves + race ultimates) keeps
## the full look and is the only tier with a screen flash / zoom punch; tier B (class skills, combos, monster shots) is
## clearly smaller; tier C (plain hits) has no debris and no screen flash; debris and smoke are capped on screen (lower on
## phones) and smoke lives shorter; every zone has a fight light and the orc night is lifted the most.

const VfxLibrary := preload("res://client/vfx/vfx_library.gd")
const Violence := preload("res://client/vfx/violence.gd")
const ViolentVfx := preload("res://client/vfx/violent_vfx.gd")
const FightLight := preload("res://client/fight_light.gd")
const BASIC_HITS := ["hit", "hit/heavy", "hit/crit", "hit/launch", "hit/knockback", "hit/armored", "skill_hit/1", "skill_hit/2", "skill_hit/3", "skill_hit/crit"]


static func _count(layers: Array, style: String) -> int:
	var n := 0
	for l in layers:
		if str(l.get("style", "")) == style:
			n += int(l.get("count", 0))
	return n


static func _has(layers: Array, type: String) -> bool:
	return layers.any(func(l): return str(l.get("type")) == type)


func run(ctx) -> void:
	var lib = VfxLibrary.load_default()
	ctx.check("vfx.json loads %s" % [lib.errors], lib.is_valid())
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Violence.DATA_PATH))["violence"]
	var tiers: Dictionary = data.get("tiers", {})
	ctx.check("every preset has a tier", Array(data["presets"]).all(func(p): return str(tiers.get(p, "")) in ["A", "B"]))
	ctx.check("boss and ultimates are tier A", tiers.get("boss") == "A" and tiers.get("ult") == "A" and tiers.get("ult_aura") == "A")
	ctx.check("class skills and shots are tier B", tiers.get("skill") == "B" and tiers.get("shot") == "B")
	var budget: Dictionary = data.get("budget", {})
	ctx.check("debris / smoke caps exist, phone lower", int(budget.get("debris_phone", 999)) < int(budget.get("debris", 0)) and int(budget.get("smoke_phone", 999)) < int(budget.get("smoke", 0)))
	ctx.check("only tier A flashes the screen", Array(budget.get("flash_tiers", [])) == ["A"])
	for lvl in ["L3", "L3_phone"]:
		var a: Array = lib.layers("violent/boss/" + lvl)
		var u: Array = lib.layers("violent/ult/" + lvl)
		var b: Array = lib.layers("violent/skill/" + lvl)
		var s: Array = lib.layers("violent/shot/" + lvl)
		ctx.check("%s: tier A keeps flash + punch" % lvl, _has(a, "flash") and _has(a, "punch") and _has(u, "flash"))
		ctx.check("%s: tier B has no flash, no punch" % lvl, not _has(b, "flash") and not _has(b, "punch") and not _has(s, "flash"))
		ctx.check("%s: tier B debris < tier A debris (%d < %d)" % [lvl, _count(b, "chunk"), _count(a, "chunk")], _count(b, "chunk") < _count(a, "chunk"))
		ctx.check("%s: tier A debris at most half the old 56 (%d)" % [lvl, _count(a, "chunk")], _count(a, "chunk") <= 28)
		ctx.check("%s: tier A debris fits the cap" % lvl, _count(a, "chunk") <= int(budget["debris_phone" if lvl.ends_with("phone") else "debris"]))
		for l in a + b + u + s:
			if str(l.get("style", "")) == "smoke":
				ctx.check("%s: smoke lives <= 2 s (%.2f)" % [lvl, float(l["seconds"])], float(l["seconds"]) <= 2.0)
	for key in BASIC_HITS:
		if lib.has(key):
			ctx.check("tier C '%s': no debris, no screen flash" % key, _count(lib.layers(key), "chunk") == 0 and not _has(lib.layers(key), "flash"))
	# runtime cap: the debris budget refuses a blow that would pass it, and frees as the particles die
	var v := ViolentVfx.new()
	v.load_data(Violence.DATA_PATH)
	var boss: Array = lib.layers("violent/boss/L3_phone")
	var cap := v.cap_of("chunk", true)
	var played := 0
	for i in 6:
		if not "chunk" in v.budget_drop(boss, true, 1.0):
			played += 1
	ctx.check("phone debris on screen stays <= cap (%d <= %d)" % [v.alive_particles("chunk"), cap], v.alive_particles("chunk") <= cap and played >= 1 and played < 6)
	v.tick_budget(10.0)
	ctx.check("the budget frees when the debris is gone", v.alive_particles("chunk") == 0 and v.alive_particles("smoke") == 0)
	ctx.check("tier_of maps keys by preset", v.tier_of("monster/orc_warlock_cataclysm") == "A" and v.tier_of("class_skill/reaping_arc") == "B")
	v.free()
	# fight light
	var orc := FightLight.zone("orc_camp_night")
	var gob := FightLight.zone("goblin_base_courtyard")
	for id in ["goblin_base_courtyard", "mummy_pyramid_hall", "orc_camp_night", "elder_grove_heart"]:
		var z := FightLight.zone(id)
		ctx.check("%s has a fight light, brighter than before" % id, float(z.get("exposure", 0)) >= 1.0 and float(z.get("rim", 0)) >= 1.0 and float(z.get("key", 0)) >= 1.0)
	ctx.check("the orc camp is lifted most", float(orc["exposure"]) > float(gob["exposure"]))
	# Boss 2026-11-25: the orc camp at DUSK: an orange -> pink -> violet sky, a low warm sun from one side, a warm rim, a violet shade
	var sky: Array = orc.get("sky", [])
	ctx.check("orc dusk sky is violet at the top and orange at the horizon %s" % [sky], sky.size() == 3 and Color.html(sky[0]).b > Color.html(sky[0]).r and Color.html(sky[2]).r > Color.html(sky[2]).b)
	ctx.check("orc dusk sun is low (< 25 deg) and warm", absf(float(orc["sun_rotation"][0])) < 25.0 and Color.html(orc["sun_color"]).r > Color.html(orc["sun_color"]).b)
	ctx.check("orc dusk rim is warm, the shade violet", Color.html(orc["rim_color"]).r > Color.html(orc["rim_color"]).b and Color.html(orc["ambient_color"]).b > Color.html(orc["ambient_color"]).g)
