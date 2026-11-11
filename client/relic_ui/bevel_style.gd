extends StyleBox
## Polygonal bevels: broad metal lip, lit upper facets, dark lower facets, inset face.
@export var tone=Color("1d3232")
@export var metal=Color("59615b")
@export var depth=5.0
@export var cut=12.0
@export var inset=false
@export var round_shape=false
@export var glow=false
@export var faceted_gold=false
@export var crest=false
func _init()->void:
	set_content_margin_all(8)
func polygon(rect:Rect2,corner:float)->PackedVector2Array:
	if round_shape:
		var points=PackedVector2Array()
		for i in 32:points.append(rect.get_center()+Vector2(cos(i*TAU/32),sin(i*TAU/32))*rect.size*.5)
		return points
	var p=rect.position;var e=rect.end;var c=minf(corner,minf(rect.size.x,rect.size.y)*.3)
	if faceted_gold:
		return PackedVector2Array([p+Vector2(c,0),Vector2(e.x-c,p.y),Vector2(e.x,p.y+c),e-Vector2(0,c),e-Vector2(c,0),Vector2(p.x+c,e.y),Vector2(p.x,e.y-c),p+Vector2(0,c)])
	var points=PackedVector2Array()
	for corner_index in 4:
		var center=[Vector2(e.x-c,p.y+c),e-Vector2(c,c),Vector2(p.x+c,e.y-c),p+Vector2(c,c)][corner_index]
		for segment in 5:
			var angle=(-PI*.5+corner_index*PI*.5)+segment*PI*.125
			points.append(center+Vector2(cos(angle),sin(angle))*c)
	return points

func fill(rid:RID,points:PackedVector2Array,colour:Color)->void:
	RenderingServer.canvas_item_add_polygon(rid,points,PackedColorArray([colour]))
func gold_edge(rid:RID,a:Vector2,b:Vector2,c:Vector2,d:Vector2,light:float,index:int)->void:
	# Irregular planar faces along the metal itself, not a uniform stroked outline.
	var count=maxi(1,ceili(a.distance_to(b)/75.0))
	for part in count:
		var t0=float(part)/count;var t1=float(part+1)/count
		var p=a.lerp(b,t0);var q=a.lerp(b,t1);var r=d.lerp(c,t1);var s=d.lerp(c,t0)
		var variation=sin((part+index*13)*2.73)*.10
		var colour=metal.lightened(maxf(0,light+variation)) if light+variation>0 else metal.darkened(-light-variation)
		fill(rid,PackedVector2Array([p,q,s]),colour)
		fill(rid,PackedVector2Array([q,r,s]),colour.darkened(.07+float((part+index)%3)*.025))
		# Occasional short engraving/seam strokes, never a repeated ornamental border.
		if (part+index*3)%5==2 and count>1:
			var at=p.lerp(q,.55);var inside=s.lerp(r,.66)
			RenderingServer.canvas_item_add_line(rid,at.lerp(inside,.15),at.lerp(inside,.73),Color("e2c283"),1,true)
func _draw(rid:RID,rect:Rect2)->void:
	if tone.a<.01:
		var focus=polygon(rect.grow(-2),cut);RenderingServer.canvas_item_add_polyline(rid,focus+PackedVector2Array([focus[0]]),PackedColorArray([metal]),2,true);return
	if glow:
		for n in [5,3,1]:fill(rid,polygon(rect.grow(n),cut+n),Color(metal,.035))
	fill(rid,polygon(Rect2(rect.position+Vector2(0,4),rect.size),cut),Color(0,0,0,.5))
	fill(rid,polygon(rect,cut),Color("0c1517"))
	var outer=polygon(rect.grow(-1),cut-1);var inner=polygon(rect.grow(-depth),maxf(2,cut-depth*.5))
	for i in outer.size():
		var next=(i+1)%outer.size();var direction=((outer[i]+outer[next])*.5-rect.get_center()).normalized()
		var light=clampf(-direction.y*.35-direction.x*.12,-.55,.55)
		if inset:light=-light
		if faceted_gold:gold_edge(rid,outer[i],outer[next],inner[next],inner[i],light,i)
		else:fill(rid,PackedVector2Array([outer[i],outer[next],inner[next],inner[i]]),metal.lightened(light) if light>0 else metal.darkened(-light))
	fill(rid,inner,tone)
	# Interpolated face lighting, with a quiet warm upper edge rather than flat web colour.
	var center=rect.get_center();var points=PackedVector2Array([center]);var colours=PackedColorArray([tone])
	for p in inner:
		points.append(p);colours.append(tone.lightened(.025) if p.y<center.y else tone.darkened(.13))
	points.append(inner[0]);colours.append(colours[1])
	var indices=PackedInt32Array()
	for i in inner.size():indices.append_array([0,i+1,i+2])
	RenderingServer.canvas_item_add_triangle_array(rid,indices,points,colours)
	RenderingServer.canvas_item_add_polyline(rid,inner+PackedVector2Array([inner[0]]),PackedColorArray([Color(metal.lightened(.15),.45)]),1,true)
	if crest:
		var center_top=Vector2(rect.get_center().x,rect.position.y+depth*.5)
		# The seal occupies the metal joint, so the broad gold lip cannot cross its face.
		fill(rid,PackedVector2Array([center_top+Vector2(-20,-5),center_top+Vector2(20,-5),center_top+Vector2(20,5),center_top+Vector2(-20,5)]),tone)
		var ornament=preload("res://client/ink_ui.gd").EngravedBox.new()
		ornament.line=Color("e4bf68");ornament.fill=tone
		ornament._crest(rid,center_top,minf(rect.size.x*.22,240),1.0)
