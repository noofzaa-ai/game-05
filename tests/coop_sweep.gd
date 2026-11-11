extends SceneTree
## Offline full-route balance sample. No stat boosts, enemy overrides or simulated kills.
## godot --headless --path . --script res://tests/coop_sweep.gd -- 10 .7
func _init():
	var args := OS.get_cmdline_user_args()
	var trials := maxi(1,int(args[0])) if args.size() else 10
	var skill := float(args[1]) if args.size() > 1 else .7
	for count in [1,2,4]:
		var wins := 0
		var ticks := 0
		var timeouts := 0
		var stages := 0
		for seed in range(1,trials + 1):
			var result := preload("res://tests/coop_bot.gd").journey_run(count,seed,skill)
			wins += int(result.won)
			ticks += result.ticks
			timeouts += result.timeouts
			stages += result.stages
		print("players=%d trials=%d skill=%.2f win=%d/%d (%.1f%%) avg_stages=%.2f avg_seconds=%.1f timeouts=%d" % [count,trials,skill,wins,trials,100.0*wins/trials,float(stages)/trials,float(ticks)/trials/60,timeouts])
	quit()
