class_name ZorxSkillData
extends Resource

@export var id: String = ""
@export var display_name: String = ""  ## English, shown in game (plain ASCII: the web font)
@export var display_name_th: String = ""  ## the Thai name, kept
@export var tags: Array[String] = []
@export var slots: Array[String] = ["shape", "effect"]
@export var built_in_statuses: Array[String] = []
@export var authored_radius_m: float = 1.498714
@export var base_stats: Dictionary = {}
@export var behavior: String = "area"
@export var number: int = 5
@export var color: Color = Color(1.0, 0.4, 0.1)

