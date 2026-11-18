extends SceneTree
const F := preload("res://tests/online_fixture.gd")
func _initialize() -> void:
	var f := F.make(77)
	preload("res://logic/test_kit.gd").fill(f.profile, f.rules, f.camp, F.rng())
	var raw: Dictionary = f.profile.to_dict()
	raw.erase("card_deck"); raw.erase("card_gear")
	raw = JSON.parse_string(JSON.stringify(raw))  # wire-like
	var P = load("res://logic/profile.gd")
	var t := Time.get_ticks_usec()
	for i in 20: P.from_dict(raw, f.rules, f.camp)
	print("from_dict us avg ", (Time.get_ticks_usec() - t) / 20)
	var d = raw
	t = Time.get_ticks_usec()
	for i in 20: preload("res://logic/inventory.gd").from_dict(d["stash"], {})
	print("stash us ", (Time.get_ticks_usec() - t) / 20, " items ", d.stash.items.size())
	t = Time.get_ticks_usec()
	for i in 20: preload("res://logic/loadout.gd").from_dict(d["loadout"], f.rules)
	print("loadout us ", (Time.get_ticks_usec() - t) / 20)
	t = Time.get_ticks_usec()
	for i in 20: preload("res://logic/card_deck.gd").repaired(null, preload("res://logic/cosmetic_options.gd").load_default())
	print("deck us ", (Time.get_ticks_usec() - t) / 20)
	quit()
