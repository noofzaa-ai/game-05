extends "res://client/mobile_training_baseline.gd"
const ArcLayout=preload("res://client/mobile_combat_layout.gd")
func _update_context() -> void:
 if _root == null:
  return
 enabled = force_mobile or device_is_mobile()
 var size := get_viewport().get_visible_rect().size
 var portrait := enabled and needs_rotation(size)
 _gate.visible = portrait
 _root.visible = enabled
 if portrait and not get_tree().paused:
  get_tree().paused = true
  _owns_pause = true
 elif not portrait and _owns_pause:
  get_tree().paused = false
  _owns_pause = false
 var scene := get_tree().current_scene
 var scene_id := scene.get_instance_id() if is_instance_valid(scene) else 0
 var combat: bool = enabled and not portrait and not get_tree().paused and is_instance_valid(scene) and scene.get_script() != null and scene.get_script().resource_path == "res://client/stage_view.gd"
 if combat:
  combat = scene.get("_screen") == null and scene.get("_session") != null
 var training:bool=is_instance_valid(scene) and scene.has_method("training_combat_active") and scene.training_combat_active()
 if training:combat=enabled and not portrait and not get_tree().paused
 if portrait and is_instance_valid(scene) and scene.get_script() != null and scene.get_script().resource_path == "res://client/hub.gd":
  var hub_stick = scene.get("_touch")
  if is_instance_valid(hub_stick):
   hub_stick.release()
 if combat != _combat or scene_id != _scene_id or size != _size:
  release()
 _combat = combat
 _scene_id = scene_id
 if size != _size:
  _size = size
  _layout()
 for child in _root.get_children():
  if child != _gate:
   child.visible = _combat
 if _combat:
  if training:
   _feedback={}
   for action in ACTIONS:
    _root.get_node(action).visible=not action in ["special","ultimate"]
    _root.get_node(action).queue_redraw()
   _use.hide();_retry.hide();_back.hide()
   return
  var hud = scene.get("_hud")
  _feedback = hud.mobile_feedback() if is_instance_valid(hud) else {}
  for action in ACTIONS:
   _root.get_node(action).visible = not (preload("res://logic/skill_build.gd").enabled() and action in ["special","ultimate"]) and not (scene.get("_session").has_method("is_lobby") and scene.get("_session").is_lobby())
   _root.get_node(action).queue_redraw()
  _use.visible = bool(scene.get("_near_campfire")) or not str(scene.get("_near_rest")).is_empty()
  _retry.visible = scene.get("_journey") == null and not str(scene.get("_result")).is_empty()
  _back.visible = scene.get("_journey") == null or bool(scene.get("_camp_mode")) or not str(scene.get("_result")).is_empty()

func _layout() -> void:
 _sync_web_geometry()
 # Reference: i14 Pro Max capture, ~370 CSS px of usable landscape game height.
 var density := _screen_unit()
 var fit := minf(1.0, minf(_size.y / density / 370.0, _size.x / density / 820.0))
 _reach = 96.0 * density * fit
 _stick.position = Vector2.ZERO
 _stick.size = Vector2(_size.x * 0.45, _size.y)
 var regions: Dictionary = ArcLayout.regions(_size,density*fit,44.0*density)
 for action in ACTIONS:
  var rect: Rect2 = regions[action]
  _buttons[action] = Rect2() if preload("res://logic/skill_build.gd").enabled() and action in ["special","ultimate"] else rect
  var control: Control = _root.get_node(action)
  control.position = rect.position
  control.size = rect.size
  control.queue_redraw()
 _stick.queue_redraw()
 var screen_unit := density * fit
 for i in 3:
  var button: Button = [_back, _use, _retry][i]
  button.position = Vector2(16 + i * 96 * screen_unit, 100)
  button.custom_minimum_size = Vector2.ZERO
  button.size = Vector2(88, 40) * screen_unit
  InkUi.text_size(button, int(14 * screen_unit))

func skill_button_rect(slot:int) -> Rect2:
 if slot<0 or slot>3:return Rect2()
 var density:=_screen_unit()
 var fit:=minf(1.0,minf(_size.y/density/370.0,_size.x/density/820.0))
 return ArcLayout.regions(_size,density*fit,44.0*density).skills[slot]
