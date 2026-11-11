class_name ZorxStatMod
extends Resource

enum Op { ADD, MUL, SET }
enum Scope { SKILL, PLAYER }
@export var stat: String = ""
@export var op: Op = Op.MUL
@export var value: float = 1.0
@export var scope: Scope = Scope.SKILL
@export var scope_tags: Array[String] = []

