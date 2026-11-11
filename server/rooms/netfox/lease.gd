extends "res://server/rooms/lifecycle.gd"
## Reuse the existing authoritative admission/start/renew/finalize/command fences.
var backend_delegate:Callable
var state_delegate:Callable
func backend(payload:Dictionary)->Dictionary:return await backend_delegate.call(payload)
func poll(now:int,send_states:bool=true)->void:
 poll_bindings(now)
 if send_states:flush_states(now)
func flush_states(now:int)->void:
 for id in peers:
  var entry:Dictionary=peers[id]
  if not entry.room.is_empty() and now-int(entry.last_send)>=50 and _room(entry.room)!=null:
   entry.last_send=now
   if state_delegate.is_valid():state_delegate.call(id,_room(entry.room))

func _start_room(id:String)->void:
 await super._start_room(id)
 if manager.rooms.has(id):manager.rooms[id]["external_tick"]=true
