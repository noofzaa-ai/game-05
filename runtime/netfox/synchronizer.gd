extends RollbackSynchronizer
## Authority is driven by Room at NetworkTime, never rolled back by the presentation adapter.
## Clients use the standard library rollback loop; authority publishes a correctly labelled state.
var _published_tick:=-100
var suspended:=false
var _processed_authority_tick:=-1
var redundant_replay_ticks_avoided:=0
func _enter_tree()->void:
 if not Engine.is_editor_hint():
  _history_transmitter=preload("res://runtime/netfox/transmitter.gd").new()
  add_child(_history_transmitter,true)
  _history_transmitter.set_multiplayer_authority(get_multiplayer_authority())
 super._enter_tree()
func _before_rollback_loop()->void:
 if suspended:return
 if multiplayer.is_server():NetworkRollback.notify_resimulation_start(NetworkTime.tick-1)
 else:
  root.begin_correction_measurement()
  var authority_tick:=get_last_known_state()
  # With no new authority/input from another peer, our completed owner history
  # already contains this range. Replay only when new authority can change it.
  # Keep netfox history/restore/input recording; do not advance or skip input IDs.
  if authority_tick==_processed_authority_tick and root.last_prediction_tick>0 and not NetworkRollback.is_mutated(root,NetworkTime.tick):
   var resume_tick:int=maxi(authority_tick,root.last_prediction_tick+1)
   redundant_replay_ticks_avoided+=maxi(0,resume_tick-authority_tick)
   NetworkRollback.notify_resimulation_start(resume_tick)
  else:super._before_rollback_loop()
  _processed_authority_tick=authority_tick
func _before_tick(dt:float,tick:int)->void:
 if suspended:return
 if not multiplayer.is_server():super._before_tick(dt,tick)
func _on_prepare_tick(tick:int)->void:
 if suspended:return
 if not multiplayer.is_server():super._on_prepare_tick(tick)
func _process_tick(tick:int)->void:
 if suspended:return
 if multiplayer.is_server():NetworkRollback.notify_simulated(root)
 else:super._process_tick(tick)
func _on_record_tick(tick:int)->void:
 if suspended:return
 if not multiplayer.is_server():
  super._on_record_tick(tick);return
 if tick!=NetworkTime.tick or tick-_published_tick<3:return
 _published_tick=tick
 _history_recorder.record_state(tick)
 _history_transmitter.set_predicted_tick(false)
 _history_transmitter.transmit_state(tick)
func _after_rollback_loop()->void:
 if suspended:return
 if multiplayer.is_server():_history_transmitter.conclude_tick_loop()
 else:super._after_rollback_loop()

func _after_tick(dt:float,tick:int)->void:
 if not suspended:super._after_tick(dt,tick)
