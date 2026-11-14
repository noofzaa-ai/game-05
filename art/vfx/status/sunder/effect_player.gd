extends Node3D
## Generic daiyooo VFX carrier. No damage, movement, sockets or terrain logic.
@export var autoplay: bool = true
@export var loop_effect: bool = false
@export var free_on_finish: bool = false
var _player: AnimationPlayer
var _clip: StringName

func _ready() -> void:
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

func _finished(_name: StringName) -> void:
    if free_on_finish and not loop_effect:
        queue_free()
