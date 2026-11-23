extends RefCounted
## Skills tab look (Boss 2026-11-23: "the pictures are too small, too many frames"): the icon is the node, one ring per
## node, nothing overlaps, finger-sized targets at 844x390 and 1280x720, and the tab still works with 3 and with many
## nodes (the tree scrolls instead of shrinking the pictures). Display only: the rules are tested in test_skill_tree_*.gd.
const CardTokens := preload("res://client/card_tokens.gd")
const Deck := preload("res://logic/card_deck.gd")
const SkillTreeNode := preload("res://client/skill_tree_node.gd")
const SkillTreeTab := preload("res://client/skill_tree_tab.gd")

## Old sizes (before 2026-11-23) of the icon picture, screen px: the new ones must be at least 1.5x.
const OLD_ICON := {Vector2i(844, 390): 25.0, Vector2i(1280, 720): 27.0, Vector2i(1920, 1080): 38.0}


func run(ctx) -> void:
	var tree: SceneTree = ctx
	for screen in [Vector2i(844, 390), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await _real_tab(ctx, tree, screen)
	for count in [3, 40]:
		await _fixture_tab(ctx, tree, count)


func _real_tab(ctx, tree: SceneTree, screen: Vector2i) -> void:
	var root := Control.new()
	root.size = Vector2(screen)
	tree.root.add_child(root)
	var hub = load("res://client/card_deck_screen.gd").new()
	hub.auto_wire = false
	hub.size = Vector2(screen)
	root.add_child(hub)
	# the character screen reads GameState's profile: a level-10 human Sword & Shield card for the test, put back after
	var gs = tree.root.get_node("GameState")
	gs.ensure_profile()
	var saved_deck: Dictionary = gs.profile.card_deck.duplicate(true)
	var progress = load("res://logic/card_progress.gd")
	var need := 0
	for level in range(1, 10):
		need += progress.xp_req(level)
	progress.grant(gs.profile.card_deck, "sword_shield", need)
	Deck.set_race(gs.profile.card_deck, "sword_shield", "human")
	var deck: Dictionary = gs.profile.card_deck
	hub.show_deck(deck, null)
	await tree.process_frame
	hub.open_character("sword_shield")
	var ch = hub._character
	ch.select_tab("skills")
	for i in 3:
		await tree.process_frame
	var tab = ch._skills
	var tag := "%dx%d" % [screen.x, screen.y]
	ctx.check("skills ui %s: the tab shows nodes" % tag, tab._nodes.size() >= 3)
	var smallest := INF
	var smallest_node := INF
	var rings_ok := true
	for id in tab._nodes:
		var b = tab._nodes[id]
		smallest = minf(smallest, b.icon_side())
		smallest_node = minf(smallest_node, minf(b.size.x, b.size.y))
		rings_ok = rings_ok and _one_frame(b)
	var old: float = OLD_ICON[screen]
	ctx.check("skills ui %s: every icon is >= 1.5x the old size (%.0f px, was %.0f)" % [tag, smallest, old], smallest >= old * 1.5)
	ctx.check("skills ui %s: every node is a finger-sized target (>= 44 px, smallest %.0f)" % [tag, smallest_node], smallest_node >= 44.0)
	ctx.check("skills ui %s: the icon fills the node (>= 75%% of it)" % tag, _icon_share(tab) >= 0.75)
	ctx.check("skills ui %s: one ring per node, no frame art / badges / extra rings" % tag, rings_ok)
	ctx.check("skills ui %s: no two nodes overlap" % tag, _no_overlap(tab))
	ctx.check("skills ui %s: every node is inside the tree content" % tag, _inside(tab))
	if not tab._compact:
		ctx.check("skills ui %s: the detail panel is beside the tree, not over it" % tag, tab._detail.position.x >= tab._scroll.position.x + tab._scroll.size.x - 0.5)
		ctx.check("skills ui %s: the tree gets most of the width (>= 70%%)" % tag, tab._scroll.size.x >= tab.size.x * 0.7)
	# behaviour kept: select shows the detail, learn drafts, cancel drops it
	var first := ""
	for n in tab.shown_nodes():
		if int(n["tier"]) == 1 and tab._data().branch_of(str(n["id"])) == "class":
			first = str(n["id"])
			break
	tab.select(first)
	ctx.check("skills ui %s: select shows the node's name in the detail" % tag, tab._d_name.text == str(tab._data().node(first)["name"]))
	ctx.check("skills ui %s: a selected node draws its glow" % tag, _layers(tab._nodes[first]).has("glow"))
	ctx.check("skills ui %s: learn puts the node in the draft" % tag, tab.learn(first) == "" and tab.node_state(first) == SkillTreeNode.State.DRAFT)
	ctx.check("skills ui %s: a draft node shows no cost, a dashed ring" % tag, not _layers(tab._nodes[first]).has("cost") and _ring(tab._nodes[first]).get("dashed", false))
	tab.cancel_draft()
	ctx.check("skills ui %s: cancel draft drops it" % tag, tab.node_state(first) == SkillTreeNode.State.AVAILABLE)
	ctx.check("skills ui %s: the combo node is shown" % tag, not tab._combo_id.is_empty() and tab._nodes.has(tab._combo_id))
	ctx.check("skills ui %s: OR pairs get their 'or' word" % tag, tab._or_marks.size() >= 4)
	gs.profile.card_deck = saved_deck
	root.queue_free()
	await tree.process_frame


## A tab on a fixture tree of `count` class nodes in four tiers (no race branch): 3 nodes stay at full size without a
## scroll, 40 nodes scroll and keep the least size.
func _fixture_tab(ctx, tree: SceneTree, count: int) -> void:
	for screen in [Vector2i(844, 390), Vector2i(1280, 720)]:
		var tag := "%d nodes %dx%d" % [count, screen.x, screen.y]
		var tab = SkillTreeTab.new()
		tab.tree_data = FakeData.new(count)
		var s := CardTokens.scale_for(Vector2(screen))
		tab.s = s
		tab.phone = CardTokens.is_phone(Vector2(screen))
		tab.size = Vector2(screen) * 0.85
		tree.root.add_child(tab)
		tab.show_card("sword_shield", Deck.initial(), 0)
		await tree.process_frame
		ctx.check("skills ui %s: every node is built" % tag, tab._nodes.size() == count)
		ctx.check("skills ui %s: no two nodes overlap" % tag, _no_overlap(tab))
		ctx.check("skills ui %s: every node is inside the tree content" % tag, _inside(tab))
		var least := INF
		for id in tab._nodes:
			least = minf(least, tab._nodes[id].size.x)
		var floor_px: float = (CardTokens.HUB_TAP_MIN_PHONE if tab.phone else CardTokens.TREE_NODE_MIN) * s
		ctx.check("skills ui %s: nodes stay tap-sized (%.0f px >= %.0f)" % [tag, least, floor_px], least >= floor_px - 0.5)
		if count <= 3:
			ctx.check("skills ui %s: a small tree does not scroll" % tag, not tab.scrolls())
			ctx.check("skills ui %s: a small tree shows big pictures (base node at its max, %.0f px)" % [tag, tab.node_base], is_equal_approx(tab.node_base, CardTokens.TREE_NODE_MAX * s))
		else:
			ctx.check("skills ui %s: a big tree scrolls instead of shrinking" % tag, tab.scrolls())
		tab.queue_free()
		await tree.process_frame


static func _layers(b) -> Array:
	return b.draw_plan().map(func(step): return str(step["layer"]))


static func _ring(b) -> Dictionary:
	for step in b.draw_plan():
		if str(step["layer"]) == "ring":
			return step
	return {}


## Exactly one frame layer ("ring"); the rest are the picture, its shadow, the selection glow and the cost numeral.
static func _one_frame(b) -> bool:
	var layers := _layers(b)
	if layers.count("ring") != 1:
		return false
	for layer in layers:
		if not layer in ["shadow", "icon", "ring", "glow", "cost"]:
			return false
	return not ("frame" in b) and not ("badges" in b)


static func _icon_share(tab) -> float:
	var least := 1.0
	for id in tab._nodes:
		var b = tab._nodes[id]
		least = minf(least, b.icon_side() / maxf(1.0, b.size.x))
	return least


static func _no_overlap(tab) -> bool:
	var rects: Array = []
	for id in tab._nodes:
		var b: Control = tab._nodes[id]
		rects.append(Rect2(b.position, b.size).grow(-0.5))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				return false
	return true


static func _inside(tab) -> bool:
	var area := Rect2(Vector2.ZERO, tab._lines.size).grow(0.5)
	for id in tab._nodes:
		var b: Control = tab._nodes[id]
		if not area.encloses(Rect2(b.position, b.size)):
			return false
	return true


## A tree data stand-in with `count` class nodes over four tiers (OR pairs on tier 2), no race branch, no combo.
class FakeData extends RefCounted:
	var nodes: Array = []

	func _init(count: int) -> void:
		for i in count:
			var tier := 1 + (i % 4)
			nodes.append({"id": "fake_%d" % i, "tier": tier, "type": "minor", "cost": 1, "excl": "",
				"name": "Fake %d" % i, "icon": "res://art/ui/skill_tree/icons/ss_t1_storm.png"})
		var by_pair := {}
		for n in nodes:  # pair tier-2 nodes two by two
			if int(n["tier"]) == 2:
				var key := "pair_%d" % (by_pair.size() / 2)
				n["excl"] = key
				by_pair[n["id"]] = key

	func class_nodes(_class_id: String) -> Array:
		return nodes

	func race_nodes(_race_id: String) -> Array:
		return []

	func combo_node(_race_id: String, _class_id: String) -> Dictionary:
		return {}

	func node(id: String) -> Dictionary:
		for n in nodes:
			if n["id"] == id:
				return n
		return {}

	func branch_of(id: String) -> String:
		return "class" if not node(id).is_empty() else ""

	func tiers(_branch: String) -> Array:
		return [{"tier": 1, "gate": 0}, {"tier": 2, "gate": 3}, {"tier": 3, "gate": 8}, {"tier": 4, "gate": 13}]

	func tier_rule(branch: String, tier: int) -> Dictionary:
		for rule in tiers(branch):
			if int(rule["tier"]) == tier:
				return rule
		return {}

	func combo_rule() -> Dictionary:
		return {"class_gate": 8, "race_gate": 6}

	func class_reset_gold_per_point() -> int:
		return 50

	func description(_id: String, _language: String = "en") -> String:
		return "A fixture node."
