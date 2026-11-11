extends SceneTree

const Progress := preload("res://logic/goblin_wave_progress.gd")
const Roster := preload("res://logic/goblin_wave_roster.gd")
const Room := preload("res://server/rooms/room.gd")

func _initialize() -> void:
	var data = preload("res://logic/journey_data.gd").load_by_id("ink_road")
	assert(data.is_valid())
	for wave in range(1, 12):
		var roster: Dictionary = Roster.build(data, wave)
		assert(not roster.enemies.is_empty())
		assert(roster.enemies.filter(func(e): return e.miniboss).size() == (1 if wave in Progress.CHEST_WAVES else 0))
		assert(roster.chest_after_clear == (wave in Progress.CHEST_WAVES))
	assert(Roster.build(data, 12).is_empty())
	var combat = preload("res://logic/combat_data_loader.gd").load_default()
	var map = preload("res://logic/map_loader.gd").load_by_id("goblin_base_gate")
	var sim = preload("res://logic/game_sim.gd").new(preload("res://logic/sim_world.gd").new(), combat)
	var wave_three: Dictionary = Roster.build(data, 3)
	var ids: Array = Roster.spawn(sim, map, wave_three, 100, 1.5)
	assert(ids.size() == wave_three.enemies.size())
	assert(Roster.spawn(sim, map, wave_three, 100).is_empty())
	assert(sim.fighters[ids.back()].enemy_type == Roster.MINIBOSS_TYPE)
	var p = Progress.new()
	for wave in range(1, 12):
		assert(p.wave == wave and p.phase == Progress.FIGHTING)
		assert(p.finish_wave(wave))
		assert(not p.finish_wave(wave))
		if wave in Progress.CHEST_WAVES:
			assert(p.phase == Progress.CHEST and not p.finish_wave(wave))
			p = Progress.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
			assert(p != null and p.open_chest() and not p.open_chest())
		else:
			assert(p.phase == (Progress.REST if wave == 11 else Progress.FIGHTING))
		p = Progress.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
		assert(p != null)
	assert(p.opened_chests == [3, 6, 9])
	assert(p.leave_rest() and not p.leave_rest())
	assert(p.finish_boss() and not p.finish_boss())
	assert(Progress.from_dict({"v": 1, "wave": 10, "phase": "fighting", "opened_chests": [3, 6]}) == null)
	assert(Progress.from_dict({"v": 1, "wave": 4, "phase": "fighting", "opened_chests": [3, 3]}) == null)
	print("Goblin wave progress contract passed")
	quit()
