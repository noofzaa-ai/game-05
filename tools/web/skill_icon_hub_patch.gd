extends "res://client/hub_skill_baseline.gd"
## Release overlay: preserve the deployed hub implementation; change only Skill button art.
func _build_menu()->void:
 super._build_menu()
 var button:Button=get("_skill_button")
 assert(button!=null,"Deployed hub must provide Skill menu button")
 preload("res://client/skill_menu_icon.gd").apply(button)
