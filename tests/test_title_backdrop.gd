extends RefCounted
## The title screen's 3D backdrop (client/title_backdrop.gd) builds itself, brings its camera, stays
## within its draw budget in node terms, animates, and its low-quality switch trims it.

const TitleBackdrop := preload("res://client/title_backdrop.gd")


func run(ctx) -> void:
	var backdrop: Node3D = TitleBackdrop.new()
	ctx.root.add_child(backdrop)
	for i in 3:
		await ctx.process_frame
	var camera: Camera3D = backdrop.camera()
	ctx.check("backdrop: has its own current camera", camera != null and camera.current)
	ctx.check("backdrop: brings a WorldEnvironment", not backdrop.find_children("*", "WorldEnvironment", false, false).is_empty())
	var lights := backdrop.find_children("*", "Light3D", true, false)
	var shadowed := lights.filter(func(light: Light3D) -> bool: return light.shadow_enabled)
	ctx.check("backdrop: few lights and no shadows (%d lights)" % lights.size(), lights.size() <= 2 and shadowed.is_empty())
	var multimeshes := backdrop.find_children("*", "MultiMeshInstance3D", true, false)
	ctx.check("backdrop: the verdant_reach props are placed as MultiMeshes (%d)" % multimeshes.size(), multimeshes.size() >= 8)
	var particles := backdrop.find_children("*", "CPUParticles3D", true, false)
	ctx.check("backdrop: fire, embers, smoke, fireflies and motes emit", particles.size() == 5 and particles.all(func(p: CPUParticles3D) -> bool: return p.emitting))
	var before := camera.global_position
	for i in 20:
		await ctx.process_frame
	ctx.check("backdrop: the camera drifts", camera.global_position.distance_to(before) > 0.0001)
	var total_high := 0
	for p in particles:
		total_high += (p as CPUParticles3D).amount
	backdrop.set_quality(true)
	var total_low := 0
	for p in particles:
		total_low += (p as CPUParticles3D).amount
	ctx.check("backdrop: low quality has fewer particles (%d -> %d)" % [total_high, total_low], total_low < total_high and total_low > 0)
	backdrop.set_quality(false)
	ctx.check("backdrop: high quality restores them", particles.reduce(func(sum: int, p: CPUParticles3D) -> int: return sum + p.amount, 0) == total_high)
	backdrop.queue_free()
	await ctx.process_frame
