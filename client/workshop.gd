extends Node3D
## Prepared visual prefab only. Camp level/economy authority remains on the server.
const WorkshopNpc := preload("res://client/workshop_npc.gd")
@export_enum("refine", "upgrade") var workshop_type := "refine"
@export_range(1, 3) var visual_level := 1
@export var spawn_npc := true

func _ready() -> void:
	var path := "res://art/props/camp_modular/workshops/%s_lv%d.glb" % [workshop_type, visual_level]
	var packed := load(path) as PackedScene
	if packed == null: return
	var props := packed.instantiate() as Node3D
	props.name = "WorkshopProps"
	add_child(props)
	if spawn_npc:
		var npc := WorkshopNpc.new()
		npc.name = "WorkshopNpc"
		npc.workshop_type = workshop_type
		npc.position = Vector3(0.0, 0.0, 3.0)
		add_child(npc)
