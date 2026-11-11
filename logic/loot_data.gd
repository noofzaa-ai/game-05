extends RefCounted
## What monsters drop, loaded from data/loot/loot.json by loot_data_loader.gd.
## EXTENDING: new drop kinds are a new key in a drop entry (read in loot.gd) and in the loader.

var gold_per_level := 0.0  ## gold grows by this fraction for each monster level above 1
var tier_weights: Array[Dictionary] = []  ## {"min_level": int, "weights": Array[float]} sorted by min_level
var tables: Dictionary = {}  ## table id -> {"gold": Vector2i, "drops": [{"chance", "material"/"item", "count": Vector2i}]}
var by_enemy: Dictionary = {}  ## enemy type id -> table id
var errors: Array[String] = []  ## filled by the loader; empty means the data is valid


func is_valid() -> bool:
	return errors.is_empty()


## The tier weights that apply to a monster of `level`: the last bracket whose min_level it reaches.
func weights_for_level(level: int) -> Array:
	var chosen: Array = tier_weights[0]["weights"] if not tier_weights.is_empty() else []
	for bracket in tier_weights:
		if level >= int(bracket["min_level"]):
			chosen = bracket["weights"]
	return chosen
