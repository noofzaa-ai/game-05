extends RefCounted
## The title screen (client/title_screen.gd, scenes/title.tscn) and its data: the version log
## (data/ui/version_info.json) loads, is newest first and every version has notes; the menu has its
## items, Start goes on to the campfire hub, the panels open and close; the boot scene goes to the title.

const VersionInfo := preload("res://client/version_info.gd")
const PackLoader := preload("res://client/pack_loader.gd")


func _frames(ctx, count: int) -> void:
	for i in count:
		await ctx.process_frame


func run(ctx) -> void:
	_check_versions(ctx)
	_check_credits(ctx)
	ctx.check("the boot scene opens the title screen", PackLoader.NEXT_SCENE == "res://scenes/title.tscn" and ResourceLoader.exists(PackLoader.NEXT_SCENE))
	ctx.check("the game still starts at the boot scene", str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/boot.tscn")
	await _check_screen(ctx)


func _check_versions(ctx) -> void:
	var info = VersionInfo.new().load_file()
	ctx.check("version_info.json loads without problems %s" % [info.errors], info.errors.is_empty())
	ctx.check("there are several versions (%d)" % info.versions.size(), info.versions.size() >= 3)
	var ordered := true
	for i in range(1, info.versions.size()):
		if VersionInfo.compare_ids(info.versions[i - 1].id, info.versions[i].id) <= 0:
			ordered = false
	ctx.check("versions are newest first", ordered)
	for v in info.versions:
		var lines := 0
		for key in v.sections:
			lines += v.sections[key].size()
		ctx.check("version %s has a name, a date and notes (%d lines)" % [v.id, lines], v.name != "" and v.date != "" and lines > 0)
		ctx.check("version %s uses only the known sections" % v.id, v.sections.keys().all(func(k) -> bool: return k in VersionInfo.SECTIONS))
	ctx.check("version numbers compare as numbers (0.10 > 0.9)", VersionInfo.compare_ids("0.10", "0.9") == 1 and VersionInfo.compare_ids("v1.0", "1") == 0)
	# Player-facing: no file names or code words leak into the notes.
	var leaks: Array = []
	var leak := RegEx.new()
	leak.compile("\\.(gd|json|glb|tscn|png)\\b|res://|logic/|client/|data/")
	for v in info.versions:
		for key in v.sections:
			for line in v.sections[key]:
				if leak.search(line) != null:
					leaks.append(line)
	ctx.check("version notes are player-facing (no file names) %s" % [leaks], leaks.is_empty())
	var broken = VersionInfo.new().load_file("res://data/ui/no_such_file.json")
	ctx.check("a missing version file is reported, not a crash", not broken.errors.is_empty() and broken.versions.is_empty())


func _check_credits(ctx) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/credits.json"))
	ctx.check("credits.json loads", data is Dictionary and not data.get("team", []).is_empty() and not data.get("credits", []).is_empty())
	if not (data is Dictionary):
		return
	var text := JSON.stringify(data.get("credits", []))
	for name in ["VSCO 2", "Sarabun", "Taviraj", "Godot"]:
		ctx.check("the credits name %s" % name, name in text)


func _check_screen(ctx) -> void:
	ctx.change_scene_to_file("res://scenes/title.tscn")
	await _frames(ctx, 3)
	var title: Node = ctx.current_scene
	ctx.check("the title scene opens", title != null and title.scene_file_path == "res://scenes/title.tscn")
	if title == null or title.scene_file_path != "res://scenes/title.tscn":
		return
	var words: Array = title.ITEMS.map(func(k): return title.TEXT[k])
	ctx.check("the menu has Start, Version Info, Settings, Staff and Exit in that order", words == ["Start", "Version Info", "Settings", "Staff", "Exit"])
	ctx.check("Start has the focus (keyboard / gamepad ready)", title.items["start"].has_focus())
	ctx.check("Exit shows only off the web", title.items["exit"].visible == not OS.has_feature("web"))
	ctx.check("every menu item is at least 44 units tall", title.items.values().all(func(b) -> bool: return b.custom_minimum_size.y >= 44.0))
	var newest = title.info.newest()
	ctx.check("the corner shows the newest version (%s)" % title._corner.text, "BETA-TEST" in title._corner.text and "Git " in title._corner.text)

	title.items["versions"].pressed.emit()
	await _frames(ctx, 2)
	ctx.check("Version Info opens a panel with one tab per version", title.panel != null and title.version_tabs.size() == title.info.versions.size())
	ctx.check("the newest version is shown first", not title.version_tabs.is_empty() and title.version_tabs[0].button_pressed and title.version_tabs[0].text.begins_with("v" + newest.id))
	ctx.check("the menu hides while a panel is open", not title._menu.visible)
	title.version_tabs[title.version_tabs.size() - 1].pressed.emit()
	await _frames(ctx, 1)
	var shown: String = title.version_notes.get_child(0).text if title.version_notes.get_child_count() > 0 else ""
	ctx.check("picking an older tab shows its notes (%s)" % shown, shown.begins_with("v" + title.info.versions[-1].id))
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	title._unhandled_input(cancel)
	await _frames(ctx, 1)
	ctx.check("Esc closes the panel and gives the menu back", title.panel == null and title._menu.visible and title.items["versions"].has_focus())

	for key in ["settings", "staff"]:
		title.items[key].pressed.emit()
		await _frames(ctx, 1)
		ctx.check("%s opens a panel" % title.TEXT[key], title.panel != null and title.panel_kind == key)
		title.close_panel()
		await _frames(ctx, 1)

	ctx.check("account entry requires server profile and has no offline button", GameState.has_method("connect_account_profile") and not title._offline_button.visible)
