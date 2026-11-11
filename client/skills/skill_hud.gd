extends CanvasLayer
## Four touch/keyboard slots. Display only: readiness is decided by the server.
const Ink := preload("res://client/ink_ui.gd")
var _row: Control
var _buttons: Array[Button] = []
var _layout_key := ""
var _ids: Array[String] = ["","","",""]
func _ready() -> void:
 layer=26
 var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.theme=Ink.make_theme();add_child(root)
 _row=Control.new();_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(_row)
 for slot in range(4):
  var button:=preload("res://client/skills/round_skill_button.gd").new();button.slot_number=slot+1;button.custom_minimum_size=Vector2(62,62);_row.add_child(button);_buttons.append(button)
  button.pressed.connect(func():
   if is_instance_valid(GameState.mobile_controls):GameState.mobile_controls.queue_skill(slot))
 get_viewport().size_changed.connect(_fit);_fit()
func _fit() -> void:
 var size:=get_viewport().get_visible_rect().size
 var controls=GameState.mobile_controls
 if is_instance_valid(controls) and controls.enabled:
  var key:=str(size)+str(controls.combat_button_rect("light"))
  if key==_layout_key:return
  _layout_key=key
  for index in range(4):
   var rect:Rect2=controls.skill_button_rect(index)
   _buttons[index].custom_minimum_size=Vector2.ZERO
   _buttons[index].position=rect.position
   _buttons[index].size=rect.size
   _buttons[index].queue_redraw()
  _row.size=size
  return
 var attack:=Rect2()
 var upper:=size.y-160.0
 var key:=str(size)+"desktop"
 if key==_layout_key:return
 _layout_key=key
 var diameter:=maxf(56,attack.size.x*.55) if attack.has_area() else 68.0
 diameter=minf(diameter,size.y*.18)
 var gap:=diameter*.16
 var width:=4*diameter+3*gap
 var left:=maxf(12,size.x-width-24)
 var baseline:=maxf(64,upper-diameter-16)
 for index in range(4):
  var button: Button=_buttons[index]
  button.custom_minimum_size=Vector2.ZERO
  button.size=Vector2.ONE*diameter
  button.position=Vector2(left+index*(diameter+gap),baseline-(diameter*.25 if index in [1,2] else 0.0))
  button.queue_redraw()
 _row.size=size
func update_from(fighter) -> void:
 _fit()
 var slots: Array=fighter.skill_view.get("slots",[])
 _row.visible=slots.size()==4 and fighter.is_alive()
 if slots.size()!=4:return
 for index in range(4):
  var data: Dictionary=slots[index];var button: Button=_buttons[index]
  if _ids[index]!=data.skill:
   _ids[index]=data.skill
   var path: String="res://art/ui/skills/128/skills/"+data.skill+".png"
   button.skill_icon=load(path) if ResourceLoader.exists(path) else null
   var skill: ZorxSkillData=load("res://data/skill_system/skills/"+data.skill+".tres")
   button.tooltip_text=skill.display_name
  button.cooldown=float(data.left)
  button.affordable=fighter.energy>=float(data.cost)
  button.queue_redraw()
