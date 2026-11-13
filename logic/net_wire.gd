extends RefCounted
## Strict, bounded binary data codec. Never decodes executable Objects/Variants.
static var last_encode_error: Dictionary = {}
const MAGIC := 0x585a
const VERSION := 3  ## 3: FIGHTER_FIELDS gained skill_net/race_net (logic/net/skill_net.gd); skill_view on the wire drops class_cast
const MAX_FRAME := 65536
const SkillNet := preload("res://logic/net/skill_net.gd")
const INPUT := 1
const STATE := 2
const EVENTS := 3
const CONTROL := 4
const PING := 5
const PONG := 6
const BODY_FIELDS := ["position", "velocity", "grounded", "move_speed_multiplier", "height", "knockback"]
const FIGHTER_FIELDS := ["team", "style", "stats", "hp", "enemy_type", "level", "state", "state_ticks", "direction", "move_id", "move_frame", "hit_ids", "spawns_done", "buffered", "hitstun_left", "launched", "down_left", "invulnerable_left", "hitstop", "combo_hits", "dodge_left", "dodge_cooldown", "cooldowns", "gauge", "energy", "energy_wait", "exhausted", "running", "run_ticks", "run_grace", "air_run", "poise", "max_poise", "poise_wait", "combo_dealt", "combo_damage", "combo_timer", "active_started", "effects", "stat_mods", "incapacitated", "rooted", "control_immune_left", "downed_at", "bleedout_left", "revive_progress", "reviver", "eliminated", "skill_view", "skill_net", "race_net", "relic_state"]

## The wire value of one FIGHTER_FIELDS entry. Use this (never fighter.get(field)) when building entity rows:
## skill_net/race_net are computed views, and skill_view is sent without class_cast (skill_net carries it) and with
## slot cooldowns rounded to 0.1 s so the row does not change every tick (bandwidth; PO default 2026-11-13).
static func fighter_value(fighter, field: String):
	match field:
		"skill_net": return SkillNet.pack_skill(fighter)
		"race_net": return SkillNet.pack_race(fighter)
		"skill_view":
			var view: Dictionary = fighter.skill_view
			if not view.has("class_cast") and not view.has("slots"): return view
			var out := view.duplicate()
			out.erase("class_cast")
			if view.has("slots"):
				var slots: Array = []
				for slot in view["slots"]:
					var row: Dictionary = slot.duplicate()
					row["left"] = snappedf(float(row.get("left", 0.0)), 0.1)
					slots.append(row)
				out["slots"] = slots
			return out
	return fighter.get(field)

static func frame(kind: int, sequence: int, payload: PackedByteArray) -> PackedByteArray:
	if kind < 1 or kind > 6 or sequence < 1 or sequence > 0xffffffff or payload.size() > MAX_FRAME - 12: return PackedByteArray()
	var out := StreamPeerBuffer.new()
	out.put_u16(MAGIC); out.put_u8(VERSION); out.put_u8(kind); out.put_u32(sequence); out.put_u32(payload.size()); out.put_data(payload)
	return out.data_array

static func parse(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 12 or bytes.size() > MAX_FRAME: return {}
	var reader := StreamPeerBuffer.new(); reader.data_array = bytes
	if reader.get_u16() != MAGIC or reader.get_u8() != VERSION: return {}
	var kind := reader.get_u8(); var sequence := reader.get_u32(); var size := reader.get_u32()
	if kind < 1 or kind > 6 or sequence < 1 or size != bytes.size() - 12: return {}
	return {"kind": kind, "sequence": sequence, "body": bytes.slice(12)}

static func encode(value, limit: int = MAX_FRAME - 12, shared_entities = null) -> PackedByteArray:
	var codec := ValueCodec.new()
	codec.limit = mini(limit, 262144); codec.budget = 32768 if limit > MAX_FRAME else 8192
	codec.shared_entities = shared_entities
	codec.write(value, 0)
	if codec.failed or codec.stream.get_size() > limit:
		last_encode_error={"reason":codec.failure_reason if not codec.failure_reason.is_empty() else "bytes" if codec.stream.get_size()>limit else "unknown","bytes":codec.stream.get_size(),"remaining_nodes":codec.budget,"max_depth":codec.max_depth_seen,"limit":limit}
		return PackedByteArray()
	last_encode_error={}
	return codec.stream.data_array

static func decode(bytes: PackedByteArray, limit: int = MAX_FRAME - 12) -> Dictionary:
	if bytes.size() > mini(limit, 262144): return {}
	var codec := ValueCodec.new(); codec.stream.data_array = bytes
	codec.limit = mini(limit, 262144); codec.budget = 32768 if limit > MAX_FRAME else 8192
	var value = codec.read(0)
	return {} if codec.failed or codec.stream.get_available_bytes() != 0 else {"value": value}

static func packet(kind: int, sequence: int, value) -> PackedByteArray:
	var bytes := encode(value)
	return PackedByteArray() if bytes.is_empty() else frame(kind, sequence, bytes)

static func inputs(sequence: int, state_ack: int, event_ack: int, newest: int, frames: Array, epoch: int = 1, view_ticks: Array = []) -> PackedByteArray:
	if frames.is_empty() or frames.size() > 4 or newest < frames.size(): return PackedByteArray()
	var out := StreamPeerBuffer.new(); out.put_u32(state_ack); out.put_u32(event_ack); out.put_u32(epoch); out.put_u32(newest); out.put_u8(frames.size())
	for bytes in frames:
		if not bytes is PackedByteArray or preload("res://logic/sim_input.gd").decode(bytes) == null: return PackedByteArray()
		out.put_data(bytes)
	if not view_ticks.is_empty():
		if view_ticks.size()!=frames.size():return PackedByteArray()
		for tick in view_ticks:out.put_u32(int(tick) if int(tick)>=0 else 4294967295)
	return frame(INPUT, sequence, out.data_array)

static func read_inputs(bytes: PackedByteArray) -> Dictionary:
	var input_size: int = preload("res://logic/sim_input.gd").wire_size()
	if bytes.size() < 17 + input_size: return {}
	var reader := StreamPeerBuffer.new(); reader.data_array = bytes
	var state_ack := reader.get_u32(); var event_ack := reader.get_u32(); var epoch := reader.get_u32(); var newest := reader.get_u32(); var count := reader.get_u8()
	if count < 1 or count > 4 or newest < count or bytes.size() not in [17+input_size*count,17+(input_size+4)*count]: return {}
	var frames := []
	for i in range(count):
		var part := bytes.slice(17 + i * input_size, 17 + (i + 1) * input_size)
		if preload("res://logic/sim_input.gd").decode(part) == null: return {}
		frames.append(part)
	var views:Array=[]
	for i in count:
		var value:int=bytes.decode_u32(17+input_size*count+i*4) if bytes.size()==17+(input_size+4)*count else 4294967295
		views.append(-1 if value==4294967295 else value)
	return {"view_ticks":views,"state_ack": state_ack, "event_ack": event_ack, "epoch": epoch, "tick": newest, "frames": frames}

class ValueCodec:
	extends RefCounted
	var stream := StreamPeerBuffer.new()
	var failed := false
	var failure_reason := ""
	var max_depth_seen := 0
	var budget := 8192
	var limit := MAX_FRAME - 12
	var shared_entities = null
	func safe(count: int) -> bool:
		if count < 0 or stream.get_available_bytes() < count: failed = true
		return not failed
	func write(value, depth: int) -> void:
		budget -= 1
		max_depth_seen=maxi(max_depth_seen,depth)
		if depth > 12 or budget < 0 or stream.get_size() > limit:
			failed=true
			if failure_reason.is_empty():failure_reason="depth" if depth>12 else "nodes" if budget<0 else "bytes"
			return
		match typeof(value):
			TYPE_NIL: stream.put_u8(0)
			TYPE_BOOL: stream.put_u8(2 if value else 1)
			TYPE_INT:
				if value >= -32768 and value <= 32767: stream.put_u8(11); stream.put_16(value)
				elif value >= 0 and value <= 0xffffffff: stream.put_u8(12); stream.put_u32(value)
				else: stream.put_u8(3); stream.put_64(value)
			TYPE_FLOAT:
				if not is_finite(value): failed = true; failure_reason="non_finite"; return
				stream.put_u8(4); stream.put_double(value)
			TYPE_STRING:
				var bytes: PackedByteArray = value.to_utf8_buffer()
				if bytes.size() > 8192: failed = true; failure_reason="string_size"; return
				stream.put_u8(5); stream.put_u16(bytes.size()); stream.put_data(bytes)
			TYPE_ARRAY:
				if value.size() > 1024: failed = true; failure_reason="array_size"; return
				stream.put_u8(6); stream.put_u16(value.size())
				for part in value: write(part, depth + 1)
			TYPE_DICTIONARY:
				if value.size() > 512: failed = true; failure_reason="dictionary_size"; return
				stream.put_u8(7); stream.put_u16(value.size())
				for key in value:
					if not key is String and not key is int: failed = true; failure_reason="key_type_%d" % typeof(key); return
					write(key, depth + 1)
					if depth == 0 and key is String and key == "entities" and shared_entities is Dictionary: write_shared(value[key], depth + 1)
					else: write(value[key], depth + 1)
			TYPE_VECTOR2, TYPE_VECTOR3:
				stream.put_u8(8 if value is Vector2 else 9)
				var values: Array = [value.x, value.y] if value is Vector2 else [value.x, value.y, value.z]
				for part in values:
					if not is_finite(part): failed = true; failure_reason="non_finite_vector"; return
					stream.put_float(part)
			TYPE_VECTOR2I: stream.put_u8(10); stream.put_32(value.x); stream.put_32(value.y)
			_: failed = true; failure_reason="value_type_%d" % typeof(value)
	func write_shared(value, depth: int) -> void:
		# Only the top-level public entity subtree, always at depth1. Bytes stay wire-identical.
		var cached: Dictionary = shared_entities.get("entities", {})
		if not cached.is_empty() and typeof(cached.value) == typeof(value) and cached.value == value:
			budget -= int(cached.nodes)
			if budget < 0 or stream.get_size() + cached.bytes.size() > limit:
				failed = true; failure_reason="nodes" if budget<0 else "bytes"; return
			stream.put_data(cached.bytes)
			return
		var offset := stream.get_size(); var nodes := budget
		write(value, depth)
		if not failed: shared_entities["entities"] = {"value": value.duplicate(true) if value is Dictionary or value is Array else value, "bytes": stream.data_array.slice(offset), "nodes": nodes-budget}
	func read(depth: int):
		budget -= 1
		if depth > 12 or budget < 0 or not safe(1): failed = true; return null
		var tag := stream.get_u8()
		match tag:
			0: return null
			1: return false
			2: return true
			3: return stream.get_64() if safe(8) else null
			4:
				if not safe(8): return null
				var number := stream.get_double()
				if not is_finite(number): failed = true
				return number
			5:
				if not safe(2): return null
				var size := stream.get_u16()
				if size > 8192 or not safe(size): failed = true; return null
				var bytes: PackedByteArray = stream.get_data(size)[1]
				if not valid_utf8(bytes): failed = true; return null
				var text := bytes.get_string_from_utf8()
				if text.to_utf8_buffer() != bytes: failed = true
				return text
			6, 7:
				if not safe(2): return null
				var count := stream.get_u16()
				if count > (1024 if tag == 6 else 512): failed = true; return null
				if tag == 6:
					var array := []
					for i in range(count): array.append(read(depth + 1))
					return array
				var dictionary := {}
				for i in range(count):
					var key = read(depth + 1)
					if not key is String and not key is int or dictionary.has(key): failed = true; return null
					dictionary[key] = read(depth + 1)
				return dictionary
			8, 9:
				if not safe(8 if tag == 8 else 12): return null
				var x := stream.get_float(); var y := stream.get_float(); var z := stream.get_float() if tag == 9 else 0.0
				if not is_finite(x) or not is_finite(y) or not is_finite(z): failed = true
				return Vector2(x, y) if tag == 8 else Vector3(x, y, z)
			11: return stream.get_16() if safe(2) else null
			12: return stream.get_u32() if safe(4) else null
			10: return Vector2i(stream.get_32(), stream.get_32()) if safe(8) else null
		failed = true
		return null

	func valid_utf8(bytes: PackedByteArray) -> bool:
		var i := 0
		while i < bytes.size():
			var first := int(bytes[i]); var count := 0; var minimum := 0; var code := 0
			if first < 128: i += 1; continue
			if first >= 194 and first <= 223: count = 1; code = first & 31; minimum = 128
			elif first >= 224 and first <= 239: count = 2; code = first & 15; minimum = 2048
			elif first >= 240 and first <= 244: count = 3; code = first & 7; minimum = 65536
			else: return false
			if i + count >= bytes.size(): return false
			for j in range(1, count + 1):
				var part := int(bytes[i + j])
				if part < 128 or part > 191: return false
				code = (code << 6) | (part & 63)
			if code < minimum or code > 1114111 or (code >= 55296 and code <= 57343): return false
			i += count + 1
		return true
