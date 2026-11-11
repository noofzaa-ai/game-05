extends RefCounted
## Lossless, canonical JSON-compatible simulation values, including 64-bit RNG state.
## Dictionaries are ordered pairs: key type and insertion order affect simulation ties.
## Checkpoints are trusted server/local data, never player-supplied ownership commands.

static func pack(value):
	match typeof(value):
		TYPE_INT:
			return ["i", str(value)]
		TYPE_FLOAT:
			return ["f", float_text(value)]
		TYPE_VECTOR2:
			return ["v2", value.x, value.y]
		TYPE_VECTOR2I:
			return ["v2i", value.x, value.y]
		TYPE_VECTOR3:
			return ["v3", value.x, value.y, value.z]
		TYPE_AABB:
			return ["box", pack(value.position), pack(value.size)]
		TYPE_ARRAY:
			return ["a", value.map(func(entry): return pack(entry))]
		TYPE_DICTIONARY:
			var entries: Array = []
			for key in value:
				entries.append([pack(key), pack(value[key])])
			return ["d", entries]
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return str(value)
	assert(false, "Unsupported checkpoint type %s" % type_string(typeof(value)))
	return null


static func unpack(value):
	if not value is Array:
		return value
	match value[0]:
		"i": return int(value[1])
		"f": return float_value(value[1])
		"v2": return Vector2(value[1], value[2])
		"v2i": return Vector2i(int(value[1]), int(value[2]))
		"v3": return Vector3(value[1], value[2], value[3])
		"box": return AABB(unpack(value[1]), unpack(value[2]))
		"a": return value[1].map(func(entry): return unpack(entry))
		"d":
			var result := {}
			for pair in value[1]:
				result[unpack(pair[0])] = unpack(pair[1])
			return result
	return null


## Capture script variables; callers must exclude computed aliases (Fighter.facing) and object references.
static var _script_fields: Dictionary = {}

static func fields(object: Object, excluded: Array = []) -> Dictionary:
	var script = object.get_script()
	var identity: int = script.get_instance_id() if script != null else object.get_instance_id()
	if not _script_fields.has(identity):
		var names: Array[String] = []
		for property in object.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE: names.append(str(property["name"]))
		_script_fields[identity] = names
	var result := {}
	for key in _script_fields[identity]:
		if not key in excluded: result[key] = object.get(key)
	return result


static func apply_fields(object: Object, values: Dictionary) -> void:
	for key in values:
		var old = object.get(key)
		if old is Array:
			old.assign(values[key])  # preserve typed Array[int]/Array[Dictionary], including empty arrays
		else:
			object.set(key, values[key])


static func digest(value) -> String:
	return JSON.stringify(pack(value)).sha256_text()


## Decimal parsers can round the last bit differently; store the exact IEEE754 double.
static func float_text(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


static func float_value(text: String) -> float:
	var bytes := text.hex_decode()
	assert(bytes.size() == 8, "Invalid checkpoint float")
	return bytes.decode_double(0)
