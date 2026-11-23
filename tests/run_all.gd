extends SceneTree
## Runs every test file and exits non-zero if any check fails.
##   godot --headless --path <project folder> --script res://tests/run_all.gd
## EXTENDING: write tests/test_<name>.gd with `func run(ctx)`, call ctx.check("what", condition),
## then add the file to TEST_FILES.

const TEST_FILES := [
	"res://tests/test_beta_cleanup.gd",
	"res://tests/test_asset_size.gd",
	"res://tests/test_snapshot_cache.gd",
	"res://tests/test_battle_card_looks.gd",
	"res://tests/test_feedback_panel.gd",
	"res://tests/test_party_online.gd",
	"res://tests/test_netcode.gd",
	"res://tests/test_skill_net.gd",
	"res://tests/test_profile_diff.gd",
	"res://tests/test_profile_patch.gd",
	"res://tests/test_entity_prune.gd",
	"res://tests/test_room_worker.gd",
	"res://tests/test_online_profiles.gd",
	"res://tests/test_online_names.gd",
	"res://tests/test_online_login.gd",
	"res://tests/test_coop.gd",
	"res://tests/test_auto_pilot.gd",
	"res://tests/test_autopilot_survival.gd",
	"res://tests/test_corpse_clear.gd",
	"res://tests/test_card_deck.gd",
	"res://tests/test_tutorial_unlocks.gd",
	"res://tests/test_tutorial_ui.gd",
	"res://tests/test_event_stream.gd",
	"res://tests/test_world_zones.gd",
	"res://tests/test_zone_quests.gd",
	"res://tests/test_main_daily_quests.gd",
	"res://tests/test_worldmap_start.gd",
	"res://tests/test_hub_quest_tracker.gd",
	"res://tests/test_hub_card_level.gd",
	"res://tests/test_hub_quests_panel.gd",
	"res://tests/test_mummy_pyramid.gd",
	"res://tests/test_orc_camp.gd",
	"res://tests/test_orc_zone.gd",
	"res://tests/test_boss_loot.gd",
	"res://tests/test_boss_weapons.gd",
	"res://tests/test_boss_procs.gd",
	"res://tests/test_squad_zone_rooms.gd",
	"res://tests/test_tier_up.gd",
	"res://tests/test_gear_purge.gd",
	"res://tests/test_loot_settle.gd",
	"res://tests/test_loot_coverage.gd",
	"res://tests/test_localstack_fixtures.gd",
	"res://tests/test_card_progress.gd",
	"res://tests/test_class_skills.gd",
	"res://tests/test_skill_point_choice.gd",
	"res://tests/test_skill_tree_data.gd",
	"res://tests/test_skill_tree_rules.gd",
	"res://tests/test_skill_tree_effects.gd",
	"res://tests/test_skill_tree_mechanics.gd",
	"res://tests/test_skill_tree_migration.gd",
	"res://tests/test_races.gd",
	"res://tests/test_race_passives.gd",
	"res://tests/test_class_identity.gd",
	"res://tests/test_race_ultimates.gd",
	"res://tests/test_race_ult_actions.gd",
	"res://tests/test_race_ult_cells.gd",
	"res://tests/test_material_counter.gd",
	"res://tests/test_card_gear.gd",
	"res://tests/test_starter_kit.gd",
	"res://tests/test_race_sets.gd",
	"res://tests/test_race_drops.gd",
	"res://tests/test_gear_levels.gd",
	"res://tests/test_race_gear_v2.gd",
	"res://tests/test_race_gear_lv15_look.gd",
	"res://tests/test_race_weapons_lv15.gd",
	"res://tests/test_item_look_by_race.gd",
	"res://tests/test_race_weapon_swap.gd",
	"res://tests/test_legacy_items.gd",
	"res://tests/test_squad_gear.gd",
	"res://tests/test_loot_by_squad.gd",
	"res://tests/test_relics_removed.gd",
	"res://tests/test_offhand_slot.gd",
	"res://tests/test_local_session.gd",
	"res://tests/test_session_architecture.gd",
	"res://tests/test_serialization.gd",
	"res://tests/test_commands.gd",
	"res://tests/test_repair.gd",
	"res://tests/test_wear_run_cap.gd",
	"res://tests/test_sim_restore.gd",
	"res://tests/test_determinism.gd",
	"res://tests/test_input_codec.gd",
	"res://tests/test_architecture.gd",
	"res://tests/test_movement.gd",
	"res://tests/test_map_data.gd",
	"res://tests/test_goblin_stages.gd",
	"res://tests/test_goblin_base_render_budget.gd",
	"res://tests/test_draw_style.gd",
	"res://tests/test_phone_graphics.gd",
	"res://tests/test_frame_cap.gd",
	"res://tests/test_lv15_metal_glint.gd",
	"res://tests/test_settings_panel.gd",
	"res://tests/test_items.gd",
	"res://tests/test_item_catalog.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_effects.gd",
	"res://tests/test_status_resist_groups.gd",
	"res://tests/test_monster_rig.gd",
	"res://tests/test_monsters.gd",
	"res://tests/test_projectiles.gd",
	"res://tests/test_vfx.gd",
	"res://tests/test_vfx_violence.gd",
	"res://tests/test_fight_vfx_anchor.gd",
	"res://tests/test_high_wizard.gd",
	"res://tests/test_boss_tempo.gd",
	"res://tests/test_status_vfx.gd",
	"res://tests/test_camera.gd",
	"res://tests/test_character_model.gd",
	"res://tests/test_animation.gd",
	"res://tests/test_race_look.gd",
	"res://tests/test_ink_style.gd",
	"res://tests/test_cosmetics.gd",
	"res://tests/test_hud.gd",
	"res://tests/test_squad_stamina.gd",
	"res://tests/test_enemy_bars.gd",
	"res://tests/test_title.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_journey.gd",
	"res://tests/test_exit_portals.gd",
	"res://tests/test_pack_loader.gd",
	"res://tests/test_ui_import_budget.gd",
	"res://tests/test_ui_tokens.gd",
	"res://tests/test_ui_fixes_1117.gd",
	"res://tests/test_skill_tree_ui.gd",
	"res://tests/test_equip_sell_fixes_1117.gd",
	"res://tests/test_bulk_sell_1122.gd",
	"res://tests/test_fonts.gd",
	"res://tests/test_title_backdrop.gd",
]

var passed := 0
var failed := 0


func check(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  PASS  " + name)
	else:
		failed += 1
		print("  FAIL  " + name)


func _initialize() -> void:
	await process_frame  # let the autoloads and the tree finish starting
	for path in TEST_FILES:
		print("--- ", path.get_file())
		var script = load(path)
		if script == null or not script.can_instantiate():
			check("%s loads (it has a script error; see the messages above)" % path.get_file(), false)
			continue
		var test = script.new()
		await test.run(self)
	print("passed=%d failed=%d" % [passed, failed])
	var audio := root.get_node_or_null("Audio")
	if audio != null:
		audio.release_all()  # (as closing the window does: no sounds left held at exit)
		await create_timer(0.3).timeout  # (the audio thread lets go of stopped playbacks a moment later)
	quit(1 if failed > 0 else 0)
