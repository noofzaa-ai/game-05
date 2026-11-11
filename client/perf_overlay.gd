extends CanvasLayer
## Frame timing readout for checking smoothness (toggled with F2 on the stage): frames per second,
## the slowest frame of the last second, and how many frames since opening took longer than
## HITCH_MS (a visible stutter). Debug aid only; it does not touch the game rules.

const InkUi := preload("res://client/ink_ui.gd")

const HITCH_MS := 50.0

var _label: Label
var _window := 0.0
var _frames := 0
var _worst_ms := 0.0
var _hitches := 0


func _ready() -> void:
	layer = 100
	_label = InkUi.hud_text("debug", InkUi.HUD_TEXT, 4)
	_label.position = Vector2(8, 8)
	add_child(_label)
	visible = OS.get_cmdline_user_args().has("--net-debug")


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	if ms > HITCH_MS:
		_hitches += 1
	_worst_ms = maxf(_worst_ms, ms)
	_window += delta
	_frames += 1
	if _window >= 1.0:
		_label.text = "FPS %d   worst %d ms   hitches %d" % [roundi(_frames / _window), roundi(_worst_ms), _hitches]
		var game = get_node_or_null("/root/GameState")
		if game != null and game.remote_session != null:
			var metrics: Dictionary = game.remote_session.debug_metrics()
			_label.text += "\nNET ping %d ms   lead %d ticks   corrections %d   drops %d" % [metrics.ping_ms, metrics.get("lead",0), metrics.get("corrections",0), metrics.get("dropped",0)]
		_window = 0.0
		_frames = 0
		_worst_ms = 0.0
