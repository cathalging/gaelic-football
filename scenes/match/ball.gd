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

## Arc height (px) of the crossbar. A shot crossing the goal line ABOVE this is a
## point (over the bar); AT or BELOW it is a goal (driven in under the bar).
## match_scene reads this to score, and _draw rings the ball once it clears this
## height so "over the bar" reads at a glance.
const CROSSBAR_HEIGHT := 30.0

## Steady lateral push (px/s²) applied to a ball in flight, set once per match by
## match_scene. Long kicks drift with it; short hand passes barely feel it.
var wind := Vector2.ZERO

# Visuals
const RADIUS  := 11.0
const C_OVER_BAR := Color(1.0, 0.85, 0.25, 0.9)  # halo when the ball is over crossbar height
## Gaelic football is carried in the hands, not at the feet. While CARRIED the ball
## is drawn (presentation only — the sim position is unchanged) lifted to about chest
## height and nudged to the carrier's leading side, so it reads as held, not dribbled.
const CARRY_HEIGHT := 22.0   # world-z the held ball sits at (≈ chest/hands)
const CARRY_SIDE   := 5.0    # screen px the held ball sits to the carrier's facing side

## Generated ball billboard (see MatchSprites). Swappable for real art — assign a
## Texture2D before the first draw and nothing else changes.
var sprite: Texture2D = null


func _ready() -> void:
	if sprite == null:
		sprite = MatchSprites.ball()


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
			velocity += wind * delta   # the ball drifts on the breeze while airborne
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
# range. Min is kept low so a close hand pass drops to a nearby team-mate instead
# of flying straight past the receiver.
const HAND_PASS_MIN := 120.0
const HAND_PASS_MAX := 560.0

## Hand pass — punched along `direction`; distance scaled by `power` (0..1).
func release_hand_pass(direction: Vector2, power: float = 1.0) -> void:
	carrier      = null
	ball_state   = State.FLYING
	velocity     = direction * lerpf(HAND_PASS_MIN, HAND_PASS_MAX, power)
	height       = 6.0
	vertical_speed = 40.0   # tiny loft so it reads as airborne
	is_goal_attempt = false
	shooter      = null     # a pass is not a shot — it can't register a score


## Kicked pass — flatter than a shot, but with far more range than a hand pass: a
## full-power kick pass is a long, raking ball downfield. power 0..1 from the hold.
func release_kick_pass(direction: Vector2, power: float) -> void:
	carrier        = null
	ball_state     = State.FLYING
	is_goal_attempt = false
	shooter        = null   # a pass is not a shot — it can't register a score
	velocity       = direction * lerpf(440.0, 900.0, power)
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
	# 2.5D height illusion in the broadcast view (see PitchProjection). The SHADOW
	# sits on the projected ground at the ball's true world position — the honest
	# read of where it is relative to the posts (what scoring uses) — and shrinks as
	# the ball climbs. The ball SPRITE lifts along the same height→screen mapping the
	# goalposts use, so a lofted point visibly clears the crossbar, while its size is
	# led by depth (near = big, far = small) so it sits properly in the tilted space.
	var gp   := global_position
	var s    := PitchProjection.scale_at(gp.y)
	var base := PitchProjection.ground(gp) - gp   # node origin → projected ground

	# While carried, lift the ball to hand height and offset it to the carrier's
	# leading side so it reads as held in the hands rather than at the feet.
	var carried  := ball_state == State.CARRIED and carrier != null
	var draw_h   := height
	var side_off := 0.0
	if carried:
		draw_h = CARRY_HEIGHT
		var cf: Variant = carrier.get("facing")
		if cf is Vector2 and (cf as Vector2).length() > 0.01:
			side_off = signf((cf as Vector2).x) * CARRY_SIDE

	# Ground shadow — a flattened ellipse that shrinks as the ball climbs.
	var shrink := clampf(1.0 - draw_h / 240.0, 0.35, 1.0)
	draw_set_transform(base, 0.0, Vector2(s, s * 0.5))
	draw_circle(Vector2.ZERO, RADIUS * shrink, Color(0.0, 0.0, 0.0, 0.30))

	# Ball sprite. Size is led by the DEPTH scale `s` (nearer touchline = bigger,
	# far = smaller) so the ball sits in the 2.5D space; height is read from the lift
	# and the over-bar ring, not by ballooning the ball — in a side-on view a lofted
	# ball rises and recedes, it doesn't grow. So `grow` is only a subtle "coming at
	# you" pop, capped low, and never fights the depth cue.
	var lift_px := PitchProjection.lift(gp.y, draw_h)
	var grow    := clampf(1.0 + draw_h / 320.0, 1.0, 1.2)
	draw_set_transform(base + Vector2(side_off * s, -lift_px), 0.0, Vector2(s * grow, s * grow))
	if sprite != null:
		var d := RADIUS * 2.0
		draw_texture_rect(sprite, Rect2(-d * 0.5, -d * 0.5, d, d), false)
	else:
		draw_circle(Vector2.ZERO, RADIUS, Color(0.97, 0.93, 0.80))

	# Over the crossbar — ring the ball so "this is a point, sailing over the bar"
	# reads instantly (and a driven goal attempt staying under the bar does not). Not
	# while carried — the carry lift isn't a shot clearing the bar.
	if not carried and height > CROSSBAR_HEIGHT:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 24, C_OVER_BAR, 2.0)
