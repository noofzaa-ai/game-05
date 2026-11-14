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
## The squad's race synergy (design/gdd/races-and-classes.md 3.5), computed ONCE at run start from the races of the
## squad's cards (logic/race_data.gd synergy_for) and fixed for the whole run, deaths included. Saved with the member.
## {"kind": "trio"|"pair"|"alliance"|"none", "race", "name", "text", "effects"}; read-only for the UI.
var squad_synergy: Dictionary = {}


## The members for `cards` (class ids, in fighter order) on the account trip `base`. `synergy_override` (online
## squads, design/gdd/online-squads.md 3.2): a 4-player room passes the synergy of the room group (all 4 cards) instead
## of this squad's own. `group`: the synergy group id; synergy effects aimed at allies reach only the same group.
static func make_squad(base, cards: Array, synergy_override: Dictionary = {}, group: String = "") -> Array:
	var members: Array = []
	for card in cards:
		var member = load("res://logic/squad_member.gd").new()
		member.shared = base
		member.profile = base.profile
		member.camp = base.camp
		member.bag = base.bag
		member.used_rests = base.used_rests
		member.card_id = str(card)
		member.squad = members
		members.append(member)
	var deck: Dictionary = base.profile.card_deck
	var races: Array = cards.map(func(card): return preload("res://logic/card_deck.gd").race_of(deck, str(card))).filter(func(race): return not str(race).is_empty())  # tutorial.md R4
	var synergy: Dictionary = synergy_override.duplicate(true) if not synergy_override.is_empty() else preload("res://logic/race_data.gd").load_default().synergy_for(races)
	if not group.is_empty():
		synergy["group"] = group
	for member in members:
		member.squad_synergy = synergy.duplicate(true)
	return members


## The squad synergy of this run (read-only copy).
func synergy() -> Dictionary:
	return squad_synergy.duplicate(true)


func loadout() -> Loadout:
	return profile.loadout_of(card_id)



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
	return {"card": card_id, "member_died": died, "member_cooldowns": skill_cooldowns.duplicate(true), "squad_synergy": squad_synergy.duplicate(true)}


func apply_member_fields(d: Dictionary) -> void:
	died = bool(d.get("member_died", false))
	skill_cooldowns = d.get("member_cooldowns", {}).duplicate(true)
	if d.get("squad_synergy") is Dictionary:  # saved before races: keep the one make_squad computed
		squad_synergy = d["squad_synergy"].duplicate(true)
