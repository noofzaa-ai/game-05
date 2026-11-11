extends SceneTree
## Deterministic reproduction of a pause with a stretched stepping clock.
class ReferenceClock extends NetworkClocks.SystemClock:
 var now:=0.0
 func get_raw_time()->float:return now
class StepClock extends NetworkClocks.SteppingClock:
 var now:=0.0
 func get_raw_time()->float:return now
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var clock=root.get_node("NetworkTime")
 var reference=root.get_node("NetworkTimeSynchronizer")
 root.get_node("NetworkRollback").enabled=false
 clock.set_process(false);clock.set_physics_process(false)
 var failures:=0
 for stretch in [0.8,1.25]:
  var step=StepClock.new();var source=ReferenceClock.new()
  var start:=1000.0/60.0
  step.time=start;step.last_step=0;step.now=0
  source.now=start
  clock._clock=step;reference._clock=source
  clock._tick=1000;clock._next_tick_time=start;clock._last_process_time=start
  clock._clock_stretch_factor=stretch;clock._was_paused=false
  step.now=2;source.now+=2
  clock._loop()
  for i in 180:
   step.now+=1.0/60.0;source.now+=1.0/60.0
   clock._loop()
  var error:int=clock.tick-clock.seconds_to_ticks(source.get_time())
  print("PAUSE CLOCK stretch=",stretch," tick_error=",error)
  if absi(error)>2:failures+=1
 if failures>0:
  printerr("PAUSE CLOCK FAIL: pause rebased tick without rebasing the stepping-clock phase")
  quit(1)
 else:
  print("PAUSE CLOCK PASS: 2s stall at slow/fast clock stretch stays within2ticks after resume")
  quit()
