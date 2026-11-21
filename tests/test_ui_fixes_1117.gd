extends RefCounted
## 2026-11-17 live smoke findings: the character screen's Blacksmith button must open the Blacksmith panel, and the
## Boss shop must say the bought piece's tier is random (list tile + detail note, Thai and English).
const CardTokens := preload("res://client/card_tokens.gd")
const Deck := preload("res://logic/card_deck.gd")


func run(ctx) -> void:
	var tree: SceneTree = ctx
	_strings(ctx)
	await _blacksmith_button(ctx, tree)


func _strings(ctx) -> void:
	var saved: String = CardTokens.language
	for lang in ["en", "th"]:
		CardTokens.language = lang
		var full: String = CardTokens.t("shop_tier_random")
		var short: String = CardTokens.t("shop_tier_random_short")
		ctx.check("shop tier note (%s): detail text exists" % lang, not full.is_empty() and full != "shop_tier_random")
		ctx.check("shop tier note (%s): tile text exists and is shorter" % lang, not short.is_empty() and short != "shop_tier_random_short" and short.length() < full.length())
	CardTokens.language = "en"
	# Boss 2026-11-21: boss pieces always show the top tier (gold); the note no longer names blue/purple
	ctx.check("shop tier note (en): boss tier gold, random stats, no blue/purple", CardTokens.t("shop_tier_random") == "Boss tier (gold)  ·  random stats")
	CardTokens.language = "th"
	ctx.check("shop tier note (th): boss tier gold, no blue/purple", CardTokens.t("shop_tier_random").contains("ทอง") and not CardTokens.t("shop_tier_random").contains("น้ำเงิน") and not CardTokens.t("shop_tier_random").contains("ม่วง"))
	ctx.check("shop boss piece line no longer carries the tier (it has its own line, shown when short of coins too)", not CardTokens.t("shop_boss_piece").contains("เกรดสุ่ม"))
	CardTokens.language = "en"
	ctx.check("shop boss piece line (en) no longer carries the tier", not CardTokens.t("shop_boss_piece").to_lower().contains("random tier"))
	CardTokens.language = saved


## The details' Blacksmith button emits blacksmith_requested; the hub must open its Blacksmith panel on it.
func _blacksmith_button(ctx, tree: SceneTree) -> void:
	var root := Control.new()
	root.size = Vector2(1280, 720)
	tree.root.add_child(root)
	var hub = load("res://client/card_deck_screen.gd").new()
	hub.auto_wire = false
	hub.size = Vector2(1280, 720)
	root.add_child(hub)
	hub.show_deck(Deck.initial(), null)
	await tree.process_frame
	hub.open_character("sword_shield")
	await tree.process_frame
	ctx.check("blacksmith button: the panel is not open before the press", not hub._panels.has("blacksmith") or not hub._panels["blacksmith"].visible)
	hub._character.blacksmith_requested.emit("starter-kit-v3-sword_shield-weapon")
	await tree.process_frame
	ctx.check("blacksmith button: the signal opens the Blacksmith panel", hub._panels.has("blacksmith") and hub._panels["blacksmith"].visible)
	root.queue_free()
	await tree.process_frame
