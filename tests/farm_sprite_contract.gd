extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var visual=load("res://client/farm_crop_sprite.gd")
	for crop in ["carrot","potato","herb"]:
		assert(visual.icon(crop).get_size()==Vector2(128,128))
		for stage in [1,2,3]:
			var plant=visual.new();root.add_child(plant);plant.setup(crop,stage)
			assert(plant.get_child_count()==1)
			var sprite=plant.get_child(0)
			assert(sprite is Sprite3D and sprite.texture.get_size()==Vector2(256,256))
			assert(sprite.billboard==BaseMaterial3D.BILLBOARD_FIXED_Y and sprite.shaded)
			assert(is_zero_approx(sprite.position.y-(240-128)*sprite.pixel_size))
			var image:=Image.load_from_file("res://art/props/farm_crops/%s_stage_%d.png"%[crop,stage])
			assert(image.get_pixel(0,0).a==0 and image.get_pixel(255,255).a==0)
			plant.free()
	assert(visual.texture("invented",1)==null and visual.texture("carrot",0)==null)
	print("FARM SPRITES PASS: nine textures, three icons, shared root, upright lit billboards, transparent corners")
	quit()
