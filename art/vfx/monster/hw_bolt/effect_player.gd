extends Node3D
## Generic daiyooo VFX carrier. No damage, movement, sockets or terrain logic.
@export var autoplay: bool = true
@export var loop_effect: bool = false
@export var free_on_finish: bool = false
## Two-endpoint (link) effects only: optional nodes followed every frame (see set_endpoints).
@export var link_from: NodePath
@export var link_to: NodePath
var _player: AnimationPlayer
var _clip: StringName
var _span: Node3D
var _link_from_node: Node3D
var _link_to_node: Node3D
var _from_target: Variant = null
var _to_target: Variant = null

func _ready() -> void:
    _span = find_child("VFXLinkSpan", true, false) as Node3D
    _link_from_node = find_child("VFXLinkFrom", true, false) as Node3D
    _link_to_node = find_child("VFXLinkTo", true, false) as Node3D
    if not link_from.is_empty() and not link_to.is_empty():
        set_endpoints(get_node_or_null(link_from), get_node_or_null(link_to))
    _player = _find_player(self)
    if _player == null:
        push_warning("daiyooo VFX: imported GLB has no AnimationPlayer")
        return
    for name in _player.get_animation_list():
        if name != "RESET":
            _clip = name
            break
    if _clip == &"":
        return
    # Duplicate before adjusting loop flags; do not mutate shared imported resources.
    var original := _player.get_animation(_clip)
    var copy := original.duplicate() as Animation
    copy.loop_mode = Animation.LOOP_LINEAR if loop_effect else Animation.LOOP_NONE
    var library_name := String(_clip).get_slice("/", 0) if "/" in String(_clip) else ""
    var animation_name := String(_clip).get_slice("/", 1) if "/" in String(_clip) else String(_clip)
    var library := _player.get_animation_library(library_name).duplicate() as AnimationLibrary
    library.remove_animation(animation_name)
    library.add_animation(animation_name, copy)
    _player.remove_animation_library(library_name)
    _player.add_animation_library(library_name, library)
    _player.animation_finished.connect(_finished)
    if autoplay:
        play_effect()

func _find_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_player(child)
        if found != null:
            return found
    return null

func play_effect() -> void:
    if _player != null and _clip != &"":
        _player.stop()
        _player.play(_clip)
        _player.advance(0.0)

func stop_effect() -> void:
    if _player != null:
        _player.stop()

## Link effects: aim the effect between two points. Each argument is a Node3D (followed every
## frame while it is valid) or a global Vector3. The span pivot is placed at from_point, its +Z
## axis aimed at to_point and stretched to the distance (X = up x Z, up = +Y unless the link is
## nearly vertical, then +X: the same rule as the Studio preview). Endpoint layers are moved to
## the two points. Does nothing for effects without link nodes.
func set_endpoints(from_point: Variant, to_point: Variant) -> void:
    _from_target = from_point
    _to_target = to_point
    _apply_endpoints()

func clear_endpoints() -> void:
    _from_target = null
    _to_target = null

func has_link() -> bool:
    return _span != null or _link_from_node != null or _link_to_node != null

func _resolve(target: Variant) -> Variant:
    if target is Vector3:
        return target
    if target is Node3D and is_instance_valid(target) and (target as Node3D).is_inside_tree():
        return (target as Node3D).global_position
    return null

func _process(_delta: float) -> void:
    if _from_target != null and _to_target != null:
        _apply_endpoints()

func _apply_endpoints() -> void:
    if not has_link() or not is_inside_tree():
        return
    var a: Variant = _resolve(_from_target)
    var b: Variant = _resolve(_to_target)
    if a == null or b == null:
        return
    var d: Vector3 = b - a
    var length := d.length()
    var z: Vector3 = Vector3.BACK if length < 0.0001 else d / length
    length = maxf(length, 0.0001)
    var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
    var x := up.cross(z).normalized()
    var y := z.cross(x)
    if _span != null:
        _span.global_transform = Transform3D(Basis(x, y, z * length), a)
    if _link_from_node != null:
        _link_from_node.global_transform = Transform3D(Basis.IDENTITY, a)
    if _link_to_node != null:
        _link_to_node.global_transform = Transform3D(Basis.IDENTITY, b)

func _finished(_name: StringName) -> void:
    if free_on_finish and not loop_effect:
        queue_free()
