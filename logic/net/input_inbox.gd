extends RefCounted
## Server receipt sequence is separate from world tick. Never discards an action only because
## its client tick is behind the current world tick. Bounded age/rate is enforced by the peer adapter.
var seen:Dictionary={}
var actions:Array=[]
var held
var latest_tick:=-1
var last_received_at:=-1
var accepted:=0
var repeated:=0
var consumed_actions:=0
var epoch:=-1
var _consumed_tick:=-1
var _held_view:=0
func clear(next_epoch:int)->void:
 seen.clear();actions.clear();held=null;latest_tick=-1;last_received_at=-1;epoch=next_epoch;_consumed_tick=-1;_held_view=0
func receive(tick:int,frame,scene_epoch:int,now_ms:int,view_tick:int=0)->bool:
 if scene_epoch!=epoch or seen.has(tick):return false
 seen[tick]=true
 while seen.size()>256:seen.erase(seen.keys()[0])
 if tick>latest_tick:
  held=frame.held_controls();latest_tick=tick;last_received_at=now_ms;_held_view=view_tick
 if frame.jump or frame.light or frame.heavy or frame.dodge or frame.special or frame.ultimate or frame.skill_slot>=0:
  if actions.size()>=32:return false
  actions.append({"tick":tick,"frame":frame.duplicate_input(),"view":view_tick})
 accepted+=1
 return true
func consume(now_ms:int)->Dictionary:
 var frame=preload("res://logic/sim_input.gd").new() if held==null or now_ms-last_received_at>400 else held.duplicate_input()
 if latest_tick==_consumed_tick:repeated+=1
 _consumed_tick=latest_tick
 var view:=_held_view
 var action_tick:=-1
 if not actions.is_empty():
  var action=actions.pop_front();consumed_actions+=1;view=action.view;action_tick=int(action.tick)
  for key in ["jump","light","heavy","dodge","special","ultimate","skill_slot","aim","aim_distance"]:frame.set(key,action.frame.get(key))
 return {"frame":frame,"view":view,"input_tick":latest_tick,"action_tick":action_tick}
