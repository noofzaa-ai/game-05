extends RefCounted
## The one icon set of the UI: thin brass line icons, drawn on a 24x24 grid as tiny SVG bodies and
## turned into textures at the size they are shown (Image.load_svg_from_string, cached). No image
## files: the whole set is the text below (about 6 KB). Colors come from the caller (tokens).
## Every icon is original: simple line drawings of the thing it names.
## Use: BrassIcons.texture("gold", 32, InkUi.GOLD) for a Button/TabContainer icon, or
## BrassIcons.draw(canvas, "ring", rect, color) inside a _draw().
## EXTENDING: a new icon is one more entry in ICONS ("{c}" = the icon color, for small filled gems).

## name -> SVG body (strokes; a filled accent uses fill="{c}")
const ICONS := {
	"player_info": "<circle cx='12' cy='7' r='4' fill='{c}'/><path d='M4 22v-3c0-5 3-7 8-7s8 2 8 7v3z' fill='{c}'/>",
	"menu_bold": "<path d='M4 4h16l1 1.5L20 7H4L3 5.5zM4 10.5h16l1 1.5-1 1.5H4L3 12zM4 17h16l1 1.5-1 1.5H4L3 18.5z' fill='{c}'/>",
	"menu_farm": "<path d='M20 3l-2 6-7 7-3-3 7-7z' fill='{c}'/><path d='M6 13l5 5M8 16l-4 4' stroke-width='2.3'/>",
	"menu_pvp": "<path d='M3 3l5 2 11 11-3 3L5 8zM21 3l-2 5L8 19l-3-3L16 5z' fill='{c}'/><path d='M4 14l6 6M14 20l6-6M6 18l-3 3M18 18l3 3' stroke-width='2'/>",
	"menu_camp": "<path d='M12 3L2 21h20zM12 9l-5 12h10z' fill='{c}' fill-rule='evenodd'/><path d='M12 2v19M11 3l7 2-6 2' stroke-width='1.4'/>",
	"menu_customize": "<path d='M8 17v2l-5 3h18l-5-3v-2c3-2 4-5 4-8 0-5-3-7-8-7S4 4 4 9c0 3 1 6 4 8z' fill='{c}'/><path d='M6 9c3 0 5-2 6-4 2 3 4 4 6 4-1 5-2 7-6 7S7 14 6 9z' fill='#102029' stroke='none'/>",
	"menu_fire": "<path d='M12 1c2 5-2 6 0 9 1-3 3-4 3-6 6 8 6 13-3 14C3 17 2 11 8 5c-1 4 0 5 1 6-1-5 4-5 3-10z' fill='{c}'/><path d='M3 19l18 4M3 23l18-4' stroke-width='2.2'/>",
	# Camp-menu additions share the existing brass atlas and never replace older symbols.
	"online": "<circle cx='12' cy='12' r='9'/><ellipse cx='12' cy='12' rx='4' ry='9'/><path d='M3 12h18M5 7h14M5 17h14'/>",
	"feedback": "<path d='M21 11c0 5-4 8-9 8H9l-5 3 1-6a7 7 0 0 1-2-5c0-5 4-8 9-8s9 3 9 8z' fill='{c}'/><circle cx='8' cy='11' r='1' stroke='#102029' fill='#102029'/><circle cx='12' cy='11' r='1' stroke='#102029' fill='#102029'/><circle cx='16' cy='11' r='1' stroke='#102029' fill='#102029'/>",
	"logout": "<path d='M10 4h9v16h-9M13 12H3m5-5-5 5 5 5'/>",
	# --- equipment slots (rules.json "slots")
	"weapon": "<path d='M20 4l-1 4-9 9-3-3 9-9z'/><path d='M6 13l5 5'/><path d='M8 16l-4 4'/>",
	"hat": "<path d='M5 18v-5a7 7 0 0 1 14 0v5z'/><path d='M5 13h14'/><path d='M12 13v5'/><path d='M12 6V3'/>",
	"shirt": "<path d='M8 4l4 2 4-2 4 3-2 4v9H6v-9L4 7z'/><path d='M12 6v14'/><path d='M8 13h8'/>",
	"pants": "<path d='M7 4h10l1 16h-4l-2-10-2 10H6z'/><path d='M7 7h10'/>",
	"armband": "<path d='M8 4h8l1 16H7z'/><path d='M7.5 9h9M7.3 15h9.4'/><path d='M12 10.5l1.5 1.5-1.5 1.5-1.5-1.5z' fill='{c}'/>",
	"shoes": "<path d='M8 3h6v10l6 3v4H5v-4l3-3z'/><path d='M5 18h15'/><path d='M8 8h6'/>",
	"necklace": "<path d='M5 4c0 6 3 9 7 9s7-3 7-9'/><path d='M12 13l3 4-3 4-3-4z'/>",
	"earring": "<circle cx='12' cy='6' r='2.5'/><path d='M12 8.5v3'/><path d='M12 11.5l3 4.5-3 5-3-5z'/>",
	"bracelet": "<ellipse cx='12' cy='13' rx='8' ry='5'/><ellipse cx='12' cy='13' rx='5' ry='2.5'/><path d='M12 6.5l1.5 1.5-1.5 1.5-1.5-1.5z' fill='{c}'/>",
	"ring": "<circle cx='12' cy='15' r='6'/><path d='M9.5 6L12 3l2.5 3-2.5 3z'/>",
	"offhand": "<path d='M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z'/><circle cx='12' cy='11' r='2.5' fill='{c}'/>",
	"back": "<path d='M8 3h8l3 17-3.5-2-3.5 3-3.5-3L5 20z'/><path d='M8 3c1 2 7 2 8 0'/>",
	# --- item categories
	"all": "<path d='M7.5 4l3.5 3.5-3.5 3.5L4 7.5zM16.5 4l3.5 3.5-3.5 3.5-3.5-3.5zM7.5 13l3.5 3.5-3.5 3.5L4 16.5zM16.5 13l3.5 3.5-3.5 3.5-3.5-3.5z'/>",
	"armor": "<path d='M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6z'/><path d='M12 7v10M8 11h8'/>",
	"trinket": "<path d='M12 21L5 9l3-5h8l3 5z'/><path d='M5 9h14M9 9l3 12 3-12M8 4l1 5M16 4l-1 5'/>",
	"material": "<path d='M9 4h6l-1 3 5 5c1 4-1 8-7 8s-8-4-7-8l5-5z'/><path d='M9 7h6'/>",
	# --- currencies and resources (data/camp.json materials)
	"gold": "<circle cx='12' cy='12' r='8'/><circle cx='12' cy='12' r='5.5'/><path d='M12 9.5l2.5 2.5-2.5 2.5-2.5-2.5z' fill='{c}'/>",
	"ore": "<path d='M6 20l-2-8 4-5 3 6z'/><path d='M11 20V9l4-6 4 6v11z'/><path d='M15 3v17'/>",
	"leather": "<path d='M6 4c2 1 4 1 6 0s4-1 6 0c-1 3 0 5 2 7-2 2-3 4-2 7-2-1-4-1-6 0s-4 1-6 0c1-3 0-5-2-7 2-2 3-4 2-7z'/>",
	"essence": "<path d='M12 3c3 4 6 7 6 11a6 6 0 0 1-12 0c0-4 3-7 6-11z'/><path d='M12 11l2 3-2 3-2-3z' fill='{c}'/>",
	"herb": "<path d='M12 21V8'/><path d='M12 13c-5 0-7-3-7-7 4 0 7 2 7 7z'/><path d='M12 10c4 0 6-2 6-6-4 0-6 2-6 6z'/><path d='M12 17c3 0 5-1 6-4-3 0-5 1-6 4z'/>",
	"stash": "<path d='M3 10h18v10H3z'/><path d='M3 10c0-4 4-6 9-6s9 2 9 6'/><path d='M10 12h4v3h-4z'/><path d='M3 14h7M14 14h7'/>",
	"bag": "<path d='M9 4h6l-1 3 5 5c1 4-1 8-7 8s-8-4-7-8l5-5z'/><path d='M9 7h6'/><path d='M9 13h6'/>",
	# --- combat actions (HUD)
	"guard": "<path d='M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6z'/><path d='M12 6.5l5 2v3.5c0 3-2.5 5-5 6-2.5-1-5-3-5-6V8.5z'/>",
	"dodge": "<path d='M4 8h9a3 3 0 1 0-3-3'/><path d='M3 13h15a3 3 0 1 1-3 3'/><path d='M5 18h5'/>",
	"skill": "<path d='M12 2l2.5 6.5L21 9l-5 4.5 1.5 7.5-5.5-4-5.5 4L8 13.5 3 9l6.5-.5z'/>",
	"ultimate": "<path d='M3 8l4 4 5-7 5 7 4-4-2 11H5z'/><path d='M5 19h14'/><path d='M12 12.5l1.5 1.5-1.5 1.5-1.5-1.5z' fill='{c}'/>",
	"enemies": "<path d='M5 4l10 10M19 4L9 14'/><path d='M7 12l5 5M17 12l-5 5'/><path d='M8 17l-3 3M16 17l3 3'/>",
	"heart": "<path d='M12 20s-8-5-8-11a4 4 0 0 1 8-1 4 4 0 0 1 8 1c0 6-8 11-8 11z'/>",
	"stamina": "<path d='M13 2L5 13h6l-1 9 8-11h-6z'/>",
	# --- screens, tabs and buttons
	"menu": "<path d='M5 7h14M5 12h14M5 17h14'/>",
	"close": "<path d='M6 6l12 12M18 6L6 18'/>",
	"back_arrow": "<path d='M15 5l-7 7 7 7'/>",
	"look": "<ellipse cx='12' cy='10' rx='6' ry='7'/><path d='M12 17v4M8 21h8'/><path d='M9 8c1-2 2.5-2.5 4-2.5'/>",
	"repair": "<path d='M14 4l6 6-3 3-6-6z'/><path d='M12.5 8.5L4 17l3 3 8.5-8.5'/>",
	"camp": "<path d='M3 20L12 4l9 16z'/><path d='M12 4v16'/><path d='M9 20l3-6 3 6'/>",
	"rest": "<path d='M12 3c3 3 4 5 4 8a4 4 0 0 1-8 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5 0-7z'/><path d='M5 20l14-4M5 16l14 4'/>",
	"journey": "<circle cx='12' cy='12' r='9'/><path d='M15.5 8.5l-2.5 4.5-4.5 2.5 2.5-4.5z' fill='{c}'/><path d='M12 3v2M12 19v2M3 12h2M19 12h2'/>",
	"challenge": "<path d='M12 3a7 7 0 0 0-7 7c0 3 2 4 2 6v2h10v-2c0-2 2-3 2-6a7 7 0 0 0-7-7z'/><circle cx='9' cy='11' r='1.5' fill='{c}'/><circle cx='15' cy='11' r='1.5' fill='{c}'/><path d='M10 18v3M14 18v3'/>",
}

## Other names that draw an existing icon (screen words -> icon).
const ALIASES := {
	"inventory": "stash", "combat": "weapon", "treasure": "stash", "boss": "ultimate", "special": "skill",
	"pve": "weapon", "pvp": "enemies", "customize": "look", "fists": "weapon",
}

static var _cache := {}


## Whether `name` has an icon (directly or through ALIASES).
static func has(name: String) -> bool:
	return ICONS.has(ALIASES.get(name, name))


## The icon as a texture `px` pixels square, in `color`. `halo` > 0 draws a dark rim under the lines
## first (for icons over the 3D world). `cog` puts it inside a cogwheel (category buttons).
static func texture(name: String, px: int, color: Color, halo: Color = Color(0, 0, 0, 0), cog: bool = false) -> Texture2D:  # token-ok: "no halo"
	var key := "%s|%d|%s|%s|%s" % [name, px, color.to_html(), halo.to_html(), cog]
	if _cache.has(key):
		return _cache[key]
	var body: String = ICONS.get(ALIASES.get(name, name), ICONS["bag"])
	if cog:
		body = _cog_path() + "<g transform='translate(12 12) scale(0.56) translate(-12 -12)'>" + body + "</g>"
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' width='24' height='24'>"
	if halo.a > 0.0:
		svg += _group(body, halo, 3.6)
	svg += _group(body, color, 1.6) + "</svg>"
	var image := Image.new()
	var tex: Texture2D = null
	if image.load_svg_from_string(svg, float(px) / 24.0) == OK:
		tex = ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


## Draws the icon into `rect` on `canvas` (from a _draw()), at the canvas's real pixel size.
static func draw(canvas: CanvasItem, name: String, rect: Rect2, color: Color, halo: Color = Color(0, 0, 0, 0)) -> void:  # token-ok: "no halo"
	var px := int(ceilf(rect.size.x * canvas.get_global_transform_with_canvas().get_scale().x))
	var tex := texture(name, clampi(px, 8, 256), color, halo)
	if tex != null:
		canvas.draw_texture_rect(tex, rect, false)


static func _group(body: String, color: Color, width: float) -> String:
	var hex := "#" + color.to_html(false)
	return "<g fill='none' stroke='%s' stroke-opacity='%.2f' stroke-width='%.1f' stroke-linecap='round' stroke-linejoin='round'>%s</g>" % [
		hex, color.a, width, body.replace("{c}", hex)]


## An 8-tooth cogwheel outline around the 24x24 box.
static func _cog_path() -> String:
	var points := PackedStringArray()
	var teeth := 8
	for i in teeth * 4:
		var angle := TAU * (float(i) - 0.5) / float(teeth * 4)
		var r := 11.2 if (i % 4) in [0, 1] else 9.2
		points.append("%.2f %.2f" % [12.0 + cos(angle) * r, 12.0 + sin(angle) * r])
	return "<path d='M" + " L".join(points) + " Z'/><circle cx='12' cy='12' r='7.6' stroke-opacity='0.5'/>"
