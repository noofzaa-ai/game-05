extends CanvasLayer
## Online squad rooms (design/gdd/online-squads.md chunk 5), presentation only: the synergy banner per group, the
## camera "next card" toggle, the leader's route/rest buttons and the auto-continue countdown everyone sees.
## Every choice goes to the server as a command; the server decides (leader only, choice 0 after the timer).
signal cycle_camera
signal choose(index: int)
const CardTokens := preload("res://client/card_tokens.gd")
const ExitPortal := preload("res://client/exit_portal.gd")
## EN/TH text (CardTokens.language picks), kept here so the shared token file is not edited by two agents at once.
const TEXT := {
	"next_card": ["การ์ดถัดไป", "Next card"],
	"you": ["ทัพของฉัน", "My squad"],
	"choose": ["เลือกเส้นทาง", "Choose the route"],
	"waiting": ["รอหัวหน้าเลือกเส้นทาง", "Waiting for the leader"],
	"auto": ["ไปต่อเองใน %d วิ", "Auto-continue in %d s"],
	"no_synergy": ["ไม่มีซินเนอร์จี", "No synergy"],
	"room": ["ทั้งห้อง", "Room"],
	"combat": ["ต่อสู้", "Combat"], "camp": ["พักแคมป์", "Rest camp"], "challenge": ["ท้าทาย", "Challenge"],
	"treasure": ["หีบสมบัติ", "Treasure"], "boss": ["บอส", "BOSS"],
}
var session
var _root: Control
var _synergy: Label
var _next: Button
var _route: VBoxContainer
var _route_title: Label
var _buttons: HBoxContainer
var _countdown: Label
var _key := ""
var _refresh := 0.0


static func text(key: String) -> String:
	var entry: Array = TEXT.get(key, [key, key])
	return str(entry[0 if CardTokens.language == "th" else 1])


func _ready() -> void:
	layer = 13
	_root = Control.new(); _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_root)
	_synergy = CardTokens.label("", 20, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium", CardTokens.HUB_OUTLINE)
	_synergy.name = "SynergyBanner"; _synergy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_synergy.mouse_filter = Control.MOUSE_FILTER_IGNORE; _root.add_child(_synergy)
	_next = Button.new(); _next.name = "NextCard"; _next.text = text("next_card"); _next.focus_mode = Control.FOCUS_ALL
	_next.custom_minimum_size = Vector2(150, 48); _next.pressed.connect(func(): cycle_camera.emit()); _root.add_child(_next)
	_route = VBoxContainer.new(); _route.name = "Route"; _route.alignment = BoxContainer.ALIGNMENT_CENTER; _root.add_child(_route)
	_route_title = CardTokens.label("", 26, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
	_route_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _route.add_child(_route_title)
	_buttons = HBoxContainer.new(); _buttons.alignment = BoxContainer.ALIGNMENT_CENTER; _route.add_child(_buttons)
	_countdown = CardTokens.label("", 20, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium", CardTokens.HUB_OUTLINE)
	_countdown.name = "Countdown"; _countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _route.add_child(_countdown)
	_route.visible = false
	get_viewport().size_changed.connect(_fit); _fit()


func _fit() -> void:
	var area := get_viewport().get_visible_rect().size
	_synergy.position = Vector2(0, 56); _synergy.size = Vector2(area.x, 30)
	_next.position = Vector2(area.x - 170, 100)
	_route.position = Vector2(0, area.y * 0.3); _route.size = Vector2(area.x, 160)


## The synergy line: "My squad: Elf Pair · Mai: Viking Trio" (a 4-player room has one "Room" group).
static func synergy_line(groups: Array, names: Dictionary, me: int) -> String:
	var parts: Array = []
	for group in groups:
		var players: Array = group.get("players", [])
		var who := text("room") if str(group.get("group", "")) == "room" else (text("you") if players.has(me) else str(names.get(int(players[0]) if not players.is_empty() else 0, "")))
		var what := text("no_synergy") if str(group.get("kind", "none")) == "none" else ("%s %s" % [str(group.get("race", "")).capitalize(), str(group.get("name", ""))]).strip_edges()
		parts.append("%s: %s" % [who, what])
	return "  ·  ".join(parts)


func _process(delta: float) -> void:
	if session == null or not session.ready or not session.is_squad_room(): visible = false; return
	visible = true
	_refresh -= delta
	if _refresh > 0.0: return
	_refresh = 0.1
	var names := {}
	for member in session.party_view().get("members", []): names[int(member.id)] = str(member.name)
	_synergy.text = synergy_line(session.synergy_groups(), names, session.player_id())
	_next.visible = session.fighters_of().size() > 1
	var choices: Array = session.journey.upcoming_choices() if session.journey != null else []
	var waiting: bool = not session.is_lobby() and session.auto_continue_left() >= 0.0 and not choices.is_empty()
	_route.visible = waiting
	if not waiting: _key = ""; return
	var leader: bool = session.is_leader()
	_route_title.text = text("choose") if leader else text("waiting")
	_countdown.text = text("auto") % ceili(session.auto_continue_left())
	var key := "%s%s" % [leader, str(choices)]
	if key == _key: return
	_key = key
	for child in _buttons.get_children(): child.queue_free()
	if not leader: return
	for index in choices.size():
		var kind := str(choices[index].get("kind", "combat"))
		var b := Button.new(); b.text = text(kind) if TEXT.has(kind) else str(ExitPortal.NAMES.get(kind, kind))
		b.custom_minimum_size = Vector2(160, 56); b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(func(): choose.emit(index))
		_buttons.add_child(b)
