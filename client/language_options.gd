extends RefCounted
## Description language (Boss 2026-11-25): "en" or "th", device-local (user://language.cfg, like graphics_options.gd).
## NARROW scope: only descriptive text follows it (skill / skill-tree / race passive + ultimate descriptions, combo
## state names, payoff effects and the "works with" line, item set / relic / boss option text, quest descriptions).
## Menus, buttons, tabs, titles, HUD labels and proper names (skills, items, monsters) stay English: they read
## CardTokens.language, which this setting never changes. Read through CardTokens.desc_language() / CardTokens.desc().
## A change applies to what is drawn next (a screen redraws its text when it is opened or refreshed); `revision`
## goes up so an open screen can poll it.
const PATH := "user://language.cfg"
const LANGUAGES := ["en", "th"]
const DEFAULT := "en"
static var revision := 0
static var _loaded := false
static var _value := DEFAULT


static func value() -> String:
	if not _loaded:
		_loaded = true
		_value = DEFAULT
		var config := ConfigFile.new()
		if config.load(PATH) == OK:
			var saved := str(config.get_value("language", "descriptions", DEFAULT))
			if saved in LANGUAGES:
				_value = saved
	return _value


static func set_value(language: String) -> void:
	if not language in LANGUAGES:
		return
	value()
	_value = language
	revision += 1
	var config := ConfigFile.new()
	config.set_value("language", "descriptions", language)
	config.save(PATH)


## Test hook: forget the cached value (the next read loads PATH again).
static func reload_settings() -> void:
	_loaded = false
	revision += 1
