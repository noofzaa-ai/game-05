extends Node2D
## One CanvasItem, one atlas, fixed slots. Presentation only; never changes combat.
const ATLAS = preload("res://art/ui/combat_numbers/digits.png")
const CHARS := "0123456789+."
const CAP := 64
const LIFE := 0.9
var slots: Array = []
var advances: Array = []
var sequence := 0
## Screen rectangles the numbers must not cover (the HUD's trip line and banners, the squad cards), in
## viewport pixels. The stage refreshes them every frame (hud.gd / squad_panel.gd keep_out_rects()).
var keep_out: Array[Rect2] = []

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
		var scale_factor: float=[0.56,0.76,0.52,0.6][slot.kind]*responsive*pop
		var opacity := 1.0-smoothstep(0.48,LIFE,age)
		var width := 0.0
		for ch in slot.text:
			var index := CHARS.find(ch)
			if index>=0: width+=float(advances[index])
		point+=avoid(Rect2(point-Vector2(width*0.5,76.0)*scale_factor,Vector2(width,112.0)*scale_factor),keep_out,get_viewport_rect().size)
		draw_set_transform(point,0,Vector2.ONE*scale_factor)
		var x := -width*0.5
		for ch in slot.text:
			var index := CHARS.find(ch)
			if index<0: continue
			draw_texture_rect_region(ATLAS,Rect2(x-12,-76,80,112),Rect2(index*80,slot.kind*112,80,112),Color(1,1,1,opacity))
			x+=float(advances[index])
	draw_set_transform(Vector2.ZERO)


## How far a pop-up whose screen box is `box` must move to stay on screen and off every `keep` rectangle
## (the shortest way out of each: down, up or sideways). Vector2.ZERO when it is already clear.
static func avoid(box: Rect2, keep: Array[Rect2], area: Vector2) -> Vector2:
	var shift := Vector2.ZERO
	var moved := Rect2(box.position, box.size)
	shift.x = clampf(moved.position.x, 4.0, maxf(4.0, area.x - moved.size.x - 4.0)) - moved.position.x
	shift.y = clampf(moved.position.y, 4.0, maxf(4.0, area.y - moved.size.y - 4.0)) - moved.position.y
	for i in range(2):  # (a second pass in case leaving one rectangle walked into another)
		for rect in keep:
			moved = Rect2(box.position + shift, box.size)
			if not moved.intersects(rect):
				continue
			var best := Vector2.ZERO
			# The shortest way out that stays on screen: down, up, left or right.
			for option in [Vector2(0.0, rect.end.y - moved.position.y), Vector2(0.0, rect.position.y - moved.end.y), Vector2(rect.position.x - moved.end.x, 0.0), Vector2(rect.end.x - moved.position.x, 0.0)]:
				var landed := Rect2(moved.position + option, moved.size)
				if landed.position.x < 0.0 or landed.position.y < 0.0 or landed.end.x > area.x or landed.end.y > area.y:
					continue
				if best == Vector2.ZERO or option.length() < best.length():
					best = option
			shift += best
	return shift
