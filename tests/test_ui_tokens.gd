extends RefCounted
## Guards the UI style rule: screens take their colors, font sizes, spacing and style boxes from the
## design tokens in client/ink_ui.gd, so a theme is changed in one place (docs/design/ui_style_guide.md).
## If this fails, a screen set a raw Color, a raw font size or a theme override of its own: use or
## add a token in ink_ui.gd instead. A justified exception is a line ending in "# token-ok: <why>".

const InkUi := preload("res://client/ink_ui.gd")
const UiThemes := preload("res://client/ui_themes.gd")

## The files that own the tokens (everything else in client/ that draws UI is checked).
const TOKEN_FILES := ["ink_ui.gd", "ui_themes.gd", "card_tokens.gd"]
## Screens and UI widgets (plus any client/ file that preloads ink_ui.gd).
const UI_FILES := ["camp_screen.gd", "character_creator.gd", "gear_panel.gd", "hud.gd", "journey_screen.gd", "look_panel.gd",
	"item_cell.gd", "item_text.gd", "item_icon.gd", "perf_overlay.gd", "paper_doll.gd", "hub.gd", "card_deck_screen.gd", "card_portrait.gd", "card_character_screen.gd",
	"hub_item_cell.gd", "hub_item_details.gd", "hub_service_panel.gd", "hub_blacksmith_panel.gd", "hub_storage_panel.gd", "hub_tailor_panel.gd", "hub_shop_panel.gd", "squad_panel.gd", "hub_look.gd"]
## 3D world / lighting lines in UI files are not UI colors: file -> words that mark such a line.
const WORLD_LINES := {
	"hub.gd": ["albedo_color", "light_color", "background_color", "gradient.set_color", "FIRE_COLOR"],
	"paper_doll.gd": ["light_color"],
}
## Files that are mostly the 3D world: only their theme overrides are checked, not every color.
const WORLD_FILES := ["stage_view.gd", "effects.gd", "fighter_view.gd", "stage_props.gd", "atmosphere.gd", "character_model.gd", "ink_style.gd", "exit_portal.gd"]

const RULES := {
	"a theme override (use an InkUi helper)": "add_theme_\\w+_override\\(",
	"a raw Color (use a token)": "Color\\(\\s*-?[0-9.]|Color\\.[A-Z]",
	"a raw font size (use a FONT_ token)": "font_size\\s*=\\s*\\d|text_size\\([^,]+,\\s*\\d|style_text\\([^,]+,[^,]+,\\s*\\d|InkUi\\.label\\([^,]+,[^,]+,\\s*\\d|make_theme\\(\\s*\\d|brush_title\\(.*,\\s*\\d+\\)|_(line|wrapped)\\(.*,\\s*\\d+\\)|_text\\(\\s*\\d",
	"a raw style box (use a named style in InkUi)": "InkUi\\.flat\\(|StyleBoxFlat\\.new\\(",
}


func run(ctx) -> void:
	_check_files(ctx)
	_check_tokens(ctx)
	_check_themes(ctx)


func _check_files(ctx) -> void:
	var regexes := {}
	for rule in RULES:
		var regex := RegEx.new()
		regex.compile(RULES[rule])
		regexes[rule] = regex
	var override_rule := RegEx.new()
	override_rule.compile(RULES["a theme override (use an InkUi helper)"])
	var checked := 0
	for file_name in DirAccess.get_files_at("res://client"):
		if not file_name.ends_with(".gd") or file_name in TOKEN_FILES:
			continue
		var text := FileAccess.get_file_as_string("res://client/" + file_name)
		var is_world: bool = file_name in WORLD_FILES
		var is_ui: bool = (file_name in UI_FILES or "res://client/ink_ui.gd" in text) and not is_world
		if not is_ui and not is_world:
			continue
		checked += 1
		var problems: Array[String] = []
		var number := 0
		for raw_line in text.split("\n"):
			number += 1
			if "token-ok:" in raw_line:
				continue
			var line: String = raw_line.split("#")[0] if not "\"#" in raw_line else raw_line
			if line.strip_edges().is_empty():
				continue
			if is_world and not is_ui:
				if override_rule.search(line) != null:
					problems.append("%d: a theme override" % number)
				continue
			var world_line := false
			for word in WORLD_LINES.get(file_name, []):
				if word in line:
					world_line = true
			for rule in regexes:
				if world_line and rule.begins_with("a raw Color"):
					continue
				if regexes[rule].search(line) != null:
					problems.append("%d: %s" % [number, rule])
		ctx.check("client/%s takes its look from the ink_ui tokens %s" % [file_name, problems], problems.is_empty())
	ctx.check("the UI token check looked at the screens (%d files)" % checked, checked >= UI_FILES.size())


func _check_tokens(ctx) -> void:
	InkUi.reset_tokens()
	var before: Color = InkUi.PAPER
	ctx.check("an unknown token name is refused", not InkUi.apply_tokens({"NOT_A_TOKEN": Color.RED}))
	InkUi.apply_tokens({"PAPER": Color(0.1, 0.2, 0.3), "FONT_BODY": 21})
	var theme := InkUi.make_theme()
	ctx.check("a token change reaches the Theme (label color)", theme.get_color("font_color", "Label") == Color(0.1, 0.2, 0.3))
	ctx.check("a token change reaches the Theme (default size)", theme.default_font_size == 21)
	InkUi.reset_tokens()
	ctx.check("reset_tokens() brings the built-in look back", InkUi.PAPER == before and InkUi.FONT_BODY == 17)
	for key in ["white", "blue", "purple", "gold"]:
		ctx.check("rarity '%s' has a menu and a world color" % key, InkUi.RARITY.has(key) and InkUi.RARITY_WORLD.has(key))
	var tiers: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/rules.json")).get("tiers", [])
	for tier in tiers:
		ctx.check("the tier color key '%s' from rules.json has a rarity token" % str(tier.get("color", "")), InkUi.RARITY.has(str(tier.get("color", ""))))
	for role in ["hp", "bar", "loot", "combo", "skill", "prompt", "help"]:
		ctx.check("HUD text role '%s' has a size" % role, int(InkUi.HUD_FONT.get(role, 0)) > 0)


## Every proposal sets only real tokens, and keeps body and secondary text readable on its panels
## (WCAG contrast 4.5:1 for body text, 3:1 for secondary text and for gains/losses).
func _check_themes(ctx) -> void:
	var tokens: Script = InkUi
	for theme_name in UiThemes.NAMES:
		ctx.check("theme '%s' applies (only known tokens)" % theme_name, UiThemes.apply(theme_name))
		for surface in ["PANEL", "PANEL_LIGHT", "INK"]:
			var back: Color = tokens.get(surface)
			ctx.check("theme '%s': body text on %s >= 4.5:1 (%.1f)" % [theme_name, surface, _contrast(InkUi.PAPER, back)], _contrast(InkUi.PAPER, back) >= 4.5)
			ctx.check("theme '%s': secondary text on %s >= 3:1 (%.1f)" % [theme_name, surface, _contrast(InkUi.MUTED, back)], _contrast(InkUi.MUTED, back) >= 3.0)
		for meaning in ["GOOD", "BAD", "GOLD"]:
			var c := _contrast(tokens.get(meaning), InkUi.PANEL)
			ctx.check("theme '%s': %s on panels >= 3:1 (%.1f)" % [theme_name, meaning, c], c >= 3.0)
	UiThemes.apply("current")
	ctx.check("after the mockups the built-in look (D, Night Brass) is back", InkUi.FONT_BODY == 17 and InkUi.TITLE_STYLE == "engraved" and InkUi.FRAME_STYLE == "engraved" and InkUi.FONT != null and InkUi.DISPLAY_FONT != null)
	_check_icons(ctx)


## The brass icon set: every icon the screens ask for exists and turns into a texture (no image files).
func _check_icons(ctx) -> void:
	var icons: Script = load("res://client/brass_icons.gd")
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/rules.json"))
	var wanted: Array = ["all", "weapon", "armor", "trinket", "material", "gold", "stash", "bag", "guard", "dodge", "special", "ultimate",
		"close", "menu", "back_arrow", "inventory", "look", "repair", "camp", "rest", "combat", "challenge", "treasure", "boss", "journey", "pve", "pvp", "customize"]
	for slot in rules.get("slots", []):
		wanted.append(str(slot["id"]))
	var camp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/camp/camp.json"))
	for id in camp.get("materials", {}):
		wanted.append(str(id))
	var missing: Array = wanted.filter(func(n) -> bool: return not icons.has(n))
	ctx.check("every slot, category, currency, action and tab has a brass icon %s" % [missing], missing.is_empty())
	var tex: Texture2D = icons.texture("ring", 48, InkUi.ICON_TINT)
	ctx.check("an icon becomes a texture of the asked size", tex != null and tex.get_width() == 48)
	var biggest := 0
	for name in icons.ICONS:
		biggest = maxi(biggest, str(icons.ICONS[name]).length())
	ctx.check("each icon stays small (largest %d bytes, under 2 KB)" % biggest, biggest < 2048)


static func _luminance(c: Color) -> float:
	var parts := []
	for v in [c.r, c.g, c.b]:
		parts.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
