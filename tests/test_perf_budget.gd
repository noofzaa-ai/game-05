extends RefCounted
## Fight performance budget, the headless half (tech-artist 2026-11-27, Boss: "the fps drops" keeps coming back).
## data/perf/budgets.json holds the numbers; the windowed half (boss wave per zone, draw calls / primitives / CPU)
## is client/perf/fight_bench.tscn -- --gate, run by tools/perf/perf_gate.ps1 before a web deploy.
## Here: every monster VFX bundle, as client/monster_vfx.gd thins it, fits its draw budget on desktop and phone (one
## mesh per live particle phase = one draw); the budget rows exist for every wave journey; the Windows-web render
## path (Options.scale_penalty: full-size 3D + FXAA, the ink screen pass kept) is chosen only for ANGLE on Direct3D.

const Options := preload("res://client/graphics_options.gd")
const MonsterVfx := preload("res://client/monster_vfx.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")
const BUDGETS := "res://data/perf/budgets.json"


func run(ctx) -> void:
	var budgets = JSON.parse_string(FileAccess.get_file_as_string(BUDGETS))
	ctx.check("budgets.json loads", budgets is Dictionary)
	if not budgets is Dictionary:
		return
	for journey in ["goblin_waves", "mummy_waves", "orc_waves"]:
		var row: Dictionary = budgets["zones"].get(journey, {})
		ctx.check("%s has desktop and phone budget rows" % journey, row.has("desktop") and row.has("phone") and int(row["phone"].get("draw_calls", 0)) > 0)
	_monster_vfx(ctx, budgets)
	_scale_penalty(ctx)


## Draws a bundle can issue at its busiest: every visible particle draws one phase mesh at a time (the slimmed
## flipbook), so count the visible particle parents (plus single meshes that are not flipbook phases).
static func peak_draws(root: Node) -> int:
	var parents := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var particle: Node = mi.get_parent()
		var hidden := false
		var p: Node = mi
		while p != null and p != root:
			if p is Node3D and not (p as Node3D).visible and p != mi: hidden = true
			p = p.get_parent()
		if not hidden: parents[particle] = true
	return parents.size()


func _monster_vfx(ctx, budgets: Dictionary) -> void:
	var spec := MonsterVfx.load_spec()
	var ids := {}
	for key in spec:
		ids[str(spec[key].get("vfx", ""))] = true
	ctx.check("monster VFX ids found (%d)" % ids.size(), ids.size() >= 5)
	for profile in ["desktop", "phone"]:
		var cap: int = MonsterVfx.PARTICLES_PER_GROUP_PHONE if profile == "phone" else MonsterVfx.PARTICLES_PER_GROUP
		var limit := int(budgets["monster_vfx_draws"][profile])
		for id in ids:
			var path := MonsterVfx.scene_path(str(id))
			if path == "":
				continue
			var inst: Node = (load(path) as PackedScene).instantiate()
			var before := peak_draws(inst)
			for n in MonsterVfx.thinned(inst, cap):
				(n as Node3D).visible = false
			var after := peak_draws(inst)
			ctx.check("monster VFX %s on %s: %d draws at most (budget %d, raw %d)" % [id, profile, after, limit, before], after <= limit)
			inst.free()


func _scale_penalty(ctx) -> void:
	ctx.check("ANGLE on Direct3D 11 is the full-size path", Options.adapter_has_scale_penalty("ANGLE (NVIDIA, NVIDIA GeForce RTX 3070 Ti (0x00002482) Direct3D11 vs_5_0 ps_5_0, D3D11)"))
	ctx.check("ANGLE on OpenGL, Mac Metal and phones are not", not Options.adapter_has_scale_penalty("ANGLE (NVIDIA Corporation, NVIDIA GeForce RTX 3070 Ti/PCIe/SSE2, OpenGL 4.5.0)") \
		and not Options.adapter_has_scale_penalty("ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)") \
		and not Options.adapter_has_scale_penalty("Adreno (TM) 740") and not Options.adapter_has_scale_penalty("Apple GPU"))
	var had := FileAccess.file_exists(Options.PATH)
	Options.force_device("desktop")
	Options.scale_penalty_override = 1
	# (the panel value comes from user://graphics.cfg when one exists on this machine: 0.5 default or whatever a tool saved)
	ctx.check("full-size path: 3D drawn at 1.0 whatever the panel says (%s)" % Options.value("render_scale"), is_equal_approx(float(Options.effective("render_scale")), 1.0) and float(Options.value("render_scale")) < 1.0)
	DrawStyle._override = ""
	DrawStyle._decided = true
	DrawStyle.slow_device = false
	ctx.check("full-size path: the drawn style keeps its screen pass (Boss: the ink look stays on)", DrawStyle.screen_allowed())
	Options.scale_penalty_override = 0
	ctx.check("elsewhere the panel scale is applied as before", is_equal_approx(float(Options.effective("render_scale")), float(Options.value("render_scale"))))
	Options.scale_penalty_override = -1
	if not had and FileAccess.file_exists(Options.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	Options.force_device("")
