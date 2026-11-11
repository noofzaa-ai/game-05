extends StateSynchronizer
## Keep authoritative tick samples in the library buffer. Presentation samples behind
## the synchronized server clock; it never writes combat/collision state.
var suspended:=false
var delay_ticks:=6
var rendered_tick:=-1.0
var starvation:=0
var _sent_tick:=-100
var _latest_seen:=-1
var _ages:Array=[]
var _delay:=6.0
func _after_tick(dt:float,tick:int)->void:
 if suspended:return
 if is_multiplayer_authority():
  # State history at60Hz, transport at20Hz. No separate custom packet history.
  var state:=_PropertySnapshot.extract(_property_config.get_properties())
  _state_history.set_snapshot(tick,state)
  if tick-_sent_tick>=3:_sent_tick=tick;_broadcast_state(tick,state)
 else:
  # Interpolation runs once per rendered frame using authoritative tick labels.
  pass
func _process(_delta:float)->void:
 if suspended:return
 if is_multiplayer_authority() or _state_history.is_empty():return
 var latest:int=_state_history.get_latest_tick()
 if latest!=_latest_seen:
  _latest_seen=latest;_ages.append(maxi(0,NetworkTime.tick-latest))
  if _ages.size()>32:_ages.pop_front()
  var sorted:=_ages.duplicate();sorted.sort();delay_ticks=clampi(int(sorted[int((sorted.size()-1)*.9)])+3,3,18)
 _delay=move_toward(_delay,delay_ticks,maxf(0,_delta)*3)
 var target:float=NetworkTime.tick+NetworkTime.tick_factor-_delay
 var ticks:Array=_state_history.ticks();ticks.sort()
 var a:int=ticks[0];var b:int=ticks.back()
 for tick in ticks:
  if tick<=target:a=tick
  if tick>=target:b=tick;break
 rendered_tick=clampf(target,a,b)
 if target>ticks.back():starvation+=1
 var from_state=_state_history.get_snapshot(a)
 var to_state=_state_history.get_snapshot(b)
 var start:Vector3=from_state.get_value(":position")
 var end:Vector3=to_state.get_value(":position")
 root.position=end if start.distance_to(end)>3 else start.lerp(end,clampf((target-a)/maxf(1,b-a),0,1))

func _send_full_state(tick:int,peer:int=0)->void:
 if peer==0:
  for target in multiplayer.get_peers():
   if _peer_open(target):_send_full_state(tick,target)
  return
 if _peer_open(peer):super._send_full_state(tick,peer)

func _peer_open(peer:int)->bool:
 if peer<=0:return true
 if peer not in multiplayer.get_peers():return false
 var transport=multiplayer.multiplayer_peer
 if transport is WebSocketMultiplayerPeer:
  var socket=transport.get_peer(peer)
  return socket!=null and socket.get_ready_state()==WebSocketPeer.STATE_OPEN and socket.get_current_outbound_buffered_amount()<65536
 return true
