extends "res://client/warp_gate_screen.gd"
## Original geography, runtime fog, real input controls; existing journey/farm entry contract.
var _map_panel: Control
var _map_rect: TextureRect
var _detail_box: VBoxContainer
var _map_title: Label
var _goblin: Button
var _orc_locked: Label
var _detail_scroll: ScrollContainer
var _home: Label
var _side_panel: Panel
var _preview: TextureRect
var _private_button: Button
func _fit() -> void:
 if _root == null:return
 _root.scale=Vector2.ONE
 _root.size=get_viewport().get_visible_rect().size
 if _map_panel == null:_build_world()
 var screen=_root.size
 var margin=12.0
 var side=clampf(screen.x*.25,230.0,350.0)
 var area=Vector2(screen.x-side-margin*3,screen.y-margin*2)
 _map_panel.position=Vector2.ONE*margin
 _map_panel.size=area
 _map_rect.position=Vector2(8,8)
 _map_rect.size=area-Vector2(16,16)
 var image_size=Vector2(1672,941)
 var scale_map=minf(_map_rect.size.x/image_size.x,_map_rect.size.y/image_size.y)
 var shown=image_size*scale_map
 var origin=_map_panel.position+Vector2(8,8)+(_map_rect.size-shown)*.5
 _goblin.position=origin+shown*Vector2(.18,.64)-Vector2(75,24)
 _goblin.size=Vector2(150,48)
 _orc_locked.position=origin+shown*Vector2(.43,.36)-Vector2(58,20)
 _home.position=origin+shown*Vector2(.07,.22)
 _side_panel.position=Vector2(screen.x-side-margin,margin)
 _side_panel.size=Vector2(side,screen.y-margin*2)
 _detail_scroll.position=Vector2(screen.x-side-margin+14,margin+48)
 _detail_scroll.size=Vector2(side-28,screen.y-margin*2-128)
 enter_button.position=Vector2(screen.x-side-margin+14,screen.y-margin-70)
 enter_button.size=Vector2(side-28,56)
 if _private_button != null:
  _private_button.position=Vector2(24,screen.y-80)
  _private_button.size=Vector2(minf(area.x-24,290),56)
 _preview.visible=screen.y>=550
 _preview.custom_minimum_size.y=clampf(screen.y*.25,60,180)
 close_button.position=Vector2(screen.x-58,8)
 close_button.size=Vector2(48,48)
 _map_title.position=Vector2(area.x*.34,24)
func _build_world() -> void:
 _map_panel=Panel.new()
 InkUi.panel(_map_panel,InkUi.window_style())
 _root.add_child(_map_panel)
 _map_rect=TextureRect.new()
 _map_rect.texture=load("res://art/ui/world_map/archipelago.png")
 _map_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 _map_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 _map_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var material=ShaderMaterial.new()
 material.shader=load("res://client/world_map.gdshader")
 _map_rect.material=material
 _map_panel.add_child(_map_rect)
 _map_title=Label.new()
 _map_title.text="WORLD MAP\nZone of Relic eXplore"
 _map_title.add_theme_font_size_override("font_size",22)
 _root.add_child(_map_title)
 _goblin=Button.new()
 _goblin.text="◆ GOBLIN BASE"
 _gold_button(_goblin)
 _goblin.custom_minimum_size=Vector2(150,48)
 _goblin.pressed.connect(func(): _play("select"))
 _root.add_child(_goblin)
 _orc_locked=Label.new()
 _orc_locked.text="ORC CAMP
ยังไม่เปิด"
 _orc_locked.add_theme_font_size_override("font_size",15)
 _orc_locked.modulate=Color(.65,.68,.7)
 _root.add_child(_orc_locked)
 _home=Label.new()
 _home.text="◆ คุณอยู่ที่นี่"
 _home.add_theme_font_size_override("font_size",18)
 _root.add_child(_home)
 _side_panel=Panel.new()
 InkUi.panel(_side_panel,InkUi.window_style())
 _root.add_child(_side_panel)
 _destinations["journey"]=_destinations.get("journey",[]).filter(func(row):return row.id=="ink_road")
 _destinations["farm"]=_destinations.get("farm",[]).filter(func(row):return str(row.id).begins_with("goblin_base_") and row.id!="goblin_base_rest")
 _detail_scroll=ScrollContainer.new()
 _detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 _root.add_child(_detail_scroll)
 _detail_box=VBoxContainer.new()
 _detail_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _detail_box.add_theme_constant_override("separation",10)
 _detail_scroll.add_child(_detail_box)
 var heading=Label.new()
 heading.text="GOBLIN BASE"
 heading.add_theme_font_size_override("font_size",24)
 _detail_box.add_child(heading)
 var modes=HBoxContainer.new()
 _detail_box.add_child(modes)
 for kind in ["journey","farm"]:
  var button=Button.new()
  button.text="เดินทาง" if kind=="journey" else "ฟาร์ม"
  button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  _gold_button(button)
  button.pressed.connect(_world_mode.bind(kind))
  modes.add_child(button)
 if GameState.can_preview_mummy():
  var private_button=Button.new()
  private_button.text="ทดสอบพีระมิด · Solo"
  private_button.custom_minimum_size.y=48
  _gold_button(private_button)
  private_button.pressed.connect(func():
   private_button.disabled=true
   GameState.start_mummy_preview()
  )
  _root.add_child(private_button)
  _private_button=private_button
 var description=Label.new()
 description.text="ฐานก็อบลิน · ด้านล่างซ้าย\nเดินทางผ่านฐานไปถึงหัวหน้าก็อบลิน"
 description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 _detail_box.add_child(description)
 _preview=TextureRect.new()
 var atlas=AtlasTexture.new()
 atlas.atlas=_map_rect.texture
 atlas.region=Rect2(10,450,570,360)
 _preview.texture=atlas
 _preview.modulate=Color(.78,.78,.78)
 _preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 _preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 _detail_box.add_child(_preview)
 var picker=OptionButton.new()
 picker.name="Destination"
 picker.custom_minimum_size.y=48
 _detail_box.add_child(picker)
 picker.item_selected.connect(func(index): selected=index)
 message=Label.new()
 message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 message.hide()
 _detail_box.add_child(message)
 enter_button=Button.new()
 enter_button.text="ออกเดินทาง"
 enter_button.custom_minimum_size.y=56
 _gold_button(enter_button)
 enter_button.pressed.connect(enter)
 _root.add_child(enter_button)
 close_button=Button.new()
 InkUi.close_button(close_button)
 close_button.pressed.connect(close)
 _root.add_child(close_button)
 InkUi.npc_help(close_button, "world_map")
 _world_mode("farm" if tab=="farm" else "journey")
func _world_mode(kind: String) -> void:
 tab=kind
 var picker=_detail_box.get_node("Destination") as OptionButton
 picker.clear()
 for destination in destinations():picker.add_item(str(destination.get("name","Goblin Base")))
 selected=0 if picker.item_count>0 else -1
 enter_button.disabled=selected<0

func _gold_button(button: Button) -> void:
 for state in ["normal","hover","pressed","focus"]:
  button.add_theme_stylebox_override(state,InkUi.panel_style())
 button.add_theme_color_override("font_color",InkUi.GOLD)
