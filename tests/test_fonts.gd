extends RefCounted
## The UI fonts carry Thai, wired through the ink_ui tokens (Boss, 2026-10-12: Sarabun body,
## Taviraj display). Thai renders everywhere, including the web build (the engine default font has
## no Thai, so Thai would otherwise show as boxes — docs/design/ui_style_guide.md section 11).
## This checks that a Thai string, Latin and digits all have glyphs in the body AND the display face
## the screens actually use (InkUi.font() / InkUi.display_font()), not just in the files on disk.

const InkUi := preload("res://client/ink_ui.gd")

## A Thai sample with tone marks and a vowel above (the parts a font without Thai drops).
const THAI := "กระเป๋า ถือดาบ"
const LATIN := "Camp Journey Gold"
const DIGITS := "0123456789"
const PUNCT := "+-%/.,:×"  ## signs the UI shows (gains/losses, sizes, costs)


func run(ctx) -> void:
	InkUi.reset_tokens()  # the live look (D, Night Brass): FONT = Sarabun, DISPLAY_FONT = Taviraj

	# The slots are set (not the engine default, which has no Thai).
	ctx.check("the body font slot (InkUi.FONT) is set", InkUi.FONT != null)
	ctx.check("the display font slot (InkUi.DISPLAY_FONT) is set", InkUi.DISPLAY_FONT != null)

	# The faces the screens use come through the tokens, not a raw load in a screen.
	var body: Font = InkUi.font()
	var display: Font = InkUi.display_font()
	ctx.check("InkUi.font() returns a face", body != null)
	ctx.check("InkUi.display_font() returns a face", display != null)

	# Every character of the Thai sample has a glyph in BOTH faces (Font.has_char per char).
	for face_name in [["body", body], ["display", display]]:
		var label: String = face_name[0]
		var face: Font = face_name[1]
		var missing_thai := _missing(face, THAI)
		ctx.check("Thai '%s' has glyphs in the %s font %s" % [THAI, label, missing_thai], missing_thai.is_empty())
		var missing_latin := _missing(face, LATIN)
		ctx.check("Latin '%s' has glyphs in the %s font %s" % [LATIN, label, missing_latin], missing_latin.is_empty())
		var missing_digits := _missing(face, DIGITS)
		ctx.check("digits have glyphs in the %s font %s" % [label, missing_digits], missing_digits.is_empty())
		var missing_punct := _missing(face, PUNCT)
		ctx.check("UI punctuation has glyphs in the %s font %s" % [label, missing_punct], missing_punct.is_empty())

	# The faces can actually measure a Thai string (a nonzero width: it is laid out, not dropped).
	var w: float = body.get_string_size(THAI, HORIZONTAL_ALIGNMENT_LEFT, -1, InkUi.FONT_BODY).x
	ctx.check("the body font lays out the Thai string (width %.0f > 0)" % w, w > 0.0)
	var wd: float = display.get_string_size("กระเป๋า", HORIZONTAL_ALIGNMENT_LEFT, -1, InkUi.FONT_TITLE).x
	ctx.check("the display font lays out a Thai title (width %.0f > 0)" % wd, wd > 0.0)

	# The engine default has no Thai: this is the problem the fonts solve (guards against a regression
	# where the slots are null again).
	var default_missing := _missing(ThemeDB.fallback_font, THAI)
	ctx.check("the engine default font still lacks Thai (so the UI fonts are needed) %s" % [default_missing], not default_missing.is_empty())

	# A theme that clears the slots falls back to the engine default without erroring (robustness).
	InkUi.apply_tokens({"FONT": null, "DISPLAY_FONT": null})
	ctx.check("clearing the font slots is allowed (engine default)", InkUi.font() == null)
	InkUi.reset_tokens()
	ctx.check("reset_tokens() brings the Thai fonts back", InkUi.FONT != null and InkUi.DISPLAY_FONT != null)


## The characters of `text` (ignoring spaces) that `face` has no glyph for.
func _missing(face: Font, text: String) -> Array:
	var out: Array = []
	for c in text:
		if c == " ":
			continue
		if not face.has_char(c.unicode_at(0)):
			out.append(c)
	return out
