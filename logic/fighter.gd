extends RefCounted
## A character's combat state: team, stats, health and what it is doing right now.
## Plain data; the rules that change it live in combat.gd.
## Buffs and debuffs live in `effects` (rules in effects.gd); read stats through stat() so they count.

enum State { IDLE, ATTACK, HITSTUN, DOWN, DEAD, GUARD, DODGE, DOWNED }

var relic_state: Dictionary = {}  ## Authoritative per-stage Relic loadout, charge and cooldown timers.
var team := "player"  ## fighters on the same team never hit each other
var style := "fists"  ## which move set this fighter uses (chosen by the weapon)
var stats: Dictionary = {}  ## HP, ATK, DEF, ATKSPD, MOVESPD, CRIRATE, CRIDMG, EFFECT_ACC, EFFECT_RES
var hp := 0.0
var enemy_type := ""  ## monsters only: the enemy id from the combat data (what loot it drops)
var level := 1  ## monsters only: how strong this one is compared with the base numbers (see CombatData.enemy_stats)

var state := State.IDLE
var state_ticks := 0  ## ticks spent in the current state
## Which of the eight directions the fighter faces: (1, 0) right, (-1, 0) left,
## (0, 1) toward the camera ("front"), (0, -1) away from the camera ("back"), and the four
## diagonals (+-1, +-1) in between.
var buffered_shot_direction := Vector2.ZERO
var shot_direction := Vector2.ZERO  ## Frozen authoritative bow aim for the current shot.
var direction := Vector2i(1, 0)
## Left/right facing only: 1, -1, or 0 when facing front or back. Setting it faces left or right.
var facing: int:
	get:
		return direction.x
	set(value):
		direction = Vector2i(1 if value >= 0 else -1, 0)

var move_id := ""  ## the move being performed (state ATTACK)
var move_frame := 0.0  ## progress through that move; grows by attack_speed_factor() each tick
var hit_ids: Array[int] = []  ## fighters this move has already hit (a move hits each target once)
var spawns_done := 0  ## how many of the move's projectiles/areas it has fired (see projectiles.gd)
var buffered := ""  ## "light" or "heavy" if pressed during the move, used to chain

var hitstun_left := 0
var launched := false  ## knocked into the air: stays stunned until landing, then lies down
var down_left := 0
var invulnerable_left := 0  ## untouchable for this many more ticks (after getting up)
var hitstop := 0  ## ticks of freeze after landing or taking a hit
var combo_hits := 0  ## hits taken in a row without recovering

var dodge_left := 0  ## ticks left in the current dodge slide
var dodge_cooldown := 0  ## ticks until the next dodge is allowed
var cooldowns: Dictionary = {}  ## move id -> ticks until a skill (special) may be used again
var gauge := 0.0  ## ultimate gauge, filled by dealing and taking hits

var energy := 0.0  ## stamina: spent by running, dodging and special skills, refills when not spending
var energy_wait := 0  ## ticks to wait after spending before the energy starts refilling
var skill_hit_filter: Callable  ## Authority-local callback, excluded from checkpoints/wire.
var skill_base_hit: Callable
var skill_view: Dictionary = {}  ## Read-only presentation state for slots, casts and statuses.
var exhausted := false  ## ran out of energy: cannot run until it refills a little
var running := false  ## true while actually running this tick (for the client's animation and dust)
var run_ticks := 0  ## how long the fighter has been running; a run attack needs a short run-up
var run_grace := 0  ## ticks left in which a run attack is still possible after letting go of run
var air_run := false  ## jumped from a run: keeps the running speed in the air

var poise := 0.0  ## armor against flinching: hits wear it down, and only when it is gone does the fighter stagger
var max_poise := 0.0  ## 0 = no armor (always flinches)
var poise_wait := 0  ## ticks since the last hit before the poise starts coming back

var combo_dealt := 0  ## hits landed in a row on anyone (resets when the combo window runs out)
var combo_damage := 0  ## damage dealt by the current combo
var combo_timer := 0  ## ticks left before the combo is over
var active_started := false  ## the current move's damaging frames have begun (the client draws its swing)

var effects: Dictionary = {}  ## buffs and debuffs now on this fighter: effect id -> {"left", "stacks", "dps", "age", "source"}
var stat_mods: Dictionary = {}  ## what the effects add up to, per stat: {"add", "mul"} (kept up to date by effects.gd)
var incapacitated := false  ## stunned or asleep: cannot do anything
var rooted := false  ## shocked: cannot move, jump, run or dodge
var control_immune_left := 0  ## ticks after a stun/shock/sleep during which no new one can land


func max_hp() -> float:
	return float(stats.get("HP", 1.0))


## The size of the stamina bar: the STAMINA stat (gear makes it bigger).
func max_energy() -> float:
	return maxf(1.0, float(stats.get("STAMINA", 100.0)))


func is_alive() -> bool:
	return state != State.DEAD and state != State.DOWNED


func attack_speed_factor() -> float:
	return maxf(0.1, 1.0 + stat("ATKSPD") / 100.0)


## A stat with the buffs and debuffs counted: (base + adds) x (1 + muls). Damage, speed and regeneration
## read this; the sizes of the health and stamina bars (HP, STAMINA) are the base values.
func stat(stat_name: String, default_value: float = 0.0) -> float:
	var value := float(stats.get(stat_name, default_value))
	if stat_mods.has(stat_name):
		value = (value + float(stat_mods[stat_name]["add"])) * (1.0 + float(stat_mods[stat_name]["mul"]))
	if stat_name == "ATKSPD" or stat_name == "MOVESPD":
		return maxf(-90.0, value)
	return maxf(0.0, value)


## How well healing works on this fighter (1 = normal; a wound lowers it).
func heal_factor() -> float:
	if float(skill_view.get("heal_allowed",1)) <= 0: return 0.0
	if not stat_mods.has("HEALING"):
		return 1.0
	return maxf(0.0, (1.0 + float(stat_mods["HEALING"]["add"])) * (1.0 + float(stat_mods["HEALING"]["mul"])))


## Co-op-only incapacitation; ordinary combat knockdown remains State.DOWN.
var downed_at := -1
var bleedout_left := 0
var revive_progress := 0
var reviver := -1
var eliminated := false
