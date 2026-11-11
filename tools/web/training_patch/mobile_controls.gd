extends "res://client/mobile_training_baseline.gd"
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
