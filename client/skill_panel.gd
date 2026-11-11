extends VBoxContainer
## Draft editing only. Gold and build changes commit through the existing authoritative command path.
const Ink := preload("res://client/ink_ui.gd")
const Build := preload("res://logic/skill_build.gd")
var profile
var session
var draft: Dictionary = {}
var tree: ZorxPassiveTreeData
var _body: VBoxContainer
var _tabs: HBoxContainer
var _page := 0
var _status: Label
var _save: Button
var _reset: Button
var _busy := false
var _request := -1
var _confirm_reset := false
var _catalog: Array = []
var _active_slot := 0
var _node_id := ""
var _tree_view: Control
var _node_detail: Label
var _allocate: Button
var _tree_zoom := 1.0
var _tree_pan := Vector2.ZERO
var _gem_scroll_position:=0
var _gem_picker: Control
var _gem_list: ScrollContainer

func setup(player, authority) -> void:
 profile=player;session=authority
 tree=load(Build.ROOT+"tree/full_tree.tres").duplicate(true);tree.build()
 _catalog=JSON.parse_string(FileAccess.get_file_as_string(Build.ROOT+"catalog.json"))
 size_flags_vertical=Control.SIZE_EXPAND_FILL
 var intro:=Ink.label("Skill · ปลดล็อกสกิลและ Gem ทั้งหมด · จัด Build ได้เฉพาะแคมป์",Ink.GOLD,Ink.FONT_SMALL)
 intro.visible=get_viewport().get_visible_rect().size.y>=560
 intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(intro)
 _tabs=HBoxContainer.new();add_child(_tabs)
 for title in ["Skill Tree","สกิล / Gem"]:
  var button:=Button.new();button.text=title;button.custom_minimum_size=Vector2(150,48);_tabs.add_child(button)
  button.pressed.connect(func():_page=0 if title=="Skill Tree" else 1;_render())
 _body=VBoxContainer.new();_body.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(_body)
 var footer:=HBoxContainer.new();add_child(footer)
 _status=Ink.label("",Ink.MUTED,Ink.FONT_SMALL);_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;footer.add_child(_status)
 _reset=Button.new();_reset.custom_minimum_size=Vector2(180,48);_reset.pressed.connect(_reset_pressed);footer.add_child(_reset)
 _save=Button.new();_save.text="บันทึก Build";_save.custom_minimum_size=Vector2(140,48);_save.pressed.connect(func():_submit("save",draft));footer.add_child(_save)
 if session!=null and session.has_signal("command_completed"):session.command_completed.connect(_completed)
 if session!=null and session.has_signal("ownership_changed"):session.ownership_changed.connect(refresh_weapon)
 _reload()

func refresh_weapon() -> void:
 if _busy or Build.has_allocated_passives(profile.skill_build):return
 var weapon=profile.loadout.item_at("weapon",0)
 var start:=Build.start_for(weapon.weapon_type if weapon!=null else "")
 if draft.get("start","")!=start:_reload()

func _reload() -> void:
 profile=session.profile if session!=null else profile
 draft=profile.skill_build.duplicate(true)
 if draft.is_empty():draft=Build.initial("")
 if str(draft.get("start","")).is_empty():
  var weapon=profile.loadout.item_at("weapon",0)
  draft.start=Build.start_for(weapon.weapon_type if weapon!=null else "")
  draft.allocated=["start_"+draft.start] if not draft.start.is_empty() else []
 _render()

func _scroll(parent: Control) -> VBoxContainer:
 var scroll:=preload("res://client/skills/touch_scroll.gd").new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(scroll)
 Ink.inventory_scrollbar(scroll.get_v_scroll_bar(),true)
 var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(box);return box

func _render() -> void:
 if is_instance_valid(_gem_picker):_close_gem_picker()
 if _body.get_child_count()>0 and _body.get_child(0) is ScrollContainer:_gem_scroll_position=_body.get_child(0).scroll_vertical
 if is_instance_valid(_tree_view) and _tree_view.is_inside_tree():
  _tree_zoom=_tree_view.zoom;_tree_pan=_tree_view.pan
 for child in _tabs.get_children().slice(2):
  _tabs.remove_child(child);child.queue_free()
 for child in _body.get_children():_body.remove_child(child);child.queue_free()
 _reset.text=("ยืนยันคืนทั้งหมด" if _confirm_reset else "รีสกิล %d Gold"%int(Build.config().reskill_gold))
 _reset.tooltip_text="Gold ที่มี %d · คืนแต้มที่บันทึกแล้วทั้งหมด" % profile.stash.gold
 _reset.disabled=_busy
 _save.disabled=_busy or not Build.validate(draft).is_empty() or not Build.enabled()
 if _page==0:
  _render_tree()
  return
 var left:=_scroll(_body)
 _restore_gem_scroll(left.get_parent(),_gem_scroll_position)
 left.add_child(Ink.label("สกิล 4 ช่อง · "+str(draft.start),Ink.GOLD,Ink.FONT_HEADING))
 for slot in range(4):
  var line:=HBoxContainer.new();left.add_child(line)
  var marker:=Button.new();marker.text=str(slot+1);marker.custom_minimum_size=Vector2(48,48);marker.pressed.connect(func():_active_slot=slot;_render());line.add_child(marker)
  var select:=OptionButton.new();select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;select.custom_minimum_size.y=48;select.expand_icon=true;select.add_theme_constant_override("icon_max_width",32);line.add_child(select)
  var groups: Array=JSON.parse_string(FileAccess.get_file_as_string(Build.ROOT+"ui_groups.json"))
  for group in groups:
   select.add_separator(str(group.name))
   for id in group.skills:
    if id not in _catalog:continue
    var skill: ZorxSkillData=load(Build.ROOT+"skills/"+id+".tres")
    select.add_icon_item(_icon("skills",id),skill.display_name)
    var index:=select.item_count-1
    select.set_item_metadata(index,id)
    if draft.skills[slot].skill==id:select.select(index)
  select.get_popup().max_size=Vector2i(440,260)
  select.disabled=_busy
  select.item_selected.connect(func(index: int):draft.skills[slot]={"skill":select.get_item_metadata(index),"shape":"","effect":""};_active_slot=slot;_render.call_deferred())
  for kind in ["shape","effect"]:
   var socket:=Button.new();socket.custom_minimum_size=Vector2(48,48);socket.expand_icon=true;socket.add_theme_constant_override("icon_max_width",32)
   var gem_id: String=draft.skills[slot][kind]
   socket.icon=_icon("gems_"+kind,gem_id) if not gem_id.is_empty() else null
   socket.text="+" if gem_id.is_empty() else "";socket.tooltip_text=kind+" Gem · ช่อง %d"%[slot+1];line.add_child(socket)
   socket.pressed.connect(func():_active_slot=slot;_render.call_deferred())
 var row: Dictionary=draft.skills[_active_slot]
 var skill: ZorxSkillData=load(Build.ROOT+"skills/"+row.skill+".tres")
 left.add_child(Ink.label("Gem · ช่อง %d · %s"%[_active_slot+1,skill.display_name],Ink.GOLD,Ink.FONT_SMALL))
 for kind in ["shape","effect"]:
  var select:=Button.new();select.custom_minimum_size.y=48;select.expand_icon=true;select.add_theme_constant_override("icon_max_width",32);left.add_child(select)
  var gem_id: String=row[kind]
  select.text=kind+" · ไม่ใส่" if gem_id.is_empty() else load(Build.ROOT+"gems/"+gem_id+".tres").display_name
  select.icon=_icon("gems_"+kind,gem_id) if not gem_id.is_empty() else null
  select.disabled=_busy
  select.pressed.connect(_open_gem_picker.bind(kind,skill))
 var stats:=Build.calculate(draft,_active_slot)
 if not stats.has("error"):
  var details:=Ink.label("ร่าย %.2fs · คูลดาวน์ %.2fs · สตามินา %d\nสถานะ: %s"%[stats.cast_time,stats.cooldown,int(Build.config().stamina.get(row.skill,0)),", ".join(stats.statuses)],Ink.MUTED,Ink.FONT_SMALL);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;left.add_child(details)

func _restore_gem_scroll(scroll: ScrollContainer,value: int)->void:
 for i in range(2):await get_tree().process_frame
 if is_instance_valid(scroll):scroll.scroll_vertical=value

func _close_gem_picker()->void:
 if is_instance_valid(_gem_picker):_gem_picker.queue_free()
 _gem_picker=null;_gem_list=null
 if _body.get_child_count()>0:_body.get_child(0).set_process_input(true)

func _open_gem_picker(kind: String,skill: ZorxSkillData)->void:
 _close_gem_picker()
 _body.get_child(0).set_process_input(false)
 var layer:=CanvasLayer.new();layer.layer=75;add_child(layer)
 var screen:=Control.new();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.theme=Ink.make_theme();layer.add_child(screen)
 _gem_picker=screen
 screen.tree_exited.connect(layer.queue_free)
 var shade:=ColorRect.new();shade.color=Ink.SCRIM;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.add_child(shade)
 var window:=PanelContainer.new();Ink.panel(window,Ink.camp_menu_window_style());screen.add_child(window)
 var area:=get_viewport().get_visible_rect().size
 window.size=Vector2(minf(560,area.x-24),area.y-24);window.position=(area-window.size)*.5
 var content:=VBoxContainer.new();window.add_child(content)
 var header:=HBoxContainer.new();content.add_child(header)
 var title:=Ink.label("Gem · "+kind,Ink.GOLD,Ink.FONT_SMALL);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
 var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(48,48);Ink.close_button(close);header.add_child(close);close.pressed.connect(_close_gem_picker)
 var entries:=_scroll(content);_gem_list=entries.get_parent()
 var ids: Array=[""]
 ids.append_array(["wide","dense","remote","echo","multishot","chain","pierce","knockback","charge","quickcast","quickcd","longer"] if kind=="shape" else ["ignite","bleed","chill","shock","stun","leech","thorns","regen"])
 for id in ids:
  var button:=Button.new();button.custom_minimum_size.y=48;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.expand_icon=true;button.clip_text=true;button.add_theme_constant_override("icon_max_width",28);entries.add_child(button)
  button.text="ไม่ใส่"
  if not str(id).is_empty():
   var gem: ZorxGemData=load(Build.ROOT+"gems/"+id+".tres")
   var problem:=ZorxBuildCalc.can_equip(skill,gem,kind)
   button.text=gem.display_name+(" · "+problem if not problem.is_empty() else "");button.disabled=not problem.is_empty();button.icon=_icon("gems_"+kind,id)
  button.set_meta("gem_id",id)
  button.tooltip_text=button.text
  button.pressed.connect(func():draft.skills[_active_slot][kind]=id;_close_gem_picker();_render.call_deferred())

func _render_tree() -> void:
 var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.size_flags_stretch_ratio=1.15;_body.add_child(column)
 var bar:=HBoxContainer.new();_tabs.add_child(bar)
 bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 var title:=Ink.label("%d / %d"%[maxi(0,draft.allocated.size()-1),int(Build.config().max_points)],Ink.GOLD,Ink.FONT_SMALL);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.add_child(title)
 for caption in ["−","+","Fit"]:
  var button:=Button.new();button.text=caption;button.custom_minimum_size=Vector2(48,44);bar.add_child(button)
  button.pressed.connect(func():
   if caption=="Fit":_tree_view.reset_view()
   else:_tree_view.magnify(1.25 if caption=="+" else .8))
 _tree_view=preload("res://client/skills/tree_canvas.gd").new();_tree_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;_tree_view.clip_contents=true;column.add_child(_tree_view);_tree_view.setup(tree,draft.allocated);_tree_view.focused=_node_id;_tree_view.zoom=_tree_zoom;_tree_view.pan=_tree_pan
 _tree_view.selected.connect(func(id: String):_node_id=id;_describe_node())
 var node_row:=HBoxContainer.new();column.add_child(node_row)
 _node_detail=Ink.label("แตะโหนดเพื่อดูรายละเอียด · ลากเพื่อเลื่อน / + − เพื่อซูม",Ink.MUTED,Ink.FONT_SMALL);_node_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_node_detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_node_detail.custom_minimum_size.y=44;node_row.add_child(_node_detail)
 _allocate=Button.new();_allocate.text="เลือกโหนด";_allocate.custom_minimum_size=Vector2(180,44);node_row.add_child(_allocate)
 _allocate.pressed.connect(func():
  if _node_id.is_empty():return
  var state:=_tree_state()
  if ZorxBuildCalc.can_allocate(tree,state,_node_id).is_empty():draft.allocated.append(_node_id);_status.text="มีการเปลี่ยนแปลง · กดบันทึก Build";_render.call_deferred())
 _describe_node()

func _tree_state() -> ZorxRunState:
 var state:=ZorxRunState.new();state.allocated.assign(draft.allocated);state.points=int(Build.config().max_points)-maxi(0,draft.allocated.size()-1);return state

func _describe_node() -> void:
 _allocate.disabled=true
 if not tree.by_id.has(_node_id):return
 var node: ZorxTreeNodeData=tree.by_id[_node_id]
 _node_detail.text=node.display_name+" · "+node.description
 var owned: bool=_node_id in draft.allocated
 _allocate.text="ปลดล็อกแล้ว" if owned else "ใช้ 1 แต้ม · ปลดล็อก"
 var problem:=ZorxBuildCalc.can_allocate(tree,_tree_state(),_node_id)
 _allocate.disabled=_busy or owned or not problem.is_empty()
 if not owned and not problem.is_empty(): _node_detail.text+="\n"+problem

var _small_icons: Dictionary = {}
func _icon(kind: String,id: String) -> Texture2D:
 var path: String="res://art/ui/skills/128/"+kind+"/"+id+".png"
 if _small_icons.has(path):return _small_icons[path]
 if not ResourceLoader.exists(path):return null
 var texture: Texture2D=load(path)
 var image:=texture.get_image()
 image.resize(28,28,Image.INTERPOLATE_LANCZOS)
 var small:=ImageTexture.create_from_image(image)
 _small_icons[path]=small
 return small

func _reset_pressed() -> void:
 if profile.skill_build.get("start","").is_empty():
  _confirm_reset=false;_reload();_status.text="ยังไม่ได้บันทึก Tree · คืนแต้มร่างแล้ว (ไม่หัก Gold)";return
 if not _confirm_reset:_confirm_reset=true;_reset.text="ยืนยันคืนทั้งหมด";return
 _confirm_reset=false;_submit("reset",{})

func _submit(action: String, value: Dictionary) -> void:
 if _busy or session==null:return
 _request=-1
 _busy=true;_status.text="กำลังบันทึกกับเซิร์ฟเวอร์…";_render()
 var result: Dictionary=session.command({"type":"skill_build","action":action,"build":value.duplicate(true)})
 if result.get("pending",false):_request=int(result.id)
 else:_completed(-1,result)

func _completed(id: int,result: Dictionary) -> void:
 if not _busy or id!=_request:return
 _busy=false;_request=-1
 _status.text="บันทึกแล้ว" if result.get("ok",false) else str(result.get("reason",result.get("error","unavailable")))
 _reload()
