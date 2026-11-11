extends SceneTree
## Focused release checks for the native armor replacement. Does not write player data.
const Rules = preload("res://logic/item_rules_loader.gd")
const Item = preload("res://logic/item.gd")
const Items = preload("res://logic/item_system.gd")
const Mobility = preload("res://logic/equipment_mobility.gd")
var checks := 0
var failures := 0
func check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var rules = Rules.load_default()
	check("rules valid", rules.is_valid())
	var tuning = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/equipment_tuning.json"))
	var worker = preload("res://server/names/worker.gd").new()
	var response = worker._dispatch("/equipment-config", {})
	check("authority includes armor and mobility", response.has("armor") and response.has("mobility"))
	response["version"] = 1
	check("authority tuning accepted by client", Rules.apply_tuning(response, rules))
	worker.free()
	var migration = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/armor_migration.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	for old_id in migration.aliases:
		var new_id: String = migration.aliases[old_id]
		var row: Dictionary = rules.catalog.entry(new_id)
		var item = Items.create_item(rules, "owned-"+old_id, row.slot, 2, rng, "", new_id)
		item.item_id = old_id
		item.refine_level = 8
		item.upgrade_count = 4
		item.durability = 47.25
		if row.slot == "shoes": item.main_stat = "MOVESPD"
		var before: Dictionary = item.to_dict()
		var decoded = Item.from_dict(before)
		var expected: Dictionary = before.duplicate(true)
		expected.item_id = new_id
		if row.slot == "shoes": expected.main_stat = "DEF"
		check("migration preserves owned fields "+old_id, decoded.to_dict() == expected)
		check("migration idempotent "+old_id, Item.from_dict(decoded.to_dict()).to_dict() == expected)
		check("legacy creation maps "+old_id, Items.create_item(rules,"legacy",row.slot,0,rng,"",old_id).item_id == new_id)
	for slot in ["hat","shirt","pants","armband","shoes"]:
		for retired_id in ["", "clothing_golden_scroll_m_"+slot, "unknown_retired_"+slot]:
			var item = Items.create_item(rules,"retired-"+slot,slot,2,rng,"","armor_ash_steel_"+slot)
			item.item_id=retired_id
			item.refine_level=10
			item.upgrade_count=5
			var decoded = Item.from_dict(item.to_dict())
			check("unknown retired maps "+retired_id+slot,decoded.item_id=="armor_ash_steel_"+slot)
			var expected: Dictionary = item.to_dict()
			expected.item_id="armor_ash_steel_"+slot
			check("unknown retired retains rolls "+retired_id+slot,decoded.to_dict()==expected)
	var font_label = preload("res://client/item_text.gd").base_label(Items.create_item(rules,"font","shirt",0,rng,"","armor_ash_steel_shirt"),rules)
	check("bold Thai glyphs present", font_label.get_theme_font("font").has_char("ก".unicode_at(0)))
	font_label.free()
	var armor_count := 0
	for identity in rules.catalog.items:
		var row: Dictionary = rules.catalog.entry(identity)
		if str(row.get("armor_class", "")).is_empty(): continue
		armor_count += 1
		check("model exists "+identity, ResourceLoader.exists(row.asset_path))
		check("icon exists "+identity, ResourceLoader.exists(row.icon_path))
		var item = Items.create_item(rules,identity,row.slot,0,rng,"",identity)
		var expected_base: float = rules.main_base(row.main_stat,0)*tuning.armor.class_base_multipliers[row.armor_class][row.main_stat]
		check("base multiplier "+identity, is_equal_approx(item.base_value(rules),expected_base))
		check("description contains penalties "+identity, preload("res://client/item_text.gd").mobility_text(item,rules).contains("แดช"))
	check("45 combat armor pieces", armor_count == 45)
	for kind in ["heavy","light","cloth"]:
		var style: String = {"heavy":"ash_steel","light":"ash_leather","cloth":"ash_cloth"}[kind]
		var worn: Array = []
		for slot in ["hat","shirt","armband","pants","shoes"]:
			worn.append(Items.create_item(rules,slot,slot,0,rng,"","armor_"+style+"_"+slot))
		var factor: float = 1.0-float(tuning.mobility.armor_penalties[kind])
		var result = Mobility.factors(rules,worn)
		check("full set walk "+kind, is_equal_approx(result.move_factor,factor))
		check("full set dodge "+kind, is_equal_approx(result.dodge_factor,factor))
		worn.append(Items.create_item(rules,"hammer","weapon",0,rng,"hammer","hammer_01"))
		worn[-1].weapon_type = "hammer"
		check("hammer composes "+kind, is_equal_approx(Mobility.factors(rules,worn).move_factor,factor*.88))
	var mixed: Array = []
	for pair in [["shirt","ash_steel"],["pants","ash_leather"],["shoes","ash_cloth"]]:
		mixed.append(Items.create_item(rules,pair[0],pair[0],0,rng,"","armor_"+pair[1]+"_"+pair[0]))
	check("mixed slots weighted", is_equal_approx(Mobility.factors(rules,mixed).move_factor,1.0-(.4*.3+.25*.15+.15*.05)))
	print("NATIVE ARMOR RELEASE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
