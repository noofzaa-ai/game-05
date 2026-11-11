extends RefCounted
## The static part of a stage as the simulation sees it: solid boxes and the walkable limits.
## Built from map data; knows nothing about how the stage looks.
## EXTENDING: add more static rules here (hazards, spawn points, trigger volumes).

var solids: Array[AABB] = []
var half_width := 14.0  ## the player may not leave x in [-half_width, half_width]
var half_depth := 2.5  ## the player may not leave z in [-half_depth, half_depth]


func add_solid(box: AABB) -> void:
	solids.append(box)
