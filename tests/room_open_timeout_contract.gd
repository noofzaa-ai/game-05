extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var game=load("res://client/game_state.gd").new()
 game._solo_generation=4;game._solo_connecting=true;game._solo_started_at=1
 game.cancel_pending_solo()
 assert(not game._solo_connecting and game._solo_started_at==0 and game._solo_generation==5)
 assert(not game._solo_current(4,{"ok":false},null))
 assert(game._solo_current(5,{"ok":false},null))
 game._solo_connecting=true;game.cancel_pending_solo(false)
 assert(not game._solo_connecting)
 game.free()
 print("ROOM OPEN CANCEL PASS:waitflagcleared,generationinvalidateslatecompletion,retryunblocked")
 quit()
