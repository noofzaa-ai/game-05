extends RefCounted
## Boss 2026-11-17, two fight VFX bugs:
##   1. the longbow's shots drew the green melee slash arc (no swing/longbow_* look: it fell through to swing/light_1);
##   2. ground cracks / rings / stains were drawn at the attacker's hitbox (a point in front of the caster) when the
##      move swung, instead of under the monsters the blow struck.
## Locks: every ground layer lands on a struck target / burst point (or is listed here as caster-centred on purpose),
## the longbow's moves have their own non-slash look, and a class skill's effect point equals the damage centre.

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const VfxLibrary := preload("res://client/vfx/vfx_library.gd")
const ClassSkillVfx := preload("res://client/skills/class_skill_vfx.gd")
const SkillData := preload("res://logic/class_skills/skill_data.gd")

## Ground layers centred on the CASTER on purpose (a roar, a landing, a spin, a stance or buff aura, a camp fire, a dead
## body's stain): the rules' area for these is the caster's own position.
const CASTER_CENTRED := [
	"swing/run_heavy", "swing/brute_roar", "land/air_heavy", "windup/ultimate", "windup/goblin_mage_hex",
	"windup/mummy_mage_curse", "windup/mummy_boss_nova", "swing/mummy_boss_nova",  # the mage's cast glyph; the Pharaoh's nova is a box on itself
	"windup/orc_mage_hex",  # the orc shaman's cast glyph (as the goblin and mummy mages)
	"windup/orc_warlock_cataclysm", "swing/orc_warlock_cataclysm",  # the Orc Warlock's cataclysm is a ring around itself (as the Pharaoh's nova)
	"skill_cast/riposte", "skill_cast/lightning_strike", "skill_cast/frost_armor",
	"guard_break", "knockdown", "death", "loot", "rest",
]
const MELEE_ONLY_SHAPE := "arc"


func run(ctx) -> void:
	var lib = VfxLibrary.load_default()
	_check_ground_anchors(ctx, lib)
	_check_helper(ctx)
	_check_longbow(ctx, lib)
	_check_class_skill_anchor(ctx)


func _check_ground_anchors(ctx, lib) -> void:
	var front: Array[String] = []
	var caster_other: Array[String] = []
	for key in lib.actions:
		for layer in lib.layers(key):
			if str(layer.get("type")) != "ground":
				continue
			var frame := VfxLibrary.ground_frame(key, layer)
			if frame == "front_of_caster":
				front.append(key)
			elif frame == "caster" and not key in CASTER_CENTRED and not key in caster_other:
				caster_other.append(key)
	ctx.check("no ground mark is drawn at a point in front of the caster %s" % [front], front.is_empty())
	ctx.check("every caster-centred ground mark is listed on purpose %s" % [caster_other], caster_other.is_empty())
	# The moves that slam the floor draw it when the blow lands, under each struck target.
	for key in ["hit/heavy", "hit/blade_ultimate", "hit/hammer_special", "hit/hammer_ultimate", "hit/brute_slam", "hit/goblin_knight_overhead"]:
		var grounds: Array = lib.layers(key).filter(func(l) -> bool: return str(l.get("type")) == "ground")
		ctx.check("%s draws its floor mark under the struck target" % key, not grounds.is_empty() and grounds.all(func(l) -> bool: return VfxLibrary.ground_frame(key, l) == "target"))
	ctx.check("swing/heavy no longer cracks the floor ahead of the swing", lib.layers("swing/heavy").filter(func(l) -> bool: return str(l.get("type")) == "ground").is_empty())


func _check_helper(ctx) -> void:
	ctx.check("helper: a swing's hitbox anchor is a point in front of the caster", VfxLibrary.ground_frame("swing/heavy", {"type": "ground", "anchor": "hitbox"}) == "front_of_caster")
	ctx.check("helper: a swing's forward offset is in front of the caster", VfxLibrary.ground_frame("swing/x", {"type": "ground", "anchor": "feet", "offset": [1.0, 0.0, 0.0]}) == "front_of_caster")
	ctx.check("helper: a hit's feet anchor is the target", VfxLibrary.ground_frame("hit/heavy", {"type": "ground", "anchor": "feet"}) == "target")
	ctx.check("helper: a swing's feet anchor is the caster", VfxLibrary.ground_frame("swing/brute_roar", {"type": "ground", "anchor": "feet"}) == "caster")


func _check_longbow(ctx, lib) -> void:
	var data := CombatDataLoader.load_default()
	var bad: Array[String] = []
	var slash: Array[String] = []
	for move_id in data.moves:
		if not str(move_id).begins_with("longbow_"):
			continue
		var key: String = lib.swing_key(move_id)
		if key != "swing/" + str(move_id):
			bad.append("%s -> %s" % [move_id, key])
			continue
		for layer in lib.layers(key):
			if str(layer.get("shape", "")) == MELEE_ONLY_SHAPE or str(layer.get("color", "")) == "weapon":
				slash.append(key)
	ctx.check("every longbow move has its own swing look, not the shared slash %s" % [bad], bad.is_empty())
	ctx.check("no longbow look is an arc or the green weapon colour %s" % [slash], slash.is_empty())
	ctx.check("the longbow's light shot is a thin forward streak", lib.layers("swing/longbow_light_1").size() == 1 and str(lib.layers("swing/longbow_light_1")[0].get("shape")) == "thrust" and float(lib.layers("swing/longbow_light_1")[0].get("width", 1.0)) <= 0.1)
	var staff: String = lib.swing_key("magic_light_1")
	ctx.check("the mage's staff does not slash either (%s)" % staff, staff == "swing/magic_light_1" and lib.layers(staff).is_empty())


## The class skills: the effect point equals the point the sim damages around, over every area skill.
func _check_class_skill_anchor(ctx) -> void:
	var skills = SkillData.load_default()
	var caster := Vector3(2.0, 0.0, 1.0)
	var aim := Vector3(7.0, 0.0, 1.0)
	var point := Vector3(6.0, 0.0, 3.0)
	var expect := {"circle": caster, "arc": caster, "pull_circle": caster, "leap_slam": caster, "delayed_circle": point, "remote_circle": point}
	var checked := 0
	var wrong: Array[String] = []
	for id in ClassSkillVfx.SPEC:
		var kind: String = str(skills.skill(id).get("kind", ""))
		if not expect.has(kind):
			continue
		checked += 1
		var spec: Dictionary = ClassSkillVfx.SPEC[id]
		var drawn := ClassSkillVfx.anchor_point(str(spec["at"]), caster, aim, point, float(spec.get("back", 0.0)))
		if not drawn.is_equal_approx(expect[kind]):
			wrong.append("%s (%s): drawn %s, damage centre %s" % [id, kind, drawn, expect[kind]])
	ctx.check("area class skills draw at the damage centre (%d skills) %s" % [checked, wrong], checked >= 5 and wrong.is_empty())
	var shot := ClassSkillVfx.anchor_point("target", caster, aim, point, 2.0)
	ctx.check("a shot's effect ends on the target, pulled back along the line", shot.is_equal_approx(Vector3(5.0, 0.0, 1.0)))
