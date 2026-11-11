extends CanvasLayer
const Ink = preload("res://client/ink_ui.gd")
const Farm = preload("res://logic/farm.gd")
var profile
var authority
var selected := 0
var body: HBoxContainer
var message: Label
var busy := false
var clock := 0.0
func setup(player, session, plot: int) -> void:
 profile=player;authority=session;selected=plot;layer=70
 var root:=PanelContainer.new();add_child(root)
 root.position=Vector2(12,12);root.size=get_viewport().get_visible_rect().size-Vector2(24,24)
 root.theme=Ink.make_theme();Ink.panel(root,Ink.camp_menu_window_style())
 var column:=VBoxContainer.new();root.add_child(column)
 var header:=HBoxContainer.new();column.add_child(header)
 var title:=Ink.label("ฟาร์ม · กองไฟ Lv.2",Ink.GOLD,24);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
 var help:=Button.new();help.text="!";help.custom_minimum_size=Vector2(48,48);header.add_child(help);help.pressed.connect(func():message.text="ซื้อเมล็ด → เลือกปลูก → รอเติบโต → เก็บเกี่ยว · ทำผ่านหน้านี้ทั้งหมด")
 var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(48,48);Ink.close_button(close);header.add_child(close);close.pressed.connect(queue_free)
 body=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(body)
 message=Ink.label("พืชเติบโตต่อแม้ออฟไลน์ · เลือกแปลงเพื่อจัดการ",Ink.GOLD,16);column.add_child(message)
 if authority.has_signal("command_completed"):authority.command_completed.connect(_completed)
 if authority.has_signal("ownership_changed"):authority.ownership_changed.connect(_render)
 get_viewport().size_changed.connect(func():root.size=get_viewport().get_visible_rect().size-Vector2(24,24))
 _render()
func _process(delta:float)->void:
 clock+=delta
 if clock>=1 and is_instance_valid(body):clock=0;_render()
func _button(parent,text:String,action:Callable)->void:
 var b:=Button.new();b.text=text;b.custom_minimum_size=Vector2(0,48);b.disabled=busy;parent.add_child(b);b.pressed.connect(action)
func _render()->void:
 for child in body.get_children():body.remove_child(child);child.queue_free()
 var plots:=GridContainer.new();plots.columns=2;plots.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(plots)
 var data:=Farm.config();var planted:Dictionary=profile.farm.get("plots",{})
 for i in range(4):
  var text:="แปลง %d · ว่าง"%(i+1)
  if planted.has(str(i)):
   var row:Dictionary=planted[str(i)];var crop:Dictionary=data.crops[row.crop]
   var remaining:=maxi(0,int(row.planted_at)+int(crop.seconds)-int(Time.get_unix_time_from_system()))
   text="แปลง %d · %s\n%s"%[i+1,crop.name,"พร้อมเก็บเกี่ยว" if remaining==0 else "เหลือ %d:%02d"%[remaining/60,remaining%60]]
  var b:=Button.new()
  if planted.has(str(i)):
   var crop_id:=str(planted[str(i)].crop)
   b.icon=preload("res://client/farm_crop_sprite.gd").icon(crop_id)
   b.expand_icon=true;b.icon_max_width=48
  b.text=("◆ " if i==selected else "")+text;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.size_flags_vertical=Control.SIZE_EXPAND_FILL;plots.add_child(b);b.pressed.connect(func():selected=i;_render())
 var controls:=VBoxContainer.new();controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(controls)
 controls.add_child(Ink.label("แปลงที่ %d"%(selected+1),Ink.GOLD,22))
 if planted.has(str(selected)):
  var planted_row: Dictionary=planted[str(selected)]
  var crop: Dictionary=data.crops[planted_row.crop]
  var remaining:=maxi(0,int(planted_row.planted_at)+int(crop.seconds)-int(Time.get_unix_time_from_system()))
  controls.add_child(Ink.label(str(crop.name),Ink.GOLD,22))
  if remaining==0:_button(controls,"เก็บเกี่ยว",func():_send({"type":"farm_harvest","plot":selected}))
  else:controls.add_child(Ink.label("กำลังเติบโต · อีก %d:%02d"%[remaining/60,remaining%60],Ink.MUTED,18))
 else:
  for id in data.crops:
   var crop:Dictionary=data.crops[id];var count:=int(profile.farm.get("seeds",{}).get(id,0))
   var row:=HBoxContainer.new();controls.add_child(row)
   var art:=TextureRect.new();art.texture=preload("res://client/farm_crop_sprite.gd").icon(str(id));art.custom_minimum_size=Vector2(40,40);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;row.add_child(art)
   var label:=Ink.label("%s ×%d\n%d นาที"%[crop.name,count,int(crop.seconds)/60],Ink.GOLD,16);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
   _button(row,"ซื้อ %d G"%int(crop.seed_price),func():_send({"type":"farm_seed","plot":selected,"crop":id}))
   if count>0:_button(row,"ปลูก",func():_send({"type":"farm_plant","plot":selected,"crop":id}))
 var total:="ผลผลิต "
 for id in data.crops:total += "%s %d  "%[data.crops[id].name,int(profile.farm.get("produce",{}).get(id,0))]
 var summary:=Ink.label(total,Ink.GOLD,14);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;controls.add_child(summary)
func _send(command:Dictionary)->void:
 if busy:return
 busy=true;_render()
 var result:Dictionary=authority.command(command)
 if not result.get("pending",false):_completed(0,result)
func _completed(_id:int,result:Dictionary)->void:
 busy=false;message.text="เรียบร้อย" if result.get("ok",false) else str(result.get("error","ไม่สำเร็จ"));_render()
