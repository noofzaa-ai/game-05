extends RefCounted
## Fight HUD layout (ux-ui 2026-11-25, phone bug at 844x390): in auto-battle the boss bar, trip line, loot feed, squad
## cards (with their ultimate banners) and the combo line never overlap, at a phone landscape (844x390, compact HUD)
## and at 1280x720 / 1920x1080. The boss bar is in the top band, the squad cards keep the bottom.

const Fighter := preload("res://logic/fighter.gd")
const Hud := preload("res://client/hud.gd")
const SquadPanel := preload("res://client/squad_panel.gd")
const ComboFight := preload("res://client/combo_fight.gd")


func run(ctx) -> void:
	ctx.check("trip line: phone splits into two lines", Hud.trip_line("Enemies  1", "Wave 9/9    Bag 0/16    Gold 78", true).split("\n").size() == 2)
	ctx.check("trip line: desktop stays one line", not Hud.trip_line("Enemies  1", "Wave 9/9    Bag 0/16    Gold 78", false).contains("\n"))
	for item in [[Vector2i(844, 390), 1], [Vector2i(1280, 720), 0], [Vector2i(1920, 1080), 0]]:
		await _check(ctx, item[0], item[1])


func _fighters() -> Dictionary:
	var out := {}
	for id in [1, 2, 3]:
		var f := Fighter.new()
		f.team = "player"
		f.stats = {"HP": 100.0, "STAMINA": 120.0}
		f.hp = 100.0
		f.energy = 120.0
		f.race_state = {"race": "elf", "class": "magic", "ultimate": {"name": "X", "vfx": "race_ult/elf_magic"}}
		out[id] = f
	return out


func _check(ctx, size: Vector2i, compact: int) -> void:
	var holder := SubViewport.new()
	holder.size = size
	holder.disable_3d = true
	ctx.root.add_child(holder)
	var hud = Hud.new()
	hud.compact_override = compact
	holder.add_child(hud)
	await ctx.process_frame
	hud.auto_battle = true
	hud.set_boss("Orc Warlock", 0.8)
	hud._trip.text = Hud.trip_line("Enemies  1", "Wave 9/9    Bag 0/16    Gold 78", hud.compact)
	hud._layout()
	for i in 6:
		hud.add_loot("+%d Golden Blossom Katana" % (i * 10), Color.WHITE)
	var panel = SquadPanel.new()
	holder.add_child(panel)
	await ctx.process_frame
	panel.reduced_motion = true  # (no pop-in scale: measure the resting banners)
	panel.update_from(_fighters(), 1, {"rules": {"ultimate_gauge_max": 100.0}})
	panel._place()
	for id in [1, 2, 3]:  # all three ultimates at once
		panel.ultimate_callout(id, "Ragnarok Whirlwind Storm", "elf")
	await ctx.process_frame
	await ctx.process_frame
	var combo = ComboFight.new()
	combo.keep_out = hud.keep_out_rects()
	var tag := "%dx%d" % [size.x, size.y]
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var rects: Dictionary = hud.layout_rects()
	rects["combo"] = combo.counter_rect(Vector2(size))
	for id in [1, 2, 3]:
		rects["card%d" % id] = panel.card_rect(id)
		rects["ult%d" % id] = (panel._cards[id]["ult_banner"] as Control).get_global_rect()
	var why := ""
	var keys := rects.keys()
	for i in keys.size():
		var a: Rect2 = rects[keys[i]]
		if not screen.encloses(a):
			why += " %s off screen %s;" % [keys[i], a]
		for j in range(i + 1, keys.size()):
			if a.intersects(rects[keys[j]]):
				why += " %s %s x %s %s;" % [keys[i], a, keys[j], rects[keys[j]]]
	ctx.check("%s fight HUD: no overlaps (%s)" % [tag, why], why.is_empty())
	var boss: Rect2 = rects["boss"]
	ctx.check("%s fight HUD: boss bar top centre (%s)" % [tag, boss], boss.end.y < size.y * 0.3 and absf(boss.get_center().x - size.x * 0.5) < size.x * 0.05)
	ctx.check("%s fight HUD: squad cards at the bottom" % tag, (rects["card1"] as Rect2).position.y > size.y * 0.7)
	combo.free()
	holder.queue_free()
	await ctx.process_frame
