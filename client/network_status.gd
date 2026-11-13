extends CanvasLayer
## Room application round-trip latency (not ICMP), visible on desktop and phones.
const Ink := preload("res://client/ink_ui.gd")
var session
var hud
var _label: Label
var _refresh := 0.0
var _graphics_button: Button
var _graphics_panel: CanvasLayer
var _lag_button: Button
var _lag := preload("res://client/lag_report.gd").new()
var _lag_request := {}
var _lag_busy := false
var _lag_next_at := 0
var _lag_owner := ""

func _ready() -> void:
	layer = 11
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ink.style_text(_label, Ink.PAPER, Ink.FONT_NOTE, 4)
	add_child(_label)
	_lag_button = Button.new()
	_lag_button.text = "Lag report"
	_lag_button.theme = Ink.make_theme(Ink.FONT_NOTE)
	Ink.text_size(_lag_button, Ink.FONT_NOTE)
	_lag_button.custom_minimum_size = Vector2(100, 28)
	_lag_button.pressed.connect(_send_lag_report)
	add_child(_lag_button)
	_graphics_button = Button.new()
	_graphics_button.text = "กราฟิก"
	_graphics_button.theme = Ink.make_theme(Ink.FONT_NOTE)
	Ink.text_size(_graphics_button, Ink.FONT_NOTE)
	_graphics_button.custom_minimum_size = Vector2(76, 28)
	_graphics_button.pressed.connect(func():
		if is_instance_valid(_graphics_panel): return
		_graphics_panel = preload("res://client/graphics_panel.gd").new()
		add_child(_graphics_panel))
	add_child(_graphics_button)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_update()

func _fit() -> void:
	var area := get_viewport().get_visible_rect().size
	_lag_button.position = hud.lag_report_position() if hud != null else Vector2(16, 88)
	_graphics_button.position = _lag_button.position + Vector2(maxf(100.0, _lag_button.size.x) + 8.0, 0)
	_label.size = Vector2(260, 28)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.position = hud.network_readout_position(260.0) if hud != null else Vector2(maxf(8, area.x - 276), 52)

## Squad rooms (design/gdd/online-squads.md 3.3: spectate + social) keep only the ping/FPS readout; the old
## online "Lag report" and "กราฟิก" buttons are for the legacy rooms (Boss squad-room playtest 2026-11-14).
static func shows_old_buttons(online_session) -> bool:
	return online_session == null or not online_session.has_method("is_squad_room") or not online_session.is_squad_room()

func _process(delta: float) -> void:
	var old_buttons := shows_old_buttons(session)
	_lag_button.visible = old_buttons; _graphics_button.visible = old_buttons
	if session != null: _lag.sample(session)
	if not _lag_busy and Time.get_ticks_msec() < _lag_next_at:
		_lag_button.disabled = true
	elif not _lag_busy:
		_lag_button.disabled = false
		if _lag_button.text in ["Sent ✓", "Wait 1 min"]: _lag_button.text = "Lag report"
	_refresh -= delta
	if _refresh > 0: return
	_refresh = 0.5
	_update()

func _update() -> void:
	if session == null: return
	var metrics: Dictionary = session.debug_metrics()
	var ping := "—"
	var color := Ink.PAPER
	if not session.connected:
		ping = "เชื่อมต่อใหม่…"
		color = Ink.BAD
	elif int(metrics.get("ping_age_ms", -1)) > 5000:
		ping = "รอสัญญาณ…"
		color = Ink.BAD
	elif int(metrics.get("ping_age_ms", -1)) >= 0:
		var latency := int(metrics.ping_ms)
		ping = "%d ms" % latency
		if latency > 200: color = Ink.BAD
		elif latency > 100: color = Ink.GOLD
	_label.text = "Ping %s · FPS %d" % [ping, roundi(Engine.get_frames_per_second())]
	_label.modulate = color


func _send_lag_report() -> void:
	if _lag_busy or Time.get_ticks_msec()<_lag_next_at:return
	var account=get_node_or_null("/root/Online")
	if account==null or account.session==null or account.client==null:
		_lag_button.text="Login required";return
	if not _lag_owner.is_empty() and _lag_owner!=account.session.user_id:_lag_request.clear()
	_lag_owner=account.session.user_id
	_lag_busy=true;_lag_button.disabled=true;_lag_button.text="Collecting…"
	var uid:String=account.session.user_id
	if _lag_request.is_empty():
		var report:Dictionary=await session.diagnostic_report()
		if not is_inside_tree():return
		if account.session==null or account.session.user_id!=uid:
			_lag_request.clear();_lag_busy=false;_lag_button.text="Login required";return
		var encoded=preload("res://runtime/diagnostics/report_codec.gd").encode(report)
		if not encoded.get("ok",false):
			_lag_busy=false;_lag_button.text="Report unavailable";return
		encoded.erase("ok");encoded["v"]=1;encoded["request_id"]=Crypto.new().generate_random_bytes(16).hex_encode();_lag_request=encoded
	_lag_button.text="Sending…"
	var response=await account.client.rpc_async(account.session,"zorx_diagnostics_v1",JSON.stringify(_lag_request))
	if not is_inside_tree():return
	_lag_busy=false
	var result=null if response==null or response.is_exception() or response.payload.length()>4096 else JSON.parse_string(response.payload)
	if account.session==null or account.session.user_id!=uid:
		_lag_request.clear();_lag_button.text="Login required";return
	if result is Dictionary and result.get("ok")==true:
		_lag_request.clear();_lag_button.text="Sent ✓";_lag_next_at=Time.get_ticks_msec()+60000
	elif result is Dictionary and result.get("error")=="rate_limited":
		_lag_request.clear();_lag_button.text="Wait 1 min";_lag_next_at=Time.get_ticks_msec()+60000
	else:_lag_button.text="Retry report"
