extends CanvasLayer
signal closed
const Ink := preload("res://client/ink_ui.gd")
const Relics := preload("res://logic/relics.gd")
const GOLD=Color("957d51")
var profile
var session
var _window:Panel
var _slots:HBoxContainer
var _list:GridContainer
var _scroll:ScrollContainer
var _detail_scroll:ScrollContainer
var _preview:TextureRect
var _name:Label
var _description:Label
var _action:Button
var _status:Label
var _close_button:Button
var _selected=""
var _busy=false
var _request=-1

var _showcase
var _title:Label
var _display_name:Label
var _back:Button
var _header_icon:TextureRect
var _small=false
var _card_size=Vector2(140,140)
var _slot_size=90.0

func _plate(colour:Color,border:Color=Ink.BORDER,_radius:int=4)->StyleBox:
	return Ink.plate(colour,border,.7,false,Ink.CLEAR,4)

func _button(button:Button,selected:bool=false,primary:bool=false)->void:
	button.custom_minimum_size=Vector2(48,48)
	if primary:Ink.make_primary(button)
	elif selected:button.add_theme_stylebox_override("normal",Ink.plate(Ink.PANEL,Ink.GOLD,1.0))

func _label(text:String,size:int=17)->Label:
	var label=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Ink.PAPER);return label

func setup(player,authority)->void:
	profile=player;session=authority;layer=55
	var shade=ColorRect.new();shade.color=Color(0,0,0,.65);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	_window=Panel.new();_window.theme=Ink.make_theme();Ink.panel(_window,Ink.window_style());shade.add_child(_window)
	_title=_label("Relic Master",30);_title.add_theme_font_override("font",load("res://art/fonts/Sarabun-SemiBold.woff2"));_window.add_child(_title)
	_header_icon=TextureRect.new();_header_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_header_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_header_icon.texture=load("res://art/relics/goblin/icons/goblin_medallion.png");_window.add_child(_header_icon)
	_close_button=Button.new();Ink.close_button(_close_button);_close_button.pressed.connect(_close);_window.add_child(_close_button)
	var slots_tray=Panel.new();slots_tray.name="SlotsTray";slots_tray.add_theme_stylebox_override("panel",Ink.panel_style());_window.add_child(slots_tray)
	_slots=HBoxContainer.new();_slots.add_theme_constant_override("separation",12);_window.add_child(_slots)
	var owned_tray=Panel.new();owned_tray.name="OwnedTray";owned_tray.add_theme_stylebox_override("panel",Ink.panel_style());_window.add_child(owned_tray)
	_scroll=preload("res://client/skills/touch_scroll.gd").new();_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_window.add_child(_scroll)
	_list=GridContainer.new();_list.columns=2;_list.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;_list.add_theme_constant_override("h_separation",10);_list.add_theme_constant_override("v_separation",10);var collection_margin=MarginContainer.new();collection_margin.name="CollectionMargin";collection_margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_scroll.add_child(collection_margin);collection_margin.add_child(_list)
	var detail=Panel.new();detail.name="Detail";detail.add_theme_stylebox_override("panel",Ink.panel_style());_window.add_child(detail)
	_preview=TextureRect.new();_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;_preview.visible=false;detail.add_child(_preview)
	var display=Panel.new();display.name="Showcase";display.add_theme_stylebox_override("panel",Ink.panel_style());_window.add_child(display)
	_showcase=preload("res://client/relic_ui/showcase.gd").new();display.add_child(_showcase)
	_display_name=_label("",19);_display_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_display_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;display.add_child(_display_name)

	_detail_scroll=preload("res://client/skills/touch_scroll.gd").new();_detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;detail.add_child(_detail_scroll)
	var words=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",3);_detail_scroll.add_child(words)
	_name=_label("เลือก Relic",21);_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;words.add_child(_name)
	_description=_label("แตะรูปไอเทมเพื่อดูรายละเอียด",16);_description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;words.add_child(_description)
	_action=Button.new();_action.text="สวมใส่";_button(_action,false,true);_action.pressed.connect(_activate);_window.add_child(_action)
	_back=Button.new();_back.text="กลับ";_button(_back);_back.pressed.connect(_close);_window.add_child(_back)
	_status=_label("",14);_status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;_window.add_child(_status)
	if session!=null and session.has_signal("ownership_changed"):session.ownership_changed.connect(_render)
	if session!=null and session.has_signal("command_completed"):session.command_completed.connect(_completed)
	get_viewport().size_changed.connect(_fit);_fit();_render()

func _fit()->void:
	var screen=get_viewport().get_visible_rect().size
	_small=screen.y<500
	var margin=20.0 if _small else 36.0
	_window.position=Vector2(margin,margin);_window.size=screen-Vector2.ONE*margin*2
	var w=_window.size.x;var h=_window.size.y;var pad=14.0 if _small else 22.0
	var header=46.0 if _small else 80.0;var footer=52.0 if _small else 66.0
	var gap=8.0 if _small else 14.0;var body=h-header-footer
	var left=floor((w-pad*2-gap)*.38);var right=w-pad*2-gap-left;var x=pad+left+gap
	_title.position=Vector2(pad+(42 if _small else 66),header*.15);_title.add_theme_font_size_override("font_size",24 if _small else 36)
	_header_icon.position=Vector2(pad,header*.14);_header_icon.size=Vector2(34,34) if _small else Vector2(50,50)
	_close_button.position=Vector2(w-44,-10);_close_button.size=Vector2(52,52)
	var display=_window.get_node("Showcase") as Panel;display.position=Vector2(pad,header);display.size=Vector2(left,body)
	_showcase.position=Vector2(8,8);_showcase.size=Vector2(left-16,body-40)
	_display_name.position=Vector2(8,body-33);_display_name.size=Vector2(left-16,25);_display_name.add_theme_font_override("font",load("res://art/fonts/Sarabun-SemiBold.woff2"));_display_name.add_theme_font_override("font",load("res://art/fonts/Sarabun-SemiBold.woff2"));_name.add_theme_font_size_override("font_size",14 if _small else 21)
	_slot_size=floor(minf(body*.28,(right-gap*2)/3));_slots.position=Vector2(x,header);_slots.size=Vector2(right,_slot_size);_slots.alignment=BoxContainer.ALIGNMENT_CENTER
	var cards_height=floor(body*.40);_card_size=Vector2(minf(floor((right-24)/2),floor((cards_height-10)*1.55)),cards_height-10)
	_scroll.position=Vector2(x,header+_slot_size+gap);_scroll.size=Vector2(right,cards_height)
	var slots_tray=_window.get_node("SlotsTray") as Panel;slots_tray.position=_slots.position-Vector2(4,4);slots_tray.size=Vector2(right+8,_slot_size+8)
	var owned_tray=_window.get_node("OwnedTray") as Panel;owned_tray.position=_scroll.position-Vector2(4,4);owned_tray.size=_scroll.size+Vector2(8,4)
	var collection_margin=_scroll.get_node("CollectionMargin") as MarginContainer
	var side_margin=maxi(4,int((right-_card_size.x*2-26)*.5))
	collection_margin.add_theme_constant_override("margin_left",side_margin);collection_margin.add_theme_constant_override("margin_right",side_margin)
	var detail=_window.get_node("Detail") as Panel;detail.position=Vector2(x,_scroll.position.y+cards_height+gap);detail.size=Vector2(right,header+body-detail.position.y)
	_detail_scroll.position=Vector2(12,8);_detail_scroll.size=detail.size-Vector2(24,16)
	_name.visible=not _small;_name.add_theme_font_override("font",load("res://art/fonts/Sarabun-SemiBold.woff2"));_name.add_theme_font_size_override("font_size",17 if _small else 24);_description.add_theme_font_size_override("font_size",14 if _small else 18)
	_action.position=Vector2(w-pad-220 if not _small else w-pad-196,h-footer+8);_action.size=Vector2(140 if not _small else 130,48)
	_back.position=Vector2(_action.position.x+_action.size.x+8,_action.position.y);_back.size=Vector2(72 if not _small else 58,48)
	_status.position=Vector2(pad,h-footer+17);_status.size=Vector2(left,25)
	if profile!=null and _slots.get_child_count()>0:_render()

func _definition(id:String)->Dictionary:
	for entry in profile.relics.owned:
		if str(entry.id)==id:return Relics.catalog().get(entry.relic,{})
	return {}

func _texture(definition:Dictionary)->Texture2D:
	var path=str(definition.get("icon",""))
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null

func _tile(texture:Texture2D,text:String,dimensions:Vector2,selected:bool=false,equipped:bool=false,locked:bool=false)->Button:
	var button=Button.new();_button(button,selected);button.custom_minimum_size=dimensions
	var icon=TextureRect.new();icon.texture=texture;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	button.add_child(icon);icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left=6;icon.offset_right=-6;icon.offset_top=4;icon.offset_bottom=-23 if not text.is_empty() else -7
	if locked:
		var lock=preload("res://client/relic_ui/lock.gd").new();button.add_child(lock);lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);lock.offset_bottom=-18
	if not text.is_empty():
		var label=_label(text,12 if _small else 17);label.add_theme_font_override("font",load("res://art/fonts/Sarabun-SemiBold.woff2"));label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);label.offset_top=-23;label.offset_bottom=-3;label.offset_left=5;label.offset_right=-5
	if equipped:
		var badge=Label.new();badge.text="✓" if _small else "✓ สวมอยู่";badge.add_theme_font_size_override("font_size",12 if _small else 15);badge.add_theme_color_override("font_color",Color("dcefc1"));badge.add_theme_stylebox_override("normal",_plate(Color("365e38"),Color("8aaa5c"),8));badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(badge);badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);badge.offset_left=-26 if _small else -84;badge.offset_top=5;badge.offset_right=-5
	return button

func _render()->void:
	if session!=null and session.profile!=null:profile=session.profile
	for box in [_slots,_list]:
		for child in box.get_children():box.remove_child(child);child.queue_free()
	var worn:String=profile.relics.equipped[0]
	if _definition(_selected).is_empty():_selected=worn
	if _selected.is_empty() and not profile.relics.owned.is_empty():_selected=str(profile.relics.owned[0].id)
	for slot in Relics.SLOT_COUNT:
		var locked=slot>=Relics.UNLOCKED_SLOTS
		var button=_tile(_texture(_definition(worn)) if slot==0 else null,"ยังไม่เปิด" if locked else "" if not worn.is_empty() else "ช่องว่าง",Vector2(_slot_size,_slot_size),slot==0,false,locked)
		button.disabled=locked or _busy
		if not locked:button.pressed.connect(_select.bind(worn))
		_slots.add_child(button)
	for entry in profile.relics.owned:
		var definition=_definition(str(entry.id))
		var button=_tile(_texture(definition),str(definition.get("name",entry.relic)),_card_size,entry.id==_selected,entry.id==worn)
		button.tooltip_text=str(definition.get("name",entry.relic));button.disabled=_busy
		button.pressed.connect(_select.bind(str(entry.id)));_list.add_child(button)
	if profile.relics.owned.is_empty():
		var empty=_label("ยังไม่มี Relic\nค้นหาได้จากบอส",16);_list.add_child(empty)
	var definition=_definition(_selected);_preview.texture=_texture(definition)
	_showcase.show_item(str(definition.get("model","")));_display_name.text=str(definition.get("name","เลือก Relic"))
	_name.text=str(definition.get("name","เลือก Relic"));_description.text=str(definition.get("description","Relic ที่ได้จากบอสจะอยู่ในช่องด้านซ้าย"))
	if _small:
		var effect:Dictionary=definition.get("effect",{})
		if effect.get("kind")=="charged_basic":_description.text="ครบ %d ครั้ง → ครั้งถัดไป +%d%%\nตีปกติ/หนัก · สะสม 1 ชั้น / %s วิ"%[int(effect.get("hits",5)),roundi((float(effect.get("damage_multiplier",1.25))-1)*100),str(float(effect.get("stack_interval_ticks",30))/60)]
		elif effect.get("kind")=="skill_poison":_description.text="ใช้สกิล → ตีใน %s วิ ติดพิษ %d%% ATK / %s วิ\nคูลดาวน์ %s วิ · พิษไม่ซ้อน"%[str(float(effect.get("window_ticks",240))/60),roundi(float(effect.get("total_atk",.3))*100),str(float(effect.get("duration_ticks",180))/60),str(float(effect.get("cooldown_ticks",480))/60)]
	_action.text="กำลังบันทึก…" if _busy else "ถอด Relic" if not _selected.is_empty() and _selected==worn else "สวมใส่"
	_action.disabled=_busy or definition.is_empty()
	_status.text="กำลังบันทึก…" if _busy else "Relic ที่มี · เปิดใช้ 1 / 3 ช่อง"

func _select(id:String)->void:
	if _busy:return
	_selected=id;_render()

func _activate()->void:
	if _selected.is_empty():return
	_submit("" if _selected==str(profile.relics.equipped[0]) else _selected)

func _submit(instance:String)->void:
	if _busy or session==null:return
	var result:Dictionary=session.command({"type":"relic_equip","relic":instance,"slot":0})
	if result.get("pending",false):_busy=true;_request=int(result.id);_render()
	elif result.get("ok",false):_render()
	else:_status.text="เปลี่ยน Relic ไม่สำเร็จ · "+str(result.get("error","unavailable"))

func _completed(id:int,result:Dictionary)->void:
	if id!=_request:return
	_busy=false;_request=-1;_render()
	if not result.get("ok",false):_status.text="เปลี่ยน Relic ไม่สำเร็จ · "+str(result.get("error","unavailable"))

func _close()->void:
	if _busy:return
	closed.emit();queue_free()
