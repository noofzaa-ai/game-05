class_name ZorxTreeNodeData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var links: Array[String] = []
@export var requires_all: Array[String] = []
@export var is_start: bool = false
@export var is_hybrid: bool = false
@export var mods: Array[ZorxStatMod] = []
@export var event_id: String = ""


@export var position: Vector2 = Vector2.ZERO
@export var arm: String = ""
@export var tier: String = "minor"
@export var runtime_supported: bool = true
