extends SpringArm3D
## TANK-01 third-person orbit camera.
##
## Captures the mouse cursor on left-click, releases it on Esc, orbits the
## SpringArm3D around the tank with relative mouse motion, and zooms the arm
## with the mouse wheel. Pitch is clamped between -20 deg (camera raised above
## the tank, looking down) and +60 deg (camera dropped below, looking up).

const MOUSE_SENSITIVITY: float = 0.0035
const PITCH_MIN_DEG: float = -20.0
const PITCH_MAX_DEG: float = 60.0
const INITIAL_PITCH_DEG: float = -15.0
const ZOOM_MIN: float = 6.0
const ZOOM_MAX: float = 15.0
const ZOOM_STEP: float = 1.5
const ZOOM_SMOOTHING: float = 10.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _target_spring_length: float = 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = deg_to_rad(INITIAL_PITCH_DEG)
	rotation = Vector3(_pitch, _yaw, 0.0)
	_target_spring_length = clampf(spring_length, ZOOM_MIN, ZOOM_MAX)
	spring_length = _target_spring_length
	_exclude_tank_body()


# The SpringArm3D must never cast against the hull it is rigged to, or the
# camera collapses into the tank. Resolve the hull through the "tank" group
# rather than the parent chain: CAM-01 reparents the pivot out of the tank.
func _exclude_tank_body() -> void:
	var tank: CollisionObject3D = get_tree().get_first_node_in_group(&"tank") as CollisionObject3D
	if tank != null:
		add_excluded_object(tank.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.is_action_pressed("camera_zoom_in"):
			_zoom(-ZOOM_STEP)
		elif event.is_action_pressed("camera_zoom_out"):
			_zoom(ZOOM_STEP)
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit(event.relative)


func _orbit(relative: Vector2) -> void:
	_yaw -= relative.x * MOUSE_SENSITIVITY
	_pitch += relative.y * MOUSE_SENSITIVITY
	_pitch = clampf(_pitch, deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))
	rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	spring_length = lerpf(spring_length, _target_spring_length, clampf(ZOOM_SMOOTHING * delta, 0.0, 1.0))


func _zoom(amount: float) -> void:
	_target_spring_length = clampf(_target_spring_length + amount, ZOOM_MIN, ZOOM_MAX)
