class_name AIPlayer
extends CharacterBody2D
## AIPlayer — unified player node for both teams.
##
## team 0 = home (blue, attacks +x toward x=+700).
## team 1 = away (red, attacks −x toward x=−700).
##
## States: Idle (hold team shape), MoveToBall (dribble), Chase (press the ball).
## When is_human_controlled: reads input instead of running the state machine.
## match_scene sets is_ball_chaser on exactly one AI per team each frame.

signal foul_committed(position: Vector2, team: int)
## Emitted when this player completes a pass (hand or kick) to a teammate — not a
## shot. The match scene uses it to hand control of the receiver to another human
## on the team (the turn-based give-and-go when two humans share a side).
signal passed(by: AIPlayer)

enum State { IDLE, MOVE_TO_BALL, CHASE }

# Movement / carry.
const WALK_SPEED    := 185.0   # normal running speed (humans & AI carriers)
const CHASE_SPEED   := 245.0   # AI sprint when chasing a LOOSE ball (a race for it)
const PRESS_SPEED   := 174.0   # AI speed when pressing an opponent CARRIER — set just
							   # BELOW carrier speed so a carrier running straight can
							   # break away; defenders rely on angles, the solo dip and
							   # the tackle to catch them, not raw pace
const ACCEL         := 14.0
const DECEL         := 10.0
const PICK_RADIUS   := 42.0
const PLAYER_RADIUS := 14.0
const MAX_STEPS     := 4.0
const STEP_DISTANCE := 125.0   # px of carry per "step" — lower = counter fills faster

# Solo dip — a solo (toe-to-hand) is unlimited but momentarily checks your stride,
# dropping you to a slow speed for a split second. A bounce/hop has no such cost
# (but is once per possession), so running and hopping is the way to keep gliding.
const SOLO_SLOW_DURATION := 0.20
const SOLO_SLOW_SPEED    := 92.0

# Pitch half-extents (must match match_scene / pitch). Used so AI carriers steer
# away from the touchline instead of dribbling out of bounds.
const PITCH_HALF_LENGTH := 900.0
const PITCH_HALF_WIDTH  := 560.0
const EDGE_MARGIN        := 70.0   # start steering back in once this close to a line

# Dash — a short burst of speed available to any controlled player (trial: not
# just the carrier), then a cooldown. A colour ring around the player shows when
# it's ready (see _draw).
const DASH_SPEED    := 380.0
const DASH_DURATION := 0.18   # seconds at dash speed
const DASH_COOLDOWN := 1.6    # seconds before another dash is available
const DASH_ACCEL    := 35.0   # snappy acceleration into the burst

# Stamina — a 0..1 reserve the carrier spends to dash and (slowly) to keep
# sprinting, recovered while walking/idle. A dash needs a minimum reserve, so a
# tired carrier can't keep bursting away. Displayed on the HUD for the human.
const STAMINA_DASH_COST   := 0.28   # spent by a single dash burst
const STAMINA_RUN_DRAIN   := 0.06   # per second while moving near full speed
const STAMINA_REGEN       := 0.20   # per second while walking slowly / idle
const DASH_MIN_STAMINA    := 0.20   # can't start a dash below this reserve

# Tackling — a defender must press `tackle` near a carrier to start a timing
# contest (resolved in match_scene). These tune reach, recovery and the stun
# applied on each outcome.
# Engagement dwell — before a tackle can be started, the defender must first close
# to within TACKLE_ENGAGE_RADIUS of the carrier and *stay* there for
# TACKLE_ENGAGE_TIME. This stops "touch-and-steal": you have to get alongside and
# harry your man before you can challenge. It gates only the tackle (can_tackle) —
# charging down a shot from the front is a separate front-on block (see
# match_scene._check_shot_block) and is unaffected.
#
# The charge radius is kept a touch *below* match_scene.TACKLE_REACH (the distance
# at which a tackle can actually be struck), so a full ring always means you are in
# range to tackle — never "bar full but the tackle is refused". Keep this invariant
# (TACKLE_ENGAGE_RADIUS < match_scene.TACKLE_REACH) if you retune either value.
const TACKLE_ENGAGE_RADIUS := 54.0   # px the defender must be within to build engagement
const TACKLE_ENGAGE_TIME   := 0.45   # seconds of close pressure needed before a tackle
const TACKLE_IMMUNITY  := 0.7    # seconds a fresh carrier cannot be tackled
const TACKLE_COOLDOWN  := 1.6    # seconds before a defender can tackle again
const TACKLE_CD_MISS   := 2.2    # longer cooldown after a mistimed (failed) tackle
const STUN_LOSE_BALL   := 1.0    # carrier stun after a clean steal
const STUN_KNOCK_LOOSE := 0.6    # carrier stun after the ball is knocked loose
const STUN_MISS        := 1.0    # tackler stun after a failed tackle

# Team shape / spacing — keeps players in distinct lanes instead of clumping.
const SEP_RADIUS   := 64.0    # teammates closer than this gently push apart
const SEP_PUSH_MAX := 90.0    # cap on the separation steering offset
const SHIFT_X_MAX  := 200.0   # how far the block slides toward the ball (x)
const SHIFT_Y_MAX  := 110.0   # …and (y)

# Steering / avoidance — players arc around bodies in their path instead of
# jamming into them. A general lateral nudge handles off-ball movers and chasers;
# the carrier gets the richer context-steering below. Scaled by the team's
# `tactics.avoidance_strength` (0 = barge straight through).
const AVOID_RADIUS   := 46.0   # a body within this, ahead of our heading, is steered around
const AVOID_STRENGTH := 1.3    # base lateral weight (× tactics.avoidance_strength)
# Carrier context-steering — each frame a fan of candidate headings is scored by
# forward progress minus the danger of bodies in that lane, and the best lane is
# driven. This is what makes a carrier veer around a defender toward open ground
# rather than running into them and stalling. Fully geometric → deterministic.
const CARRY_LANES      : Array[float] = [-1.05, -0.7, -0.35, 0.0, 0.35, 0.7, 1.05]
const CARRY_LOOKAHEAD  := 160.0   # px ahead a candidate lane is scanned for blockers
const CARRY_LANE_WIDTH := 42.0    # px either side of a lane within which a body blocks it

# Man-marking & off-the-ball movement (Group A). Backs/mids track their man when
# defending, which pulls them out of the goalmouth when a forward roams; forwards
# make runs / hold a supporting shape when attacking, giving the carrier a runner to
# find. The tunables for this — mark tightness, support push, pass lead, runner
# count, attacking width — now live on TacticsData and are read via _tactics().
const KICK_PASS_RANGE := 330.0 # passes longer than this are delivered as a kick pass
# Off-the-ball runs — a chosen runner samples receiving spots (a fan goalside of
# itself) and moves to the most open one that sits in a clear passing lane, so the
# carrier always has a forward option instead of a static line. See _run_into_space.
const RECEIVE_ANGLES : Array[float] = [-1.0, -0.55, -0.25, 0.0, 0.25, 0.55, 1.0]
const RECEIVE_DISTS  : Array[float] = [85.0, 160.0]
const MAX_RECEIVE_DIST := 540.0          # ignore a run needing an unrealistically long pass
const RECEIVE_LANE_PENALTY := 100000.0   # a blocked passing lane all but rules a spot out
# Sidestep — dashing while carrying beats a close defender: a lateral kink around
# them plus a brief window where their tackle can't land.
const SIDESTEP_IMMUNITY := 0.35
const SIDESTEP_RANGE    := 60.0

# AI decision timing
const SHOOT_RANGE    := 200.0   # px from goal centre — comfortable goal range
const DECISION_DELAY := 0.5     # seconds after pickup before pass/shoot decision

# Carrier decision-making — the AI backs itself to carry and commits to a run;
# it only looks for a pass when it is actually pressured (or grinding to a halt),
# and never fires two passes in quick succession. This is what gives a defender a
# carrier to chase down and tackle, instead of the ball being offloaded the
# instant you close in.
const PASS_COOLDOWN    := 0.8     # min seconds between AI passes (no ping-pong)
const POINT_RANGE      := 430.0   # will take a point from out to here (GAA long range)
const GOAL_MOUTH_RANGE := 380.0   # inside this, funnel the carry toward the goal mouth
const GOAL_LANE_CLEARANCE := 30.0 # an opponent nearer than this to the shot line blocks a goal attempt

# Goalkeeper — holds the goal line, tracks the ball's y within the posts, and
# edges out to narrow the angle. The save itself is a seeded roll in match_scene;
# good positioning here is what makes that roll likely.
const KEEPER_SPEED      := 215.0   # how fast the keeper slides along its line
const KEEPER_GUARD_Y    := 70.0    # max |y| the keeper strays from goal centre
const KEEPER_LINE_INSET := 56.0    # px the keeper stands in front of its goal line
const KEEPER_CLAIM_DIST := 120.0   # rush out to gather a loose ball this close
const C_KEEPER_BODY     := Color(0.95, 0.78, 0.16)  # amber — keepers wear a clashing kit
const STUCK_WINDOW     := 0.6     # window over which carry progress is measured
const STUCK_DISTANCE   := 26.0    # less ground than this made in the window = stuck
const PASS_LANE_RADIUS := 36.0    # an opponent this close to the pass line cuts it out
const MARKED_RADIUS    := 56.0    # a receiver with an opponent this close is too marked
const KICKOUT_SHORT_RANGE := 360.0 # keeper plays it short to an open man inside this

# Jockey / contain — a defender (without the ball) holds `jockey` to shadow the
# carrier at a controlled, slower speed, staying square to them to line up a clean
# tackle. Defending becomes positioning, not out-and-out pace.
const JOCKEY_SPEED := 150.0
const C_JOCKEY     := Color(0.30, 0.80, 1.00, 0.85)  # contain arc

# Human input timing
const TAP_THRESHOLD    := 0.20  # seconds — tap vs hold for pass and shoot
const SHOOT_DOUBLE_TAP := 0.28  # window to register a 2nd shoot tap (goal attempt)
const SHOOT_MAX_HOLD   := 0.8   # hold time that maps to full power — short, so the bar fills fast

# Shooting skill (Group B). A shot drifts more the harder it is — long range and
# tight marking spray it wide — so picking the right moment to shoot is the skill.
const MAX_SHOT_SPREAD  := 0.13   # radians of aim error on the hardest shot
# Overcharge — holding the shot bar to the very top sprays it. There's a sweet spot
# just below full power, so you can't mash to max every time; release a touch early.
const OVERCHARGE_KNEE   := 0.82  # power above which accuracy starts to fall away
const OVERCHARGE_SPREAD := 0.12  # extra radians of aim error at full (overcharged) power
const FIST_RANGE       := 150.0  # within this, a hand pass at goal is a fisted finish
const FIRST_TIME_RANGE := 62.0   # strike a loose / incoming ball first-time within this

# Visual
const C_DOT       := Color(1.0, 1.0, 1.0)
## World px the upright billboard sprite stands tall (feet on the ground shadow, head
## at the top). Indicators anchor relative to this — see _draw and SEL_Y / DOTS_Y.
const SPRITE_HEIGHT := 56.0
const SEL_Y       := -SPRITE_HEIGHT - 2.0    # selection-triangle tip, just above the head
const DOTS_Y      := -SPRITE_HEIGHT - 18.0   # step dots / stun stars, above the head
const CHEST_Y     := -SPRITE_HEIGHT * 0.5    # aim-arrow origin, mid-figure
const C_MARKER    := Color(1.0, 0.88, 0.1)   # yellow selection triangle
const C_CHEVRON   := Color(1.0, 1.0, 1.0, 0.5)  # ground facing chevron
const C_AIM       := Color(1.0, 0.88, 0.1, 0.90)
const C_DASH_RDY  := Color(0.30, 1.00, 0.55, 0.95)  # dash ready ring
const C_DASH_CD   := Color(0.45, 0.45, 0.50, 0.55)  # dash cooling ring (track)
const C_DASH_FILL := Color(0.30, 0.80, 1.00, 0.90)  # dash cooldown progress arc
const C_STUN      := Color(1.0, 0.85, 0.2, 0.95)    # stun indicator
const C_ENGAGE_TRK := Color(0.55, 0.50, 0.45, 0.45) # tackle engagement track
const C_ENGAGE_FIL := Color(1.00, 0.55, 0.10, 0.95) # tackle engagement filling
const C_ENGAGE_RDY := Color(1.00, 0.20, 0.20, 0.98) # engaged — tackle ready (press F)
const C_ENGAGE_CD  := Color(0.55, 0.30, 0.28, 0.55) # post-tackle recovery (can't yet)

# ── Configuration (set by match_scene before add_child) ──────────────────────

## 0 = home (blue, attacks +x).  1 = away (red, attacks −x).
var team: int = 1

## Wired by match_scene after instantiation.
var ball: Ball   = null
var teammates: Array = []  # all players on this team (including self)
var enemies:   Array = []  # all players on the opposing team

## This team's behaviour profile (press, marking, runs, steering). Set by
## match_scene on spawn; every tactical decision reads from it instead of a baked
## constant, so a club's tactics can vary behaviour without touching this script.
## Falls back to baseline values when null (see _tactics).
var tactics: TacticsData = null

## Upright billboard texture drawn in the 2.5D view. Left null, a generated
## placeholder kit is built in _ready (see MatchSprites); assign a real Texture2D
## before the node draws to swap in finished art with no other changes.
var sprite: Texture2D = null

## Formation position to drift back to when idle/supporting.
var home_position := Vector2.ZERO

## Set by match_scene each frame — true for exactly one AI per team.
var is_ball_chaser      := false
var is_human_controlled := false
var is_selected         := false  # draw the selection marker
## Colour of this player's selection marker — set per human seat so two players on
## one team can be told apart. Defaults to the classic yellow for AI / unassigned.
var marker_color: Color = C_MARKER

## The input source driving this player when human-controlled — one per human
## seat, routed to a single device (see PlayerInput). null for AI players. Set by
## match_scene alongside is_human_controlled; all human input reads go through it
## instead of the global Input singleton, so each seat drives only its own player.
var input: PlayerInput = null

## Set by match_scene to hold a player still: the taker of a set piece (holding the
## ball on the spot until they kick) and everyone during a tackle contest. Other
## players are left unfrozen during a set piece so they can move and make runs.
var frozen := false

## Set by match_scene during the slow-motion goal replay — the player suspends all
## of its own logic and is positioned frame-by-frame from the recorded buffer.
var replay := false

## Set by match_scene during the pre-set-piece countdown. While true the taker may
## aim but not yet kick; cleared when the countdown ends and play resumes.
var set_piece_locked := false

## Squad number (1..15), assigned on spawn. Used to credit/display scorers.
var jersey := 0

## True for the goalkeeper (roster index 0). The keeper holds its goal line and
## makes saves instead of chasing upfield (see _run_keeper and the keeper save
## roll in match_scene). Set by match_scene before add_child so _ready sees it.
var is_keeper := false

## The opponent this player man-marks when defending (set by match_scene). Backs
## and midfielders mark; forwards and the keeper leave this null and hold a zone,
## so the attacking unit stays high to stretch the defence.
var mark_target: AIPlayer = null

## 0..1 stamina reserve (see the stamina constants above).
var stamina := 1.0

## Set by match_scene on the player taking a free/45/sideline/kickout. While
## frozen, this player may still aim and pass/shoot (human) or be told to take
## the kick (AI) — but cannot run until play resumes.
var is_set_piece_taker := false

# ── Runtime state ─────────────────────────────────────────────────────────────

var state   := State.IDLE
var facing  := Vector2.LEFT
var aim_dir := Vector2.LEFT   # updated in _update_aim when human-controlled

var is_carrying := false
var steps_taken := 0.0
var has_bounced := false
var _carry_timer := 0.0
var _solo_slow  := 0.0   # >0 for the split-second stride check just after a solo

# Carrier decision state.
var _pass_cd      := 0.0           # >0 just after a pass (blocks rapid re-passing)
var _stuck_timer  := 0.0           # accumulates toward STUCK_WINDOW while carrying
var _stuck_anchor := Vector2.ZERO  # position at the last stuck check

# Human defender is holding the contain (jockey) button this frame.
var _jockeying := false

# Tackle / stun timers — counted down each frame.
var _stun_timer      := 0.0  # >0 while stunned (can't move, act, pick up or tackle)
var _tackle_cd       := 0.0  # >0 while this player can't start another tackle
var _tackle_immunity := 0.0  # >0 while this carrier can't be tackled
var _engage_time     := 0.0  # seconds spent within engage radius of the enemy carrier

# Wind-up for human pass / shoot
var _pass_held_t  := 0.0
var _shoot_held_t := 0.0

# Pass gesture machine (human), mirroring the shoot gesture: 0 idle, 1 first press
# held, 2 awaiting a 2nd tap, 3 second press held (kick-pass charging). A single
# tap is a hand pass; a double-tap-and-hold is a kicked pass (power from the hold).
var _pass_phase  := 0
var _pass_wait_t := 0.0

# Shoot state machine (human): 0 idle, 1 first press held, 2 awaiting 2nd tap,
# 3 second press held (goal attempt charging).
var _shoot_phase       := 0
var _shoot_wait_t      := 0.0   # time since the first quick tap was released
var _shoot_tap_power   := 0.0   # power captured from a single quick tap

# Dash timers — counted down each frame.
var _dash_time := 0.0   # >0 while the dash burst is active
var _dash_cd   := 0.0   # >0 while the dash is on cooldown
var _dash_dir  := Vector2.RIGHT   # locked direction for the current dash

# Team-derived values — computed in _ready.
var _goal_centre: Vector2
var _attack_dir:  Vector2
var _c_body:      Color
var _c_outline:   Color

# Per-player shot RNG, seeded from team+jersey so shot spread is deterministic and
# reproducible rather than using global randf() (see CLAUDE.md determinism rules).
var _shot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	if team == 0:
		_goal_centre = Vector2( 900.0, 0.0)
		_attack_dir  = Vector2.RIGHT
		_c_body      = Color(0.22, 0.42, 0.78)
		_c_outline   = Color(0.10, 0.20, 0.44)
		aim_dir      = Vector2.RIGHT
		facing       = Vector2.RIGHT
	else:
		_goal_centre = Vector2(-900.0, 0.0)
		_attack_dir  = Vector2.LEFT
		_c_body      = Color(0.78, 0.22, 0.22)
		_c_outline   = Color(0.44, 0.10, 0.10)
		aim_dir      = Vector2.LEFT
		facing       = Vector2.LEFT
	if is_keeper:
		_c_body = C_KEEPER_BODY   # clashing kit so the keeper reads at a glance
	if sprite == null:
		sprite = MatchSprites.player(_c_body, _c_outline)   # generated placeholder kit
	_shot_rng.seed = hash(Vector2i(team, jersey))


## Shared fallback profile so the node is runnable even if match_scene never wired
## one (isolated scene, tests). Construct lazily — every default plays as the old
## hand-tuned constants did.
static var _default_tactics: TacticsData = null

## The active tactics profile (the team's, or the shared baseline default).
func _tactics() -> TacticsData:
	if tactics != null:
		return tactics
	if _default_tactics == null:
		_default_tactics = TacticsData.new()
	return _default_tactics


func _physics_process(delta: float) -> void:
	if replay:
		# Goal replay — match_scene drives our position/facing from the recorded
		# buffer; we do nothing but redraw at whatever pose we've been placed in.
		queue_redraw()
		return
	if frozen:
		# Set-piece — stand still (a carried ball follows us in place). The taker
		# may still aim and kick; everyone else just holds position. During the
		# pre-kick countdown (set_piece_locked) the taker can aim but not yet kick.
		velocity = Vector2.ZERO
		move_and_slide()
		if is_set_piece_taker and is_human_controlled:
			_aim_in_place()
			_update_aim()
			if not set_piece_locked:
				_process_human_actions(delta)
		queue_redraw()
		return
	_tackle_immunity = maxf(0.0, _tackle_immunity - delta)
	_tackle_cd       = maxf(0.0, _tackle_cd - delta)
	_stun_timer      = maxf(0.0, _stun_timer - delta)
	_dash_cd         = maxf(0.0, _dash_cd - delta)
	_dash_time       = maxf(0.0, _dash_time - delta)
	_pass_cd         = maxf(0.0, _pass_cd - delta)
	_solo_slow       = maxf(0.0, _solo_slow - delta)

	# Stunned — frozen in place for a moment (after losing the ball or a missed
	# tackle). No movement, no actions; a carried ball would already be gone.
	if _stun_timer > 0.0:
		velocity = velocity.lerp(Vector2.ZERO, DECEL * delta)
		move_and_slide()
		queue_redraw()
		return

	if is_human_controlled:
		_update_aim()
		_process_human_movement(delta)
		_process_pickup()
		_process_human_actions(delta)
		if is_carrying:
			_process_carry(delta)
	else:
		if is_keeper and not is_carrying:
			_run_keeper(delta)
		else:
			_update_state()
			_run_state(delta)
		_process_pickup()
		if is_carrying:
			_process_carry(delta)
	_update_tackle_engagement(delta)
	_update_stamina(delta)
	move_and_slide()
	queue_redraw()


## Build up "engagement" while shadowing the enemy carrier: the timer climbs only
## while within TACKLE_ENGAGE_RADIUS of them and resets the moment they break away
## (or we win the ball). A defender can only start a tackle once it has reached
## TACKLE_ENGAGE_TIME — see can_tackle. Both the human and AI tackle paths share it.
func _update_tackle_engagement(delta: float) -> void:
	if is_carrying:
		_engage_time = 0.0
		return
	var carrier := _current_enemy_carrier()
	if carrier != null \
			and global_position.distance_to(carrier.global_position) <= TACKLE_ENGAGE_RADIUS:
		_engage_time += delta
	else:
		_engage_time = 0.0


## Spend stamina while sprinting near full speed, recover it while taking it easy.
## The dash burst spends a lump up front (see _process_human_movement), so here we
## only meter the cost of sustained running versus recovery.
func _update_stamina(delta: float) -> void:
	if _dash_time > 0.0:
		return
	if velocity.length() > WALK_SPEED * 0.9:
		stamina = maxf(0.0, stamina - STAMINA_RUN_DRAIN * delta)
	else:
		stamina = minf(1.0, stamina + STAMINA_REGEN * delta)


# ── Tackling outcomes ───────────────────────────────────────────────────────--
# Tackles are *initiated* and *resolved* by match_scene (a timing minigame for
# the human, a seeded roll for AI). These methods just apply the agreed outcome
# so both paths share one implementation.

## True if this defender may start a tackle right now: not carrying, not stunned,
## off cooldown, and having spent enough time pressing the carrier up close (see
## _update_tackle_engagement). The proximity dwell is what stops instant steals.
func can_tackle() -> bool:
	return not is_carrying and _stun_timer <= 0.0 and _tackle_cd <= 0.0 \
			and _engage_time >= TACKLE_ENGAGE_TIME


## True when a defender meets the carrier from the front or side. A tackle from
## behind (relative to the carrier's facing) is illegal — a foul.
func is_legal_tackle_angle(victim: AIPlayer) -> bool:
	var to_tackler := global_position - victim.global_position
	if to_tackler.length() < 0.01:
		return true
	return victim.facing.dot(to_tackler.normalized()) > -0.25


## Stun this player in place for `t` seconds (clears any carry/wind-up).
func apply_stun(t: float) -> void:
	_stun_timer = maxf(_stun_timer, t)
	_pass_phase  = 0
	_shoot_phase = 0


func begin_tackle_cooldown(t: float) -> void:
	_tackle_cd = t


## Top the dash back up (no cooldown, no active burst). Called when a player comes
## under human control so a switched-to player always has their dash ready — the
## dash recovers in the background regardless of who you were controlling.
func refill_dash() -> void:
	_dash_cd   = 0.0
	_dash_time = 0.0


## Outcome: clean steal. The victim loses the ball and is stunned; this defender
## takes possession.
func steal_from(victim: AIPlayer) -> void:
	victim._drop_carry()
	victim.apply_stun(STUN_LOSE_BALL)
	_pick_up()
	begin_tackle_cooldown(TACKLE_COOLDOWN)


## Outcome: knocked loose. The victim loses the ball (stunned briefly) and the
## ball spills free in `dir`; nobody is handed possession — both must recover it.
func knock_loose(victim: AIPlayer, dir: Vector2, speed: float) -> void:
	victim._drop_carry()
	victim.apply_stun(STUN_KNOCK_LOOSE)
	if ball:
		ball.carrier    = null
		ball.ball_state = Ball.State.FREE
		ball.velocity   = dir * speed
		ball.height     = 0.0
		ball.vertical_speed = 0.0
	begin_tackle_cooldown(TACKLE_COOLDOWN)


## Outcome: missed tackle. This defender is stunned and put on a long cooldown.
func miss_tackle() -> void:
	apply_stun(STUN_MISS)
	begin_tackle_cooldown(TACKLE_CD_MISS)


## Drop possession without any award (used by the tackle outcomes above).
func _drop_carry() -> void:
	is_carrying  = false
	_carry_timer = 0.0
	steps_taken  = 0.0
	_pass_phase  = 0
	_shoot_phase = 0


# ── AI state selection ────────────────────────────────────────────────────────

func _update_state() -> void:
	# Carrier dribbles; the one designated chaser presses the ball; everyone
	# else holds their position in the team shape (see _tactical_position).
	# match_scene assigns exactly one chaser per team, so only one player ever
	# converges on the ball — the rest stay spread across the pitch.
	if is_carrying:
		state = State.MOVE_TO_BALL
	elif is_ball_chaser:
		state = State.CHASE
	else:
		state = State.IDLE


# ── AI state execution ────────────────────────────────────────────────────────

func _run_state(delta: float) -> void:
	match state:
		State.IDLE:
			_move_toward(_off_ball_target(), WALK_SPEED, delta)
		State.MOVE_TO_BALL:
			if is_carrying:
				_run_with_ball(delta)
			else:
				_maybe_ai_dash()
				_move_toward(ball.global_position, _chase_speed(), delta)
		State.CHASE:
			_maybe_ai_dash()
			_move_toward(ball.global_position, _chase_speed(), delta)


## Goalkeeper movement. Sit just in front of the goal line and track the ball's y
## (capped to within the posts), so a shot has to beat the keeper's reach. Rush out
## to gather a loose ball that strays into the area. Shot-stopping itself is a
## seeded save roll in match_scene — this positioning is what makes saves likely.
func _run_keeper(delta: float) -> void:
	var goal_x := -_goal_centre.x   # the goal this keeper defends
	# Rush out for a loose ball that has come into the keeper's area.
	if ball.ball_state == Ball.State.FREE \
			and global_position.distance_to(ball.global_position) < KEEPER_CLAIM_DIST:
		_move_toward(ball.global_position, CHASE_SPEED, delta)
		return
	var line_x   := goal_x - signf(goal_x) * KEEPER_LINE_INSET
	var target_y := clampf(ball.global_position.y, -KEEPER_GUARD_Y, KEEPER_GUARD_Y)
	_move_toward(Vector2(line_x, target_y), KEEPER_SPEED, delta)


## Pursuit speed: a full sprint for a loose ball (a 50/50 race), but only a gentle
## press when the ball is held by an opponent — otherwise the carrier can never
## make ground and gets reeled in every time.
func _chase_speed() -> float:
	if ball != null and ball.ball_state == Ball.State.CARRIED and ball.carrier != null:
		var c := ball.carrier as AIPlayer
		if c != null and c.team != team:
			return PRESS_SPEED
	return CHASE_SPEED


## Carrier running speed — full pace normally, dropping to a crawl for the brief
## window right after a solo (see _solo_slow). Used by both human and AI carriers.
func _carry_speed() -> float:
	return SOLO_SLOW_SPEED if _solo_slow > 0.0 else WALK_SPEED


## Trigger a dash burst toward `dir` if one is available (off cooldown, enough
## stamina, not mid-solo). Deterministic — no RNG — so the sim stays reproducible.
## The burst itself is applied in _move_toward while _dash_time > 0.
func _maybe_dash(dir: Vector2) -> void:
	if _dash_cd > 0.0 or _dash_time > 0.0 or _solo_slow > 0.0:
		return
	if stamina < DASH_MIN_STAMINA or dir.length() < 0.01:
		return
	_dash_time = DASH_DURATION
	_dash_cd   = DASH_COOLDOWN
	_dash_dir  = dir.normalized()
	stamina    = maxf(0.0, stamina - STAMINA_DASH_COST)


## Off-ball dash decisions: explode onto a loose ball that's a short sprint away
## (winning the race), or lunge to close the last gap on an enemy carrier so a
## tackle can land despite the gentle press speed.
func _maybe_ai_dash() -> void:
	if ball == null:
		return
	if ball.ball_state == Ball.State.FREE:
		var d := global_position.distance_to(ball.global_position)
		if d >= 70.0 and d <= 340.0:
			_maybe_dash(ball.global_position - global_position)
	elif ball.ball_state == Ball.State.CARRIED and ball.carrier != null:
		var c := ball.carrier as AIPlayer
		if c.team != team:
			var d := global_position.distance_to(c.global_position)
			if d >= 30.0 and d <= 130.0:
				_maybe_dash(c.global_position - global_position)


func _run_with_ball(delta: float) -> void:
	_carry_timer += delta

	# Settle on the ball briefly before deciding anything.
	if _carry_timer < DECISION_DELAY:
		_move_dir(_carry_steer_dir(), _carry_speed(), delta)
		return

	var dist_goal := global_position.distance_to(_goal_centre)

	# In close — go for goal if there's a clear lane to the corner, otherwise take
	# the point on (a lofted point clears the bar and can't be blocked low).
	if dist_goal < SHOOT_RANGE:
		_ai_shoot(_goal_lane_clear())
		return

	var pressured := _nearest_enemy_distance() < _tactics().press_trigger_distance
	var stuck := _carry_is_stuck(delta)

	# Only offload when actually pressured (or grinding to a halt). Otherwise back
	# yourself to carry — this is what leaves a defender a carrier to engage.
	if (pressured or stuck) and _pass_cd <= 0.0:
		var target := _best_pass_target()
		if target:
			_ai_pass_to(target)
			return
		# No pass on, but in range — take the point on rather than running into the
		# tackle / grinding into traffic in front of goal.
		if dist_goal < POINT_RANGE:
			_ai_shoot(false)
			return

	# Simulate a solo to reset the step counter (with the brief solo stride check).
	if steps_taken > 2.5:
		steps_taken = 0.0
		_solo_slow  = SOLO_SLOW_DURATION
		return

	# Burst away from a close presser, bursting along the open lane (not blindly
	# downfield) so the dash carries the carrier around the defender, not into them.
	var steer := _carry_steer_dir()
	if pressured:
		_maybe_dash(steer)
	_move_dir(steer, _carry_speed(), delta)


## Closest opponent distance — used to decide if the carrier is under pressure.
func _nearest_enemy_distance() -> float:
	var best := INF
	for e in enemies:
		var d := (e as AIPlayer).global_position.distance_to(global_position)
		if d < best:
			best = d
	return best


## True if the carrier has made almost no ground over the last STUCK_WINDOW — e.g.
## bottled up against the keeper/defenders near the posts. Resets each check.
func _carry_is_stuck(delta: float) -> bool:
	_stuck_timer += delta
	if _stuck_timer < STUCK_WINDOW:
		return false
	var moved := global_position.distance_to(_stuck_anchor)
	_stuck_anchor = global_position
	_stuck_timer  = 0.0
	return moved < STUCK_DISTANCE


## The opposing carrier, if any — used by the human jockey to face who they contain.
func _current_enemy_carrier() -> AIPlayer:
	for e in enemies:
		var a := e as AIPlayer
		if a.is_carrying:
			return a
	return null


## The carrier's *desired* heading before avoidance: toward the goal mouth when in
## range (so an off-centre carrier converges on a shooting position instead of
## running along the end line), otherwise downfield — steered back infield near a
## touchline or end line so it doesn't dribble out of bounds and force a restart.
func _carry_heading() -> Vector2:
	if global_position.distance_to(_goal_centre) < GOAL_MOUTH_RANGE:
		var to_goal := _goal_centre - global_position
		return to_goal.normalized() if to_goal.length() > 0.01 else _attack_dir
	var drive := _attack_dir
	if absf(global_position.y) > PITCH_HALF_WIDTH - EDGE_MARGIN:
		drive.y -= signf(global_position.y) * 1.3
	if absf(global_position.x) > PITCH_HALF_LENGTH - EDGE_MARGIN:
		drive.x -= signf(global_position.x) * 1.3
	return drive.normalized()


## Context-steering: choose the carry heading that best trades forward progress for
## a clear lane, so the carrier arcs around defenders toward open ground instead of
## dribbling into them and grinding to a halt. Samples a fan of headings around the
## goal-seeking direction, scores each by progress minus the danger of bodies in
## that lane, and returns the winner. Deterministic — no RNG.
func _carry_steer_dir() -> Vector2:
	var goal_dir := _carry_heading()
	var avoid := _tactics().avoidance_strength
	var best_dir := goal_dir
	var best_score := -INF
	for off in CARRY_LANES:
		var cand := goal_dir.rotated(off)
		var progress := cand.dot(goal_dir)   # 1 dead ahead … less to the sides
		var score := progress - _lane_danger(cand) * avoid
		if score > best_score:
			best_score = score
			best_dir   = cand
	return best_dir


## How blocked a candidate carry lane is: opponents standing ahead within
## CARRY_LOOKAHEAD and close to the lane add danger, weighted by how central and how
## near they are. 0 = a clear run. Used only by _carry_steer_dir.
func _lane_danger(dir: Vector2) -> float:
	var danger := 0.0
	for e in enemies:
		var rel := (e as AIPlayer).global_position - global_position
		var along := rel.dot(dir)
		if along <= 0.0 or along > CARRY_LOOKAHEAD:
			continue   # behind us, or beyond how far we look ahead
		var lateral := (rel - dir * along).length()
		if lateral > CARRY_LANE_WIDTH:
			continue   # not in this lane
		var lat_w  := 1.0 - lateral / CARRY_LANE_WIDTH   # central blockers are worse
		var near_w := 1.0 - along / CARRY_LOOKAHEAD       # closer blockers are worse
		danger += lat_w * near_w
	return danger


# ── Team shape ───────────────────────────────────────────────────────────────

## Off-the-ball destination: man-mark when defending, push up to support when our
## team is attacking, otherwise hold the zonal block. This is what pulls defenders
## out of the goalmouth (they follow their man) and gives the carrier a runner.
func _off_ball_target() -> Vector2:
	if _should_mark():
		return _marking_position()
	if _team_in_possession() == team and not is_keeper and not is_carrying:
		return _attack_off_ball_target()
	return _tactical_position()


## Which team currently holds the ball (carrier's team), or -1 if it's loose.
func _team_in_possession() -> int:
	if ball != null and ball.carrier != null:
		return (ball.carrier as AIPlayer).team
	return -1


## True when this player's team is defending — an opponent has the ball, or it is
## loose in our defensive half.
func _is_defending() -> bool:
	var poss := _team_in_possession()
	if poss == team:
		return false
	if poss != -1:
		return true
	var own_goal_x := -_goal_centre.x
	return ball != null and ball.global_position.x * own_goal_x > 0.0


## Backs and midfielders man-mark when defending; forwards and the keeper don't.
func _should_mark() -> bool:
	return mark_target != null and not is_keeper and _is_defending()


## Stand goalside of the marked man — between him and our goal — so he has to beat
## us to get a clean shot or receive in space.
func _marking_position() -> Vector2:
	var own_goal := Vector2(-_goal_centre.x, 0.0)
	var to_goal := (own_goal - mark_target.global_position)
	if to_goal.length() > 0.01:
		to_goal = to_goal.normalized()
	return mark_target.global_position + to_goal * _tactics().mark_goalside + _separation()


## Off-the-ball destination when our team has the ball: the chosen runners break
## into open space to receive; everyone else holds a supporting attacking shape that
## stretches the defence and offers a recycle outlet. This is what gives the carrier
## (AI or human) someone to pass to instead of a static line.
func _attack_off_ball_target() -> Vector2:
	var carrier := _own_carrier()
	if carrier != null and _is_attacker() and _is_active_runner(carrier):
		return _run_into_space(carrier)
	return _support_shape_position()


## Our team's current ball carrier (the human or an AI teammate), or null.
func _own_carrier() -> AIPlayer:
	for t in teammates:
		var tm := t as AIPlayer
		if tm.is_carrying:
			return tm
	return null


## A forward — holds no marking duty and is not the keeper, so it plays high and is
## eligible to make off-the-ball runs. (Backs and midfielders mark / hold shape.)
func _is_attacker() -> bool:
	return not is_keeper and mark_target == null


## True if this attacker is one of the team's `runner_count` designated runners — the
## attackers nearest the opposition goal. Every teammate evaluates the same ranking
## over the same data (deterministically, tie-broken by jersey), so they agree on who
## runs without any central assignment. The carrier and the human pick their own
## movement, so both are excluded from the runner pool.
func _is_active_runner(carrier: AIPlayer) -> bool:
	var rc := _tactics().runner_count
	if rc <= 0:
		return false
	var my_d := global_position.distance_to(_goal_centre)
	var ahead := 0   # eligible attackers ranked above us (nearer goal)
	for t in teammates:
		var tm := t as AIPlayer
		if tm == self or tm == carrier or tm.is_human_controlled or not tm._is_attacker():
			continue
		var d := tm.global_position.distance_to(_goal_centre)
		if d < my_d or (is_equal_approx(d, my_d) and tm.jersey < jersey):
			ahead += 1
	return ahead < rc


## Pick a spot to run onto: sample a fan of points goalside of ourselves and choose
## the one that is most open AND sits in a clear passing lane from the carrier, with a
## bias toward getting in behind (stronger the more `directness` the tactics carry).
## Deterministic — geometric scoring, no RNG. Separation keeps multiple runners apart.
func _run_into_space(carrier: AIPlayer) -> Vector2:
	var goal_dir := _goal_centre - global_position
	goal_dir = goal_dir.normalized() if goal_dir.length() > 0.01 else _attack_dir
	var w_goal := 0.4 + _tactics().directness * 0.6   # direct sides favour the run in behind
	var best := global_position
	var best_score := -INF
	for ang in RECEIVE_ANGLES:
		var dir := goal_dir.rotated(ang)
		for dist in RECEIVE_DISTS:
			var spot := global_position + dir * dist
			if absf(spot.x) > PITCH_HALF_LENGTH - EDGE_MARGIN \
					or absf(spot.y) > PITCH_HALF_WIDTH - EDGE_MARGIN:
				continue   # would run off the pitch
			var score := _receive_spot_score(spot, carrier, w_goal)
			if score > best_score:
				best_score = score
				best       = spot
	return best + _separation()


## Score a candidate receiving spot: reward open space and getting goalside of the
## carrier; all but rule out a spot whose passing lane is already cut, or one so far
## the pass would be unrealistic.
func _receive_spot_score(spot: Vector2, carrier: AIPlayer, w_goal: float) -> float:
	var openness := _nearest_enemy_to(spot)
	var goal_gain := carrier.global_position.distance_to(_goal_centre) \
			- spot.distance_to(_goal_centre)
	var score := openness + maxf(0.0, goal_gain) * w_goal
	if _pass_lane_blocked(carrier.global_position, spot):
		score -= RECEIVE_LANE_PENALTY
	if carrier.global_position.distance_to(spot) > MAX_RECEIVE_DIST:
		score -= RECEIVE_LANE_PENALTY
	return score


## A supporting attacking shape for non-runners: the zonal slot (widened by the
## tactics' attacking width), with forwards still pushing toward goal so the defence
## has to come up and space opens behind. Midfielders/backs hold to offer a recycle.
func _support_shape_position() -> Vector2:
	var base := _tactical_position(_tactics().attacking_width)
	if _is_attacker():
		var to_goal := _goal_centre - global_position
		if to_goal.length() > GOAL_MOUTH_RANGE:
			base += to_goal.normalized() * _tactics().support_distance
	return base


## The zonal slot, with the whole team sliding toward the ball as one block so each
## player keeps their formation lane instead of converging on the ball (this is what
## stops the "everyone in one pile" behaviour). `width` scales the lane's spread off
## centre — the attacking shape widens it (see _support_shape_position); defaults to
## 1.0 so every other caller is unchanged.
func _tactical_position(width: float = 1.0) -> Vector2:
	var shift_x := clampf(ball.global_position.x * 0.40, -SHIFT_X_MAX, SHIFT_X_MAX)
	var shift_y := clampf(ball.global_position.y * 0.30, -SHIFT_Y_MAX, SHIFT_Y_MAX)
	var tx := clampf(home_position.x + shift_x, -860.0, 860.0)
	var ty := clampf(home_position.y * width + shift_y, -540.0, 540.0)
	return Vector2(tx, ty) + _separation()


func _separation() -> Vector2:
	# Steer away from any teammate who has crept too close, so players spread
	# out and never stack on top of each other.
	var push := Vector2.ZERO
	for t in teammates:
		var mate := t as AIPlayer
		if mate == self:
			continue
		var off := global_position - mate.global_position
		var d := off.length()
		if d > 0.01 and d < SEP_RADIUS:
			push += off / d * (SEP_RADIUS - d)
	return push.limit_length(SEP_PUSH_MAX)


# ── AI actions ────────────────────────────────────────────────────────────────

## Shoot at goal. `go_for_goal` true = drive for a goal (flat, powerful); false =
## a point attempt over the bar, with power scaled to the range.
func _ai_shoot(go_for_goal: bool) -> void:
	# A goal attempt is placed to the corner away from the keeper; a point is aimed
	# at the centre of the posts (height, not placement, clears the bar).
	var aim := _goal_aim_point() if go_for_goal else _goal_centre
	var dir := (aim - global_position).normalized()
	is_carrying  = false
	_carry_timer = 0.0
	var power := 0.85
	if not go_for_goal:
		power = clampf(global_position.distance_to(_goal_centre) / POINT_RANGE, 0.45, 1.0)
	_shoot_ball(dir, power, go_for_goal)


## Release a shot in `dir`, applying an accuracy spread that grows with shot
## difficulty (range + pressure). Shared by AI and human shots and first-time
## strikes so accuracy is modelled in exactly one place.
func _shoot_ball(dir: Vector2, power: float, is_goal: bool) -> void:
	ball.shooter         = self
	ball.last_touch_team = team
	var spread := _shot_spread(power)
	var aimed := dir.rotated(_shot_rng.randf_range(-spread, spread))
	ball.release_kick(aimed.normalized(), power, is_goal)


## Aim error (radians) for the current shot: farther from goal and tighter marking
## both spray it wider, so a good shot is a well-chosen one. Overcharging the power
## bar (releasing right at the top) adds spread on top, so there's a sweet spot.
func _shot_spread(power: float) -> float:
	var dist := global_position.distance_to(_goal_centre)
	var range_factor := clampf(dist / POINT_RANGE, 0.0, 1.0)
	var pressure := 1.0 - clampf(_nearest_enemy_distance() / _tactics().press_trigger_distance, 0.0, 1.0)
	var difficulty := clampf(range_factor * 0.7 + pressure * 0.5, 0.0, 1.0)
	var overcharge := clampf((power - OVERCHARGE_KNEE) / (1.0 - OVERCHARGE_KNEE), 0.0, 1.0)
	return difficulty * MAX_SHOT_SPREAD + overcharge * OVERCHARGE_SPREAD


## The opposing goalkeeper, if any — used to place goal shots away from them.
func _enemy_keeper() -> AIPlayer:
	for e in enemies:
		var a := e as AIPlayer
		if a.is_keeper:
			return a
	return null


## Aim point inside the goal for a goal attempt: a spot near the post on the side
## away from the keeper, so a well-placed shot beats their reach (see the save
## roll in match_scene).
func _goal_aim_point() -> Vector2:
	const POST_INSET := 14.0   # keep just inside the posts (GOAL_HW ≈ 58)
	var side := 1.0 if global_position.y <= 0.0 else -1.0
	var keeper := _enemy_keeper()
	if keeper != null and absf(keeper.global_position.y) > 1.0:
		side = -signf(keeper.global_position.y)   # opposite side to the keeper
	return Vector2(_goal_centre.x, side * (58.0 - POST_INSET))


## True if the lane from here to the goal aim point is clear enough to drive a goal
## shot through — no outfield opponent sits across its first stretch. The keeper is
## ignored (beating them is the save roll's job). A blocked lane → take the point.
func _goal_lane_clear() -> bool:
	var aim := _goal_aim_point()
	var to_goal := aim - global_position
	var dist := to_goal.length()
	if dist < 1.0:
		return true
	var dir := to_goal / dist
	for e in enemies:
		var a := e as AIPlayer
		if a.is_keeper:
			continue
		var rel := a.global_position - global_position
		var along := rel.dot(dir)
		if along <= 0.0 or along > dist:
			continue   # behind the shooter or beyond the goal
		var lateral := (rel - dir * along).length()
		if lateral < GOAL_LANE_CLEARANCE:
			return false
	return true


func _ai_pass_to(target: AIPlayer) -> void:
	# Lead a forward making a run slightly toward goal, so the ball is played into
	# space ahead of them rather than to their feet (a through ball).
	var spot := target.global_position
	if target._is_attacker():
		var to_goal := _goal_centre - target.global_position
		if to_goal.length() > GOAL_MOUTH_RANGE:
			spot += to_goal.normalized() * _tactics().pass_lead
	var dir := (spot - global_position).normalized()
	is_carrying  = false
	_carry_timer = 0.0
	_pass_cd     = PASS_COOLDOWN
	# Hand pass when short; drive a kick pass for a longer through ball.
	var dist := global_position.distance_to(spot)
	if dist > KICK_PASS_RANGE:
		ball.release_kick_pass(dir, clampf(dist / 700.0, 0.3, 1.0))
	else:
		ball.release_hand_pass(dir)


## Take a set-piece kick (free, 45, sideline, kickout). Called by match_scene
## for an AI taker once the opposition has stood back. Shoots if in range,
## otherwise finds a forward pass, else drives the ball downfield.
func take_set_piece() -> void:
	if is_keeper:
		_take_kickout()
		return
	if global_position.distance_to(_goal_centre) < SHOOT_RANGE:
		_ai_shoot(true)
		return
	var target := _best_pass_target()
	if target:
		_ai_pass_to(target)
		return
	is_carrying  = false
	_carry_timer = 0.0
	ball.release_kick(_attack_dir, 0.7, false)


## Keeper kickout strategy: play it short to an open defender when one is available
## (keeps possession), otherwise drive it long into the midfield contest.
func _take_kickout() -> void:
	var short_target := _open_short_kickout_target()
	if short_target != null:
		_ai_pass_to(short_target)
		return
	is_carrying  = false
	_carry_timer = 0.0
	ball.release_kick(_attack_dir, 0.95, false)   # long, contestable


## The most open teammate within short-kickout range (a corner/half back to restart
## possession with), or null if everyone short is marked — then we go long.
func _open_short_kickout_target() -> AIPlayer:
	var best: AIPlayer = null
	var best_open := MARKED_RADIUS * 1.4   # must be clearly open to risk a short one
	for t in teammates:
		var tm := t as AIPlayer
		if tm == self or tm.is_keeper:
			continue
		if global_position.distance_to(tm.global_position) > KICKOUT_SHORT_RANGE:
			continue
		if _pass_lane_blocked(global_position, tm.global_position):
			continue
		var open := _nearest_enemy_to(tm.global_position)
		if open > best_open:
			best_open = open
			best      = tm
	return best


## Pick a teammate to pass to. Only considers options whose passing lane is clear
## (so the ball isn't fired straight to an opponent — the classic "pass to the
## other team" bug) and rewards both forward progress and an open receiver, so a
## carrier pinned in its own half can find a safe outlet rather than a marked man.
## Returns null when there is no safe pass — the carrier then keeps it or clears.
func _best_pass_target() -> AIPlayer:
	var best: AIPlayer = null
	var best_score := -INF
	for t in teammates:
		var tm := t as AIPlayer
		if tm == self or tm.is_carrying or tm.is_human_controlled:
			continue
		var advance := (tm.global_position - global_position).dot(_attack_dir)
		if advance < -60.0:
			continue   # don't pass deep backwards into our own danger zone
		if _pass_lane_blocked(global_position, tm.global_position):
			continue   # an opponent would cut it out
		var openness := _nearest_enemy_to(tm.global_position)
		if openness < MARKED_RADIUS:
			continue   # too tightly marked — the receiver gets tackled at once
		# Reward forwards who have run closer to goal than the carrier — the through
		# ball to a runner in behind, not the safe square pass.
		var goal_gain := global_position.distance_to(_goal_centre) \
				- tm.global_position.distance_to(_goal_centre)
		var score := advance + openness * 0.4 + maxf(0.0, goal_gain) * 0.5
		if score > best_score:
			best_score = score
			best       = tm
	return best


## True if an opponent stands close enough to the line from→to to intercept a pass.
func _pass_lane_blocked(from: Vector2, to: Vector2) -> bool:
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 < 1.0:
		return false
	for e in enemies:
		var ep := (e as AIPlayer).global_position
		var t := (ep - from).dot(seg) / len2
		if t <= 0.05 or t >= 1.0:
			continue   # only opponents *between* passer and target block the lane
		if ep.distance_to(from + seg * t) < PASS_LANE_RADIUS:
			return true
	return false


## Distance from `pos` to the nearest opponent — a read on how open a spot is.
func _nearest_enemy_to(pos: Vector2) -> float:
	var best := INF
	for e in enemies:
		var d := (e as AIPlayer).global_position.distance_to(pos)
		if d < best:
			best = d
	return best


# ── Human-controlled input ────────────────────────────────────────────────────

func _update_aim() -> void:
	# Joypad seat: the ball goes the way the player is facing (per the design doc).
	if input == null or not input.is_keyboard:
		aim_dir = facing
		return
	# Keyboard + mouse seat: aim toward the mouse cursor.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 12.0:
		aim_dir = to_mouse.normalized()
	else:
		aim_dir = facing


## A frozen set-piece taker can't run, but may spin on the spot to choose a
## direction. On a joypad seat the movement input turns the player (aim follows
## facing); the keyboard seat aims with the mouse, so this does nothing — the
## cursor already steers the kick.
func _aim_in_place() -> void:
	if input == null or input.is_keyboard:
		return
	var dir := input.move_vector()
	if dir != Vector2.ZERO:
		facing = dir.normalized()


func _process_human_movement(delta: float) -> void:
	var dir := input.move_vector() if input != null else Vector2.ZERO

	# Dash is a short burst of speed, then a cooldown. Trial: available to any
	# controlled player (attacker or defender), not just the ball carrier. The
	# dash-ready ring (see _draw) shows when it's available.
	if input != null and input.just_pressed("sprint") \
			and _dash_cd <= 0.0 and _dash_time <= 0.0 and stamina >= DASH_MIN_STAMINA:
		_dash_time = DASH_DURATION
		_dash_cd   = DASH_COOLDOWN
		_dash_dir  = dir.normalized() if dir != Vector2.ZERO else facing
		stamina    = maxf(0.0, stamina - STAMINA_DASH_COST)
		if is_carrying:
			_apply_sidestep()   # a dash with the ball is a beat-your-man sidestep

	# Jockey / contain — hold to shadow the carrier at a controlled (slower) speed
	# without the ball, keeping square to them so the next tackle commits from the
	# front. Defending is then about positioning, not raw pace.
	_jockeying = input != null and input.pressed("jockey") and not is_carrying

	if _dash_time > 0.0:
		facing   = _dash_dir
		velocity = velocity.lerp(_dash_dir * DASH_SPEED, DASH_ACCEL * delta)
	elif dir != Vector2.ZERO:
		var spd := WALK_SPEED
		if is_carrying:
			spd = _carry_speed()        # carriers dip for a moment after a solo
		elif _jockeying:
			spd = JOCKEY_SPEED
		velocity = velocity.lerp(dir * spd, ACCEL * delta)
		facing   = _contain_facing(dir)
	else:
		velocity = velocity.lerp(Vector2.ZERO, DECEL * delta)
		if _jockeying:
			facing = _contain_facing(facing)


## Sidestep: a dash with the ball kinks the burst laterally around the nearest
## defender ahead and grants a brief tackle-immunity window, so a well-timed dash
## beats your man in a 1v1 instead of running straight into the tackle.
func _apply_sidestep() -> void:
	_tackle_immunity = maxf(_tackle_immunity, SIDESTEP_IMMUNITY)
	var foe := _nearest_enemy_node()
	if foe == null:
		return
	var to_foe := foe.global_position - global_position
	if to_foe.length() > SIDESTEP_RANGE or to_foe.length() < 0.01:
		return
	to_foe = to_foe.normalized()
	var lateral := Vector2(-to_foe.y, to_foe.x)   # perpendicular — step around him
	if lateral.dot(_dash_dir) < 0.0:
		lateral = -lateral
	_dash_dir = (_dash_dir + lateral * 0.7).normalized()


## The nearest opponent node (not just the distance) — used by the sidestep.
func _nearest_enemy_node() -> AIPlayer:
	var best: AIPlayer = null
	var best_d := INF
	for e in enemies:
		var a := e as AIPlayer
		var d := a.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best   = a
	return best


## While jockeying, face the carrier being contained (so a tackle comes in from
## the front); otherwise face the way we're moving. `fallback` is the facing to
## use when there is no carrier to square up to.
func _contain_facing(fallback: Vector2) -> Vector2:
	if _jockeying:
		var c := _current_enemy_carrier()
		if c != null:
			var to_c := c.global_position - global_position
			if to_c.length() > 0.01:
				return to_c.normalized()
	return fallback.normalized() if fallback.length() > 0.01 else facing


func _process_human_actions(delta: float) -> void:
	# PASS — tap = hand pass; double-tap and hold = kick pass (see _process_pass).
	_process_pass(delta)

	# SHOOT — hold = point attempt (over the bar); double-tap and hold the
	# second press = goal attempt, charging power while held.
	_process_shoot(delta)

	# First-time strike — pressing shoot with no ball but one right beside you
	# volleys it goalward rather than gathering it first.
	if not is_carrying and input != null and input.just_pressed("shoot"):
		_try_first_time_shot()

	# SOLO — resets step counter (unlimited), but briefly checks your stride.
	if input != null and input.just_pressed("solo") and is_carrying:
		steps_taken = 0.0
		_solo_slow  = SOLO_SLOW_DURATION

	# BOUNCE / hop — resets step counter (once per possession), no speed cost, so
	# running and hopping keeps you gliding past a chaser.
	if input != null and input.just_pressed("bounce") and is_carrying and not has_bounced:
		has_bounced = true
		steps_taken = 0.0


func _human_hand_pass() -> void:
	is_carrying = false
	# Fisted finish: a hand pass taken in close and aimed at goal is a punch at the
	# net — it can score a goal (low and stoppable, like a shot) instead of a pass.
	var to_goal := _goal_centre - global_position
	if to_goal.length() < FIST_RANGE and to_goal.length() > 0.01 \
			and aim_dir.dot(to_goal.normalized()) > 0.6:
		_shoot_ball(aim_dir, 0.5, true)
		return
	ball.release_hand_pass(aim_dir)
	passed.emit(self)


func _human_kick_pass(power: float) -> void:
	is_carrying = false
	ball.release_kick_pass(aim_dir, power)
	passed.emit(self)


func _human_shoot(power: float, is_goal: bool) -> void:
	is_carrying = false
	_shoot_ball(aim_dir, power, is_goal)


## First-time strike: press shoot without the ball while a loose or incoming ball
## is right beside you, and you volley it goalward first time instead of gathering.
## A quick point attempt — fast, but the spread model makes it a real gamble.
func _try_first_time_shot() -> void:
	if is_carrying or ball == null:
		return
	if ball.ball_state == Ball.State.CARRIED:
		return
	if global_position.distance_to(ball.global_position) > FIRST_TIME_RANGE:
		return
	var to_goal := _goal_centre - global_position
	var dir := aim_dir if aim_dir.length() > 0.01 else to_goal.normalized()
	ball.carrier = null
	_shoot_ball(dir, 0.85, false)


## Passing gesture machine (phases): 0 idle, 1 first press held, 2 first tap
## released — waiting for a 2nd tap, 3 second press held (kick pass charging).
##  • Single tap → hand pass (short, flat).
##  • Double-tap, holding the second press → kick pass, power from that hold.
func _process_pass(delta: float) -> void:
	if not is_carrying or input == null:
		_pass_phase = 0
		return
	var pressed := input.pressed("pass")
	match _pass_phase:
		0:
			if input.just_pressed("pass"):
				_pass_phase  = 1
				_pass_held_t = 0.0
		1:
			_pass_held_t += delta
			if not pressed:
				# Quick first tap — could be the first half of a double tap.
				_pass_phase  = 2
				_pass_wait_t = 0.0
			elif _pass_held_t >= SHOOT_DOUBLE_TAP:
				# Held with no second tap → just a hand pass.
				_fire_hand_pass()
		2:
			_pass_wait_t += delta
			if input.just_pressed("pass"):
				_pass_phase  = 3   # second press → kick pass
				_pass_held_t = 0.0
			elif _pass_wait_t >= SHOOT_DOUBLE_TAP:
				_fire_hand_pass()  # single quick tap → hand pass
		3:
			_pass_held_t += delta
			if not pressed:
				_fire_kick_pass(clampf(_pass_held_t / SHOOT_MAX_HOLD, 0.2, 1.0))


func _fire_hand_pass() -> void:
	_pass_phase = 0
	if is_carrying:
		_human_hand_pass()


func _fire_kick_pass(power: float) -> void:
	_pass_phase = 0
	if is_carrying:
		_human_kick_pass(power)


## Shooting gesture machine (phases): 0 idle, 1 first press held (undecided),
## 2 first tap released — waiting for a 2nd tap, 3 second press held (goal
## attempt charging), 4 single hold (point attempt charging).
##  • Hold the button once → point attempt (over the bar), power from hold time.
##  • Double-tap, holding the second press → goal attempt, power from that hold.
func _process_shoot(delta: float) -> void:
	if not is_carrying or input == null:
		_shoot_phase = 0
		return
	var pressed := input.pressed("shoot")
	match _shoot_phase:
		0:
			if input.just_pressed("shoot"):
				_shoot_phase  = 1
				_shoot_held_t = 0.0
		1:
			_shoot_held_t += delta
			if not pressed:
				# Quick first tap — could be the first half of a double tap.
				_shoot_tap_power = clampf(_shoot_held_t / SHOOT_MAX_HOLD, 0.0, 1.0)
				_shoot_phase  = 2
				_shoot_wait_t = 0.0
			elif _shoot_held_t >= SHOOT_DOUBLE_TAP:
				# Held past the double-tap window → committed point attempt.
				_shoot_phase = 4
		2:
			_shoot_wait_t += delta
			if input.just_pressed("shoot"):
				_shoot_phase  = 3   # second press → goal attempt
				_shoot_held_t = 0.0
			elif _shoot_wait_t >= SHOOT_DOUBLE_TAP:
				_fire_shoot(maxf(_shoot_tap_power, 0.4), false)   # single quick point
		3:
			_shoot_held_t += delta
			if not pressed:
				_fire_shoot(clampf(_shoot_held_t / SHOOT_MAX_HOLD, 0.3, 1.0), true)
		4:
			_shoot_held_t += delta
			if not pressed:
				_fire_shoot(clampf(_shoot_held_t / SHOOT_MAX_HOLD, 0.3, 1.0), false)


func _fire_shoot(power: float, is_goal: bool) -> void:
	_shoot_phase = 0
	if is_carrying:
		_human_shoot(power, is_goal)


## 0..1 power currently being charged for a pass or shot; -1 if not winding up.
## Used by match_scene to drive the HUD power bar.
func windup_power() -> float:
	if _pass_phase == 3:
		return clampf(_pass_held_t / SHOOT_MAX_HOLD, 0.0, 1.0)
	if _shoot_phase == 3 or _shoot_phase == 4:
		return clampf(_shoot_held_t / SHOOT_MAX_HOLD, 0.0, 1.0)
	return -1.0


## While the human is winding up, describe the kick that would fire if released now,
## so match_scene can project where it lands and mark the spot. Returns
## {active: bool, dir: Vector2, power: float, kind: String} where kind is one of
## "point", "goal", "kick_pass". The power floors match the real release clamps in
## _fire_shoot / _fire_kick_pass so the prediction tracks the actual kick.
func windup_shot() -> Dictionary:
	if _pass_phase == 3:
		return {"active": true, "dir": aim_dir, "kind": "kick_pass",
			"power": clampf(_pass_held_t / SHOOT_MAX_HOLD, 0.2, 1.0)}
	if _shoot_phase == 3:
		return {"active": true, "dir": aim_dir, "kind": "goal",
			"power": clampf(_shoot_held_t / SHOOT_MAX_HOLD, 0.3, 1.0)}
	if _shoot_phase == 4:
		return {"active": true, "dir": aim_dir, "kind": "point",
			"power": clampf(_shoot_held_t / SHOOT_MAX_HOLD, 0.3, 1.0)}
	return {"active": false}


## Cancel any active wind-up — called by match_scene when switching away.
func cancel_windup() -> void:
	_pass_phase   = 0
	_pass_wait_t  = 0.0
	_pass_held_t  = 0.0
	_shoot_held_t = 0.0
	_shoot_phase  = 0
	_shoot_wait_t = 0.0
	_jockeying    = false


## Send the player back to a formation spot for a restart (half-time, etc.),
## clearing possession, wind-ups and every transient timer so the second half
## starts from a clean slate.
func reset_for_restart(pos: Vector2) -> void:
	global_position  = pos
	home_position    = pos
	velocity         = Vector2.ZERO
	facing           = _attack_dir
	is_carrying      = false
	steps_taken      = 0.0
	has_bounced      = false
	_carry_timer     = 0.0
	_stuck_timer     = 0.0
	_stuck_anchor    = pos
	_stun_timer      = 0.0
	_tackle_cd       = 0.0
	_tackle_immunity = 0.0
	_engage_time     = 0.0
	_dash_time       = 0.0
	_dash_cd         = 0.0
	_pass_cd         = 0.0
	stamina          = 1.0
	cancel_windup()


# ── Shared pickup / carry ─────────────────────────────────────────────────────

func _process_pickup() -> void:
	if is_carrying or ball == null:
		return
	if ball.ball_state == Ball.State.FREE:
		if global_position.distance_to(ball.global_position) < PICK_RADIUS:
			_pick_up()


func _pick_up() -> void:
	is_carrying      = true
	steps_taken      = 0.0
	has_bounced      = false
	_carry_timer     = 0.0
	_tackle_immunity = TACKLE_IMMUNITY
	_stuck_timer     = 0.0
	_stuck_anchor    = global_position
	ball.pick_up(self)


func _process_carry(delta: float) -> void:
	steps_taken += velocity.length() * delta / STEP_DISTANCE
	if steps_taken < MAX_STEPS:
		return
	if is_human_controlled:
		foul_committed.emit(global_position, team)
	_force_drop()


func _force_drop() -> void:
	is_carrying  = false
	_carry_timer = 0.0
	steps_taken  = 0.0
	has_bounced  = false
	_pass_phase  = 0
	if ball:
		ball.carrier    = null
		ball.ball_state = Ball.State.FREE
		ball.velocity   = Vector2.ZERO


## Seek a point, steering around any body in the way (see _avoid_offset) so movers
## arc past each other instead of jamming up. The carrier bypasses this and drives
## its context-steered heading through _move_dir directly.
func _move_toward(target: Vector2, speed: float, delta: float) -> void:
	# Mid-dash, an AI bursts straight along its locked dash direction (the human
	# dash is driven separately in _process_human_movement).
	if _dash_time > 0.0:
		_move_dir(_dash_dir, speed, delta)
		return
	var to_target := target - global_position
	var dist := to_target.length()
	if dist < 10.0:
		velocity = velocity.lerp(Vector2.ZERO, DECEL * delta)
		return
	var dir := to_target / dist
	# Avoid bodies *between* us and the target, but not the body sitting at the
	# target itself — otherwise a defender chasing a carrier would steer off it and
	# never close for the tackle.
	_move_dir(dir + _avoid_offset(dir, dist - PLAYER_RADIUS * 2.0), speed, delta)


## Low-level drive: accelerate toward `dir` (any length) at `speed`, updating
## facing. A mid-dash burst overrides with the locked dash direction. This is the
## one place velocity/facing are set for AI movement — both _move_toward and the
## carrier's context-steered drive route through here.
func _move_dir(dir: Vector2, speed: float, delta: float) -> void:
	if _dash_time > 0.0:
		facing   = _dash_dir
		velocity = velocity.lerp(_dash_dir * DASH_SPEED, DASH_ACCEL * delta)
		return
	if dir.length() < 0.01:
		velocity = velocity.lerp(Vector2.ZERO, DECEL * delta)
		return
	dir      = dir.normalized()
	facing   = dir
	velocity = velocity.lerp(dir * speed, ACCEL * delta)


## A steering nudge that pushes `desired_dir` laterally around bodies sitting ahead
## of it within AVOID_RADIUS — the open side gets picked, so the player arcs past
## traffic rather than running into it. Considers both teams; the keeper opts out
## (it must hold a precise goal line). Bodies further along the heading than
## `max_along` are ignored (the target we're seeking shouldn't be avoided). Returns
## a vector to add to the heading.
func _avoid_offset(desired_dir: Vector2, max_along: float = INF) -> Vector2:
	if is_keeper:
		return Vector2.ZERO
	var strength := AVOID_STRENGTH * _tactics().avoidance_strength
	if strength <= 0.0 or desired_dir.length() < 0.01:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for arr in [enemies, teammates]:
		for n in arr:
			var a := n as AIPlayer
			if a == self:
				continue
			var rel := a.global_position - global_position
			var d := rel.length()
			if d < 0.01 or d > AVOID_RADIUS:
				continue
			var along := rel.dot(desired_dir)
			if along <= 0.0 or along >= max_along:
				continue   # beside/behind our heading, or at/past the target — not in the way
			var lateral := rel - desired_dir * along
			var side: Vector2
			if lateral.length() > 1.0:
				side = -lateral.normalized()                        # steer to the open side
			else:
				side = Vector2(-desired_dir.y, desired_dir.x)        # dead ahead — pick a side
			push += side * (1.0 - d / AVOID_RADIUS)                 # closer = stronger
	return push * strength


# ── Rendering ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	# 2.5D sprite billboard (see PitchProjection / MatchSprites). Drawing happens in
	# three layered transforms, all hung off the projected ground point of the (never
	# moved) physics body:
	#   • the GROUND plane (flattened ellipse) — shadow, facing chevron and the status
	#     rings, which read best lying flat around the feet like a broadcast overlay;
	#   • the UPRIGHT figure — the depth-scaled sprite standing feet-on-ground;
	#   • the UPRIGHT labels — selection marker, step dots, stun, aim arrow, anchored
	#     above the head / at the chest.
	var gp   := global_position
	var s    := PitchProjection.scale_at(gp.y)
	var base := PitchProjection.ground(gp) - gp   # node origin → projected ground

	# ── Ground plane ────────────────────────────────────────────────────────────
	draw_set_transform(base, 0.0, Vector2(s, s * 0.5))
	draw_circle(Vector2.ZERO, PLAYER_RADIUS * 1.05, Color(0.0, 0.0, 0.0, 0.28))
	_draw_facing_chevron()
	if _stun_timer > 0.0:
		draw_arc(Vector2.ZERO, PLAYER_RADIUS + 6.0, 0.0, TAU, 28, C_STUN, 2.0, true)
	if is_human_controlled:
		_draw_dash_ring()   # dash is available to any controlled player (trial)
		if not is_carrying:
			if _jockeying:
				_draw_jockey()
			# Tackle engagement — the dwell filling while pressing a carrier, then a
			# solid ring the instant a tackle can be committed (see can_tackle).
			if _engage_time > 0.0 or _tackle_cd > 0.0:
				_draw_engage_ring()

	# ── Upright billboard ───────────────────────────────────────────────────────
	draw_set_transform(base, 0.0, Vector2(s, s))
	if sprite != null:
		var ts := sprite.get_size()
		var h  := SPRITE_HEIGHT
		var w  := h * ts.x / ts.y
		draw_texture_rect(sprite, Rect2(-w * 0.5, -h, w, h), false)
	else:
		# Fallback if no texture was built — a plain upright disc.
		draw_circle(Vector2(0.0, -PLAYER_RADIUS), PLAYER_RADIUS, _c_body)

	# ── Upright labels (above the head / at the chest) ──────────────────────────
	if is_selected:
		var tip   := Vector2(0.0, SEL_Y)
		var left  := tip + Vector2(-7.0, -13.0)
		var right := tip + Vector2( 7.0, -13.0)
		draw_colored_polygon(PackedVector2Array([left, right, tip]), marker_color)
	if _stun_timer > 0.0:
		_draw_stun_stars()
	if is_human_controlled:
		if is_set_piece_taker or _pass_phase != 0 or _shoot_phase != 0:
			_draw_aim_arrow()
		if is_carrying:
			_draw_step_dots()


## A small ground-plane arrow at the feet pointing where the player faces — the
## billboard sprite is front-on, so this is what reads facing/aim in the tilted view.
func _draw_facing_chevron() -> void:
	if facing.length() < 0.01:
		return
	var f    := facing.normalized()
	var perp := Vector2(-f.y, f.x)
	var tip  := f * (PLAYER_RADIUS + 7.0)
	var bl   := f * (PLAYER_RADIUS - 1.0) + perp * 5.0
	var br   := f * (PLAYER_RADIUS - 1.0) - perp * 5.0
	draw_colored_polygon(PackedVector2Array([bl, br, tip]), C_CHEVRON)


## Ring around the human carrier showing dash availability: solid green when
## ready, otherwise a dim track with a blue arc filling as the cooldown recovers.
func _draw_dash_ring() -> void:
	var r := PLAYER_RADIUS + 6.0
	if _dash_cd > 0.0:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, C_DASH_CD, 2.0, true)
		var frac  := clampf(1.0 - _dash_cd / DASH_COOLDOWN, 0.0, 1.0)
		var start := -PI * 0.5
		draw_arc(Vector2.ZERO, r, start, start + TAU * frac, 32, C_DASH_FILL, 2.5, true)
	else:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, C_DASH_RDY, 2.5, true)


## Ring (just outside the dash ring) showing tackle readiness while defending:
##  • recovering from a tackle → a dim red ring (can't challenge yet);
##  • building engagement      → an orange arc filling toward a full ring;
##  • engaged & ready          → a solid red ring (a tackle will land — press F).
func _draw_engage_ring() -> void:
	var r := PLAYER_RADIUS + 10.0
	if _tackle_cd > 0.0:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, C_ENGAGE_CD, 2.0, true)
		return
	if _engage_time >= TACKLE_ENGAGE_TIME:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, C_ENGAGE_RDY, 2.5, true)
	else:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, C_ENGAGE_TRK, 1.5, true)
		var frac  := clampf(_engage_time / TACKLE_ENGAGE_TIME, 0.0, 1.0)
		var start := -PI * 0.5
		draw_arc(Vector2.ZERO, r, start, start + TAU * frac, 32, C_ENGAGE_FIL, 2.5, true)


## Stun "stars" above the head (the matching ground ring is drawn in _draw).
func _draw_stun_stars() -> void:
	for i in 3:
		draw_circle(Vector2((i - 1) * 8.0, DOTS_Y), 2.5, C_STUN)


## A short arc in the facing direction while containing — a read on who you're
## jockeying and which way you're shepherding them.
func _draw_jockey() -> void:
	var a := facing.angle()
	draw_arc(Vector2.ZERO, PLAYER_RADIUS + 6.0, a - 0.7, a + 0.7, 16, C_JOCKEY, 2.5, true)


func _draw_aim_arrow() -> void:
	var o    := Vector2(0.0, CHEST_Y)   # springs from the chest, not the feet
	var tip  := o + aim_dir * 52.0
	var perp := Vector2(-aim_dir.y, aim_dir.x)
	draw_line(o, tip,                                         C_AIM, 2.0)
	draw_line(tip, tip - aim_dir * 11.0 + perp * 7.0,         C_AIM, 2.0)
	draw_line(tip, tip - aim_dir * 11.0 - perp * 7.0,         C_AIM, 2.0)


func _draw_step_dots() -> void:
	var spacing    := 11.0
	var total_w    := (MAX_STEPS - 1.0) * spacing
	var y_off      := DOTS_Y
	var steps_used := int(steps_taken)
	for i in int(MAX_STEPS):
		var cx  := -total_w * 0.5 + i * spacing
		var col := Color.RED if i < steps_used else Color(1.0, 1.0, 1.0, 0.45)
		draw_circle(Vector2(cx, y_off), 4.5, col)
