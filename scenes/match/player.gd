class_name Player
extends CharacterBody2D
## Player — the user-controlled character.
##
## Handles: smooth top-down movement, sprint, ball pickup, hand-pass / kick-pass
## (tap vs hold), shooting (tap = point attempt, hold = goal attempt), and GAA
## ball-carrying rules (4-step limit, one bounce per possession, unlimited solos).
##
## Aim direction:  gamepad → the ball goes the way the player is facing;
##                 keyboard + mouse → aim toward the mouse cursor.
## All input reads through named actions from the project input map.

signal foul_committed(position: Vector2)

# Movement
const WALK_SPEED   := 210.0
const SPRINT_SPEED := 340.0
const ACCEL        := 14.0     # velocity lerp speed (higher = snappier)
const DECEL        := 10.0

# Ball interaction
const PICK_RADIUS  := 38.0     # px from ball centre to auto-pickup

# Visuals
const PLAYER_RADIUS := 14.0
const C_BODY        := Color(0.22, 0.42, 0.78)
const C_OUTLINE     := Color(0.10, 0.20, 0.44)
const C_FACING_DOT  := Color(1.0,  1.0,  1.0)
const C_AIM_ARROW   := Color(1.0,  0.88, 0.1, 0.90)

# Press-and-hold threshold: below this = tap, above = hold.
const TAP_THRESHOLD := 0.20    # seconds

# GAA carry rules
const MAX_STEPS      := 4.0
const STEP_DISTANCE  := 150.0  # px per step (~1.5 m at 10 px/m; ~2.5 steps/s walking)

# ── State ─────────────────────────────────────────────────────────────────────

var facing    := Vector2.RIGHT    # direction player is physically moving toward
var aim_dir   := Vector2.RIGHT    # separate aim, updated from right stick / mouse

## Set by match_scene after instantiation.
var ball: Ball = null

var is_carrying   := false
var steps_taken   := 0.0    # accumulates pixel distance / STEP_DISTANCE
var has_bounced   := false  # one bounce allowed per possession

# Wind-up tracking for pass and shoot
enum WindUp { NONE, PASS, SHOOT }
var _wind_up       := WindUp.NONE
var _pass_held_t   := 0.0
var _shoot_held_t  := 0.0


func _physics_process(delta: float) -> void:
	_update_aim()
	_process_movement(delta)
	_process_pickup()
	_process_actions(delta)
	_process_carry_rules(delta)
	move_and_slide()
	queue_redraw()


# ── Movement ──────────────────────────────────────────────────────────────────

func _process_movement(delta: float) -> void:
	var dir  := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var fast := Input.is_action_pressed("sprint")
	var top  := SPRINT_SPEED if fast else WALK_SPEED

	if dir != Vector2.ZERO:
		facing  = dir.normalized()
		velocity = velocity.lerp(dir * top, ACCEL * delta)
	else:
		velocity = velocity.lerp(Vector2.ZERO, DECEL * delta)


# ── Aim direction ─────────────────────────────────────────────────────────────

func _update_aim() -> void:
	# Controller: the ball goes the way the player is facing.
	if not Input.get_connected_joypads().is_empty():
		aim_dir = facing
		return
	# Keyboard + mouse: aim toward the mouse cursor.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 12.0:
		aim_dir = to_mouse.normalized()
	else:
		aim_dir = facing


# ── Ball pickup ───────────────────────────────────────────────────────────────

func _process_pickup() -> void:
	if is_carrying or ball == null:
		return
	if ball.ball_state == Ball.State.FREE:
		if global_position.distance_to(ball.global_position) < PICK_RADIUS:
			_pick_up()


func _pick_up() -> void:
	is_carrying  = true
	steps_taken  = 0.0
	has_bounced  = false
	ball.pick_up(self)


# ── Pass / shoot / solo / bounce ──────────────────────────────────────────────

func _process_actions(delta: float) -> void:
	# -- PASS (tap = hand pass, hold = kick pass) --
	if Input.is_action_just_pressed("pass") and is_carrying:
		_wind_up      = WindUp.PASS
		_pass_held_t  = 0.0

	if _wind_up == WindUp.PASS:
		if Input.is_action_pressed("pass"):
			_pass_held_t += delta
		if Input.is_action_just_released("pass"):
			_wind_up = WindUp.NONE
			if _pass_held_t < TAP_THRESHOLD:
				_do_hand_pass()
			else:
				_do_kick_pass(clampf(_pass_held_t / 1.5, 0.1, 1.0))

	# -- SHOOT (tap = point attempt, hold = goal attempt) --
	if Input.is_action_just_pressed("shoot") and is_carrying:
		_wind_up       = WindUp.SHOOT
		_shoot_held_t  = 0.0

	if _wind_up == WindUp.SHOOT:
		if Input.is_action_pressed("shoot"):
			_shoot_held_t += delta
		if Input.is_action_just_released("shoot"):
			var is_goal := _shoot_held_t >= TAP_THRESHOLD
			var power   := clampf(_shoot_held_t / 1.5, 0.2, 1.0)
			_wind_up = WindUp.NONE
			_do_shoot(power, is_goal)

	# -- SOLO (unlimited, resets step count) --
	if Input.is_action_just_pressed("solo") and is_carrying:
		_do_solo()

	# -- BOUNCE (once per possession, resets step count) --
	if Input.is_action_just_pressed("bounce") and is_carrying:
		_do_bounce()


func _do_hand_pass() -> void:
	is_carrying = false
	ball.release_hand_pass(aim_dir)


func _do_kick_pass(power: float) -> void:
	is_carrying = false
	ball.release_kick(aim_dir, power, false)


func _do_shoot(power: float, is_goal: bool) -> void:
	is_carrying = false
	ball.release_kick(aim_dir, power, is_goal)


func _do_solo() -> void:
	# Ball briefly drops to foot and is kicked back up — step counter resets.
	steps_taken = 0.0


func _do_bounce() -> void:
	if has_bounced:
		return
	has_bounced = true
	steps_taken = 0.0


# ── GAA carry rules ───────────────────────────────────────────────────────────

func _process_carry_rules(delta: float) -> void:
	if not is_carrying:
		return
	steps_taken += velocity.length() * delta / STEP_DISTANCE
	if steps_taken >= MAX_STEPS:
		_commit_foul()


func _commit_foul() -> void:
	foul_committed.emit(global_position)
	is_carrying = false
	if ball:
		ball.carrier    = null
		ball.ball_state = Ball.State.FREE
		ball.velocity   = Vector2.ZERO
	steps_taken = 0.0
	has_bounced = false


# ── Rendering ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Body circle
	draw_circle(Vector2.ZERO, PLAYER_RADIUS,        C_OUTLINE)
	draw_circle(Vector2.ZERO, PLAYER_RADIUS - 2.5,  C_BODY)

	# Facing dot — small circle offset in facing direction
	draw_circle(facing * (PLAYER_RADIUS * 0.60), 4.0, C_FACING_DOT)

	# Aim arrow when winding up a pass or shot
	if _wind_up != WindUp.NONE:
		_draw_aim_arrow()

	# Step counter dots when carrying
	if is_carrying:
		_draw_step_dots()


func _draw_aim_arrow() -> void:
	var tip    := aim_dir * 52.0
	var perp   := Vector2(-aim_dir.y, aim_dir.x)
	draw_line(Vector2.ZERO, tip,                                   C_AIM_ARROW, 2.0)
	draw_line(tip, tip - aim_dir * 11.0 + perp * 7.0,             C_AIM_ARROW, 2.0)
	draw_line(tip, tip - aim_dir * 11.0 - perp * 7.0,             C_AIM_ARROW, 2.0)


func _draw_step_dots() -> void:
	var steps_used  := int(steps_taken)
	var spacing     := 11.0
	var total_w     := (MAX_STEPS - 1.0) * spacing
	var y_off       := -PLAYER_RADIUS - 14.0
	for i in int(MAX_STEPS):
		var cx   := -total_w * 0.5 + i * spacing
		var col  := Color.RED if i < steps_used else Color(1.0, 1.0, 1.0, 0.45)
		draw_circle(Vector2(cx, y_off), 4.5, col)

	# Remaining text label (drawn as a very small string using draw_string is complex
	# in _draw; dots alone are sufficient for the scaffold)
