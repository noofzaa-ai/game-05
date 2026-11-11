extends Node
## Client input property owned by its authenticated peer. The server consumes only validated bytes.
const Frame=preload("res://logic/sim_input.gd")
var payload:=PackedByteArray()
var suspended:=false
var epoch:=0
var view_tick:=0
var held=Frame.new()
var edges:Array=[]
func push(frame,scene_epoch:int,view:int)->void:
 epoch=scene_epoch;view_tick=view;held=frame.held_controls()
 if frame.jump or frame.light or frame.heavy or frame.dodge or frame.special or frame.ultimate or frame.skill_slot>=0:
  if edges.size()<32:edges.append(frame.duplicate_input())
func _ready()->void:
 get_node("/root/NetworkTime").before_tick.connect(_capture)
func _exit_tree()->void:
 var clock=get_node_or_null("/root/NetworkTime")
 if clock!=null and clock.before_tick.is_connected(_capture):clock.before_tick.disconnect(_capture)
func _capture(_dt:float,_tick:int)->void:
 if suspended or not is_multiplayer_authority():return
 var frame=held.duplicate_input()
 if not edges.is_empty():
  var edge=edges.pop_front()
  for key in ["jump","light","heavy","dodge","special","ultimate","skill_slot","aim","aim_distance"]:frame.set(key,edge.get(key))
 if _tick%12==0 or frame.jump or frame.light or frame.heavy or frame.dodge or frame.skill_slot>=0:
  get_parent().diagnostic.record("capture",{"input_tick":_tick,"epoch":epoch,"captured_ms":held.captured_at_ms if held.captured_at_ms>=0 else null,"view_tick":view_tick,"edge_queue":edges.size(),"action":frame.skill_slot,"move_x":frame.move.x,"move_y":frame.move.y})
 var stream=StreamPeerBuffer.new();stream.put_u32(epoch);stream.put_u32(maxi(0,view_tick));stream.put_data(frame.encode());payload=stream.data_array
static func decode(bytes:PackedByteArray)->Dictionary:
 if bytes.size()!=Frame.wire_size()+8:return {}
 var stream=StreamPeerBuffer.new();stream.data_array=bytes
 var e:=stream.get_u32();var viewed:=stream.get_u32();var input=Frame.decode(bytes.slice(8))
 return {"epoch":e,"view_tick":viewed,"frame":input} if input!=null else {}
