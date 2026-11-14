extends Node
## New-player tutorial driver (design/gdd/tutorial.md 3-6). One per hub (attach_hub) and one per solo battle
## (attach_battle). It reads the CURRENT step from the profile (logic/tutorial.gd, server-owned), shows the
## spotlight overlay on the step's target, listens for the step's done_on event and sends `tutorial_step`; a refusal
## means the server knows better, so the driver re-reads the profile's step and shows that one.
## Resume: on load the hub re-opens the screen the current step needs (character screen / race picker).
## Battle: commands only work in camp (logic/commands.gd), so `fight` is confirmed when FIGHT is pressed (still in
## camp) and `battle_tip` is queued in GameState meta and confirmed by the next hub (DEVIATION, see PROGRESS.md).
## Display + requests only: every rule (order, skip, auto-advance) is the server's.

const Tutorial := preload("res://logic/tutorial.gd")
const Unlocks := preload("res://logic/unlocks.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const Overlay := preload("res://client/tutorial_overlay.gd")
const Ceremony := preload("res://client/tutorial_ceremony.gd")

const MISSING_SECONDS := 2.0
const BATTLE_TIP_SECONDS := 8.0
const TOUR_PANEL_SECONDS := 1.2  ## a tour panel stays open this long, then the driver closes it (tutorial.md 4 notes)
const PENDING_META := "tutorial_pending"  ## GameState meta: step ids confirmed in battle, sent by the next hub
const LAST_FIGHT_META := "tutorial_last_fight"  ## GameState meta: "defeated" / "cleared" of the last solo fight
const FIRST_FIGHT_META := "tutorial_first_fight"  ## GameState meta: the fight that ran the battle tip (the first one)

var hub: Control  ## client/card_deck_screen.gd
var overlay: Overlay
var step := ""  ## the step on screen ("" none)
var _missing := 0.0
var _fallback := false
var _busy := false
var _ceremony: Control
var _lost_tip := false
## Test seam: a Callable(request) -> Dictionary; default = the hub's sender.
var send: Callable


# ================================================================== hub
static func attach_hub(p_hub: Control) -> Node:
	var d = load("res://client/tutorial_driver.gd").new()
	d.name = "TutorialDriver"
	d.hub = p_hub
	p_hub.add_child(d)
	return d


func _ready() -> void:
	if hub == null:
		return
	overlay = Overlay.new()
	overlay.reduced_motion = hub.reduced_motion
	hub.add_child(overlay)
	hub.move_child(overlay, hub.toast_index())  # above every screen, below the toast
	overlay.next_pressed.connect(_on_next)
	overlay.skip_pressed.connect(func() -> void: _confirm(Tutorial.SKIP_TOUR))
	hub.tutorial_event.connect(on_event)
	_start.call_deferred()


func _start() -> void:
	await _flush_pending()
	var last := str(GameState.get_meta(LAST_FIGHT_META, "")) if GameState.has_meta(LAST_FIGHT_META) else ""
	var first := GameState.has_meta(FIRST_FIGHT_META)
	for key in [LAST_FIGHT_META, FIRST_FIGHT_META]:
		if GameState.has_meta(key):
			GameState.remove_meta(key)
	_lost_tip = first and last == "defeated"
	refresh()


## Sends the battle-confirmed steps (battle_tip) now that we are in camp.
func _flush_pending() -> void:
	if not GameState.has_meta(PENDING_META):
		return
	var pending: Array = GameState.get_meta(PENDING_META)
	GameState.remove_meta(PENDING_META)
	for id in pending:
		if current() == str(id):
			await _send({"type": "tutorial_step", "step": str(id)})


func _profile():
	return GameState.profile


func current() -> String:
	var p = _profile()
	return Tutorial.current(p) if p != null and "tutorial" in p else Tutorial.DONE


## Shows the current step (or nothing). Re-opens the screen it needs (resume, tutorial.md 6).
func refresh() -> void:
	if overlay == null:
		return
	if _lost_tip:  # tutorial.md 6: first fight lost, one line at FIGHT, dismissed with Next or FIGHT
		step = "lost_tip"
		overlay.show_skip = false
		overlay.show_step(Overlay.word("lost_tip"), true)
		_missing = 0.0
		_fallback = false
		return
	step = current()
	var data := Tutorial.step_data(step)
	if step == Tutorial.DONE or data.is_empty() or str(data.get("screen")) == "battle":
		step = "" if data.is_empty() or step == Tutorial.DONE else step
		overlay.hide_step()
		return
	_missing = 0.0
	_fallback = false
	overlay.show_skip = str(data.get("group")) == "tour"
	_open_screen(data)
	if step == "unlock_ceremony":
		overlay.hide_step()
		_show_ceremony(data)
		return
	var target := str(data.get("target", ""))
	overlay.show_step(text_of(data), target.is_empty())
	overlay.set_hole(Rect2())


static func text_of(data: Dictionary) -> String:
	return str(data.get("text_th" if CardTokens.language == "th" else "text_en", ""))


func _open_screen(data: Dictionary) -> void:
	var screen := str(data.get("screen"))
	var card := str(data.get("card", ""))
	match screen:
		"hub":
			hub.tutorial_show_hub()
		"character":
			if card.is_empty():
				card = hub.tutorial_first_card()
			hub.tutorial_open_character(card, false)
		"race_picker":
			hub.tutorial_open_character(card, true)


func _process(delta: float) -> void:
	if overlay == null or step.is_empty() or _ceremony != null:
		return
	var target_name := "FightButton" if step == "lost_tip" else str(Tutorial.step_data(step).get("target", ""))
	if target_name.is_empty() or _fallback:
		return
	var node := find_target(hub, target_name)
	if node == null:
		_missing += delta
		overlay.set_hole(Rect2())
		if _missing >= MISSING_SECONDS:
			_fallback = true
			push_warning("tutorial_target_missing %s (%s)" % [target_name, step])
			print("tutorial_target_missing ", target_name, " step=", step)
			overlay.show_step(text_of(Tutorial.step_data(step)), true)
		return
	_missing = 0.0
	_scroll_into_view(node)
	if not overlay.visible:
		overlay.visible = true
	overlay.set_hole(node.get_global_rect())


## A target inside a scrolling row (the phone card row) is scrolled into view once per step.
var _scrolled := ""
func _scroll_into_view(node: Control) -> void:
	if _scrolled == step:
		return
	_scrolled = step
	var parent := node.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent != null:
		(parent as ScrollContainer).ensure_control_visible(node)


## The visible control named `target_name` under `root` (the deepest visible match), or null.
static func find_target(root: Node, target_name: String) -> Control:
	if root == null:
		return null
	for node in root.find_children(target_name, "Control", true, false):
		var c := node as Control
		if c != null and c.is_visible_in_tree() and c.size.x > 0.0:
			return c
	return null


# ================================================================== events
## A done_on event from the hub / character screen / picker: {"event": ..., params}.
func on_event(event: Dictionary) -> void:
	if step == "lost_tip":
		if str(event.get("event")) == "fight_pressed":
			_lost_tip = false
		return
	var data := Tutorial.step_data(step)
	if data.is_empty() or not matches(data.get("done_on", {}), event):
		if str(event.get("event")) == "fight_pressed" and step == "fight":
			pass
		else:
			return
	var id := step
	var done_on: Dictionary = data.get("done_on", {})
	if str(done_on.get("event")) == "panel_open" and str(data.get("group")) == "tour":
		await get_tree().create_timer(TOUR_PANEL_SECONDS).timeout
		hub.tutorial_close_panels()
	_confirm(id)


## True when `event` fulfils `done_on` (event name and every param but timeout_s). FIGHT counts for battle_loaded.
static func matches(done_on: Dictionary, event: Dictionary) -> bool:
	var want := str(done_on.get("event", ""))
	var got := str(event.get("event", ""))
	if want == "battle_loaded" and got == "fight_pressed":
		return true
	if want != got:
		return false
	for key in done_on:
		if key in ["event", "timeout_s"]:
			continue
		if str(event.get(key, "")) != str(done_on[key]):
			return false
	return true


func _on_next() -> void:
	if step == "lost_tip":
		_lost_tip = false
		refresh()
		return
	var data := Tutorial.step_data(step)
	if _fallback or str(data.get("done_on", {}).get("event")) == "next":
		_confirm(step)


## Sends tutorial_step for `id`; refused = follow the server's step (refresh re-reads it).
func _confirm(id: String) -> void:
	if _busy:
		return
	_busy = true
	var result := await _send({"type": "tutorial_step", "step": id})
	_busy = false
	if not result.get("ok", false):
		print("tutorial step refused: ", id, " -> following the server step ", current())
	if str(Tutorial.step_data(id).get("group")) == "tour" and Tutorial.group_of(current()) != "tour":
		hub.tutorial_close_character()
	hub.tutorial_after_step()
	refresh()


func _send(request: Dictionary) -> Dictionary:
	if send.is_valid():
		return await send.call(request)
	return await hub._send(request)


## Waits until no tutorial_step is out (FIGHT waits for `fight` to be saved before leaving camp).
func idle() -> void:
	await get_tree().process_frame
	while _busy:
		await get_tree().process_frame


## Settings "Replay tour" (tutorial.md 6).
func replay_tour() -> void:
	var result := await _send({"type": "tutorial_replay"})
	if result.get("ok", false):
		refresh()
	else:
		hub.toast(CardTokens.error_text(str(result.get("error", ""))))


func _show_ceremony(data: Dictionary) -> void:
	if _ceremony != null:
		return
	_ceremony = Ceremony.new()
	_ceremony.reduced_motion = hub.reduced_motion
	_ceremony.text = text_of(data)
	hub.add_child(_ceremony)
	hub.move_child(_ceremony, hub.toast_index())
	_ceremony.finished.connect(func() -> void:
		_ceremony.queue_free()
		_ceremony = null
		_confirm("unlock_ceremony"))


# ================================================================== battle
## The battle tip (tutorial.md 4 battle_tip): solo auto-battle only, never in online rooms. `squad_panel` is
## client/squad_panel.gd. Done on a card-name tap or after 8 s; queued for the next hub (commands are camp-only).
static func attach_battle(parent: Node, squad_panel: CanvasLayer, online: bool) -> CanvasLayer:
	var p = GameState.profile
	if online or squad_panel == null or p == null or not "tutorial" in p or Tutorial.current(p) != "battle_tip":
		return null
	GameState.set_meta(FIRST_FIGHT_META, true)
	var layer := CanvasLayer.new()
	layer.name = "TutorialBattle"
	layer.layer = 20
	parent.add_child(layer)
	var tip := Overlay.new()
	layer.add_child(tip)
	tip.prefer_top = true
	tip.show_step(text_of(Tutorial.step_data("battle_tip")), false)
	var done := func() -> void:
		if not is_instance_valid(layer) or layer.is_queued_for_deletion():
			return
		var pending: Array = GameState.get_meta(PENDING_META, []) if GameState.has_meta(PENDING_META) else []
		if not pending.has("battle_tip"):
			pending.append("battle_tip")
		GameState.set_meta(PENDING_META, pending)
		layer.queue_free()
	squad_panel.selected.connect(func(_id: int) -> void: done.call(), CONNECT_ONE_SHOT)
	layer.get_tree().create_timer(BATTLE_TIP_SECONDS).timeout.connect(done)
	var follow := func() -> void:
		if is_instance_valid(tip):
			tip.set_hole(squad_panel.tutorial_rect())
	layer.get_tree().process_frame.connect(follow)
	layer.tree_exiting.connect(func() -> void:
		if layer.get_tree().process_frame.is_connected(follow):
			layer.get_tree().process_frame.disconnect(follow))
	return layer


## The last solo fight's outcome (for the first-fight-lost tip).
static func note_fight_result(title: String) -> void:
	if title in ["defeated", "stage_clear", "journey_complete"]:
		GameState.set_meta(LAST_FIGHT_META, "defeated" if title == "defeated" else "cleared")
