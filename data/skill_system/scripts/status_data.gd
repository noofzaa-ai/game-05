extends Resource
## Shared status tuning; referenced by all skills, never owned by a Gem instance.
@export var id: String = ""
@export var duration_s: float = 0.0
@export var damage_per_tick: float = 0.0
@export var tick_interval_s: float = 1.0
@export var max_stacks: int = 1
@export var magnitude: float = 0.0
@export var threshold: float = 0.0

