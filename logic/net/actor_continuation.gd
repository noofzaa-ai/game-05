extends RefCounted
## Versioned VALUE snapshot for a prediction-owned actor. No Nodes, history, RPC or rendering.
## A transport adapter must accept authority snapshots only; this is not a client command API.
const Codec=preload("res://logic/state_codec.gd")
const VERSION=2
const MAX_BYTES=262144
const EXCLUDED=["facing","skill_hit_filter","skill_base_hit"]
## `validate`=false skips the recursive _value_safe() walk (measured 60-68% of this
## function's cost, see docs/tech/lag_analysis_20261101_TH.md). Safe to skip on the
## client's per-rollback-tick prediction capture: inspect() independently re-runs
## _value_safe() on any bytes before restore() ever applies them, so a NaN/Inf that
## slips past an unvalidated capture() is still caught there, just one hop later.
## Authority capture (once per world tick, cached) keeps the default so a bad value
## is still caught and logged at its source.
static func capture(sim,id:int,validate:bool=true)->PackedByteArray:
 if not sim.bodies.has(id) or not sim.fighters.has(id):return PackedByteArray()
 var context:Dictionary={}
 for target in sim.bodies:
  if target!=id and sim.fighters.has(target):context[target]={"body":Codec.fields(sim.bodies[target]),"fighter":Codec.fields(sim.fighters[target],EXCLUDED)}
 var skills:Dictionary={}  # (the old skill-build runtime's block: always empty now; class skills ride in skill_state)
 var values={"v":VERSION,"actor":id,"body":Codec.fields(sim.bodies[id]),"fighter":Codec.fields(sim.fighters[id],EXCLUDED),"context":context,"skills":skills}
 if validate and not _value_safe(values):
  print("ACTOR SNAPSHOT REJECT ",_unsafe_path(values))
  return PackedByteArray()
 var bytes:=var_to_bytes(values)
 return bytes if bytes.size()<=MAX_BYTES else PackedByteArray()
static func inspect(bytes:PackedByteArray,id:int)->Dictionary:
 if bytes.is_empty() or bytes.size()>MAX_BYTES:return {}
 var value=bytes_to_var(bytes) # Object decoding disabled. Never use bytes_to_var_with_objects.
 if not value is Dictionary or value.size()!=6 or not value.has_all(["v","actor","body","fighter","context","skills"]):return {}
 if typeof(value.v)!=TYPE_INT or value.v!=VERSION or typeof(value.actor)!=TYPE_INT or value.actor!=id:return {}
 if not value.body is Dictionary or not value.fighter is Dictionary or not value.context is Dictionary or not value.skills is Dictionary or not _value_safe(value):return {}
 return value
static func restore(sim,id:int,bytes:PackedByteArray)->bool:
 if not sim.bodies.has(id) or not sim.fighters.has(id):return false
 var value:=inspect(bytes,id)
 if value.is_empty():return false
 # Validate the entire schema before mutating either object; no partial restore.
 if not _same_shape(Codec.fields(sim.bodies[id]),value.body):return false
 if not _same_shape(Codec.fields(sim.fighters[id],EXCLUDED),value.fighter):return false
 for target in value.context:
  if typeof(target)!=TYPE_INT or target==id:return false
  var row=value.context[target]
  if not row is Dictionary or row.size()!=2 or not row.get("body") is Dictionary or not row.get("fighter") is Dictionary:return false
  if not _same_shape(Codec.fields(sim.bodies[id]),row.body) or not _same_shape(Codec.fields(sim.fighters[id],EXCLUDED),row.fighter):return false
 if not value.skills.is_empty():return false
 # Context is combat-only: no stash, profile, bag, credentials or persistence state.
 for target in value.context:
  if not sim.bodies.has(target):sim.add_player(target,Vector3.ZERO)
  Codec.apply_fields(sim.bodies[target],value.context[target].body)
  Codec.apply_fields(sim.fighters[target],value.context[target].fighter)
 for target in sim.bodies.keys():
  if target!=id and not value.context.has(target):sim.remove_player(target)
 Codec.apply_fields(sim.bodies[id],value.body)
 Codec.apply_fields(sim.fighters[id],value.fighter)
 return true
static func _same_shape(expected:Dictionary,received:Dictionary)->bool:
 if expected.size()!=received.size():return false
 for key in expected:
  if not received.has(key) or typeof(expected[key])!=typeof(received[key]):return false
  if expected[key] is Array and expected[key].is_typed():
   var element_type:int=expected[key].get_typed_builtin()
   for item in received[key]:
    if typeof(item)!=element_type:return false
 return true
static func _value_safe(value,depth:int=0)->bool:
 if depth>16:return false
 match typeof(value):
  TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING,TYPE_STRING_NAME,TYPE_VECTOR2I,TYPE_VECTOR3I:return true
  TYPE_FLOAT:return is_finite(value)
  TYPE_VECTOR2:return is_finite(value.x) and is_finite(value.y)
  TYPE_VECTOR3:return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
  TYPE_AABB:return _value_safe(value.position,depth+1) and _value_safe(value.size,depth+1)
  TYPE_ARRAY:
   if value.size()>1024:return false
   for item in value:
    if not _value_safe(item,depth+1):return false
   return true
  TYPE_DICTIONARY:
   if value.size()>1024:return false
   for key in value:
    if typeof(key) not in [TYPE_INT,TYPE_STRING,TYPE_STRING_NAME] or not _value_safe(value[key],depth+1):return false
   return true
 return false

static func _unsafe_path(value,path:String="root",depth:int=0)->String:
 if depth>16:return path+":depth"
 if value is Dictionary:
  for key in value:
   if not _value_safe(value[key],depth+1):return _unsafe_path(value[key],path+"."+str(key),depth+1)
 elif value is Array:
  for i in value.size():
   if not _value_safe(value[i],depth+1):return _unsafe_path(value[i],path+"["+str(i)+"]",depth+1)
 return path+":"+type_string(typeof(value))
