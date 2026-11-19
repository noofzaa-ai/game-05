extends RefCounted
## Hub card level (Boss 2026-11-19, client/card_deck_screen.gd HubCard): every unlocked card shows its level
## (CardProgress.level_of) in the chosen look (CardTokens.hub_level_style 1..3), locked cards show none, two digits fit,
## a level change on the profile sync updates it, it never covers the portrait window, it takes no taps (tap card =
## open, tap bottom plate = squad), and the strings exist in th + en.
const Deck := preload("res://logic/card_deck.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const CardProgress := preload("res://logic/card_progress.gd")


func _deck(lv: int) -> Dictionary:
	var deck := Deck.initial()
	for id in deck["cards"]:
		deck["cards"][id]["race"] = "human"
		deck["cards"][id]["progress"] = {"level": lv, "xp": 0}
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	return deck


func _text_w(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x


func run(ctx) -> void:
	var tree: SceneTree = ctx
	var saved_style: int = CardTokens.hub_level_style
	var lang := CardTokens.language
	CardTokens.language = "th"
	var th := CardTokens.t("hub_level") % 7
	var th_full := CardTokens.t("hub_level_full") % 7
	CardTokens.language = "en"
	ctx.check("tokens: level strings in th + en", th == "Lv 7" and th_full == "เลเวล 7" and CardTokens.t("hub_level") % 7 == "Lv 7" and CardTokens.t("hub_level_full") % 7 == "Level 7")
	ctx.check("tokens: the default style is one of the three options", CardTokens.HUB_LEVEL_STYLE_DEFAULT in [1, 2, 3])
	# the squad plate tap area with no level piece (style 0): the options must leave it unchanged
	var base_tap := {}
	for style in [0, 1, 2, 3]:
		CardTokens.hub_level_style = style
		for sz in [Vector2(1280, 720), Vector2(1558, 720)]:  # desktop; the 844x390 phone canvas (canvas_items expand)
			var root := Control.new()
			root.size = sz
			tree.root.add_child(root)
			var hub = load("res://client/card_deck_screen.gd").new()
			hub.auto_wire = false
			hub.size = sz
			root.add_child(hub)
			hub.show_deck(_deck(10), null)
			await tree.process_frame
			var tag := "style %d %s" % [style, sz]
			var ss = hub._cards["sword_shield"]
			var tap := Rect2(ss.squad_button.position, ss.squad_button.size)
			if style == 0:
				base_tap[sz] = tap
				ctx.check("%s: no level piece when off" % tag, ss.level_box == null and not ss.level_shown())
				root.queue_free()
				await tree.process_frame
				continue
			ctx.check("%s: squad plate tap area unchanged" % tag, tap.is_equal_approx(base_tap[sz]) and ss.squad_button.visible)
			ctx.check("%s: the card itself still takes the tap (open)" % tag, ss.mouse_filter == Control.MOUSE_FILTER_STOP)
			var ignores: bool = ss.level_box.mouse_filter == Control.MOUSE_FILTER_IGNORE
			for child in ss.level_box.get_children():
				ignores = ignores and (child as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
			ctx.check("%s: the level piece takes no taps" % tag, ignores)
			var expect := "10" if style == 3 else "Lv 10"
			for id in ["sword_shield", "greatsword", "longbow", "magic"]:
				var card = hub._cards[id]
				ctx.check("%s: %s shows its level %s" % [tag, id, card.level_label.text], card.level_shown() and card.level_label.text == expect and card.level == CardProgress.level_of(hub._deck, id))
			# never over the portrait window (the face / figure area)
			var win := CardTokens.HUB_CARD_WINDOW
			var window := Rect2(win.position.x * ss.size.x, win.position.y * ss.size.y, win.size.x * ss.size.x, win.size.y * ss.size.y)
			var box := Rect2(ss.level_box.position, ss.level_box.size)
			ctx.check("%s: the level stays off the portrait window %s %s" % [tag, box, window], not box.grow(-0.5).intersects(window))
			# inside the clipped card row (a hanging tab must not be cut off)
			var row_rect: Rect2 = hub._row_scroll.get_global_rect()
			ctx.check("%s: the level piece is inside the card row clip" % tag, row_rect.grow(0.5).encloses(ss.level_box.get_global_rect()))
			ctx.check("%s: the level stays clear of the hint ribbon" % tag, not ss.level_box.get_global_rect().intersects(hub._hint_strip.get_global_rect()))
			# two digits fit; the plate split keeps the whole squad text too
			hub.show_deck(_deck(15), null)
			await tree.process_frame
			ctx.check("%s: level-up on sync updates the number" % tag, ss.level_label.text == ("15" if style == 3 else "Lv 15"))
			ctx.check("%s: two digits fit their box (%.1f <= %.1f)" % [tag, _text_w(ss.level_label), ss.level_label.size.x], _text_w(ss.level_label) <= ss.level_label.size.x + 0.5)
			if style == 1:
				ctx.check("%s: the squad text is whole beside the level" % tag, _text_w(ss._squad_label) <= ss._squad_label.size.x + 0.5)
			# phone: the canvas is shrunk ~0.54 into the window; the number stays >= 12 window px (styles 2, 3)
			var k := 390.0 / 720.0
			ss.screen_k = k
			ss.layout(ss.size.x, ss.s, ss.phone)
			var window_px: float = ss.level_label.get_theme_font_size("font_size") * k
			if style != 1:
				ctx.check("%s: number >= 12 window px on a phone (%.1f)" % [tag, window_px], window_px >= CardTokens.HUB_LEVEL_SCREEN_MIN - 0.01)
				ctx.check("%s: two digits still fit at phone size" % tag, _text_w(ss.level_label) <= ss.level_label.size.x + 0.5)
			# locked card: no level
			hub.locked_classes = ["magic"]
			hub.show_deck(_deck(15), null)
			await tree.process_frame
			ctx.check("%s: a locked card shows no level" % tag, not hub._cards["magic"].level_shown() and hub._cards["magic"].tooltip_text == "")
			ctx.check("%s: unlocked cards still show theirs" % tag, hub._cards["longbow"].level_shown())
			hub.locked_classes = []
			hub.show_deck(_deck(15), null)
			await tree.process_frame
			ctx.check("%s: unlocking shows the level again" % tag, hub._cards["magic"].level_shown())
			root.queue_free()
			await tree.process_frame
	CardTokens.hub_level_style = saved_style
	CardTokens.language = lang
