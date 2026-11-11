extends "res://logic/run.gd"
## One fighter of the auto-battle squad (docs/tech/per_card_gear_plan.md step 4, Boss answers 2026-11-11).
## The account goes on ONE trip: one shared Run (one profile, one bag). Each squad card fights as a member
## wrapping that run: its stats, worn gear (wear) and skill build come from its own card
## (Profile.card_gear[card_id]); loot goes into the shared bag; a member falling only ends the trip
## (Run.death: carried loot secured in the stash) once every member of the squad is down.
## It IS a Run, so GameSim/Journey/Commands use it unchanged.

var card_id := ""
var shared  ## the account's Run (owns the bag)
var squad: Array = []  ## every member of this squad, this one included (one shared Array)


## The members for `cards` (class ids, in fighter order) on the account trip `base`.
static func make_squad(base, cards: Array) -> Array:
	var members: Array = []
	for card in cards:
		var member = load("res://logic/squad_member.gd").new()
		member.shared = base
		member.profile = base.profile
		member.camp = base.camp
		member.bag = base.bag
		member.relic_loot = base.relic_loot
		member.used_rests = base.used_rests
		member.card_id = str(card)
		member.squad = members
		members.append(member)
	return members


func loadout() -> Loadout:
	return profile.loadout_of(card_id)


func skill_build() -> Dictionary:
	return profile.build_of(card_id)


func loot_into_bag(drop: Dictionary) -> Dictionary:
	return shared.loot_into_bag(drop)


func discard_item(index: int) -> bool:
	return shared.discard_item(index)


func return_to_camp() -> Dictionary:
	return shared.return_to_camp()


func discard_loot() -> Dictionary:
	return shared.discard_loot()


## This member is out. The account trip ends (loot secured) only when the whole squad is out.
func death() -> Dictionary:
	if died:
		return {"items": 0, "gold": 0, "materials": {}}
	died = true
	if squad.all(func(member): return member.died):
		return shared.death()
	return {"items": 0, "gold": 0, "materials": {}}


## The shared trip (with the profile) plus this member's own fields. Several members of one squad save
## the same shared part; restore code rebuilds it once (GameSim.restore, PartyJourney.from_dict).
func to_dict(include_profile: bool = true) -> Dictionary:
	var data: Dictionary = shared.to_dict(include_profile)
	data.merge(member_fields(), true)
	return data


func member_fields() -> Dictionary:
	return {"card": card_id, "member_died": died, "member_cooldowns": skill_cooldowns.duplicate(true)}


func apply_member_fields(d: Dictionary) -> void:
	died = bool(d.get("member_died", false))
	skill_cooldowns = d.get("member_cooldowns", {}).duplicate(true)
