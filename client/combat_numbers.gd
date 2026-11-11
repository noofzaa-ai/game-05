extends Node2D
## One CanvasItem, one atlas, fixed slots. Presentation only; never changes combat.
const ATLAS = preload("res://art/ui/combat_numbers/digits.png")
const CHARS := "0123456789+."
const CAP := 64
const LIFE := 0.9
var slots: Array = []
var advances: Array = []
var sequence := 0

func _ready() -> void:
	advances = JSON.parse_string(FileAccess.get_file_as_string("res://art/ui/combat_numbers/digits.json")).advances
	for i in range(CAP): slots.append({"age":LIFE})
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func show_amount(at: Vector3, amount: int, kind: int = 0) -> void:
	if amount <= 0: return
	var selected := 0
	var oldest := -1.0
	for i in range(slots.size()):
		if slots[i].age >= LIFE: selected=i;break
		if slots[i].age > oldest: oldest=slots[i].age;selected=i
	for slot in slots:
		if slot.age < LIFE and slot.at.distance_squared_to(at+Vector3(0,2.45,0))<0.8:
			slot.push=minf(slot.push+14.0,64.0)
	sequence+=1
	slots[selected]={"age":0.0,"at":at+Vector3(0,2.45,0),"text":("+" if kind==2 else "")+str(amount),
		"kind":clampi(kind,0,3),"push":0.0,"pushed":0.0,"scatter":float((sequence*17)%21-10)}
	queue_redraw()

func _process(delta: float) -> void:
	var changed := false
	for slot in slots:
		if slot.age >= LIFE: continue
		slot.age+=delta
		slot.pushed=move_toward(slot.pushed,slot.push,delta*140.0)
		changed=true
	if changed: queue_redraw()

func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var responsive := clampf(get_viewport_rect().size.y/720.0,0.7,1.25)
	for slot in slots:
		var age: float=slot.age
		if age >= LIFE or camera.is_position_behind(slot.at): continue
		var point := camera.unproject_position(slot.at)
		point+=Vector2(slot.scatter,-age*48.0-slot.pushed)*responsive
		var pop := lerpf(0.65,1.22,age/0.07) if age<0.07 else lerpf(1.22,1.0,clampf((age-0.07)/0.11,0,1))
		var scale_factor: float=[0.64,0.80,0.58,0.64][slot.kind]*responsive*pop
		var opacity := 1.0-smoothstep(0.48,LIFE,age)
		var width := 0.0
		for ch in slot.text:
			var index := CHARS.find(ch)
			if index>=0: width+=float(advances[index])
		draw_set_transform(point,0,Vector2.ONE*scale_factor)
		var x := -width*0.5
		for ch in slot.text:
			var index := CHARS.find(ch)
			if index<0: continue
			draw_texture_rect_region(ATLAS,Rect2(x-12,-76,80,112),Rect2(index*80,slot.kind*112,80,112),Color(1,1,1,opacity))
			x+=float(advances[index])
	draw_set_transform(Vector2.ZERO)
