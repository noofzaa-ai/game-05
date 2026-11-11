extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var script=preload("res://client/loot_popups.gd")
	var popup=script.new()
	root.add_child(popup)
	assert(is_equal_approx(script.responsive_scale(Vector2(844,390)),0.9))
	assert(is_equal_approx(script.responsive_scale(Vector2(1920,1080)),1.15))
	var icon=preload("res://art/ui/materials/ore.png")
	for i in range(100): popup.show_pickup(Vector3.ZERO,"เกราะอัศวิน Rare Sword ×1",Color.SKY_BLUE,icon,i%5)
	assert(popup.slots.size()==20 and popup.get_child_count()==20)
	for slot in popup.slots:
		assert(slot.icon.texture==icon and slot.width<=248)
		assert(slot.label.get_theme_font_size("font_size")==18)
	popup._process(2.0)
	for slot in popup.slots: assert(not slot.row.visible)
	print("LOOT POPUP PASS:100pickups/20fixed rows, existingicons, Thai fallback, PC/mobile landscape scales,expiry")
	quit()
