extends Node
## Integration bridge under an isolated compatibility project, not enabled in live game.
const Continuation=preload("res://logic/net/actor_continuation.gd")
var simulation
var actor_id:=1
var rollback_calls:=0
var _state:=PackedByteArray()
var continuation:PackedByteArray:
 get:return _state
 set(value):
  if simulation!=null and not value.is_empty():
   if not Continuation.restore(simulation,actor_id,value):return
  _state=value
func configure(sim,id:int,input_authority:int)->void:
 simulation=sim;actor_id=id;_state=Continuation.capture(sim,id)
 var input=Node.new();input.name="Input";input.set_script(load("res://bridge_input.gd"));input.set_multiplayer_authority(input_authority)
 add_child(input)
 var sync=load("res://addons/netfox/rollback/rollback-synchronizer.gd").new()
 sync.name="Rollback";sync.root=self;sync.enable_prediction=true;sync.enable_input_broadcast=false
 sync.state_properties.assign([":continuation"]);sync.input_properties.assign(["Input:payload"])
 add_child(sync)
func _rollback_tick(dt:float,_tick:int,_fresh:bool)->void:
 assert(is_equal_approx(dt,1.0/60.0))
 var input=preload("res://logic/sim_input.gd").decode(get_node("Input").payload)
 if input==null:return
 simulation.tick_count=_tick-1
 preload("res://logic/net/actor_step.gd").advance(simulation,actor_id,input)
 _state=Continuation.capture(simulation,actor_id);rollback_calls+=1
