extends Node3D
class_name GunController
## TANK-04 firing controller: reload gating, dispersion spread and tracers.
##
## Reads the [code]tank_fire[/code] action. When the reload timer has elapsed it
## traces a shell from the barrel [b]Muzzle[/b] with a random offset inside the
## reticle's dispersion cone, spawns a short-lived tracer along the shell path,
## applies a temporary dispersion spike to the reticle, and starts the reload.
##
## The dispersion fraction is read from the [ReticleHUD] found in the
## [code]reticle_hud[/code] group and mapped from its minimum to maximum cone
## half-angle with [method lerpf]. The dependency is one-way
## (GunController -> ReticleHUD) so the two scripts cannot form a cyclic
## [code]class_name[/code] reference.
##
## A shell is resolved instantly with a raycast (no travelling projectile) for
## deterministic gameplay; the tracer is a stretched unshaded [BoxMesh] between
## the muzzle and the traced impact (or [member tracer_range] when nothing is
## hit), freed after [member tracer_lifetime] seconds.

const ACTION_FIRE: StringName = &"tank_fire"
const GROUP_RETICLE_HUD: StringName = &"reticle_hud"
const MUZZLE_PATH: NodePath = ^"../Hull/TurretMount/GunMount/Muzzle"

const TRACER_WIDTH: float = 0.08
const TRACER_COLOR: Color = Color(1.0, 0.88, 0.35, 1.0)
const TRACER_EMISSION: Color = Color(1.0, 0.75, 0.15, 1.0)

## Seconds between shots (reload cycle).
@export var reload_time: float = 4.0
## Seconds a tracer stays visible.
@export var tracer_lifetime: float = 0.5
## Distance (m) the shell ray travels when it hits nothing.
@export var tracer_range: float = 500.0
## Firing-cone half-angle (deg) at minimum dispersion.
@export var spread_min_deg: float = 0.5
## Firing-cone half-angle (deg) at maximum dispersion.
@export var spread_max_deg: float = 4.0
## Physics collision layers the shell ray can hit.
@export_flags_3d_physics var collision_mask: int = 1

## Emitted after every shot. [param spread_angle] is the cone half-angle (rad).
signal fired(start: Vector3, end: Vector3, spread_angle: float)

@onready var _muzzle: Node3D = get_node_or_null(MUZZLE_PATH)
@onready var _tank: CollisionObject3D = get_parent() as CollisionObject3D

var _reload_timer: float = 0.0
var _reticle_hud: ReticleHUD = null
var _tracer_material: StandardMaterial3D


func _ready() -> void:
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = TRACER_COLOR
	_tracer_material.emission_enabled = true
	_tracer_material.emission = TRACER_EMISSION
	_tracer_material.emission_energy_multiplier = 4.0


# All gun state advances on the physics tick. The hull and turret controllers run
# in _physics_process, so reading input and firing here keeps the muzzle
# transform and aim state in sync with them (no one-tick stale transform) and
# makes the raycast frame-rate independent. The reload countdown lives here too
# for consistency with the rest of the cycle.
func _physics_process(delta: float) -> void:
	_reload_timer = maxf(_reload_timer - delta, 0.0)
	if _reticle_hud == null:
		_reticle_hud = get_tree().get_first_node_in_group(GROUP_RETICLE_HUD) as ReticleHUD
	if _reticle_hud != null:
		_reticle_hud.set_reload_state(get_reload_progress(), is_reloading())
	if Input.is_action_pressed(ACTION_FIRE) and can_fire():
		_fire()


## True while the gun is cycling between shots.
func is_reloading() -> bool:
	return _reload_timer > 0.0


## Reload completion fraction in [code]0..1[/code] (0 just fired, 1 ready).
func get_reload_progress() -> float:
	if reload_time <= 0.0:
		return 1.0
	return clampf(1.0 - _reload_timer / reload_time, 0.0, 1.0)


## True when the gun is loaded and the muzzle exists.
func can_fire() -> bool:
	return _reload_timer <= 0.0 and _muzzle != null


func _fire() -> void:
	_reload_timer = reload_time
	var fraction: float = _reticle_hud.get_dispersion_fraction() if _reticle_hud != null else 0.0
	var spread_angle: float = deg_to_rad(lerpf(spread_min_deg, spread_max_deg, fraction))
	var start: Vector3 = _muzzle.global_position
	var direction: Vector3 = _random_cone_direction(spread_angle)
	var end: Vector3 = _trace_shell(start, direction)
	_spawn_tracer(start, end)
	if _reticle_hud != null:
		_reticle_hud.apply_shot_penalty()
	fired.emit(start, end, spread_angle)


# Returns a unit direction inside a cone of half-angle spread_angle around the
# barrel axis. sqrt(randf()) gives a uniform distribution over the cone disc.
func _random_cone_direction(spread_angle: float) -> Vector3:
	var basis: Basis = _muzzle.global_transform.basis
	var forward: Vector3 = -basis.z
	var azimuth: float = randf() * TAU
	var radial: float = sqrt(randf()) * tan(spread_angle)
	var offset: Vector3 = (basis.x * cos(azimuth) + basis.y * sin(azimuth)) * radial
	return (forward + offset).normalized()


# Raycasts the shell path against world geometry, ignoring the tank's own body.
func _trace_shell(from: Vector3, direction: Vector3) -> Vector3:
	var to: Vector3 = from + direction * tracer_range
	var exclude: Array[RID] = []
	if _tank != null:
		exclude.append(_tank.get_rid())
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, to, collision_mask, exclude)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return to if hit.is_empty() else (hit.position as Vector3)


func _spawn_tracer(start: Vector3, end: Vector3) -> void:
	var length: float = start.distance_to(end)
	if length < 0.01:
		return
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(TRACER_WIDTH, TRACER_WIDTH, length)
	var tracer: MeshInstance3D = MeshInstance3D.new()
	tracer.mesh = box
	tracer.material_override = _tracer_material

	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	parent.add_child(tracer)

	var direction: Vector3 = (end - start) / length
	var up: Vector3 = Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.FORWARD
	tracer.global_transform = Transform3D(
			Basis.looking_at(direction, up), (start + end) * 0.5)

	var timer: SceneTreeTimer = get_tree().create_timer(tracer_lifetime)
	timer.timeout.connect(tracer.queue_free)
