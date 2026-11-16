extends RefCounted
## Repair regression (Boss 2026-11-16 "can't repair"): an item worn to 0 (five deaths at death_wear 20) took the
## "broken" price, which asked for Leather x5 + Essence x2 on top of gold. A starter stash holds Ore 10 / Leather 4 and
## no Essence, so the Repair button was live but every press answered "Not enough gold or materials", even with
## 500k gold. data/camp/camp.json broken repair now asks for Ore only; Repair.missing names any shortfall.
const F := preload("res://tests/online_fixture.gd")
const Commands := preload("res://logic/commands.gd")
const Repair := preload("res://logic/repair.gd")
const Wear := preload("res://logic/wear.gd")


func run(ctx) -> void:
	var f := F.make()
	var p = f["profile"]
	p.stash.gold = 500000
	ctx.check("starter stash is what a new player has (no essence)", p.stash.material_count("essence") == 0)

	# A greatsword card that died five times: every worn piece at 0.
	var card := "greatsword"
	var loadout = p.loadout_of(card)
	for i in 5:
		Wear.death(loadout, f["rules"])
	var weapon = loadout.item_at("weapon")
	ctx.check("five deaths wear the weapon to 0", weapon.durability == 0.0 and weapon.is_broken_down())

	var quote := Repair.quote(weapon, f["camp"])
	ctx.check("broken repair is the costly kind", quote["kind"] == "broken" and int(quote["gold"]) > 0)
	ctx.check("broken repair of a starter piece is payable from the starter stash", p.stash.can_afford(quote))
	var result := Commands.apply(f, {"type": "repair", "item": weapon.id}, F.rng())
	ctx.check("repair command on a worn-out weapon succeeds", result.get("ok", false))
	ctx.check("weapon back to full durability", weapon.durability == weapon.max_durability)

	# A partly worn piece (normal repair) still works and costs ore.
	var shirt = loadout.item_at("shirt")
	shirt.durability = 40.0
	p.stash.add_material("ore", 20)  # the broken repair above spent the starter ore
	var ore_before: int = p.stash.material_count("ore")
	result = Commands.apply(f, {"type": "repair", "item": shirt.id}, F.rng())
	ctx.check("normal repair succeeds", result.get("ok", false) and shirt.durability == shirt.max_durability)
	ctx.check("normal repair spends ore", p.stash.material_count("ore") < ore_before)

	# repair_all on the card brings the rest back when payable.
	p.stash.add_material("ore", 100)
	result = Commands.apply(f, {"type": "repair_all", "card": card}, F.rng())
	var all_full := true
	for item in loadout.items():
		all_full = all_full and item.durability == item.max_durability
	ctx.check("repair_all on the card repairs every worn-out piece", result.get("ok", false) and all_full)

	# Unaffordable: Repair.missing names exactly what is short, so the screen can say it.
	weapon.durability = 0.0
	p.stash.gold = 0
	p.stash.remove_material("ore", p.stash.material_count("ore"))
	quote = Repair.quote(weapon, f["camp"])
	result = Commands.apply(f, {"type": "repair", "item": weapon.id}, F.rng())
	ctx.check("no gold, no ore -> cannot_afford", not result.get("ok", true) and str(result.get("error", "")) == "cannot_afford")
	var missing := Repair.missing(quote, p.stash)
	ctx.check("missing gold reported", int(missing["gold"]) == int(quote["gold"]))
	ctx.check("missing ore reported", int(missing["materials"].get("ore", 0)) == int(quote["materials"].get("ore", 0)) and int(quote["materials"].get("ore", 0)) > 0)
	p.stash.gold = 999999
	p.stash.add_material("ore", 999)
	missing = Repair.missing(quote, p.stash)
	ctx.check("nothing missing when payable", int(missing["gold"]) == 0 and missing["materials"].is_empty())
