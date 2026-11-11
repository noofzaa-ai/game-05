extends RefCounted
## Collision remains owned by the simulation; its debug-style boxes must not cover or duplicate the terrain art.
## On the generated goblin_base maps (tools/maps/build_goblin_base.gd) every solid already has art: solid 0 is the
## floor (the vertex-painted Ground replaces it) and every other solid is enclosed by its crate/stone/log dressing
## (scaled x1.03 around the collider). So StageView builds no collider boxes there at all: each box was two
## hidden draws (box + ink outline pass) and a freshly generated 512x512 noise texture (load time on the web).

static func dressed(map)->bool:
 return str(map.art_scene).begins_with("res://art/maps/goblin_base/")

## Older/unknown builds: hide a generated floor box if one was built anyway.
static func apply(parent:Node3D,map)->void:
 if not dressed(map):return
 for child in parent.get_children():
  if child is MeshInstance3D and child.mesh is BoxMesh:
   var top=child.position.y+child.mesh.size.y*.5
   if absf(top)<.002 and child.mesh.size.x>map.half_width and child.mesh.size.z>map.half_depth:
    child.visible=false;child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
