extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var stage = load("res://client/stage_view.gd")
	assert(stage.damage_style(9999,false,false).color==Color.WHITE)
	assert(stage.damage_style(10,true,false).color==Color("ff8b18"))
	var numbers=preload("res://client/combat_numbers.gd").new()
	root.add_child(numbers)
	var stage_node = stage.new()
	stage_node._combat_numbers = numbers
	stage_node._spawn_damage_number(Vector3.ZERO,42,true,false,true)
	assert(numbers.slots[0].kind==3) # Incoming critical stays red, never orange.
	stage_node.free()
	for i in range(200):numbers.show_amount(Vector3.ZERO,i+1,i%4)
	assert(numbers.slots.size()==64)
	assert(numbers.get_child_count()==0)
	var kinds:Dictionary={}
	for slot in numbers.slots:
		kinds[slot.kind]=true
		assert(slot.push<=64)
	assert(kinds.size()==4)
	for i in range(60):numbers._process(1.0/60)
	for slot in numbers.slots:assert(slot.age>=numbers.LIFE)
	print("COMBAT NUMBER PRESENTATION PASS: palette,200hits/64fixed slots,expiry,no child nodes")
	quit()
