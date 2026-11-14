extends Node3D
## Status effects drawn as small looping daiyooo-vfx effects on a fighter (tech-artist 2026-11-14, Boss: statuses
## must never recolour the whole character). Replaces the old full-body status tint: a fighter keeps its own look
## and a status shows as at most TWO small loops, one over the head (stun / sleep) and one at the feet (the
## strongest other status). Display only: it reads fighter.effects and changes nothing in the fight.
## Assets: res://art/vfx/status/<key>/effect.tscn (generated with the daiyooo-vfx MCP, recipes next to them).
## Each instance gets the same draw-call slimming as the class skill effects (ClassSkillVfx.slim_animation):
## only the live lifetime phase of each particle is drawn. Budget: <= 40 draws per instance (docs/tech/performance_budget.md).

const ClassSkillVfx := preload("res://client/skills/class_skill_vfx.gd")
const InkVfx := preload("res://client/vfx/ink_vfx.gd")
const ROOT := "res://art/vfx/status/"

## Effect id (data/combat/effects.json) -> status look. An id not listed falls back by its kind (buff / debuff).
const LOOK_OF := {
	"stun": "stun", "sleep": "sleep", "shock": "shock",
	"burn": "burn", "poison": "poison", "bleed": "bleed", "wound": "bleed",
	"slow": "slow", "exhaust": "slow", "sunder": "sunder", "weaken": "sunder",
	"regen": "regen",
}
const HEAD_LOOKS := ["stun", "sleep"]
## Looks made from another look's asset with its materials tinted (no extra download): look -> [source, colour].
## The source rings are near-white, so the tint sets the colour. "immune": the fighter cannot be hit right now
## (dodge, skill i-frames, getting up); PO 2026-11-14 in place of the old cyan body tint.
const RECOLOR := {"immune": ["buff", Color(0.35, 0.95, 1.0, 1.0)]}
const IMMUNE_MIN_SECONDS := 0.25  ## a short i-frame window still shows long enough to read, without flicker
## Which feet look wins when several statuses are on (the first one found in this order).
const FEET_ORDER := ["shock", "burn", "poison", "bleed", "slow", "sunder", "debuff", "regen", "buff"]

static var _packed: Dictionary = {}  ## look -> PackedScene (null = asset missing)
static var _slim_clip: Dictionary = {}  ## look -> slimmed Animation, shared by every instance of the look
static var _tinted: Dictionary = {}  ## [look, source material] -> tinted copy (RECOLOR looks)
static var _warmed := false

var _live: Dictionary = {"head": null, "feet": null, "guard": null}  ## slot -> {"look", "node"}
var _immune_left := 0.0  ## seconds the immune ring stays on after the fighter stops being immune
var _idle: Dictionary = {}  ## look -> hidden instance kept for reuse on this fighter
var head_height := 1.6  ## metres above the feet for the head slot (set by fighter_view)
var size_scale := 1.0  ## the fighter's width against a 0.8 m character (monsters are bigger)


static func scene_path(look: String) -> String:
	if RECOLOR.has(look):
		look = RECOLOR[look][0]
	var path := ROOT + look + "/effect.tscn"
	return path if ResourceLoader.exists(path) else ""


## The looks to show for `effects` (fighter.effects) with their definitions: {"head": look or "", "feet": look or ""}.
static func pick(effect_ids: Array, definitions: Dictionary) -> Dictionary:
	var looks := {}
	for id in effect_ids:
		var look: String = LOOK_OF.get(str(id), "")
		if look == "":
			var definition: Dictionary = definitions.get(id, {})
			look = "buff" if str(definition.get("kind", "debuff")) == "buff" else "debuff"
		looks[look] = true
	var head := ""
	for look in HEAD_LOOKS:
		if looks.has(look):
			head = look
			break
	var feet := ""
	for look in FEET_ORDER:
		if looks.has(look):
			feet = look
			break
	return {"head": head, "feet": feet}


## Shows the statuses of `fighter` (alive, with its effects) using `data.effects` for unknown ids; `immune` adds
## the cyan ring in its own slot (so a status ring under it stays visible).
func show_effects(effect_ids: Array, definitions: Dictionary, alive: bool, immune: bool = false) -> void:
	var wanted := pick(effect_ids, definitions) if alive else {"head": "", "feet": ""}
	if immune and alive:
		_immune_left = IMMUNE_MIN_SECONDS
	elif not alive:
		_immune_left = 0.0
	wanted["guard"] = "immune" if _immune_left > 0.0 else ""
	for slot in ["head", "feet", "guard"]:
		var current = _live[slot]
		var look: String = wanted[slot]
		if current != null and str(current["look"]) == look:
			continue
		if current != null:
			_hide(current)
			_live[slot] = null
		if look != "":
			var node := _take(look)
			if node != null:
				node.position = Vector3(0.0, head_height if slot == "head" else (0.035 if slot == "guard" else 0.02), 0.0)
				node.scale = Vector3.ONE * size_scale * (1.15 if slot == "guard" else 1.0)
				_play(node)
				_live[slot] = {"look": look, "node": node}


func _process(delta: float) -> void:
	if _immune_left > 0.0:
		_immune_left = maxf(0.0, _immune_left - delta)


## The looks shown now (tests).
func shown() -> Dictionary:
	var out := {}
	for slot in _live:
		out[slot] = "" if _live[slot] == null else str(_live[slot]["look"])
	return out


## Meshes drawn now by the shown status effects (tests, the performance budget).
func visible_draws() -> int:
	var count := 0
	for slot in _live:
		if _live[slot] != null:
			count += count_draws(_live[slot]["node"])
	return count


static func count_draws(node: Node) -> int:
	var count := 0
	for mi in node.find_children("*", "GeometryInstance3D", true, false):
		if (mi as GeometryInstance3D).is_visible_in_tree():
			count += 1
	return count


## Compiles every status look's materials once per run (no shader cache on the web): each look is built at a
## tiny scale under `parent` for a few frames and then freed. Called by the first fighter view that enters a stage.
static func prewarm(parent: Node3D) -> void:
	if _warmed or not parent.is_inside_tree():
		return
	_warmed = true
	var looks := ["stun", "sleep", "shock", "burn", "poison", "bleed", "slow", "sunder", "debuff", "regen", "buff", "immune"]
	var holder := Node3D.new()
	holder.name = "StatusVfxWarmup"
	parent.add_child(holder)
	for look in looks:
		var node := _build(look)
		if node == null:
			continue
		holder.add_child(node)
		node.scale = Vector3.ONE * 0.001
		for mi in node.find_children("*", "GeometryInstance3D", true, false):
			(mi as Node3D).visible = true
	var timer := parent.get_tree().create_timer(0.25)
	timer.timeout.connect(func(): if is_instance_valid(holder): holder.queue_free())


func _take(look: String) -> Node3D:
	var node: Node3D = _idle.get(look)
	if node != null:
		_idle.erase(look)
		return node
	node = _build(look)
	if node != null:
		add_child(node)
	return node


func _hide(entry: Dictionary) -> void:
	var node: Node3D = entry["node"]
	if not is_instance_valid(node):
		return
	var player := _player_of(node)
	if player != null:
		player.stop()
	node.visible = false
	_idle[str(entry["look"])] = node


func _play(node: Node3D) -> void:
	node.visible = true
	var player := _player_of(node)
	if player == null:
		return
	var clip := _clip_of(player)
	if clip != &"":
		player.play(clip)
		player.seek(randf() * player.get_animation(clip).length, true)  # several fighters do not pulse in step


## One instance of `look`, looping, slimmed (only the live phase of each particle drawn), no shadows.
static func _build(look: String) -> Node3D:
	if not _packed.has(look):
		var path := scene_path(look)
		_packed[look] = load(path) if path != "" else null
	var packed: PackedScene = _packed[look]
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	node.set("autoplay", false)
	node.set("loop_effect", true)
	node.set("free_on_finish", false)
	node.visible = false
	for mi in node.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if RECOLOR.has(look):
		_tint(node, look, RECOLOR[look][1])
	InkVfx.apply(node)  # ink-wash materials when the drawn style is on (after the tint, so the tint is kept)
	var player := _player_of(node)
	if player != null:
		var clip := _clip_of(player)
		if clip != &"":
			if not _slim_clip.has(look):
				var anim := ClassSkillVfx.slim_animation(player.get_animation(clip), player.get_node(player.root_node))
				anim.loop_mode = Animation.LOOP_LINEAR
				_slim_clip[look] = anim
			else:
				# slim_animation sets the mesh scales back to 1 on the instance it reads; do the same here.
				_reset_scales(_slim_clip[look], player)
			var anim: Animation = _slim_clip[look]
			var lib_name := String(clip).get_slice("/", 0) if "/" in String(clip) else ""
			var anim_name := String(clip).get_slice("/", 1) if "/" in String(clip) else String(clip)
			var lib := player.get_animation_library(lib_name).duplicate() as AnimationLibrary
			lib.remove_animation(anim_name)
			lib.add_animation(anim_name, anim)
			player.remove_animation_library(lib_name)
			player.add_animation_library(lib_name, lib)
			_start_hidden(anim, player)
	return node


## Every surface of `node` gets a copy of its material with the albedo multiplied by `tint` (copies shared per look).
static func _tint(node: Node, look: String, tint: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			if not source is BaseMaterial3D:
				continue
			var key := [look, source]
			if not _tinted.has(key):
				var copy := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
				copy.albedo_color = copy.albedo_color * tint
				_tinted[key] = copy
			mesh_instance.set_surface_override_material(surface, _tinted[key])


static func _reset_scales(anim: Animation, player: AnimationPlayer) -> void:
	var root := player.get_node(player.root_node)
	for t in anim.get_track_count():
		var path := String(anim.track_get_path(t))
		if anim.track_get_type(t) == Animation.TYPE_VALUE and path.ends_with(":visible"):
			var node := root.get_node_or_null(NodePath(path.get_slice(":", 0)))
			if node is Node3D:
				(node as Node3D).scale = Vector3.ONE


static func _start_hidden(anim: Animation, player: AnimationPlayer) -> void:
	var root := player.get_node(player.root_node)
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_VALUE and anim.track_get_key_count(t) > 0:
			var node := root.get_node_or_null(NodePath(String(anim.track_get_path(t)).get_slice(":", 0)))
			if node is Node3D:
				(node as Node3D).visible = bool(anim.track_get_key_value(t, 0))


static func _player_of(node: Node) -> AnimationPlayer:
	var found := node.find_children("*", "AnimationPlayer", true, false)
	return found[0] if not found.is_empty() else null


static func _clip_of(player: AnimationPlayer) -> StringName:
	for name in player.get_animation_list():
		if name != &"RESET":
			return name
	return &""
