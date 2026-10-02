extends Node3D
## TANK-03 decoupled turret traverse and gun elevation controller.
##
## Every physics frame this reads the chase camera's screen-centre ray to resolve
## a world-space [member target_aim_point], then drives [b]TurretMount[/b] yaw and
## [b]GunMount[/b] pitch toward that point at fixed angular speeds. The desired
## angles are computed in each mount's parent-local frame, so the turret
## automatically compensates while the driver steers the hull and keeps the
## crosshair on a fixed world point.
##
## The aim ray is a code-side [PhysicsRayQueryParameters3D] query rather than a
## [RayCast3D] node on purpose: TANK-02's [TankController] averages every direct
## child [RayCast3D] into its floor normal, so adding a probe under the tank root
## would corrupt hull orientation.
##
## Sign conventions (verified with a headless harness):
## - Turret yaw: [code]TurretMount.rotation.y[/code] rotates the barrel's local
##   -Z direction about the hull's up axis; [code]atan2(-x, -z)[/code] of the
##   parent-local vector to the target yields the desired yaw.
## - Gun pitch: positive [code]GunMount.rotation.x[/code] raises the barrel, so
##   elevation is positive and depression is negative, matching the export names.

## Fixed turret traverse rate toward the aim point (rad/s).
@export var turret_traverse_speed: float = deg_to_rad(30.0)
## Maximum upward gun pitch (rad).
@export var max_elevation: float = deg_to_rad(20.0)
## Maximum downward gun depression (rad).
@export var max_depression: float = deg_to_rad(8.0)
## Fixed gun elevation rate (rad/s).
@export var gun_traverse_speed: float = deg_to_rad(25.0)
## Distance (m) the aim ray falls back to when it hits no geometry.
@export var aim_fallback_distance: float = 500.0
## Physics collision layers the aim ray is allowed to hit.
@export_flags_3d_physics var aim_collision_mask: int = 1

# Node paths are relative to this controller node, which is a direct child of the
# tank root (see scenes/TankBase.tscn).
@onready var _turret_mount: Node3D = get_node("../Hull/TurretMount")
@onready var _gun_mount: Node3D = get_node("../Hull/TurretMount/GunMount")
@onready var _camera: Camera3D = get_node("../CameraPivot/Camera3D")

## World-space point the camera crosshair is currently aimed at. When the ray
## hits no geometry it lies [member aim_fallback_distance] metres along the ray.
var target_aim_point: Vector3 = Vector3.ZERO

# RIDs the aim ray ignores so it cannot hit the tank's own hull.
var _exclude_rids: Array[RID] = []


func _ready() -> void:
	var body: CollisionObject3D = _find_body_collider()
	if body != null:
		_exclude_rids.append(body.get_rid())
	target_aim_point = _camera.global_position \
			+ -_camera.global_transform.basis.z * aim_fallback_distance


func _physics_process(delta: float) -> void:
	_update_target_aim_point()
	_update_turret_yaw(delta)
	_update_gun_pitch(delta)


# Resolves where the camera centre ray lands this frame. Falls back to a far
# point along the ray when the crosshair is against the sky or out of range.
func _update_target_aim_point() -> void:
	var screen_center: Vector2 = _camera.get_viewport().get_visible_rect().size * 0.5
	var from: Vector3 = _camera.project_ray_origin(screen_center)
	var direction: Vector3 = _camera.project_ray_normal(screen_center)
	var to: Vector3 = from + direction * aim_fallback_distance

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, to, aim_collision_mask, _exclude_rids)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	target_aim_point = to if hit.is_empty() else (hit.position as Vector3)


# Slews TurretMount.rotation.y toward the parent-local bearing of the target,
# taking the shortest arc and capped at turret_traverse_speed.
func _update_turret_yaw(delta: float) -> void:
	var hull: Node3D = _turret_mount.get_parent()
	var local_target: Vector3 = hull.global_transform.affine_inverse() * target_aim_point
	var to_target: Vector3 = local_target - _turret_mount.position
	var target_yaw: float = atan2(-to_target.x, -to_target.z)
	var next_yaw: float = rotate_toward(
			_turret_mount.rotation.y, target_yaw, turret_traverse_speed * delta)
	_turret_mount.rotation.y = wrapf(next_yaw, -PI, PI)


# Slews GunMount.rotation.x toward the turret-local elevation of the target,
# clamped between max_depression and max_elevation.
func _update_gun_pitch(delta: float) -> void:
	var turret: Node3D = _gun_mount.get_parent()
	var local_target: Vector3 = turret.global_transform.affine_inverse() * target_aim_point
	var to_target: Vector3 = local_target - _gun_mount.position
	var horizontal_distance: float = sqrt(
			to_target.x * to_target.x + to_target.z * to_target.z)
	var target_pitch: float = clampf(
			atan2(to_target.y, horizontal_distance), -max_depression, max_elevation)
	_gun_mount.rotation.x = rotate_toward(
			_gun_mount.rotation.x, target_pitch, gun_traverse_speed * delta)


# Walks up the tree to the nearest collision object (the tank's CharacterBody3D)
# so its body RID can be excluded from the aim ray.
func _find_body_collider() -> CollisionObject3D:
	var node: Node = get_parent()
	while node != null:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
	return null
