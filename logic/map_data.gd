extends RefCounted
## A stage described as plain data (loaded from data/maps/*.json by map_loader.gd).
## The same data feeds the simulation (solids, bounds, spawn) and the client (materials, camera zones).
## EXTENDING: add a field here and a line in map_loader.gd; old map files keep working as long as
## the new field is optional.

var id := ""
var display_name := ""
var modes: Array[String] = []  ## which game modes may use this map: "pve", "pvp"
var half_width := 14.0
var half_depth := 2.5
var spawn := Vector3.ZERO
var solids: Array[Dictionary] = []  ## {"box": AABB, "material": String}
var camera_zones: Array[Dictionary] = []  ## {"box": AABB, "camera": Dictionary, "lock": bool}
var enemy_spawns: Array[Dictionary] = []  ## {"type": String (an enemy id from combat.json), "level": int (1 = base strength), "position": Vector3}
var rest_points: Array[Dictionary] = []  ## {"id": String, "position": Vector3, "radius": float}: where the player may rest, re-organise the bag or go back to camp
var props: Array[Dictionary] = []  ## scenery with no collision: {"kind": String, "position": Vector3, "scale": float, "yaw": float, "count": int, "radius": float}
var camera_style := "side"  ## "side" (a lane seen from the side) or "top_down" (a wide arena seen from above)
var atmosphere := "golden"  ## the mood of the stage: "golden" (warm, low sun) or "ink" (soft, misty, painterly)
var kind := "fight"  ## "fight" (monsters; the stage is cleared when they are all down) or "rest" (a safe camp: no monsters)
var art_scene := ""  ## optional res:// path of a ready-made scene (a .glb) shown as the stage's scenery; colliders still come from `solids`
var art_mood := ""  ## optional lighting mood for the art scene: "" (the atmosphere's own), "night" or "camp" (client/stage_props.gd)
var exit_portals: Array[Vector3] = []  ## where the end-of-stage portals stand (default: two spots north of the centre, from the bounds)
var campfire := Vector3.ZERO  ## the camp's fire (rest maps only; see has_campfire)
var has_campfire := false
var errors: Array[String] = []  ## filled by the loader; empty means the map is valid


func is_valid() -> bool:
	return errors.is_empty()


## Optional explicit party spawn positions; absent maps use deterministic collision-safe offsets.
var player_spawns: Array[Vector3] = []
