extends RefCounted
## Statuses never recolour the whole character (Boss 2026-11-14: a hero with Slow/Sunder turned into a pale white
## ghost). Checks: the Studio model's shader flash stays clear while statuses, hit-stun and immunity are on; a hit
## flash is brief and always clears; statuses show as small looping effects (client/status_vfx.gd) inside the
## draw budget; every effect id in data/combat/effects.json maps to a look.

const FighterView := preload("res://client/fighter_view.gd")
const StatusVfx := preload("res://client/status_vfx.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimBody := preload("res://logic/sim_body.gd")
const PLAYER_MODEL := "res://art/characters/studio05/split/body_sword_shield.glb"
const MAX_DRAWS_PER_STATUS := 40


func run(ctx) -> void:
	var data := CombatDataLoader.load_default()
	ctx.check("combat data loads", data.is_valid())
	_check_mapping(ctx, data)
	await _check_no_body_tint(ctx, data)


func _check_mapping(ctx, data) -> void:
	var unmapped: Array = []
	for id in data.effects:
		var picked := StatusVfx.pick([id], data.effects)
		var look: String = picked["head"] if picked["head"] != "" else picked["feet"]
		if look == "" or StatusVfx.scene_path(look) == "" and not look in ["buff", "debuff", "sleep", "shock", "bleed", "regen"]:
			unmapped.append(id)
	ctx.check("every status maps to a status look %s" % [unmapped], unmapped.is_empty())
	var both := StatusVfx.pick(["stun", "slow"], data.effects)
	ctx.check("stun shows over the head and slow at the feet together", both["head"] == "stun" and both["feet"] == "slow")


func _flash_of(view) -> Vector4:
	for material in view._model._toon:
		return material.get_shader_parameter("flash")
	return Vector4.ZERO


func _check_no_body_tint(ctx, data) -> void:
	var view: Node3D = FighterView.new()
	view.model_path = PLAYER_MODEL
	view.looks = {"class": "sword_shield"}
	ctx.root.add_child(view)
	await ctx.process_frame
	ctx.check("the Studio hero model loads for the status check", view._model != null and not view._model._toon.is_empty())
	if view._model == null or view._model._toon.is_empty():
		view.queue_free()
		return
	var fighter = Fighter.new()
	fighter.team = "player"
	fighter.stats = {"HP": 100.0}
	fighter.hp = 100.0
	fighter.effects = {"slow": {"left": 300, "stacks": 1}, "sunder": {"left": 300, "stacks": 1}}
	var body = SimBody.new()
	view.show_state(body, fighter, data)
	await ctx.process_frame
	ctx.check("Slow + Sunder do not tint the hero (shader flash %s)" % [_flash_of(view)], _flash_of(view).w == 0.0)
	var looks: Dictionary = view.status_looks()
	ctx.check("Slow + Sunder show a status loop at the feet (%s)" % [looks], looks["feet"] == "slow")
	var draws: int = view._status_vfx.visible_draws() if view._status_vfx != null else 0
	ctx.check("the status loops stay inside %d draws (%d)" % [MAX_DRAWS_PER_STATUS * 2, draws], draws > 0 and draws <= MAX_DRAWS_PER_STATUS * 2)

	fighter.state = Fighter.State.HITSTUN
	fighter.invulnerable_left = 30
	view.show_state(body, fighter, data)
	ctx.check("hit-stun and immunity do not tint the hero either", _flash_of(view).w == 0.0)
	ctx.check("immunity shows the cyan feet ring with the status ring still on (%s)" % [view.status_looks()],
		view.status_looks()["guard"] == "immune" and view.status_looks()["feet"] == "slow")
	var ring_draws: int = StatusVfx.count_draws(view._status_vfx._live["guard"]["node"])
	ctx.check("the immune ring stays inside %d draws (%d)" % [MAX_DRAWS_PER_STATUS, ring_draws], ring_draws > 0 and ring_draws <= MAX_DRAWS_PER_STATUS)
	fighter.invulnerable_left = 0
	fighter.state = Fighter.State.IDLE
	await ctx.create_timer(StatusVfx.IMMUNE_MIN_SECONDS + 0.1).timeout
	view.show_state(body, fighter, data)
	ctx.check("the immune ring goes away shortly after immunity ends", view.status_looks()["guard"] == "")

	view.flash()
	view.show_state(body, fighter, data)
	var during := _flash_of(view).w
	ctx.check("a hit flash is faint (%.2f)" % during, during > 0.0 and during <= 0.25)
	await ctx.create_timer(FighterView.FLASH_SECONDS + 0.1).timeout
	await ctx.process_frame
	ctx.check("the hit flash clears by itself, without another show_state (%.2f)" % _flash_of(view).w, _flash_of(view).w == 0.0)
	view.flash()
	view.show_state(body, fighter, data)
	ctx.check("a hit right after a flash does not flash again (no stacked whitening)", _flash_of(view).w == 0.0)
	await ctx.create_timer(FighterView.FLASH_GAP + 0.05).timeout
	await ctx.process_frame
	view.flash()
	view.show_state(body, fighter, data)
	ctx.check("a later hit flashes again", _flash_of(view).w > 0.0)

	fighter.effects = {}
	view.show_state(body, fighter, data)
	ctx.check("status loops go away with the statuses", view.status_looks()["feet"] == "" and view.status_looks()["head"] == "")
	view.queue_free()
	await ctx.process_frame
