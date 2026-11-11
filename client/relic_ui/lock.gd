extends Control
func _ready():mouse_filter=Control.MOUSE_FILTER_IGNORE;resized.connect(queue_redraw)
func _draw():
	var s=minf(size.x,size.y);var c=size*.5;var ink=Color("77807a")
	draw_arc(c-Vector2(0,s*.12),s*.17,PI,TAU,16,ink,s*.075,true)
	draw_style_box(style(),Rect2(c+Vector2(-s*.26,-s*.08),Vector2(s*.52,s*.38)))
	draw_circle(c+Vector2(0,s*.06),s*.05,Color("25302d"));draw_line(c+Vector2(0,s*.06),c+Vector2(0,s*.17),Color("25302d"),s*.035,true)
func style()->StyleBoxFlat:
	var b=StyleBoxFlat.new();b.bg_color=Color("77807a");b.set_corner_radius_all(3);return b
