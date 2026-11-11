extends RefCounted
## Protocol-independent admission. Trusted backend decides room, slot, profile and fences.
## No RPC/input/replication becomes available before this completes.
const MAX_BYTES=256
const MAX_PENDING=8
const MAX_ADMITTED=32
var pending:Dictionary={}
var admitted:Dictionary={}
var slots:Dictionary={}
var maintenance:=false
func begin(peer:int,now_ms:int)->bool:
 if peer<=1 or maintenance or pending.size()>=MAX_PENDING or admitted.size()>=MAX_ADMITTED or pending.has(peer) or admitted.has(peer):return false
 pending[peer]={"since":now_ms,"verifying":false}
 return true
func request(peer:int,bytes:PackedByteArray)->Dictionary:
 if not pending.has(peer) or pending[peer].verifying or bytes.size()>MAX_BYTES or bytes.is_empty():return {}
 var value=JSON.parse_string(bytes.get_string_from_utf8())
 if not value is Dictionary or value.size()!=3 or not value.has_all(["v","room","ticket"]):return {}
 if typeof(value.v) not in [TYPE_INT,TYPE_FLOAT] or value.v!=2 or not value.room is String or not value.ticket is String:return {}
 if RegEx.create_from_string("^[a-f0-9]{32}$").search(value.room)==null or RegEx.create_from_string("^[a-f0-9]{64}$").search(value.ticket)==null:return {}
 pending[peer].verifying=true
 pending[peer]["room"]=value.room
 return {"op":"redeem","room":value.room,"ticket":value.ticket}
func complete(peer:int,result:Dictionary)->Dictionary:
 if not pending.has(peer) or not pending[peer].verifying:return {}
 if not result.get("ok",false) or result.get("room","")!=pending[peer].room:return {}
 if typeof(result.get("slot")) not in [TYPE_INT,TYPE_FLOAT] or typeof(result.get("capacity")) not in [TYPE_INT,TYPE_FLOAT]:return {}
 var slot:=int(result.slot);var capacity:=int(result.capacity)
 if result.slot!=slot or result.capacity!=capacity or capacity<1 or capacity>4 or slot<1 or slot>4:return {}
 if not result.get("profile") is Dictionary or not result.get("fence") is String or str(result.fence).is_empty():return {}
 var key:String=str(result.room)+":"+str(slot)
 var replaced:int=slots.get(key,0)
 var binding:Dictionary={"peer":peer,"room":result.room,"slot":slot,"capacity":capacity,"fence":result.fence,"member_fence":result.get("member_fence",""),"replaced_peer":replaced}
 # No ticket retained. Profile is passed once to trusted room setup, not stored on the gate.
 pending.erase(peer);admitted[peer]=binding;slots[key]=peer
 return binding.duplicate(true)
func route(peer:int)->Dictionary:
 # Callers must not accept client-supplied room or slot overrides.
 return admitted.get(peer,{}).duplicate(true)
func drop(peer:int)->void:
 pending.erase(peer)
 if admitted.has(peer):
  var row:Dictionary=admitted[peer];var key:String=str(row.room)+":"+str(row.slot)
  if slots.get(key,0)==peer:slots.erase(key)
  admitted.erase(peer)
func expired(now_ms:int)->Array:
 var result:Array=[]
 for peer in pending:
  if now_ms-int(pending[peer].since)>=3000:result.append(peer)
 return result
