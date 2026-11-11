extends RefCounted
## Small transparent HUD illustration; keeps the original button signal and hit target.
const TEXTURE=preload("res://assets/ui/hub_shortcuts/skill.png")
static func apply(button:Button)->void:
 if button.has_meta("skill_icon_ready"):return
 button.set_meta("skill_icon_ready",true)
 button.text="";button.tooltip_text="Skill";button.custom_minimum_size=Vector2(60,60)
 button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
 var art:=TextureRect.new();art.name="SkillMenuArt";art.texture=TEXTURE;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE
 art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);art.offset_left=3;art.offset_top=1;art.offset_right=-3;art.offset_bottom=-12;button.add_child(art)
 var caption:=Label.new();caption.text="Skill";caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.add_theme_font_size_override("font_size",10);caption.add_theme_color_override("font_color",Color("f1e6c8"));caption.add_theme_color_override("font_outline_color",Color("111e24"));caption.add_theme_constant_override("outline_size",2)
 caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);caption.offset_top=-14;button.add_child(caption)
