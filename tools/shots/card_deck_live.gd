extends SceneTree
## Live viewer: opens the class card screen in a window and stays open so you can hover (tilt/holo), click a card
## to open the editor, and press Fight to see the loading bar. Run windowed: godot --path . --script res://tools/shots/card_deck_live.gd
func _initialize():
	call_deferred("run")

func run():
	root.size = Vector2i(1280, 720)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
