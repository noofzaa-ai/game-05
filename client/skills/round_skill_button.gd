extends Button
## Circular mobile control, independent of the panel theme's clipped-corner styles.
const Ink := preload("res://client/ink_ui.gd")
var skill_icon: Texture2D
var slot_number := 1
var cooldown := 0.0
var affordable := true

func _ready() -> void:
 text=""
 for state in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
  add_theme_stylebox_override(state,StyleBoxEmpty.new())
 resized.connect(queue_redraw)
 button_down.connect(queue_redraw)
 button_up.connect(queue_redraw)
 mouse_entered.connect(queue_redraw)
 mouse_exited.connect(queue_redraw)

func _draw() -> void:
 var center:=size*.5
 var radius:=minf(size.x,size.y)*.5-3
 var gold:=Ink.GOLD
 var active:=cooldown<=0 and affordable
 var fill:=Ink.INK.lightened(.13 if button_pressed else .03)
 draw_circle(center,radius,fill)
 draw_arc(center,radius,0,TAU,96,gold,1.8,true)
 draw_arc(center,radius-4,0,TAU,96,Color(gold,.5),1,true)
 if skill_icon!=null:
  var edge:=radius*1.27
  draw_texture_rect(skill_icon,Rect2(center-Vector2.ONE*edge*.5,Vector2.ONE*edge),false,Color.WHITE if active else Color(.48,.48,.48))
 if cooldown>0:
  draw_circle(center,radius-5,Color(0,0,0,.48))
  var label: String="%.1f"%cooldown
  var font:=Ink.font()
  var font_size:=maxi(16,int(radius*.62))
  var width:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
  draw_string(font,center+Vector2(-width*.5,font_size*.34),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Ink.PAPER)
 else:
  var font:=Ink.font()
  var font_size:=maxi(10,int(radius*.36))
  draw_string(font,center+Vector2(radius*.38,radius*.63),str(slot_number),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Ink.PAPER)
 if has_focus():draw_arc(center,radius+2,0,TAU,96,Ink.PAPER,1,true)

func _has_point(point:Vector2) -> bool:
 return (point-size*.5).length()<=minf(size.x,size.y)*.5
