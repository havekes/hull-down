extends CharacterBody3D
## TANK-01 placeholder controller.
##
## Applies gravity only, so the tank drops cleanly onto the arena floor and
## settles there. TANK-02 replaces this with the tracked-vehicle driving
## controller; there is deliberately no input handling yet.

var _gravity: float = 9.8


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
