extends RefCounted
## Read view only; server commands own navigation/rewards.
var state := "in_stage"
var current := {}
var completed := 0
var treasure_pending := false
var path: Array[String] = []
var run
var last_reward := {}
var hp_fraction := 1.0
var _choices := []
var _players := []
var _stage := 1
var wave := 1  ## wave-mode rooms: the wave on the field (meta.wave)
var data = preload("res://logic/journey_data.gd").new()

func update(meta: Dictionary, trip) -> void:
	state = meta.state; current = meta.current; treasure_pending = meta.treasure_pending
	_stage = int(meta.stage); completed = _stage - 1; path.assign(meta.path)
	_choices = meta.choices; _players = meta.players; run = trip
	data.display_name = str(meta.get("content_name", "The Ink Road")); data.stage_count = int(meta.get("stage_count", 12))
	data.wave_mode = bool(meta.get("wave_mode", false)); wave = int(meta.get("wave", 1))

func is_over() -> bool: return state in ["won", "lost", "retreated", "abandoned"]
func is_at_camp() -> bool: return state == "at_node" and current.get("kind") == "camp"
func choices() -> Array: return _choices if state == "choosing" else []
func upcoming_choices() -> Array: return [] if treasure_pending else _choices
func stage_number() -> int: return _stage
func wave_total() -> int: return data.stage_count
func progress_text() -> String: return ("Wave %d/%d" % [wave, data.stage_count]) if data.wave_mode else ("Stage %d/%d" % [_stage, data.stage_count])
func player_ids() -> Array: return _players
func can_bank_bag() -> bool: return is_at_camp()
