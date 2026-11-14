extends SceneTree
## Material audit of the daiyooo VFX assets (class skills + status loops): per effect, the kinds of materials it
## uses (shading, transparency, blend, emission, texture, billboard). For the ink VFX treatment (2026-11-15).
##   godot --headless --path . --script res://tools/perf/vfx_material_audit.gd

func _initialize() -> void:
	for root_dir in ["res://art/vfx/class_skills/", "res://art/vfx/status/"]:
		for sid in DirAccess.get_directories_at(root_dir):
			var path: String = root_dir + sid + "/effect.tscn"
			if not ResourceLoader.exists(path):
				continue
			var inst: Node = load(path).instantiate()
			var kinds := {}
			var mats := {}
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				for s in mi.mesh.get_surface_count():
					var m = mi.get_active_material(s)
					if m == null or mats.has(m):
						continue
					mats[m] = true
					var k := ""
					if m is BaseMaterial3D:
						var b := m as BaseMaterial3D
						k = "%s shade=%d transp=%d blend=%d emis=%s tex=%s vcol=%s bb=%d cull=%d a=%.2f col=%s" % [b.get_class(), b.shading_mode, b.transparency, b.blend_mode, b.emission_enabled, b.albedo_texture != null, b.vertex_color_use_as_albedo, b.billboard_mode, b.cull_mode, b.albedo_color.a, b.albedo_color.to_html(false)]
					else:
						k = m.get_class()
					kinds[k] = int(kinds.get(k, 0)) + 1
			print("AUDIT %s/%s mats=%d" % [root_dir.get_slice("/", 4), sid, mats.size()])
			for k in kinds:
				print("   %3d x %s" % [kinds[k], k])
			inst.free()
	quit()
