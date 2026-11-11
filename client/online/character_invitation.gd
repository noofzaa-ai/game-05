extends Node
## One selection/invitation UI for nearby player characters, irrespective of input owner.
const Ink := preload("res://client/ink_ui.gd")
var hub
var popup: CanvasLayer
var poll_left := 0.0
var polling := false
var seen := {}
var expires_at := 0
var touch_start := Vector2.INF

func _ready() -> void:
	hub.set_meta("character_invitation",self)

func has_open_panel() -> bool:
	return is_instance_valid(popup)

func _process(delta: float) -> void:
	if is_instance_valid(popup) and expires_at > 0 and Time.get_ticks_msec() >= expires_at: _close()
	poll_left -= delta
	if poll_left <= 0 and not polling:
		poll_left = 3.0
		_poll_invites()

func _unhandled_input(event: InputEvent) -> void:
	if not hub.can_walk() or hub.training_combat_active(): return
	if event is InputEventScreenTouch:
		if event.pressed: touch_start = event.position
		elif touch_start != Vector2.INF:
			var click: bool = event.position.distance_to(touch_start) < 12
			touch_start = Vector2.INF
			if click: _select(event.position)
	elif event is InputEventScreenDrag and event.position.distance_to(touch_start) >= 12:
		touch_start = Vector2.INF
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(event.position)

func _select(screen: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or get_viewport().gui_get_hovered_control() != null: return
	var candidates := []
	var resident = hub._adventurer
	if is_instance_valid(resident) and resident.offer_ready:
		candidates.append({"id":"companion:"+resident.offer_seed,"name":resident.entry.name,"position":resident.body.position,"match":""})
	for child in hub.get_children():
		if child.get_script() != null and child.get_script().resource_path == "res://client/online/plaza_client.gd":
			for uid in child.actors:
				var actor: Dictionary = child.actors[uid]
				candidates.append({"id":uid,"name":child.descriptions.get(uid,{}).get("name","Player"),"position":actor.model.global_position,"match":child.match_id})
	var best := {};var distance := 52.0
	for candidate in candidates:
		var at: Vector3 = candidate.position
		if hub.player_position().distance_to(at) > 4.0 or camera.is_position_behind(at): continue
		var d := screen.distance_to(camera.unproject_position(at+Vector3.UP*0.8))
		if d < distance: best=candidate;distance=d
	if best.is_empty(): return
	var box := _open(str(best.name))
	_button(box,"ชวนออกเดินทาง",func():
		_close()
		var panel = _room_panel()
		panel.invite_target = str(best.id)
		panel.invite_match = str(best.match)
		hub.add_child(panel))
	_button(box,"ปิด",_close)
	get_viewport().set_input_as_handled()

func _open(title: String) -> VBoxContainer:
	_close()
	popup = CanvasLayer.new();popup.layer=45;add_child(popup)
	var shade := ColorRect.new();shade.color=Ink.SCRIM;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);popup.add_child(shade)
	var center := CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.add_child(center)
	var plate := PanelContainer.new();plate.theme=Ink.make_theme();plate.custom_minimum_size=Vector2(300,160);Ink.panel(plate,Ink.window_style());center.add_child(plate)
	var box := VBoxContainer.new();plate.add_child(box)
	var label := Label.new();label.text=title;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.x=280;box.add_child(label)
	return box

func _button(box: Node, text: String, action: Callable) -> void:
	var button := Button.new();button.text=text;button.custom_minimum_size.y=48;button.pressed.connect(action);box.add_child(button)

func _close() -> void:
	if is_instance_valid(popup): popup.queue_free()
	popup=null;expires_at=0

func _room_panel():
	var panel = preload("res://client/online/room_panel.gd").new()
	hub._adventurer.panel=panel
	return panel

func _poll_invites() -> void:
	var service = get_node_or_null("/root/Online")
	if service == null or service.session == null or not hub.can_walk(): return
	polling=true
	var result: Dictionary = await preload("res://client/online/social_client.gd").new().call_rpc(service,"inbox")
	polling=false
	if not is_inside_tree() or not hub.can_walk() or not result.get("ok",false): return
	for entry in result.get("invites",[]):
		if seen.has(str(entry.id)): continue
		seen[str(entry.id)]=true
		if seen.size()>128:seen.erase(seen.keys()[0])
		_show_invite(entry,service)
		break

func _show_invite(entry: Dictionary, service) -> void:
	var box := _open(str(entry.name)+" ชวนออกเดินทาง")
	expires_at=Time.get_ticks_msec()+30000
	_button(box,"ยอมรับ",func():
		_close()
		var panel = _room_panel();panel.incoming_invite=entry.duplicate(true);hub.add_child(panel))
	_button(box,"ปฏิเสธ",func():
		_close()
		if service != null: preload("res://client/online/social_client.gd").new().call_rpc(service,"ack",{"id":entry.id}))
