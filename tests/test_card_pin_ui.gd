extends RefCounted
## Card pin UI (Boss 2026-11-26, client/card_pin.gd): select/deselect a squad card, a ground tap pins the selected
## card through the session wrapper, a tap on the HUD/cards never pins, unpin on deselect, badge + marker feedback,
## and online rooms do not get the feature.

const Fighter := preload("res://logic/fighter.gd")
const Hud := preload("res://client/hud.gd")
const SquadPanel := preload("res://client/squad_panel.gd")
const CardPin := preload("res://client/card_pin.gd")


class FakeSession:
	extends RefCounted
	var fighters := {}
	var pins := {}
	var calls: Array = []
	func set_pin(id: int, x: float, z: float, owner_ids: Array = []) -> Dictionary:
		calls.append(["set", id, x, z, owner_ids.duplicate()])
		for o in owner_ids: pins.erase(o)
		pins[id] = {"x": x, "z": z}
		return pins[id].duplicate()
	func clear_pin(id: int) -> bool:
		calls.append(["clear", id])
		return pins.erase(id)
	func get_pin(id: int) -> Dictionary:
		return pins.get(id, {}).duplicate()


class FakeRemote:
	extends FakeSession
	func is_remote() -> bool: return true


func run(ctx) -> void:
	ctx.check("enabled for a local session", CardPin.enabled_for(FakeSession.new()))
	ctx.check("hidden for an online (remote) session", not CardPin.enabled_for(FakeRemote.new()))
	ctx.check("hidden without a session", not CardPin.enabled_for(null))
	ctx.check("the real LocalSession exposes the pin wrapper", preload("res://client/session/local_session.gd").new().has_method("set_pin"))
	await _ui(ctx, Vector2i(844, 390))
	await _ui(ctx, Vector2i(1280, 720))


func _fighters() -> Dictionary:
	var out := {}
	for id in [1, 2, 3]:
		var f := Fighter.new()
		f.team = "player"
		f.stats = {"HP": 100.0, "STAMINA": 120.0}
		f.hp = 100.0
		f.energy = 120.0
		out[id] = f
	return out


func _ui(ctx, size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	var holder := SubViewport.new()
	holder.size = size
	ctx.root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(0, 14, 9)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	var hud = Hud.new()
	hud.compact_override = 1 if size.x < 1000 else 0
	holder.add_child(hud)
	await ctx.process_frame
	hud.auto_battle = true
	hud.set_boss("Orc Warlock", 0.8)
	hud._layout()
	var panel = SquadPanel.new()
	holder.add_child(panel)
	await ctx.process_frame
	var session := FakeSession.new()
	session.fighters = _fighters()
	panel.update_from(session.fighters, 1, {"rules": {"ultimate_gauge_max": 100.0}})
	panel._place()
	var views := {}
	for id in [1, 2, 3]:
		var v := Node3D.new()
		v.position = Vector3(float(id) - 2.0, 0, 0)
		holder.add_child(v)
		views[id] = v
	var pin = CardPin.new()
	pin.session = session
	pin.squad_panel = panel
	pin.hud = hud
	pin.views = views
	pin.owner_ids = [1, 2, 3]
	pin.camera_of = func(): return cam
	holder.add_child(pin)
	await ctx.process_frame

	var mid := Vector2(size.x * 0.5, size.y * 0.5)
	ctx.check("%s nothing selected: a ground tap does nothing" % tag, pin.tap(mid).is_empty() and session.calls.is_empty())
	panel.select(2)
	ctx.check("%s tapping card 2 selects it" % tag, pin.selected_id() == 2 and panel.selected_id() == 2)
	panel.select(3)
	ctx.check("%s tapping card 3 moves the selection (one at a time)" % tag, pin.selected_id() == 3)
	panel.select(2)
	var card_rect: Rect2 = panel.card_rect(2)
	ctx.check("%s tap on a squad card never pins" % tag, pin.tap(card_rect.get_center()).is_empty() and session.calls.is_empty())
	var boss: Rect2 = hud.layout_rects()["boss"]
	ctx.check("%s tap on the boss bar never pins" % tag, pin.tap(boss.get_center()).is_empty() and session.calls.is_empty())
	var target := Vector3(3.0, 0.0, -1.5)
	var screen_at: Vector2 = cam.unproject_position(target)
	var stored: Dictionary = pin.tap(screen_at)
	var call: Array = session.calls[-1] if not session.calls.is_empty() else []
	ctx.check("%s ground tap pins the selected card at the floor point (%s)" % [tag, call],
		call.size() == 5 and call[0] == "set" and call[1] == 2 and absf(call[2] - 3.0) < 0.05 and absf(call[3] + 1.5) < 0.05 and call[4] == [1, 2, 3])
	ctx.check("%s the marker shows right away at the pin" % tag, pin.marker_shown() and pin.marker_position().distance_to(Vector3(stored["x"], 0, stored["z"])) < 0.1)
	await ctx.process_frame
	ctx.check("%s the pinned card shows its PIN badge" % tag, panel.pinned_shown(2) and not panel.pinned_shown(1))
	ctx.check("%s the selection ring is under the fighter" % tag, pin._ring.visible and pin._ring.position.distance_to(views[2].position) < 0.1)
	var badge: Rect2 = (panel._cards[2]["pin_badge"] as Control).get_global_rect()
	ctx.check("%s the PIN badge stays on screen and off the boss bar" % tag, Rect2(Vector2.ZERO, Vector2(size)).encloses(badge) and not badge.intersects(boss))
	panel.select(2)
	ctx.check("%s tapping the selected card again deselects and clears its pin" % tag, pin.selected_id() == -1 and session.calls[-1] == ["clear", 2])
	await ctx.process_frame
	ctx.check("%s the marker and badge go with the pin" % tag, not pin.marker_shown() and not panel.pinned_shown(2))
	panel.select(1)
	pin.tap(screen_at)
	session.pins.clear()  # logic released it (wave end / death)
	await ctx.process_frame
	ctx.check("%s a pin released by logic hides the marker" % tag, not pin.marker_shown() and not panel.pinned_shown(1))
	session.fighters[1].hp = 0.0
	session.fighters[1].state = Fighter.State.DEAD
	await ctx.process_frame
	ctx.check("%s a fallen selected card is deselected" % tag, pin.selected_id() == -1)
	holder.queue_free()
