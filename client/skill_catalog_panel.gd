extends CanvasLayer
## Merchant reference catalog. Unlock-all is authority content policy, not repeated item grants.
const Ink := preload("res://client/ink_ui.gd")
const Build := preload("res://logic/skill_build.gd")
var _window: PanelContainer
var _grid: GridContainer
var _detail: Label
var _gems := false

func _ready() -> void:
 layer=70
 var root:=Control.new();root.theme=Ink.make_theme();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(root)
 var shade:=ColorRect.new();shade.color=Ink.SCRIM;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(shade)
 _window=PanelContainer.new();Ink.panel(_window,Ink.camp_menu_window_style());root.add_child(_window)
 var content:=VBoxContainer.new();_window.add_child(content)
 var header:=HBoxContainer.new();content.add_child(header)
 var title:=Ink.label("Merchant · คลังสกิลและ Gem",Ink.GOLD,Ink.FONT_HEADING);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
 var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(52,48);Ink.close_button(close);close.pressed.connect(queue_free);header.add_child(close)
 var tabs:=HBoxContainer.new();content.add_child(tabs)
 for kind in ["สกิล 20","Gem 20"]:
  var button:=Button.new();button.text=kind;button.custom_minimum_size=Vector2(140,48);tabs.add_child(button);button.pressed.connect(func():_gems=kind=="Gem 20";_render())
 var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(scroll)
 _grid=GridContainer.new();_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(_grid)
 _detail=Ink.label("ปลดล็อกทั้งหมดแล้ว · จัดสกิล/Gem ได้ที่เมนู Skill ในแคมป์",Ink.MUTED,Ink.FONT_SMALL);_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(_detail)
 get_viewport().size_changed.connect(_fit);_fit();_render()

func _fit() -> void:
 var size:=get_viewport().get_visible_rect().size
 _window.position=Vector2(20,20);_window.size=size-Vector2(40,40)
 _grid.columns=maxi(2,floori((size.x-80)/155.0))

func _render() -> void:
 for child in _grid.get_children():_grid.remove_child(child);child.queue_free()
 var ids: Array=JSON.parse_string(FileAccess.get_file_as_string(Build.ROOT+"catalog.json")) if not _gems else ["wide","dense","remote","echo","multishot","chain","pierce","knockback","charge","quickcast","quickcd","longer","ignite","bleed","chill","shock","stun","leech","thorns","regen"]
 var kind: String="gems" if _gems else "skills"
 for id in ids:
  var resource=load(Build.ROOT+kind+"/"+id+".tres")
  var button:=Button.new();button.custom_minimum_size=Vector2(145,76);button.text=resource.display_name;button.expand_icon=true;button.add_theme_constant_override("icon_max_width",48)
  var path: String="res://art/ui/skills/128/"+kind+"/"+id+".png"
  if ResourceLoader.exists(path):button.icon=load(path)
  _grid.add_child(button)
  button.pressed.connect(func():
   _detail.text=resource.display_name+" · ปลดล็อกแล้ว · "+("ช่อง "+resource.slot if _gems else "ร่าย %.2fs / คูลดาวน์ %.2fs / สตามินา %d"%[resource.base_stats.get("cast_time",0),resource.base_stats.get("cooldown",0),Build.config().stamina.get(id,0)]))
