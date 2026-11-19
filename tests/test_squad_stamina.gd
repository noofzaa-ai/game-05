extends RefCounted
## The stamina strip on the battle squad cards (client/squad_panel.gd, Boss 2026-11-19): one thin strip per card under
## the HP bar, fill = Fighter.energy / max_energy(), hidden on a fallen card, red blink under SQUAD_HUD_STA_LOW (steady
## red with reduced motion), thinner than the ult strip, clear of the ult strip and the HP number on a 1280x720 desktop
## and on the 844x390 phone canvas (1558x720 logical, scale 0.54), and >= 3 window px tall on that phone.

const Fighter := preload("res://logic/fighter.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const SquadPanel := preload("res://client/squad_panel.gd")


func run(ctx) -> void:
	_check_tokens(ctx)
	await _check_values(ctx)
	for size in [Vector2i(1280, 720), Vector2i(1558, 720)]:
		await _check_layout(ctx, size)


func _fighters() -> Dictionary:
	var out := {}
	for id in [1, 2, 3]:
		var f := Fighter.new()
		f.team = "player"
		f.stats = {"HP": 100.0, "STAMINA": 120.0}
		f.hp = 100.0
		f.energy = 120.0
		f.race_state = {"race": "elf", "class": "magic", "ultimate": {"name": "X", "vfx": "race_ult/elf_magic"}}
		f.gauge = 40.0
		out[id] = f
	return out


func _check_tokens(ctx) -> void:
	ctx.check("stamina strip is thinner than the ult strip", CardTokens.SQUAD_HUD_STA_H < CardTokens.SQUAD_HUD_ULT_H)
	var phone_scale := 390.0 / 720.0
	ctx.check("stamina strip is >= 3 window px on a 844x390 phone (%.2f)" % (CardTokens.SQUAD_HUD_STA_H * phone_scale), CardTokens.SQUAD_HUD_STA_H * phone_scale >= 3.0)
	ctx.check("stamina colour differs from HP red and the warning red", not CardTokens.SQUAD_HUD_STA.is_equal_approx(CardTokens.HUD_HP) and not CardTokens.SQUAD_HUD_STA.is_equal_approx(CardTokens.SQUAD_HUD_STA_EMPTY))
	# Contrast of the fill against its dark leather back (WCAG relative luminance): a bar needs >= 3:1.
	var ratio := _contrast(CardTokens.SQUAD_HUD_STA, CardTokens.SQUAD_HUD_STA_BACK)
	ctx.check("stamina fill reads on its back (contrast %.1f:1)" % ratio, ratio >= 3.0)
	ctx.check("the low blink alternates; reduced motion stays red",
		SquadPanel.stamina_tint(true, 0.0, false) != SquadPanel.stamina_tint(true, 1.0 / CardTokens.SQUAD_HUD_STA_BLINK_HZ / 2.0 + 0.01, false)
		and SquadPanel.stamina_tint(true, 0.0, true) == CardTokens.SQUAD_HUD_STA_EMPTY
		and SquadPanel.stamina_tint(true, 0.17, true) == CardTokens.SQUAD_HUD_STA_EMPTY
		and SquadPanel.stamina_tint(false, 0.1, false) == CardTokens.SQUAD_HUD_STA)


func _check_values(ctx) -> void:
	var panel = SquadPanel.new()
	ctx.root.add_child(panel)
	await ctx.process_frame
	var fighters := _fighters()
	var data := {"rules": {"ultimate_gauge_max": 100.0}}
	fighters[2].energy = 30.0  # 25 %
	fighters[3].energy = 12.0  # 10 %: low
	panel.update_from(fighters, 1, data)
	ctx.check("every card has a stamina strip", [1, 2, 3].all(func(id): return panel._cards[id].has("sta_back") and panel._cards[id].has("sta_fill")))
	ctx.check("full stamina shows a full strip (%.2f)" % panel.stamina_shown(1), absf(panel.stamina_shown(1) - 1.0) < 0.01)
	ctx.check("stamina strip = energy / max_energy (%.2f)" % panel.stamina_shown(2), absf(panel.stamina_shown(2) - 0.25) < 0.01)
	ctx.check("25% stamina is not a warning; 10% is", not panel._cards[2]["sta_low"] and panel._cards[3]["sta_low"])
	fighters[2].energy = 0.0
	panel.update_from(fighters, 1, data)
	ctx.check("empty stamina keeps the back, no fill", panel.stamina_shown(2) == 0.0 and panel._cards[2]["sta_back"].visible)
	fighters[2].energy = 500.0
	panel.update_from(fighters, 1, data)
	ctx.check("stamina over max clamps to a full strip", absf(panel.stamina_shown(2) - 1.0) < 0.01)
	fighters[3].hp = 0.0
	fighters[3].state = Fighter.State.DEAD
	panel.update_from(fighters, 1, data)
	ctx.check("a fallen card hides its stamina strip", panel.stamina_shown(3) < 0.0 and not panel._cards[3]["sta_low"])
	panel.reduced_motion = true
	fighters[2].energy = 6.0
	panel.update_from(fighters, 1, data)
	var tints := []
	for i in 6:
		await ctx.process_frame
		tints.append(panel._cards[2]["sta_fill"].self_modulate)
	ctx.check("reduced motion: the low strip is steady red", tints.all(func(c): return c == CardTokens.SQUAD_HUD_STA_EMPTY))
	panel.queue_free()
	await ctx.process_frame


func _check_layout(ctx, size: Vector2i) -> void:
	var holder := SubViewport.new()
	holder.size = size
	holder.disable_3d = true
	ctx.root.add_child(holder)
	var panel = SquadPanel.new()
	holder.add_child(panel)
	await ctx.process_frame
	var fighters := _fighters()
	fighters[2].energy = 50.0
	panel.update_from(fighters, 1, {"rules": {"ultimate_gauge_max": 100.0}})
	panel._place()
	var tag := "%dx%d" % [size.x, size.y]
	var area := Vector2(size)
	var ok := true
	var why := ""
	for id in [1, 2, 3]:
		var card: Dictionary = panel._cards[id]
		var sta: Rect2 = card["sta_back"].get_global_rect()
		var hp: Rect2 = card["hp_back"].get_global_rect()
		var hp_text: Rect2 = card["hp_text"].get_global_rect()
		var ult: Rect2 = card["ult_back"].get_global_rect()
		var paper: Rect2 = card["paper"].get_global_rect()
		if sta.intersects(ult) or sta.intersects(hp) or sta.intersects(hp_text):
			ok = false; why += " card %d overlaps" % id
		if not paper.encloses(sta):
			ok = false; why += " card %d strip off the parchment" % id
		if sta.position.y < hp.end.y or absf(sta.size.x - hp.size.x) > 0.5:
			ok = false; why += " card %d strip not under / as wide as the HP bar" % id
		if not Rect2(Vector2.ZERO, area).encloses(card["panel"].get_global_rect()):
			ok = false; why += " card %d off screen" % id
	ctx.check("%s: stamina strip under the HP bar, clear of the ult strip and HP number%s" % [tag, why], ok)
	var top: float = panel.tutorial_rect().position.y
	ctx.check("%s: the squad tray stays in the bottom 13%% of the screen (top %.0f)" % [tag, top], top >= area.y * 0.87)
	panel.queue_free()
	holder.queue_free()
	await ctx.process_frame


static func _lum(c: Color) -> float:
	var ch := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)


static func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
