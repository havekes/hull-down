extends CharacterBody3D
## TANK-02 kinematic tracked-vehicle driving controller.
##
## Drives a [CharacterBody3D] hull with World-of-Tanks-style weight: the tank
## pivots in place when stationary (neutral steer), smoothly accelerates to a
## capped top speed, coasts to a stop, and arcs while steering under way. No
## [VehicleBody3D]; movement is fully deterministic via [method move_and_slide].
##
## A set of four downward [RayCast3D] corner probes is averaged to keep the
## hull flush with sloped terrain. On perfectly flat ground the probes resolve
## to [constant Vector3.UP] and the alignment is a no-op.

const ACTION_FORWARD: StringName = &"tank_forward"
const ACTION_BACKWARD: StringName = &"tank_backward"
const ACTION_LEFT: StringName = &"tank_left"
const ACTION_RIGHT: StringName = &"tank_right"

## Forward speed below which steering pivots the hull in place instead of
## arcing under way. Small enough to read as "stationary", large enough that
## the crossover does not chatter.
const NEUTRAL_STEER_SPEED_EPSILON: float = 0.5
## Fraction of top speed still available at full steering lock: steering hard
## drags the tracks and limits how fast the hull can travel.
const MIN_TURN_SPEED_SCALE: float = 0.4
## How quickly the hull re-levels to the averaged floor normal (1/s).
const FLOOR_ALIGN_SPEED: float = 8.0
## Averaged normals closer to [constant Vector3.UP] than this are treated as
## flat, which avoids fighting [method move_and_slide] on the test arena.
const FLOOR_NORMAL_FLAT_THRESHOLD: float = 0.9999
## A slide normal more opposed than this to the heading counts as a head-on
## wall, and the stored speed is damped so the hull does not grind into it.
const WALL_BLOCK_DOT: float = -0.7

@export var max_forward_speed: float = 12.0
@export var max_reverse_speed: float = 4.0
@export var acceleration: float = 6.0
@export var braking_deceleration: float = 10.0
@export var hull_traverse_speed: float = deg_to_rad(35.0)
@export var gravity: float = 9.8
@export var debug: bool = false

var _yaw: float = 0.0
var _forward_speed: float = 0.0
var _floor_up: Vector3 = Vector3.UP
var _corner_raycasts: Array[RayCast3D] = []


func _ready() -> void:
	_yaw = rotation.y
	up_direction = Vector3.UP
	_corner_raycasts = _collect_corner_raycasts()


func _physics_process(delta: float) -> void:
	var drive_input: float = Input.get_action_strength(ACTION_FORWARD) \
			- Input.get_action_strength(ACTION_BACKWARD)
	var turn_input: float = Input.get_action_strength(ACTION_LEFT) \
			- Input.get_action_strength(ACTION_RIGHT)

	_update_speed(drive_input, turn_input, delta)
	_update_turn(turn_input, delta)
	_update_orientation(delta)
	_apply_motion(delta)

	if debug:
		_print_debug_state(drive_input, turn_input)


## Signed scalar speed along the hull heading, positive forward (m/s).
func get_forward_speed() -> float:
	return _forward_speed


# Selects the target speed from the drive input, lowers it while steering, and
# approaches it with move_toward at acceleration or braking_deceleration.
func _update_speed(drive_input: float, turn_input: float, delta: float) -> void:
	var target_speed: float = 0.0
	if drive_input > 0.0:
		target_speed = max_forward_speed * drive_input
	elif drive_input < 0.0:
		target_speed = max_reverse_speed * drive_input

	# Track drag: steering toward lock shrinks the speed the hull can hold.
	if not is_zero_approx(turn_input) and absf(_forward_speed) > NEUTRAL_STEER_SPEED_EPSILON:
		target_speed *= lerpf(1.0, MIN_TURN_SPEED_SCALE, absf(turn_input))

	var rate: float = acceleration
	if is_zero_approx(target_speed):
		rate = braking_deceleration
	elif not is_zero_approx(_forward_speed) and signf(target_speed) != signf(_forward_speed):
		rate = braking_deceleration
	_forward_speed = move_toward(_forward_speed, target_speed, rate * delta)


# Neutral steer and driving turn share one yaw rate: the hull always rotates at
# hull_traverse_speed, which keeps pivot-in-place and wide under-way arcs
# consistent. The difference between the two is purely the speed behaviour.
func _update_turn(turn_input: float, delta: float) -> void:
	if is_zero_approx(turn_input):
		return
	_yaw = wrapf(_yaw + turn_input * hull_traverse_speed * delta, -PI, PI)


# Rebuilds the hull basis from the heading yaw and the averaged floor normal so
# the tank stays flush with the terrain while preserving its heading.
func _update_orientation(delta: float) -> void:
	var target_up: Vector3 = _sample_floor_normal()
	_floor_up = _floor_up.slerp(target_up, clampf(FLOOR_ALIGN_SPEED * delta, 0.0, 1.0)).normalized()

	var forward: Vector3 = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	forward = forward - _floor_up * forward.dot(_floor_up)
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(_floor_up).normalized()
	global_transform.basis = Basis(right, _floor_up, -forward)


func _apply_motion(delta: float) -> void:
	var heading: Vector3 = -global_transform.basis.z
	velocity.x = heading.x * _forward_speed
	velocity.z = heading.z * _forward_speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_damp_on_wall_collision(heading, delta)


# Averages the floor normals reported by the four corner probes. Falls back to
# up when nothing is hit or when the surface is effectively flat.
func _sample_floor_normal() -> Vector3:
	var normal_sum: Vector3 = Vector3.ZERO
	var hits: int = 0
	for ray in _corner_raycasts:
		if not is_instance_valid(ray):
			continue
		ray.force_raycast_update()
		if ray.is_colliding():
			normal_sum += ray.get_collision_normal()
			hits += 1
	if hits == 0:
		return Vector3.UP
	var average: Vector3 = (normal_sum / float(hits)).normalized()
	if average.dot(Vector3.UP) > FLOOR_NORMAL_FLAT_THRESHOLD:
		return Vector3.UP
	return average


# Bleeds off stored speed when the hull runs head-on into a wall so the body
# settles against it instead of grinding.
func _damp_on_wall_collision(heading: Vector3, delta: float) -> void:
	if absf(_forward_speed) < 0.01:
		return
	var flat_heading: Vector3 = Vector3(heading.x, 0.0, heading.z).normalized()
	for i in get_slide_collision_count():
		var normal: Vector3 = get_slide_collision(i).get_normal()
		if normal.dot(flat_heading) < WALL_BLOCK_DOT:
			_forward_speed = move_toward(_forward_speed, 0.0, braking_deceleration * delta)
			return


func _collect_corner_raycasts() -> Array[RayCast3D]:
	var rays: Array[RayCast3D] = []
	for child in get_children():
		if child is RayCast3D:
			rays.append(child)
	return rays


func _print_debug_state(drive_input: float, turn_input: float) -> void:
	print("[TankController] speed=%.2f yaw=%.1f deg drive=%.2f turn=%.2f floor=%s" % [
		_forward_speed,
		rad_to_deg(_yaw),
		drive_input,
		turn_input,
		is_on_floor(),
	])
