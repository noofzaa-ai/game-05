extends RefCounted
## Helpers that bring the approved hub look (leather, parchment, ink-brown text, Taviraj / Sarabun) to the screens
## outside the hub: the end-of-run summary, the battle HUD, the online status pill and long names in tiles.
## Every colour, size and word comes from card_tokens.gd (the STRINGS_HUB_LOOK table and the hub tokens).

const CardTokens := preload("res://client/card_tokens.gd")


## A word of STRINGS_HUB_LOOK in the current language.
static func t(key: String) -> String:
	var entry: Array = CardTokens.STRINGS_HUB_LOOK.get(key, [key, key])
	return str(entry[0 if CardTokens.language == "th" else 1])


static func font_of(face: String) -> Font:
	return CardTokens.display_font() if face == "display" else (CardTokens.medium_font() if face == "medium" else CardTokens.body_font())


## Fits `text` into `width` screen px and at most `max_lines` lines (spec §7: shrink, then wrap, never clip):
## 1) one line, shrinking from `size` (reference px at 1080p) down to FONT_MIN; 2) wrapped on words into up to
## `max_lines` lines, again from `size` down to FONT_MIN; 3) at FONT_MIN, the last line ends in "…".
## Returns {"text": the text with its line breaks, "px": font px, "lines": line count}.
static func fit_text(text: String, size: int, width: float, s: float, max_lines: int = CardTokens.FIT_MAX_LINES, face: String = "display") -> Dictionary:
	var font := font_of(face)
	var start := maxi(int(round(size * s)), CardTokens.FONT_MIN)
	if font == null or width <= 0.0:
		return {"text": text, "px": start, "lines": 1}
	for px in range(start, CardTokens.FONT_MIN - 1, -1):
		if _w(font, text, px) <= width:
			return {"text": text, "px": px, "lines": 1}
	for px in range(start, CardTokens.FONT_MIN - 1, -1):
		var lines := _wrap(font, text, px, width)
		if lines.size() <= max_lines:
			return {"text": "\n".join(lines), "px": px, "lines": lines.size()}
	var px := CardTokens.FONT_MIN
	var lines := _wrap(font, text, px, width).slice(0, max_lines)
	var last: String = lines[-1]
	while last.length() > 1 and _w(font, last + "…", px) > width:
		last = last.substr(0, last.length() - 1).strip_edges()
	lines[-1] = last + "…"
	return {"text": "\n".join(lines), "px": px, "lines": lines.size()}


## Sets a Label / Button to the fitted text, styled like hub_text (ink on parchment, or cream with an outline).
## `extra` lines (a price, "Owned 1") are added under the name at the same size, never wrapped.
static func fit(control: Control, text: String, size: int, width: float, color: Color, s: float, max_lines: int = CardTokens.FIT_MAX_LINES, face: String = "display", outline: int = 0, extra: String = "") -> Dictionary:
	var fitted := fit_text(text, size, width, s, max_lines, face)
	if not extra.is_empty():
		var font := font_of(face)
		var px: int = fitted["px"]
		while px > CardTokens.FONT_MIN and font != null and _w(font, extra, px) > width:
			px -= 1
		if px < fitted["px"]:
			fitted = fit_text(text, px, width, 1.0, max_lines, face)
			fitted["px"] = mini(fitted["px"], px)
	CardTokens.style_text(control, fitted["px"], color, 1.0, int(round(outline * s)), face, CardTokens.HUB_OUTLINE)
	control.set("text", str(fitted["text"]) + ("\n" + extra if not extra.is_empty() else ""))
	if control is Button:
		(control as Button).autowrap_mode = TextServer.AUTOWRAP_OFF
		(control as Button).clip_text = true
	elif control is Label:
		(control as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		(control as Label).text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return fitted


## Height in screen px of `lines` lines at `px`.
static func lines_height(lines: int, px: int) -> float:
	return float(lines) * float(px) * CardTokens.FIT_LINE_HEIGHT


static func _w(font: Font, text: String, px: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## Greedy word wrap; a word wider than the line is broken between characters (Thai has no spaces).
static func _wrap(font: Font, text: String, px: int, width: float) -> Array:
	var lines: Array = []
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line.is_empty() else line + " " + word
		if _w(font, trial, px) <= width:
			line = trial
			continue
		if not line.is_empty():
			lines.append(line)
			line = ""
		while _w(font, word, px) > width and word.length() > 1:
			var cut := word.length() - 1
			while cut > 1 and _w(font, word.substr(0, cut), px) > width:
				cut -= 1
			lines.append(word.substr(0, cut))
			word = word.substr(cut)
		line = word
	if not line.is_empty():
		lines.append(line)
	return lines if not lines.is_empty() else [text]


# ------------------------------------------------------------------ leather / parchment boxes
## A leather plate (stitched-leather colour, dark edge, soft drop shadow) in screen px.
static func leather(s: float, radius: float = CardTokens.HUB_RADIUS, line: float = CardTokens.HUB_LINE) -> StyleBox:
	return CardTokens.flat(CardTokens.HUB_LEATHER, CardTokens.HUB_LEATHER_EDGE, line, radius, s, true)


## Parchment inside a leather rim.
static func parchment(s: float, radius: float = CardTokens.HUB_RADIUS * 0.5) -> StyleBox:
	return CardTokens.flat(CardTokens.HUB_PAPER, CardTokens.HUB_PAPER_EDGE, CardTokens.HUB_LINE * 0.5, radius, s)


## The class emblem medallion cut from the class card frame art (the round badge top right), or null.
static func class_emblem(class_id: String) -> Texture2D:
	var frame := CardTokens.tex(CardTokens.HUB_CARD_FRAME_PREFIX + class_id)
	if frame == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = frame
	atlas.region = CardTokens.CARD_FRAME_EMBLEM
	return atlas


## The colour of an item tier on the hub (pips 1..4).
static func tier_color(tier: int) -> Color:
	return CardTokens.HUB_TIER[clampi(tier, 0, CardTokens.HUB_TIER.size() - 1)]
