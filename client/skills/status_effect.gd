extends "res://client/skills/mcp_skill_visual.gd"
## Presentation only: status lifetime always comes from the fighter's status snapshot.
@export_enum("burn", "bleed", "freeze", "chill", "shock", "stun") var status: String="burn"
var _body_size:=Vector2(-1,-1)

func fit_body(height: float,width: float) -> void:
 var size:=Vector2(clampf(height,.4,8.0),clampf(width,.3,6.0))
 if _body_size.is_equal_approx(size):return
 _body_size=size
 var horizontal:=clampf(size.y/.8,.45,4.0)
 var vertical:=clampf(size.x/1.8,.25,4.5)
 axis_scale=Vector3(horizontal,vertical,horizontal)*3.0
 visual_offset=Vector3.ZERO
 match status:
  "bleed":
   axis_scale*=Vector3(.45,.22,.45);visual_offset=Vector3(0,height*.3,width*.9+.2)
  "freeze":axis_scale*=Vector3(.3,.75,.3)
  "chill":axis_scale*=Vector3(.5,.65,.5);visual_offset.z=width*.3
  "shock":
   axis_scale*=Vector3(.75,.5,.75);visual_offset=Vector3(0,height*.1,width*.5)
  "stun":
   visual_offset.y=height+.2
   axis_scale=Vector3.ONE*clampf(width/.8,.6,1.6)*2.5
 if visual!=null:
  visual.scale=axis_scale;visual.position=visual_offset

func play_effect() -> void:
 asset_path="res://art/skill_system/status_vfx/"+status+"/effect.glb"
 preserve_materials=true
 effect_phase="persistent"
 super.play_effect()

func _style_frame(mesh: Mesh,original: Material,modes: Dictionary) -> Dictionary:
 var result:=super._style_frame(mesh,original,modes)
 if not original is BaseMaterial3D:return result
 var key:=str(original.get_instance_id())
 if not _style_cache.has(key):
  var material:=original.duplicate() as BaseMaterial3D
  if status!="freeze":
   material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
   material.billboard_keep_scale=true
  if status=="chill":material.albedo_color.a=minf(1.0,material.albedo_color.a*1.9)
  if status=="freeze":
   material.albedo_color=material.albedo_color*Color(.65,.85,1,1)
   material.emission_energy_multiplier*=.5
  _style_cache[key]=material
 result.material=_style_cache[key]
 return result
