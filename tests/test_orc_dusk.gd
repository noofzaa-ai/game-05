extends RefCounted
## Orc camp dusk holds (tech-artist 2026-11-26, Boss: "changed to dusk, but it went dark again" on the web/phone).
## The night base (arena_props.set_night_sky) + client/fight_light.gd + every graphics preset's environment pass
## (client/graphics_runtime.gd) must end on the dusk sky / warm low sun, and bright enough that the phone path
## (lite style, no shadows, no glow) does not read as night.
const ArenaProps := preload("res://client/arena_props.gd")
const FightLight := preload("res://client/fight_light.gd")
const Options := preload("res://client/graphics_options.gd")
const Runtime := preload("res://client/graphics_runtime.gd")


func run(ctx) -> void:
	var z := FightLight.zone("orc_camp_night")
	ctx.check("orc dusk: zone has a 3-colour sky", z.get("sky") is Array and z["sky"].size() == 3)
	ctx.check("orc dusk: sun bright enough for the phone path (>= 1.3)", float(z.get("sun_energy", 0)) >= 1.3)
	ctx.check("orc dusk: exposure >= 1.15", float(z.get("exposure", 0)) >= 1.15)
	for device in ["phone", "desktop"]:
		Options.force_device(device)
		var root := Node3D.new()
		var holder := WorldEnvironment.new()
		holder.environment = Environment.new()
		root.add_child(holder)
		var sun := DirectionalLight3D.new()
		root.add_child(sun)
		ArenaProps.set_night_sky(root)
		FightLight.apply(root, "orc_camp_night", device == "phone")
		var runtime: Node = Runtime.new()
		runtime._register(weakref(holder))  # the graphics preset pass that runs when the stage enters the tree
		runtime._register(weakref(sun))
		var env := holder.environment
		var tag := "orc dusk (%s): " % device
		ctx.check(tag + "procedural dusk sky kept", env.background_mode == Environment.BG_SKY and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial)
		ctx.check(tag + "drawn style keeps the sky (meta)", env.has_meta(FightLight.KEEP_SKY_META))
		var want := z.duplicate()
		if device == "phone": want.merge(z["phone"], true)
		ctx.check(tag + "sun is the warm dusk sun", sun.light_color.is_equal_approx(Color.html(str(z["sun_color"]))) and is_equal_approx(sun.light_energy, float(want["sun_energy"])))
		ctx.check(tag + "exposure from the zone (phone block on a phone)", is_equal_approx(env.tonemap_exposure, float(want["exposure"])))
		ctx.check(tag + "ambient is the dusk tint", env.ambient_light_color.is_equal_approx(Color.html(str(z["ambient_color"]))))
		ctx.check(tag + "ambient brighter than the night base", env.ambient_light_energy > ArenaProps.NIGHT_AMBIENT_ENERGY)
		runtime.free()
		root.free()
	var p: Dictionary = z.get("phone", {})
	ctx.check("orc dusk: phone block lifts exposure / ambient / sun over desktop", p.size() > 0 and float(p.get("exposure", 0)) > float(z["exposure"]) and float(p.get("ambient", 0)) > float(z["ambient"]) and float(p.get("sun_energy", 0)) > float(z["sun_energy"]))
	Options.force_device("phone")
	ctx.check("orc dusk: a phone takes the lifted path", FightLight.is_lifted())
	Options.force_device("")
