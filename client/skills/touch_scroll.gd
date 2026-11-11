extends ScrollContainer
## A swipe may start over a button. Activate that button only after a stationary release.
var _finger: int=-1
var _from:=Vector2.ZERO
var _last:=Vector2.ZERO
var _moved:=false
var _button: BaseButton
var _last_touch_ms: int=-1000

func _input(event: InputEvent) -> void:
 if not is_visible_in_tree():_cancel();return
 if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION:
  if Time.get_ticks_msec()-_last_touch_ms<250 and get_global_rect().has_point(event.position):
   get_viewport().set_input_as_handled()
  return
 if event is InputEventScreenTouch:
  if event.pressed and not event.canceled and _finger<0:
   if not get_global_rect().has_point(event.position):return
   if get_v_scroll_bar().get_global_rect().has_point(event.position):return
   _finger=event.index;_from=event.position;_last=_from;_moved=false
   _button=_button_at(self,event.position)
  elif event.index==_finger:
   var button:=_button
   var tap: bool=not event.canceled and not _moved
   _cancel()
   if tap and is_instance_valid(button) and not button.disabled and button.get_global_rect().has_point(event.position):
    if button is OptionButton:button.show_popup()
    else:
     if button.toggle_mode:button.button_pressed=not button.button_pressed
     button.pressed.emit()
  else:return
  _last_touch_ms=Time.get_ticks_msec();get_viewport().set_input_as_handled()
 elif event is InputEventScreenDrag and event.index==_finger:
  if event.position.distance_to(_from)>10:_moved=true
  if _moved:scroll_vertical+=roundi((_last.y-event.position.y)/maxf(get_global_transform_with_canvas().get_scale().y,.01))
  _last=event.position;_last_touch_ms=Time.get_ticks_msec();get_viewport().set_input_as_handled()

func _button_at(node: Node,point: Vector2) -> BaseButton:
 for child in node.get_children():
  if child is Control and not child.is_visible_in_tree():continue
  var found:=_button_at(child,point)
  if found!=null:return found
 if node is BaseButton and node.get_global_rect().has_point(point):return node
 return null

func _cancel()->void:_finger=-1;_button=null;_moved=false
func _notification(what: int)->void:
 if what==NOTIFICATION_APPLICATION_FOCUS_OUT:_cancel()
