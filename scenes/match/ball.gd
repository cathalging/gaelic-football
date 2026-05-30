class_name Ball
extends CharacterBody2D
## Ball — physics, states, and rendering for the match ball.
##
## Height is a separate scalar that simulates the ball rising and falling on a
## kick. It does not affect the 2D world position — it only shifts the draw
## offset and scales the ground shadow, giving a top-down arc illusion.

enum State { FREE, CARRIED, FLYING }

var ball_state: State = State.FREE
var carrier: Node2D = null

## Team (0 = home, 1 = away) that last had possession. Used by the referee to
## decide 45s vs kickouts and which side a sideline ball goes to. -1 = untouched.
var last_touch_team: int = -1

## Set by match_scene before the first pass/shot so scoring logic can branch.
var is_goal_attempt := false

## The player who took the current shot — set on release, used to credit scorers.
## Cleared on pick-up so a score is only credited to whoever actually shot it.
var shooter: Node2D = null

## Set by match_scene during the goal replay — the ball suspends its own physics
## and is positioned frame-by-frame from the recorded buffer.
var replay_frozen := false

# Horizontal physics
const H_FRICTION := 4.5       # applied as: vel = vel.move_toward(ZERO, H_FRICTION * |vel| * dt + 30)

# Vertical (arc) simulation — does not affect world position
var height          := 0.0
var vertical_speed  := 0.0
const GRAVITY       := 560.0  # px / s² (gentler = longer hang time so shots carry over the line)

# Visuals
const RADIUS  := 11.0
const C_SEAM  := Color(0.55, 0.34, 0.14)
const C_INNER := Color(0.98, 0.93, 0.76)


func _physics_process(delta: float) -> void:
	if replay_frozen:
		# Goal replay — match_scene positions us from the recorded buffer.
		queue_redraw()
		return
	# Collision is only active for a loose ball on the ground (FREE). While CARRIED
	# the shape would depenetrate the carrier and launch them; while FLYING the
	# ball is in the air and must pass *over* players — otherwise shots and passes
	# get "blocked" by bodies they should be sailing above.
	$CollisionShape2D.disabled = ball_state != State.FREE
	match ball_state:
		State.FREE:
			var speed := velocity.length()
			velocity = velocity.move_toward(Vector2.ZERO, H_FRICTION * speed * delta + 30.0 * delta)
			move_and_slide()
		State.CARRIED:
			if carrier:
				global_position = carrier.global_position
			velocity = Vector2.ZERO
		State.FLYING:
			move_and_slide()
			vertical_speed -= GRAVITY * delta
			height += vertical_speed * delta
			if height <= 0.0:
				height = 0.0
				vertical_speed = 0.0
				ball_state = State.FREE
	queue_redraw()


## Called by Player when they pick the ball up.
func pick_up(new_carrier: Node2D) -> void:
	ball_state   = State.CARRIED
	carrier      = new_carrier
	shooter      = null   # a fresh carry — clear any stale shooter credit
	height       = 0.0
	vertical_speed = 0.0
	velocity     = Vector2.ZERO
	var t: Variant = new_carrier.get("team")
	if t != null:
		last_touch_team = t


# Hand pass — short, flat punch. Distance scales with the hold (power 0..1): a
# quick tap is a short pass to a nearby player; a full hold reaches the old fixed
# range. Min is low so close passes don't fly straight past the receiver.
const HAND_PASS_MIN := 210.0
const HAND_PASS_MAX := 560.0

## Hand pass — punched along `direction`; distance scaled by `power` (0..1).
func release_hand_pass(direction: Vector2, power: float = 1.0) -> void:
	carrier      = null
	ball_state   = State.FLYING
	velocity     = direction * lerpf(HAND_PASS_MIN, HAND_PASS_MAX, power)
	height       = 6.0
	vertical_speed = 40.0   # tiny loft so it reads as airborne
	is_goal_attempt = false


## Kicked pass — flatter and shorter than a shot, but with more range than a hand
## pass. power 0..1 from the hold time.
func release_kick_pass(direction: Vector2, power: float) -> void:
	carrier        = null
	ball_state     = State.FLYING
	is_goal_attempt = false
	velocity       = direction * lerpf(440.0, 700.0, power)
	vertical_speed = lerpf(120.0, 200.0, power)
	height         = 5.0


## Charged kick. power 0..1. is_goal drives the scoring branch in match_scene.
## A point attempt is lofted so it clears the bar; a goal attempt is driven in
## low and hard, so a defender standing in front can block it (see match_scene).
func release_kick(direction: Vector2, power: float, is_goal: bool) -> void:
	carrier      = null
	ball_state   = State.FLYING
	is_goal_attempt = is_goal
	if is_goal:
		velocity       = direction * lerpf(540.0, 820.0, power)
		vertical_speed = lerpf(50.0, 120.0, power)   # stays low — blockable
		height         = 4.0
	else:
		velocity       = direction * lerpf(360.0, 720.0, power)
		vertical_speed = lerpf(240.0, 460.0, power)  # lofted to clear the bar
		height         = 5.0


func _draw() -> void:
	# Top-down height illusion. The SHADOW is always drawn at the ball's true
	# ground position (Vector2.ZERO = its real world coords), so the shadow is the
	# honest read of where the ball is relative to the posts — that's what scoring
	# uses. The ball SPRITE lifts slightly and, more importantly, GROWS with height
	# so "in the air / over the bar" is obvious at a glance.
	var lift  := -height * 0.30                       # modest screen-up offset
	var scale := clampf(1.0 + height / 90.0, 1.0, 2.4)  # grows the higher it goes

	# Ground shadow at the true position — shrinks as the ball climbs.
	var s := clampf(1.0 - height / 240.0, 0.35, 1.0)
	draw_circle(Vector2.ZERO, RADIUS * s, Color(0.0, 0.0, 0.0, 0.30))

	var c := Vector2(0.0, lift)
	draw_circle(c, RADIUS * scale,         C_SEAM)
	draw_circle(c, (RADIUS - 1.8) * scale, C_INNER)
