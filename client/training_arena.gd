extends Node3D
const Rules=preload("res://logic/training_ground.gd")
const Ink=preload("res://client/ink_ui.gd")
var session
var player:Node3D
var views:Dictionary={}
var _presenter:Node3D
var _ranged:Node3D
var _numbers:Node2D
var _hud:CanvasLayer
var _layer:CanvasLayer
var _status:Label
var _hint:Label3D
var _was_enabled:=false
var _yard_surfaces:Dictionary={}
func setup(training,looks:Dictionary)->void:
 session=training
 _build_yard()
 for index in Rules.DUMMY_IDS.size():
  var id:int=Rules.DUMMY_IDS[index]
  var dummy=preload("res://client/training_dummy.gd").new();dummy.position=Rules.dummy_position(index);add_child(dummy);views[id]=dummy
 player=preload("res://client/fighter_view.gd").new();player.model_path="res://art/characters/studio05/our_character_lowpoly_toon_hair_a_5k.glb";player.looks=looks;add_child(player);views[1]=player;player.hide()
 _presenter=preload("res://client/skills/presenter.gd").new();add_child(_presenter)
 _ranged=preload("res://client/projectile_view.gd").new();add_child(_ranged)
 _hud=preload("res://client/skills/skill_hud.gd").new();add_child(_hud);_hud.hide()
 _layer=CanvasLayer.new();_layer.layer=28;add_child(_layer)
 var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.theme=Ink.make_theme();_layer.add_child(root)
 var bar:=HBoxContainer.new();bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);bar.position=Vector2(-230,38);bar.size=Vector2(460,44);root.add_child(bar)
 _status=Ink.label("TRAINING",Ink.GOLD,16);_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.add_child(_status)
 var reset:=Button.new();reset.text="Reset";reset.custom_minimum_size=Vector2(80,44);bar.add_child(reset);reset.pressed.connect(func():session.reset())
 var build:=Button.new();build.text="Build";build.custom_minimum_size=Vector2(70,44);bar.add_child(build);build.pressed.connect(func():get_parent()._open_camp(4))
 _numbers=preload("res://client/combat_numbers.gd").new();_layer.add_child(_numbers);_layer.hide()
func refresh(looks:Dictionary)->void:
 if is_instance_valid(player):player.set_looks(looks)
func update()->void:
 var enabled:bool=session.enabled
 player.visible=enabled;_hud.visible=enabled;_layer.visible=enabled
 if enabled:
  player.show_state(session.sim.bodies[1],session.sim.fighters[1],session.sim.combat)
  _hud.update_from(session.sim.fighters[1])
  _status.text="TRAINING · %d hits · %.0f dmg"%[session.hits,session.damage] if session.sim.skill_system!=null else "TRAINING · Set weapon / Build"
 for event in session.sim.events:
  if event.type=="skill_visual":_presenter.event(event)
  if event.type in ["hit","skill_hit","skill_dot","dot"] and views.has(int(event.get("target",-1))):
   var id:int=event.target
   if id in Rules.DUMMY_IDS:
    views[id].flash();_numbers.show_amount(session.sim.bodies[id].position,int(ceilf(event.get("damage",0))),1 if event.get("crit",false) else 0)
 _presenter.update_from(session.sim.fighters,session.sim.bodies,views)
 _ranged.show_state(session.sim)
 _was_enabled=enabled
func _box(at:Vector3,size:Vector3,color:Color)->void:
 var key:=color.to_html()+str(size.y<.15)
 if not _yard_surfaces.has(key):
  var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
  _yard_surfaces[key]={"surface":surface,"color":color,"flat":size.y<.15}
 var box:=BoxMesh.new();box.size=size
 _yard_surfaces[key].surface.append_from(box,0,Transform3D(Basis.IDENTITY,at))
func _finish_yard()->void:
 for entry in _yard_surfaces.values():
  var mesh:=MeshInstance3D.new();mesh.mesh=entry.surface.commit()
  var mat:=StandardMaterial3D.new();mat.albedo_color=entry.color;mat.roughness=1
  if entry.flat:mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  mesh.material_override=mat;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mesh)
 _yard_surfaces.clear()
func _build_yard()->void:
 # Muted forest soil, continuous with the camp rather than a yellow arena mat.
 _box(Rules.CENTER+Vector3(0,-.045,0),Vector3(14,.12,13),Color("283a33"))
 for index in range(22):
  var patch:=MeshInstance3D.new();var disk:=CylinderMesh.new();disk.top_radius=.25+fmod(index*.17,.6);disk.bottom_radius=disk.top_radius;disk.height=.008;disk.radial_segments=7;patch.mesh=disk
  patch.position=Rules.CENTER+Vector3(sin(index*4.3)*6,.026,cos(index*2.7)*5.4)
  var soil:=StandardMaterial3D.new();soil.albedo_color=Color("2d3e36") if index%2==0 else Color("25352f");soil.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;patch.material_override=soil;patch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(patch)
 # East entrance connects directly to the existing quest-board path.
 _box(Vector3(-10.5,-.01,5.8),Vector3(3,.03,1.8),Color("34423a"))
 preload("res://client/modular_fence.gd").build(self,preload("res://client/modular_fence.gd").training_segments())
 # Entrance threshold and modest sign; no wall across the walking path.
 _box(Vector3(-11,.02,5.8),Vector3(.07,.03,1.8),Color("526158"))
 _box(Vector3(-11.3,.7,4.6),Vector3(.14,1.4,.14),Color("65503b"))
 _box(Vector3(-11.3,1.3,4.6),Vector3(1.3,.4,.12),Color("65503b"))
 _hint=Label3D.new();_hint.text="TRAINING ←";_hint.font_size=32;_hint.pixel_size=.01;_hint.position=Vector3(-11.3,1.3,4.68);_hint.modulate=Ink.GOLD;add_child(_hint)
 for x in [-23.7,-12.3]:
  _box(Vector3(x,.8,10.3),Vector3(.16,1.6,.16),Color("65503b"))
  _box(Vector3(x,1.7,10.3),Vector3(.3,.4,.3),Color("f2bb65"))
  var light:=OmniLight3D.new();light.position=Vector3(x,2,10.3);light.light_color=Color("ffbd77");light.light_energy=1.5;light.omni_range=9;light.shadow_enabled=false;add_child(light)
 _finish_yard()
