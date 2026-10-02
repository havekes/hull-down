extends Control
class_name ReticleHUD
## TANK-04 dynamic dispersion reticle (bloom) and reload HUD.
##
## Draws a fixed screen-centre dot, an outer ring whose radius tracks the
## current dispersion, a marker for where the barrel actually points, and a
## reload progress bar while the gun is cycling.
##
## Dispersion is accumulated from three continuous penalties (hull speed, hull
## traverse, turret traverse) plus a temporary spike applied on firing. When a
## penalty is present the ring blooms out to the target radius within
## [member bloom_time]; with no penalties it shrinks back to
## [member base_dispersion_radius] at a constant rate that covers the full
## range in [member aim_time] seconds.
##
## Wiring: [member tank_path] points at the tank root; the camera, muzzle and
## controllers are resolved from it. The gun finds this HUD through the
## [code]reticle_hud[/code] group and pushes reload state into it. This script
## never references the gun type, so the two scripts have no cyclic
## [code]class_name[/code] dependency.

const GROUP_RETICLE_HUD: StringName = &"reticle_hud"
const CAMERA_PATH: NodePath = ^"CameraPivot/Camera3D"
const MUZZLE_PATH: NodePath = ^"Hull/TurretMount/GunMount/Muzzle"
const TURRET_PATH: NodePath = ^"TurretController"

const COLOR_CENTER_DOT: Color = Color(0.92, 0.96, 1.0, 0.95)
const COLOR_RING: Color = Color(0.95, 0.95, 0.88, 0.85)
const COLOR_MUZZLE_MARKER: Color = Color(1.0, 0.62, 0.2, 0.95)
const COLOR_RELOAD_BG: Color = Color(0.0, 0.0, 0.0, 0.45)
const COLOR_RELOAD_FILL: Color = Color(0.4, 1.0, 0.52, 0.95)

const RING_SEGMENTS: int = 64
const RING_WIDTH: float = 2.0
const CENTER_DOT_RADIUS: float = 2.0
const MUZZLE_MARKER_RADIUS: float = 3.5
const RELOAD_BAR_SIZE: Vector2 = Vector2(120.0, 6.0)
const RELOAD_BAR_OFFSET: Vector2 = Vector2(0.0, 96.0)

## Node path (relative to this Control) to the tank root. Falls back to the
## first node in the [code]tank[/code] group when left empty.
@export var tank_path: NodePath
## Minimum dispersion radius in screen pixels; the resting size.
@export var base_dispersion_radius: float = 30.0
## Maximum dispersion radius in screen pixels.
@export var max_dispersion_radius: float = 180.0
## Seconds for dispersion to shrink from max back to base when stationary.
@export var aim_time: float = 2.5
## Seconds for dispersion to bloom out to the target when a penalty appears.
@export var bloom_time: float = 0.25
## Pixels added at full hull speed (full forward or full reverse).
@export var movement_penalty: float = 200.0
## Pixels added while the hull is steering.
@export var traverse_penalty: float = 200.0
## Pixels added while the turret or gun is traversing.
@export var turret_penalty: float = 60.0
## Temporary pixel spike added immediately after firing (decays over ~aim_time).
@export var shot_penalty: float = 150.0
## Distance (m) along the barrel used to place the muzzle-direction marker.
@export var muzzle_marker_distance: float = 100.0
## Hull yaw rate (rad/s) above which the hull-traverse penalty applies.
@export var yaw_rate_epsilon: float = 0.01
## Turret traverse rate (rad/s) above which the turret penalty applies.
@export var traverse_rate_epsilon: float = 0.02

## Current dispersion radius in screen pixels. Kept within
## [code]base_dispersion_radius..max_dispersion_radius[/code].
var current_dispersion_radius: float = 0.0

var _tank: Node3D
var _camera: Camera3D
var _muzzle: Node3D
var _tank_controller: TankController
var _turret_controller: TurretController

var _shot_spike: float = 0.0
var _reload_progress: float = 1.0
var _reloading: bool = false


func _ready() -> void:
	add_to_group(GROUP_RETICLE_HUD)
	current_dispersion_radius = base_dispersion_radius
	_resolve_references()


func _process(delta: float) -> void:
	if _tank == null:
		_resolve_references()
	_update_dispersion(delta)
	queue_redraw()


## Current dispersion radius in screen pixels.
func get_dispersion_radius() -> float:
	return current_dispersion_radius


## Current dispersion normalised in [code]0..1[/code]: base radius is 0 and max
## radius is 1. Used by the gun to size its firing cone.
func get_dispersion_fraction() -> float:
	var span: float = max_dispersion_radius - base_dispersion_radius
	if span <= 0.0:
		return 0.0
	return clampf((current_dispersion_radius - base_dispersion_radius) / span, 0.0, 1.0)


## Applies the temporary firing spike to the dispersion. The ring snaps out to
## the spiked radius immediately, then decays over roughly [member aim_time].
func apply_shot_penalty() -> void:
	_shot_spike = shot_penalty
	current_dispersion_radius = clampf(
			base_dispersion_radius + _shot_spike,
			base_dispersion_radius,
			max_dispersion_radius)


## Pushes reload state from the gun. [param progress] is the completion
## fraction in [code]0..1[/code] (0 just fired, 1 ready).
func set_reload_state(progress: float, reloading: bool) -> void:
	_reload_progress = clampf(progress, 0.0, 1.0)
	_reloading = reloading


# Resolves the tank and its children, retrying each frame until the tank exists
# (the HUD may be readied before the tank depending on scene order).
func _resolve_references() -> void:
	if tank_path != NodePath():
		_tank = get_node_or_null(tank_path) as Node3D
	if _tank == null:
		_tank = get_tree().get_first_node_in_group(&"tank") as Node3D
	if _tank == null:
		return
	_camera = _tank.get_node_or_null(CAMERA_PATH) as Camera3D
	_muzzle = _tank.get_node_or_null(MUZZLE_PATH) as Node3D
	_tank_controller = _tank as TankController
	_turret_controller = _tank.get_node_or_null(TURRET_PATH) as TurretController


func _update_dispersion(delta: float) -> void:
	var shrink_rate: float = (max_dispersion_radius - base_dispersion_radius) \
			/ maxf(aim_time, 0.001)
	var bloom_rate: float = (max_dispersion_radius - base_dispersion_radius) \
			/ maxf(bloom_time, 0.001)
	_shot_spike = move_toward(_shot_spike, 0.0, shrink_rate * delta)

	var penalties: float = _continuous_penalties() + _shot_spike
	if penalties > 0.0:
		var target: float = clampf(
				base_dispersion_radius + penalties,
				base_dispersion_radius,
				max_dispersion_radius)
		current_dispersion_radius = move_toward(
				current_dispersion_radius, target, bloom_rate * delta)
	else:
		current_dispersion_radius = move_toward(
				current_dispersion_radius, base_dispersion_radius, shrink_rate * delta)
	current_dispersion_radius = clampf(
			current_dispersion_radius, base_dispersion_radius, max_dispersion_radius)


# Sum of the continuous movement/traverse penalties for this frame.
func _continuous_penalties() -> float:
	var total: float = 0.0
	if _tank_controller != null:
		total += movement_penalty * _tank_controller.get_speed_fraction()
		if _tank_controller.get_yaw_rate() > yaw_rate_epsilon:
			total += traverse_penalty
	if _turret_controller != null and _turret_controller.get_traverse_rate() > traverse_rate_epsilon:
		total += turret_penalty
	return total


func _draw() -> void:
	var center: Vector2 = size * 0.5
	draw_arc(center, current_dispersion_radius, 0.0, TAU, RING_SEGMENTS,
			COLOR_RING, RING_WIDTH, true)
	draw_circle(center, CENTER_DOT_RADIUS, COLOR_CENTER_DOT)
	_draw_muzzle_marker()
	_draw_reload_bar(center)


# Projects a point along the barrel's forward axis to the screen so the marker
# shows where the gun actually points, independent of the camera crosshair.
func _draw_muzzle_marker() -> void:
	if _camera == null or _muzzle == null:
		return
	var forward: Vector3 = -_muzzle.global_transform.basis.z
	var point: Vector3 = _muzzle.global_position + forward * muzzle_marker_distance
	if _camera.is_position_behind(point):
		return
	var screen_point: Vector2 = _camera.unproject_position(point)
	screen_point = screen_point.clamp(Vector2.ZERO, size)
	draw_circle(screen_point, MUZZLE_MARKER_RADIUS, COLOR_MUZZLE_MARKER)


func _draw_reload_bar(center: Vector2) -> void:
	if not _reloading:
		return
	var origin: Vector2 = center + RELOAD_BAR_OFFSET - RELOAD_BAR_SIZE * 0.5
	draw_rect(Rect2(origin, RELOAD_BAR_SIZE), COLOR_RELOAD_BG, true)
	var fill: Vector2 = Vector2(RELOAD_BAR_SIZE.x * _reload_progress, RELOAD_BAR_SIZE.y)
	draw_rect(Rect2(origin, fill), COLOR_RELOAD_FILL, true)
	draw_rect(Rect2(origin, RELOAD_BAR_SIZE), COLOR_RING, false, 1.0)
