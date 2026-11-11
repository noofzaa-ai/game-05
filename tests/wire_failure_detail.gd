extends SceneTree
const Wire=preload("res://logic/net_wire.gd")
func _initialize() -> void:
 var value:Dictionary={"ok":true,"n":42,"text":"test","position":Vector3.ONE}
 var data:=Wire.encode(value)
 assert(not data.is_empty() and Wire.decode(data).value==value and Wire.last_encode_error.is_empty())
 assert(Wire.encode({"bad":RefCounted.new()}).is_empty())
 assert(str(Wire.last_encode_error.reason).begins_with("value_type_"))
 var deep:Dictionary={};var cursor:=deep
 for i in range(15):cursor["next"]={};cursor=cursor.next
 assert(Wire.encode(deep).is_empty() and Wire.last_encode_error.reason=="depth")
 assert(Wire.encode({"s":"x".repeat(2000)},1000).is_empty() and Wire.last_encode_error.reason=="bytes")
 assert(not Wire.encode(value).is_empty() and Wire.last_encode_error.is_empty())
 print("WIRE FAILURE DETAIL PASS:roundtripunchanged;type/depth/bytesidentified;limitsunchanged;staleerrorcleared")
 quit()
