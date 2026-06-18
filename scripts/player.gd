extends CharacterBody3D

const BASE_SPEED: float = 6.0
const SPRINT_SPEED: float = 10.0
const ACCEL: float = 40.0
const FRICTION: float = 20.0
const AIR_ACCEL: float = 8.0
const AIR_FRICTION: float = 4.0

const JUMP_VELOCITY: float = 8.0
const COYOTE_TIME: float = 0.1

const MOUSE_SENSITIVITY: float = 0.002

const CAMERA_LAG: float = 8.0
const EYE_HEIGHT: float = 1.8
const CAMERA_BACK: float = 4.0
const BASE_FOV: float = 75.0
const SPRINT_FOV: float = 85.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var anim_player: AnimationPlayer = $Character/AnimationPlayer
@onready var footstep_dust: GPUParticles3D = $FootstepDust

var coyote_timer: float = 0.0
var was_on_floor: bool = true
var jump_pressed: bool = false
var landing_vel: float = 0.0
var footstep_timer: float = 0.0
var shake_timer: float = 0.0
var shake_intensity: float = 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.current = true
	camera.fov = BASE_FOV


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x += -event.relative.y * MOUSE_SENSITIVITY
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		toggle_mouse_capture()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer -= delta

	var just_landed := not was_on_floor and is_on_floor()
	if just_landed:
		on_land()
	was_on_floor = is_on_floor()

	var is_sprinting := Input.is_key_pressed(KEY_SHIFT) and is_on_floor()
	var target_speed := SPRINT_SPEED if is_sprinting else BASE_SPEED

	if Input.is_action_just_pressed("ui_accept") and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_pressed = true

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var direction := (transform.basis * input_dir).normalized()
	var target_vel := direction * target_speed

	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	var friction := FRICTION if is_on_floor() else AIR_FRICTION

	if direction.length() > 0:
		velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	move_and_slide()

	landing_vel = velocity.y if not is_on_floor() else landing_vel
	update_footsteps(delta, is_sprinting)
	update_animation(is_sprinting, just_landed)


func on_land() -> void:
	var fall_speed := abs(landing_vel)
	if fall_speed > 8.0:
		footstep_dust.amount = int(clamp(fall_speed * 0.8, 6, 20))
		footstep_dust.emitting = true

	if fall_speed > 10.0:
		shake_intensity = clamp(fall_speed * 0.05, 0.0, 0.15)
		shake_timer = 0.3


func update_footsteps(delta: float, sprinting: bool) -> void:
	if not is_on_floor():
		footstep_timer = 0.0
		return
	var speed_h := Vector2(velocity.x, velocity.z).length()
	if speed_h < 0.5:
		footstep_timer = 0.0
		return

	var interval := 0.35 if not sprinting else 0.2
	footstep_timer += delta
	if footstep_timer >= interval:
		footstep_timer = 0.0
		footstep_dust.amount = 4
		footstep_dust.emitting = true


func update_animation(is_sprinting: bool, just_landed: bool) -> void:
	if not is_on_floor():
		anim_player.play("idle")
		return

	var speed_h := Vector2(velocity.x, velocity.z).length()

	if speed_h > 6.0 and is_sprinting:
		anim_player.play("sprint")
	elif speed_h > 0.5:
		anim_player.play("walk")
	else:
		anim_player.play("idle")

	if anim_player.current_animation in ["walk", "sprint"]:
		var max_s := SPRINT_SPEED if is_sprinting else BASE_SPEED
		anim_player.speed_scale = clamp(speed_h / max_s * 1.2, 0.3, 1.8)
	else:
		anim_player.speed_scale = 1.0


func _process(delta: float) -> void:
	var target_fov := SPRINT_FOV if Input.is_key_pressed(KEY_SHIFT) and is_on_floor() else BASE_FOV
	camera.fov = lerpf(camera.fov, target_fov, 8.0 * delta)

	var target_pos := Vector3(0, EYE_HEIGHT, 0)
	camera_pivot.position = camera_pivot.position.lerp(target_pos, CAMERA_LAG * delta)

	var space := get_world_3d().direct_space_state
	var pivot_pos := camera_pivot.global_position
	var query := PhysicsRayQueryParameters3D.create(pivot_pos, pivot_pos - camera_pivot.global_basis.z * CAMERA_BACK)
	query.exclude = [self]
	var hit := space.intersect_ray(query)

	if hit:
		var d := hit.position.distance_to(pivot_pos) - 0.3
		camera.position.z = lerpf(camera.position.z, -max(d, 0.5), 15.0 * delta)
	else:
		camera.position.z = lerpf(camera.position.z, -CAMERA_BACK, 10.0 * delta)

	if shake_timer > 0.0:
		shake_timer -= delta
		var decay := shake_timer / 0.3
		var s := shake_intensity * decay
		camera_pivot.rotation.z = sin(Time.get_ticks_msec() * 0.05) * s * 0.5
		camera_pivot.rotation.x += sin(Time.get_ticks_msec() * 0.07) * s * 0.3
	else:
		camera_pivot.rotation.z = lerpf(camera_pivot.rotation.z, 0.0, 12.0 * delta)
