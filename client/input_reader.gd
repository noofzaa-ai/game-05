extends RefCounted
## Turns keyboard (later touch and gamepad) into the simulation's input. This is the only place
## that knows which key means what.
## EXTENDING: map a new action in setup_actions() and copy it into the SimInput in read().

const SimInput := preload("res://logic/sim_input.gd")


static func setup_actions() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_up", [KEY_W, KEY_UP])
	_add_key_action("move_down", [KEY_S, KEY_DOWN])
	_add_key_action("jump", [KEY_SPACE])
	_add_mouse_action("light", MOUSE_BUTTON_LEFT)
	_add_mouse_action("heavy", MOUSE_BUTTON_RIGHT)
	_add_key_action("guard", [KEY_F])  # not Ctrl: Ctrl+W closes the browser tab on web
	_add_key_action("run", [KEY_SHIFT])
	_add_key_action("dodge", [KEY_C])
	# Skill slots in the order the weapon has them: 1 = skill, 2 = ultimate (3-5 reserved for more skills)
	_add_key_action("special", [KEY_1])
	_add_key_action("ultimate", [KEY_2])
	_add_key_action("skill_3", [KEY_3])
	_add_key_action("skill_4", [KEY_4])


## Give `viewport` so a mouse click on an on-screen button (a menu, later touch buttons) is not
## also read as an attack: attacks are on the mouse buttons.
static func read(viewport: Viewport = null) -> SimInput:
	var input := SimInput.new()
	var over_ui := viewport != null and viewport.gui_get_hovered_control() != null
	input.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input.jump = Input.is_action_just_pressed("jump")
	input.light = Input.is_action_just_pressed("light") and not over_ui and not Input.is_key_pressed(KEY_ALT) # Alt+drag is free camera
	input.heavy = Input.is_action_just_pressed("heavy") and not over_ui
	input.run = Input.is_action_pressed("run")  # held
	input.guard = Input.is_action_pressed("guard")  # held, not just pressed
	input.dodge = Input.is_action_just_pressed("dodge")
	input.special = Input.is_action_just_pressed("special")
	input.ultimate = Input.is_action_just_pressed("ultimate")
	if preload("res://logic/skill_build.gd").enabled():
		for index in range(4):
			if Input.is_action_just_pressed(["special","ultimate","skill_3","skill_4"][index]): input.skill_slot = index
		input.special = false
		input.ultimate = false
	return input


## The short name of the first key or mouse button bound to an action ("Ctrl", "C", "LMB"), for
## on-screen hints, so hints can never disagree with the real controls. `fallback` if unbound.
static func key_label(action: StringName, fallback: String = "") -> String:
	if not InputMap.has_action(action):
		return fallback
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				_:
					return "Mouse %d" % (event as InputEventMouseButton).button_index
	return fallback


static func _add_key_action(action: StringName, keys: Array[Key]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


static func _add_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


## Opt-in local co-op keyboard. Separate actions never consume P1 mouse/touch input.
static func setup_secondary() -> void:
	for pair in [["left", KEY_J], ["right", KEY_L], ["up", KEY_I], ["down", KEY_K], ["light", KEY_U], ["heavy", KEY_O], ["guard", KEY_N], ["dodge", KEY_M], ["jump", KEY_B], ["run", KEY_H], ["special", KEY_P], ["ultimate", KEY_Y]]:
		_add_key_action("p2_" + pair[0], [pair[1]])

static func read_secondary() -> SimInput:
	var input := SimInput.new()
	input.move = Input.get_vector("p2_left", "p2_right", "p2_up", "p2_down")
	for action in ["jump", "light", "heavy", "dodge", "special", "ultimate"]:
		input.set(action, Input.is_action_just_pressed("p2_" + action))
	for action in ["run", "guard"]:
		input.set(action, Input.is_action_pressed("p2_" + action))
	return input
