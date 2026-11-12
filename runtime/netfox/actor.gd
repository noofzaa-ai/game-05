extends Node3D
const Blob=preload("res://logic/net/compressed_blob.gd")
const State=preload("res://logic/net/actor_continuation.gd")
var state_payload_bytes:=0
var state_packets:=0
var state_decode_us:=0
var input_send_calls:=0
var input_payload_bytes:=0
var diagnostic=preload("res://runtime/diagnostics/flight_recorder.gd").new()
var simulation
var actor_id:=1
var epoch:=0
var paused:=true
var base_tick:=0
var authority_room
var state_bytes:=PackedByteArray()
var _cached_world_tick:=-1
var _cached_world_epoch:=-1
var continuation:PackedByteArray:
 get:
  if multiplayer.is_server() and authority_room!=null:
   if _cached_world_tick!=authority_room.clock_tick or _cached_world_epoch!=authority_room.epoch:
    state_bytes=State.capture(authority_room.sim,actor_id);_cached_world_tick=authority_room.clock_tick;_cached_world_epoch=authority_room.epoch
   return state_bytes
  return state_bytes
 set(value):
  if multiplayer.is_server() or value==state_bytes:return
  if simulation!=null:
   var started:=Time.get_ticks_usec()
   if State.restore(simulation,actor_id,value):state_bytes=value;restore_count+=1
   restore_us+=Time.get_ticks_usec()-started
var inbox=preload("res://logic/net/input_inbox.gd").new()
var sync
var last_prediction_tick:=0
var prediction_ticks:=0
var prediction_us:=0
var restore_count:=0
var restore_us:=0
var correction_count:=0
var correction_max_m:=0.0
var correction_last_m:=0.0
var correction_tick:=-1
var correction_state:=""
var _compare_tick:=-1
var _compare_position:=Vector3.ZERO
var _compare_state:=-1
var _compare_fields:Dictionary={}
var last_diag_snapshot_ms:=-250
var _last_present_diag_tick:=-1
func begin_correction_measurement()->void:
 if simulation==null:return
 _compare_tick=last_prediction_tick
 _compare_position=simulation.bodies[actor_id].position
 _compare_state=int(simulation.fighters[actor_id].state)
 _compare_fields=_motion_fields()

var visual_interpolator
func configure(sim,id:int,scene_epoch:int,owner:int,room=null)->void:
 simulation=sim;actor_id=id;epoch=scene_epoch;authority_room=room;inbox.clear(epoch)
 state_bytes=State.capture(sim,id)
 var input=preload("res://runtime/netfox/input_frame.gd").new();input.name="Input";input.set_multiplayer_authority(owner);add_child(input)
 sync=preload("res://runtime/netfox/synchronizer.gd").new();sync.name="Rollback";sync.root=self;sync.enable_prediction=true;sync.enable_input_broadcast=false
 sync.state_properties.assign([":continuation"]);sync.input_properties.assign(["Input:payload"]);sync.visibility_filter.default_visibility=false;sync.visibility_filter.set_visibility_for(owner,room==null)
 add_child(sync)
 if room==null:
  position=simulation.bodies[id].position
  visual_interpolator=TickInterpolator.new();visual_interpolator.name="Presentation";visual_interpolator.root=self;visual_interpolator.properties.assign([":position"]);visual_interpolator.enable_recording=false;add_child(visual_interpolator)
  get_node("/root/NetworkRollback").after_loop.connect(_present)
func collect_input(current_tick:int,now_ms:int)->void:
 var history=sync._inputs
 var ticks:Array=history.ticks();ticks.sort()
 for tick in ticks:
  if tick>current_tick+24 or tick<current_tick-64:continue
  var value=history.get_snapshot(tick).get_value("Input:payload")
  if not value is PackedByteArray:continue
  var row:Dictionary=preload("res://runtime/netfox/input_frame.gd").decode(value)
  if not row.is_empty():
   if inbox.receive(tick,row.frame,row.epoch,now_ms,row.view_tick) and (tick%12==0 or row.frame.jump or row.frame.light or row.frame.heavy or row.frame.dodge or row.frame.skill_slot>=0):diagnostic.record("inbox",{"input_tick":tick,"view_tick":row.view_tick,"worker_tick":current_tick,"epoch":row.epoch},now_ms)
func _rollback_tick(dt:float,tick:int,_fresh:bool)->void:
 if multiplayer.is_server() or simulation==null or paused:return
 assert(is_equal_approx(dt,1.0/60.0))
 var row:Dictionary=preload("res://runtime/netfox/input_frame.gd").decode(get_node("Input").payload)
 if row.is_empty() or row.epoch!=epoch:return
 var started:=Time.get_ticks_usec()
 simulation.tick_count=tick-base_tick
 preload("res://logic/net/actor_step.gd").advance(simulation,actor_id,row.frame)
 if tick==_compare_tick:
  var error_m:float=_compare_position.distance_to(simulation.bodies[actor_id].position)
  if error_m>.03:
   correction_count+=1;correction_last_m=error_m;correction_max_m=maxf(correction_max_m,error_m);correction_tick=tick
   correction_state="%d>%d"%[_compare_state,int(simulation.fighters[actor_id].state)]
   var actual:=_motion_fields();var first:="position"
   for key in ["state","move_id","move_frame","hitstun_left","hitstop","knockback","velocity","position"]:
    if actual.get(key)!=_compare_fields.get(key):first=key;break
   diagnostic.record("correction",{"input_tick":tick,"distance_m":error_m,"first_field":first,"predicted":str(_compare_fields.get(first)),"authority_replayed":str(actual.get(first)),"before_state":_compare_state,"after_state":int(simulation.fighters[actor_id].state),"replay_from":sync.get_last_known_state(),"replay_ticks":tick-sync.get_last_known_state()})
  _compare_tick=-1
 # validate=false: this runs on every rollback/replay tick; inspect() independently
 # re-checks _value_safe() before any restore() ever applies these bytes (see
 # logic/net/actor_continuation.gd), so skipping the redundant walk here is safe.
 state_bytes=State.capture(simulation,actor_id,false);last_prediction_tick=tick
 prediction_ticks+=1;prediction_us+=Time.get_ticks_usec()-started

func _present()->void:
 if simulation==null or visual_interpolator==null:return
 var target:Vector3=simulation.bodies[actor_id].position
 var teleported:bool=position.distance_to(target)>3
 position=target
 if last_prediction_tick%12==0 and _last_present_diag_tick!=last_prediction_tick:
  _last_present_diag_tick=last_prediction_tick
  diagnostic.record("present",{"input_tick":last_prediction_tick,"epoch":epoch,"position":str(target)})
 if teleported:visual_interpolator.teleport()
 else:visual_interpolator.push_state()

func retire()->void:
 paused=true;sync.suspended=true;get_node("Input").suspended=true

func _exit_tree()->void:
 pass

func _motion_fields()->Dictionary:
 var body=simulation.bodies[actor_id];var fighter=simulation.fighters[actor_id]
 return {"position":body.position,"velocity":body.velocity,"knockback":body.knockback,"state":fighter.state,"move_id":fighter.move_id,"move_frame":fighter.move_frame,"hitstun_left":fighter.hitstun_left,"hitstop":fighter.hitstop}
