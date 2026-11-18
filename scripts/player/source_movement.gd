class_name SourceMovement
extends RefCounted
## Faithful port of CS2GO / Source Engine player movement in meters (SOURCE_UNIT = 0.0254).

const SOURCE_UNIT := 0.0254
const GROUND_ACCELERATION := 5.5
const AIR_ACCELERATION := 12.0
const AIR_WISH_SPEED := 30.0 * SOURCE_UNIT
const FRICTION := 5.2
const STOP_SPEED := 80.0 * SOURCE_UNIT
const GRAVITY := 800.0 * SOURCE_UNIT
const JUMP_IMPULSE := 301.99338 * SOURCE_UNIT
const WALK_MODIFIER := 0.52
const CROUCH_MODIFIER := 0.34
const JUMP_SPEED_LIMIT := 1.1

const HULL_RADIUS := 16.0 * SOURCE_UNIT
const STANDING_HEIGHT := 72.0 * SOURCE_UNIT
const DUCK_HEIGHT := 54.0 * SOURCE_UNIT
const STANDING_EYE := 64.0 * SOURCE_UNIT
const DUCK_EYE := 46.0 * SOURCE_UNIT

var eye_height: float = STANDING_EYE
var crouch_amount: float = 0.0
var step_distance: float = 0.0

func reset() -> void:
	eye_height = STANDING_EYE
	crouch_amount = 0.0
	step_distance = 0.0

func accelerate(vel_xz: Vector2, wish_dir_xz: Vector2, wish_speed: float, dt: float, grounded: bool, accel_speed: float = -1.0) -> Vector2:
	if accel_speed < 0.0:
		accel_speed = wish_speed
	var v := vel_xz
	if grounded:
		var mag := v.length()
		if mag > 0.0001:
			var drop := maxf(mag, STOP_SPEED) * FRICTION * dt
			var factor := maxf(0.0, mag - drop) / mag
			v *= factor
		else:
			v = Vector2.ZERO

	var len_dir := wish_dir_xz.length()
	if len_dir < 0.0001:
		return v
	var dir := wish_dir_xz / len_dir
	var target_speed := wish_speed if grounded else minf(wish_speed, AIR_WISH_SPEED)
	var current_speed := v.dot(dir)
	var add := maxf(0.0, target_speed - current_speed)
	var accel := GROUND_ACCELERATION if grounded else AIR_ACCELERATION
	var amount := minf(add, accel * accel_speed * dt)
	return v + dir * amount

func limit_jump_speed(vel_xz: Vector2, max_speed: float) -> Vector2:
	var mag := vel_xz.length()
	var limit := max_speed * JUMP_SPEED_LIMIT
	if mag > limit and mag > 0.0001:
		return vel_xz * (limit / mag)
	return vel_xz

func step_player(body: CharacterBody3D, wish_dir_3d: Vector3, max_weapon_speed_su: float, dt: float, want_jump: bool, want_walk: bool, want_duck: bool) -> Dictionary:
	var grounded := body.is_on_floor()
	var target_crouch := 1.0 if want_duck else 0.0
	crouch_amount = lerpf(crouch_amount, target_crouch, 1.0 - exp(-15.0 * dt))
	eye_height = lerpf(STANDING_EYE, DUCK_EYE, crouch_amount)

	var base_speed := max_weapon_speed_su * SOURCE_UNIT
	var move_speed := base_speed
	if want_duck:
		move_speed *= CROUCH_MODIFIER
	elif want_walk:
		move_speed *= WALK_MODIFIER

	var prev_y_vel := body.velocity.y
	var horiz := Vector2(body.velocity.x, body.velocity.z)
	var wish_xz := Vector2(wish_dir_3d.x, wish_dir_3d.z)

	var jumped := false
	if grounded and want_jump:
		horiz = limit_jump_speed(horiz, move_speed)
		body.velocity.y = JUMP_IMPULSE
		grounded = false
		jumped = true

	horiz = accelerate(horiz, wish_xz, move_speed, dt, grounded, move_speed)
	body.velocity.x = horiz.x
	body.velocity.z = horiz.y

	if not grounded:
		body.velocity.y -= GRAVITY * dt

	var was_grounded := grounded
	body.move_and_slide()
	var now_grounded := body.is_on_floor()

	var landed_speed := 0.0
	if not was_grounded and now_grounded and prev_y_vel < -2.0:
		landed_speed = absf(prev_y_vel)

	# Footstep cadence (Source stride ~1.45m when running, silent when walking or crouched)
	var footstep := false
	var speed_xz := Vector2(body.velocity.x, body.velocity.z).length()
	if now_grounded and not want_walk and not want_duck and speed_xz > base_speed * 0.56:
		step_distance += speed_xz * dt
		if step_distance >= 1.45:
			step_distance = 0.0
			footstep = true
	elif speed_xz < 0.2:
		step_distance = 0.7

	return {
		"grounded": now_grounded,
		"jumped": jumped,
		"landed_speed": landed_speed,
		"footstep": footstep,
		"speed": speed_xz,
		"crouch": crouch_amount,
	}
