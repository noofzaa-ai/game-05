extends Node3D
## Native parametric VFX library: one recipe per skill, reused by Gem instances.
@export var profile: String = "burst"
@export var tint: Color = Color.CYAN
@export var number: int = 1
var autoplay: bool = false
var loop_effect: bool = false
var free_on_finish: bool = true
var age: float = 0.0
var playing: bool = false
var pieces: Array[Node3D] = []
var materials: Array[StandardMaterial3D] = []
var effect_phase: String = "impact"
var beam_jitter: float=.2
var endpoint: Vector3 = Vector3.ZERO

func play_effect() -> void:
 for child in get_children(): child.queue_free()
 pieces.clear()
 materials.clear()
 age = 0.0
 playing = true
 var material := StandardMaterial3D.new()
 material.albedo_color = tint
 material.emission_enabled = true
 material.emission = tint
 material.emission_energy_multiplier = 1.8
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 materials.append(material)
 if effect_phase=="beam" or profile=="lightning":
  var end:=endpoint if effect_phase=="beam" else Vector3(0,6,0)
  var previous:=Vector3.ZERO
  for i in range(1,9):
   var point:=end*float(i)/8.0
   if i<8: point+=Vector3(sin(float(i)*2.7)*beam_jitter,0,cos(float(i)*2.1)*beam_jitter*.75)
   var segment:=CylinderMesh.new()
   segment.top_radius=.035
   segment.bottom_radius=.06
   segment.height=previous.distance_to(point)
   segment.radial_segments=5
   var stroke:=MeshInstance3D.new()
   stroke.mesh=segment
   stroke.material_override=material
   stroke.position=(previous+point)*.5
   stroke.quaternion=Quaternion(Vector3.UP,(point-previous).normalized())
   add_child(stroke)
   previous=point
 var shape:=profile
 if effect_phase=="impact" and profile in ["projectile","bolt","lance"]: shape="shards"
 for i in range(12):
  var mesh: Mesh
  if shape in ["projectile","lance","bolt"]:
   var cone := CylinderMesh.new()
   cone.top_radius = 0.0
   cone.bottom_radius = .06 + .03 * float(i%3)
   cone.height = .4
   cone.radial_segments = 6
   mesh = cone
  elif shape in ["wall","totem","trap"]:
   var prism := PrismMesh.new()
   prism.size = Vector3(.15,.7,.18)
   mesh = prism
  else:
   var shard := SphereMesh.new()
   shard.radius = .04
   shard.height = .16
   shard.radial_segments = 6
   shard.rings = 3
   mesh = shard
  var piece := MeshInstance3D.new()
  piece.mesh = mesh
  piece.material_override = material
  var angle := float(i)/12.0*TAU
  piece.position = Vector3(cos(angle),.05,sin(angle)) * (.15 if shape in ["projectile","bolt","lance"] else .75)
  if shape == "wall": piece.position = Vector3(float(i)/11.0*2.0-1.0,.4,0)
  if shape == "totem": piece.position = Vector3(cos(angle)*.2,float(i)/12.0,sin(angle)*.2)
  if shape == "trap": piece.position *= .5
  if shape in ["projectile","bolt","lance"]: piece.rotation.x = PI/2.0
  add_child(piece)
  pieces.append(piece)
 # Broken, asymmetric energy fragments; no hard circular ground outline.
 for i in range(5):
  var shard := PrismMesh.new()
  shard.size = Vector3(.12,.035,.35+.08*float(i%3))
  var fragment := MeshInstance3D.new()
  fragment.mesh = shard
  fragment.material_override = material
  var angle := float(i)*1.19+.15
  fragment.position = Vector3(cos(angle)*(.5+.07*i),.03,sin(angle)*(.5+.07*i))
  fragment.rotation.y = angle
  if profile in ["projectile","bolt","lance"]: fragment.scale=Vector3.ONE*.15
  add_child(fragment)
  pieces.append(fragment)

func _process(delta: float) -> void:
 if not playing: return
 age += delta
 var phase := fmod(age,1.2) if loop_effect else age
 for i in range(mini(12,pieces.size())):
  var piece: Node3D = pieces[i]
  if profile not in ["wall","totem","trap","projectile","bolt","lance"]:
   var angle := float(i)/12.0*TAU
   piece.position = Vector3(cos(angle)*(.3+phase*.65),sin(phase*PI)*.35,sin(angle)*(.3+phase*.65))
 if not loop_effect:
  for material in materials: material.albedo_color.a = clampf(1.0-phase/1.2,0,1)
  if age >= 1.2 and free_on_finish: queue_free()
