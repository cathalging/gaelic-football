extends Node2D
## Match scene root — 15 v 15 with a match clock and player switching.
##
## Team A (home, blue) attacks toward +x.  Team B (away, red) attacks toward −x.
## The human controls one Team A player and can switch to the nearest teammate.
## All other players on both teams are AI-driven (same state machine).

@onready var _ball: Ball = $Ball
@onready var _hud:  HUD  = $HUD

const HALF_LENGTH   := 900.0     # must match pitch.gd
const HALF_WIDTH    := 560.0     # must match pitch.gd
const GOAL_HW       := 58.0      # must match pitch.gd (widened so low shots can score)
const HALF_DURATION := 30.0 * 60.0  # 30 game-minutes in game-seconds

# ── Referee geometry (px from the relevant goal/end line; ~13 px/m) ─────────────
const SMALL_SQ_DEPTH := 58.0     # small rectangle — kickouts & square-ball checks
const SMALL_SQ_HW    := 91.0
const LARGE_SQ_DEPTH := 170.0    # large rectangle (13 m line) — penalty area
const LARGE_SQ_HW    := 124.0
const FORTY_FIVE_X   := 315.0    # |x| of the 45 m line (900 − 585; see pitch.gd)
const PENALTY_DIST   := 143.0    # penalty spot, 11 m out from goal
const SET_PIECE_RETREAT := 170.0 # opposition must stand 13 m back from the ball
const SET_PIECE_COUNTDOWN := 3.0 # ball placed, then a 3-second countdown before play resumes

# ── Play / set-piece state ──────────────────────────────────────────────────────
# LIVE      — open play.
# SET_PIECE — ball placed for a free/45/penalty/kickout/sideline, counting down.
# REPLAY    — slow-motion action replay of the last couple of seconds (after a goal).
enum Play { LIVE, SET_PIECE, REPLAY }
var _play_state := Play.LIVE
var _sp_timer     := 0.0
var _sp_countdown := 0.0
var _sp_taker: AIPlayer = null
var _sp_label   := ""

# ── Goal feel: screen shake + slow-motion replay ─────────────────────────────────
const GOAL_SHAKE     := 16.0    # camera shake magnitude (px) on a goal
const FOUL_SHAKE     := 6.0     # smaller jolt when a card is shown
const SHAKE_DECAY    := 34.0    # px/sec the shake magnitude bleeds off
const REPLAY_SECONDS := 2.0     # how much footage to replay after a goal
const REPLAY_SPEED   := 0.3     # 0.3× = slow motion
const REPLAY_FRAMES  := 130     # ring-buffer capacity (~2.1 s at 60 fps)

@onready var _camera: Camera2D = $Ball/Camera2D
@onready var _crowd_audio: Node = $CrowdAudio

var _fx_rng := RandomNumberGenerator.new()   # presentation-only (shake) — not the sim RNG
var _shake_mag := 0.0

# Replay ring buffer of per-frame snapshots and playback cursor.
var _replay_frames: Array = []
var _replay_pos := 0.0
var _replay_dt  := 0.016667
var _pending_kickout_team := 1

# Per-player score tally for the full-time top-scorers panel: AIPlayer → Vector2i(goals, points).
var _scorers: Dictionary = {}

# ── Tackling ──────────────────────────────────────────────────────────────────--
# A defender presses `tackle` near a carrier. The human plays a quick timing
# minigame (a cursor sweeps a bar; strike in the centre); the AI rolls a seeded
# outcome. Perfect = clean steal, slightly off = ball knocked loose, miss =
# tackler stunned + long cooldown. A tackle from behind is always a foul.
const TACKLE_REACH        := 48.0   # px from carrier needed to start a tackle
const CONTEST_DURATION    := 2.0    # seconds before an un-struck contest is a miss
const CONTEST_LEASH       := 84.0   # carrier breaks away if it gets this far off
const CONTEST_SWEEP_SPEED := 1.7    # cursor sweeps across the bar (cycles/sec, ping-pong)
const CONTEST_GOOD_HW     := 0.20   # half-width of the "good" (knock-loose) zone
const CONTEST_PERFECT_HW  := 0.07   # half-width of the "perfect" (clean steal) zone
const KNOCK_LOOSE_SPEED   := 360.0  # speed the ball spills at when knocked loose

# A foul is only the *extreme* edge of a mistimed strike — most mis-hits are just a
# failed tackle, so the game keeps flowing. Striking from behind the carrier widens
# the foul band a little (a behind tackle is riskier), but is still mostly a miss.
const CONTEST_FOUL_OFF       := 0.46  # |cursor-0.5| at/above this = foul (front/side)
const CONTEST_FOUL_OFF_BEHIND := 0.36 # …a bit easier to foul when tackling from behind

# AI tackle tuning (stat-scaled later). Per-physics-frame chance an in-range AI
# defender commits, then the odds of each outcome on an attempt.
const AI_TACKLE_CHANCE  := 0.05
const AI_PERFECT_CHANCE := 0.30     # roll < this           → clean steal
const AI_SUCCESS_CHANCE := 0.65     # roll < this (and ≥ above) → knock loose; else fail
const AI_FOUL_FRONT     := 0.06     # chance a failed front/side tackle is a foul
const AI_FOUL_BEHIND    := 0.20     # chance a failed behind tackle is a foul

var _rng := RandomNumberGenerator.new()

# Live human tackle contest.
var _contest_active   := false
var _contest_cursor   := 0.0
var _contest_dir      := 1.0
var _contest_timer    := 0.0
var _contest_defender: AIPlayer = null
var _contest_victim:   AIPlayer = null

## 1.0 = real-time 30-minute halves.  60.0 = 1 real-second per game-minute (testing).
const CLOCK_SPEED   := 60.0

var _home_goals  := 0
var _home_points := 0
var _away_goals  := 0
var _away_points := 0

var _match_time   := 0.0  # game-seconds elapsed this half
var _half         := 1
var _clock_frozen := false
var _halftime_pause := false  # true during the half-time interval — play is suspended

# ── Formation positions ────────────────────────────────────────────────────────
# Team A: home, attacks +x, defends left goal (x=−700).
# GK | 3 full backs | 3 half backs | 2 midfielders | 3 half fwds | 3 full fwds
const _TEAM_A_POSITIONS: Array = [
	Vector2(-820.0,    0.0),   # GK
	Vector2(-630.0, -220.0),   # Full back L
	Vector2(-630.0,    0.0),   # Full back C
	Vector2(-630.0,  220.0),   # Full back R
	Vector2(-375.0, -275.0),   # Half back L
	Vector2(-375.0,    0.0),   # Half back C
	Vector2(-375.0,  275.0),   # Half back R
	Vector2(-105.0, -140.0),   # Midfielder L  ← index 7, initially controlled
	Vector2(-105.0,  140.0),   # Midfielder R
	Vector2( 205.0, -275.0),   # Half forward L
	Vector2( 205.0,    0.0),   # Half forward C
	Vector2( 205.0,  275.0),   # Half forward R
	Vector2( 490.0, -180.0),   # Full forward L
	Vector2( 490.0,    0.0),   # Full forward C
	Vector2( 490.0,  180.0),   # Full forward R
]

# Team B: away, attacks −x, defends right goal (x=+700).
const _TEAM_B_POSITIONS: Array = [
	Vector2( 820.0,    0.0),   # GK
	Vector2( 630.0, -220.0),   # Full back L
	Vector2( 630.0,    0.0),   # Full back C
	Vector2( 630.0,  220.0),   # Full back R
	Vector2( 375.0, -275.0),   # Half back L
	Vector2( 375.0,    0.0),   # Half back C
	Vector2( 375.0,  275.0),   # Half back R
	Vector2( 105.0, -140.0),   # Midfielder L
	Vector2( 105.0,  140.0),   # Midfielder R
	Vector2(-205.0, -275.0),   # Half forward L
	Vector2(-205.0,    0.0),   # Half forward C
	Vector2(-205.0,  275.0),   # Half forward R
	Vector2(-490.0, -180.0),   # Full forward L
	Vector2(-490.0,    0.0),   # Full forward C
	Vector2(-490.0,  180.0),   # Full forward R
]

const _INITIAL_CONTROLLED := 7   # Team A midfielder L

var _team_a: Array = []   # Array[AIPlayer]
var _team_b: Array = []   # Array[AIPlayer]
var _controlled: AIPlayer = null

# Player switching. switch_player picks a defender in the carrier's path, then
# repeated presses within SWITCH_CYCLE_TIME cycle through the three nearest the
# carrier. A right-stick flick instead grabs the nearest player in that direction.
const SWITCH_CYCLE_TIME := 1.3
var _switch_cycle: Array = []   # Array[AIPlayer] — the current shortlist
var _switch_index := 0
var _switch_timer := 0.0
const RS_FLICK_ON  := 0.6       # right-stick magnitude that registers a flick
const RS_FLICK_OFF := 0.3       # must fall below this before another flick fires
var _rs_ready := true


func _ready() -> void:
	_spawn_team(0, _TEAM_A_POSITIONS, _team_a)
	_spawn_team(1, _TEAM_B_POSITIONS, _team_b)

	for ai in _team_a:
		(ai as AIPlayer).enemies = _team_b
	for ai in _team_b:
		(ai as AIPlayer).enemies = _team_a
	# Referee signals — both teams can commit steps fouls. Illegal-tackle fouls are
	# raised directly by the tackle resolution in this script (see _on_tackle_foul).
	for ai in _team_a + _team_b:
		(ai as AIPlayer).foul_committed.connect(_on_foul)

	# Seeded RNG for AI tackle resolution — avoids global randf() so the live
	# scene stays reproducible from a fixed seed (see CLAUDE.md determinism rules).
	_rng.seed = 0x6AA11
	# A separate, randomised RNG for purely cosmetic effects (camera shake) so it
	# never perturbs the seeded simulation rolls above.
	_fx_rng.randomize()

	_controlled = _team_a[_INITIAL_CONTROLLED] as AIPlayer
	_controlled.is_human_controlled = true
	_controlled.is_selected         = true

	_hud.update_score(0, 0, 0, 0)
	_hud.set_clock("H1  00:00")
	_hud.setup_minimap(_team_a, _team_b, _ball, HALF_LENGTH, HALF_WIDTH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.return_to_main_menu()
	if event.is_action_pressed("switch_player"):
		_switch_player()
	if event.is_action_pressed("tackle"):
		_on_tackle_pressed()


func _physics_process(delta: float) -> void:
	if _play_state == Play.REPLAY:
		return
	if _play_state == Play.SET_PIECE:
		_tick_set_piece(delta)
		return
	if _halftime_pause:
		# The whole match is suspended during the interval (see _on_half_over).
		_update_hud_indicators()
		return
	if _contest_active:
		# The whole match is frozen for the tackle minigame — only the contest
		# advances, so the carrier can't run off with the ball before you strike.
		_tick_human_contest(delta)
		_update_hud_indicators()
		return
	_record_frame()
	_poll_switch_stick()
	_update_ball_chasers()
	_auto_control_carrier()
	_ai_tackles()
	_check_shot_block(delta)
	_check_keeper_save()
	_check_scoring()
	_check_out_of_bounds()
	_update_power_bar()
	_update_hud_indicators()


func _process(delta: float) -> void:
	_switch_timer = maxf(0.0, _switch_timer - delta)
	_update_shake(delta)
	if _play_state == Play.REPLAY:
		_tick_replay(delta)
		return
	if _clock_frozen or _play_state == Play.SET_PIECE or _contest_active:
		return
	_match_time += delta * CLOCK_SPEED
	_update_clock_display()
	if _match_time >= HALF_DURATION:
		_on_half_over()


# ── Spawning ───────────────────────────────────────────────────────────────────

func _spawn_team(team_id: int, positions: Array, roster: Array) -> void:
	for i in positions.size():
		var pos: Vector2 = positions[i]
		var ai     := AIPlayer.new()
		ai.team    = team_id
		ai.jersey  = i + 1   # 1 = GK … 15 = full forward (see formation arrays)
		ai.is_keeper = i == 0   # roster index 0 is the goalkeeper
		ai.ball    = _ball
		var shape  := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = AIPlayer.PLAYER_RADIUS
		shape.shape   = circle
		ai.add_child(shape)
		ai.global_position = pos
		ai.home_position   = pos
		add_child(ai)
		roster.append(ai)
	for ai in roster:
		(ai as AIPlayer).teammates = roster


# ── Player switching ───────────────────────────────────────────────────────────

## Switching takes a defender in the carrier's path (the man you're running at),
## not whoever is merely nearest — that was usually a player trailing behind. The
## first press grabs the best interceptor of the three nearest the carrier;
## repeated presses cycle through those three.
func _switch_player() -> void:
	var ref_pos := _ball.global_position
	var ref_dir := _ball.velocity
	var carrier := _opponent_carrier()
	if carrier:
		ref_pos = carrier.global_position
		ref_dir = carrier.velocity if carrier.velocity.length() > 10.0 else carrier.facing
	if ref_dir.length() < 0.01:
		ref_dir = Vector2.RIGHT
	ref_dir = ref_dir.normalized()

	# Keep cycling the same shortlist on rapid presses; rebuild once it lapses.
	if _switch_timer <= 0.0 or _switch_cycle.is_empty():
		_switch_cycle = _switch_shortlist(ref_pos, ref_dir)
		_switch_index = 0
	else:
		_switch_index = (_switch_index + 1) % _switch_cycle.size()
	_switch_timer = SWITCH_CYCLE_TIME
	if _switch_index < _switch_cycle.size():
		_set_controlled(_switch_cycle[_switch_index])


## The opposing (Team B) carrier, if any.
func _opponent_carrier() -> AIPlayer:
	for t in _team_b:
		if (t as AIPlayer).is_carrying:
			return t as AIPlayer
	return null


## The three Team A players nearest the carrier, ordered with whoever the carrier
## is running straight at first — so the default switch is the best interceptor and
## repeated presses cycle through the near three. Excludes the current player.
func _switch_shortlist(ref_pos: Vector2, ref_dir: Vector2) -> Array:
	var pool: Array = []
	for t in _team_a:
		var ai := t as AIPlayer
		if ai != _controlled:
			pool.append(ai)
	pool.sort_custom(func(a, b):
		return a.global_position.distance_to(ref_pos) < b.global_position.distance_to(ref_pos))
	var near: Array = pool.slice(0, 3)
	near.sort_custom(func(a, b):
		return (a.global_position - ref_pos).dot(ref_dir) > (b.global_position - ref_pos).dot(ref_dir))
	return near


## Read the right stick; a flick switches control to the nearest Team A player in
## roughly that direction from the current player (edge-triggered per flick).
func _poll_switch_stick() -> void:
	var rs := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var mag := rs.length()
	if mag < RS_FLICK_OFF:
		_rs_ready = true
		return
	if mag >= RS_FLICK_ON and _rs_ready:
		_rs_ready = false
		_switch_in_direction(rs.normalized())


## Switch to the closest Team A player lying roughly in `dir` from the current one.
func _switch_in_direction(dir: Vector2) -> void:
	if _controlled == null:
		return
	var origin := _controlled.global_position
	var best: AIPlayer = null
	var best_score := -INF
	for t in _team_a:
		var ai := t as AIPlayer
		if ai == _controlled:
			continue
		var off := ai.global_position - origin
		var d := off.length()
		if d < 1.0:
			continue
		var align := off.normalized().dot(dir)
		if align < 0.35:
			continue   # must be roughly in the flicked direction
		var score := align * 1000.0 - d   # prefer well-aligned, then nearest
		if score > best_score:
			best_score = score
			best       = ai
	if best:
		_set_controlled(best)


## Hand human control to a specific Team A player, clearing the previous one.
func _set_controlled(target: AIPlayer) -> void:
	if target == _controlled:
		return
	_controlled.is_human_controlled = false
	_controlled.is_selected         = false
	_controlled.cancel_windup()
	target.is_human_controlled = true
	target.is_selected         = true
	_controlled = target


## Whenever a Team A player wins the ball, the human takes over that carrier —
## so possession always puts you in control of the player running with the ball.
func _auto_control_carrier() -> void:
	for t in _team_a:
		var ai := t as AIPlayer
		if ai.is_carrying and ai != _controlled:
			_set_controlled(ai)
			return


# ── Tackling ──────────────────────────────────────────────────────────────────--

func _current_carrier() -> AIPlayer:
	for t in _team_a + _team_b:
		var ai := t as AIPlayer
		if ai.is_carrying:
			return ai
	return null


## The human pressed `tackle`. Either strike the active contest, or start one
## against an opponent carrier in reach (an illegal angle is an instant foul).
func _on_tackle_pressed() -> void:
	if _play_state != Play.LIVE:
		return
	if _contest_active:
		_resolve_human_contest()
		return
	var defender := _controlled
	if defender == null or not defender.can_tackle():
		return
	var victim := _current_carrier()
	if victim == null or victim.team == defender.team:
		return
	if defender.global_position.distance_to(victim.global_position) > TACKLE_REACH:
		return
	# Any in-range tackle starts the timing contest — the angle only nudges how
	# foul-prone a badly mistimed strike is (resolved at the end).
	_start_human_contest(defender, victim)


func _start_human_contest(defender: AIPlayer, victim: AIPlayer) -> void:
	_contest_active   = true
	_contest_defender = defender
	_contest_victim   = victim
	_contest_cursor   = 0.0
	_contest_dir      = 1.0
	_contest_timer    = 0.0
	# Freeze the whole match while the timing minigame plays out — the tackler is
	# committed and the carrier can't escape until you strike (or mistime it).
	for t in _team_a + _team_b:
		(t as AIPlayer).frozen = true
	_hud.set_status("Tackle! — time it")


func _tick_human_contest(delta: float) -> void:
	_contest_timer += delta

	# Sweep the cursor back and forth across the bar.
	_contest_cursor += _contest_dir * CONTEST_SWEEP_SPEED * delta
	if _contest_cursor >= 1.0:
		_contest_cursor = 1.0
		_contest_dir    = -1.0
	elif _contest_cursor <= 0.0:
		_contest_cursor = 0.0
		_contest_dir    = 1.0
	_hud.show_tackle_meter(_contest_cursor, CONTEST_GOOD_HW, CONTEST_PERFECT_HW)

	var v := _contest_victim
	# Carrier was dispossessed some other way (steps, another tackler) → call it off.
	if v == null or not v.is_carrying:
		_end_human_contest()
		return
	# Carrier broke away out of reach → contest lost, brief recovery.
	if _contest_defender.global_position.distance_to(v.global_position) > CONTEST_LEASH:
		_contest_defender.begin_tackle_cooldown(AIPlayer.TACKLE_COOLDOWN)
		_end_human_contest()
		return
	# Ran out of time without striking → mistimed.
	if _contest_timer >= CONTEST_DURATION:
		_contest_defender.miss_tackle()
		_hud.show_event("Mistimed!", 1.0)
		_end_human_contest()


func _resolve_human_contest() -> void:
	var off := absf(_contest_cursor - 0.5)
	var def := _contest_defender
	var vic := _contest_victim
	var foul := false
	if vic != null and vic.is_carrying:
		var foul_off := CONTEST_FOUL_OFF_BEHIND if not def.is_legal_tackle_angle(vic) else CONTEST_FOUL_OFF
		if off <= CONTEST_PERFECT_HW:
			def.steal_from(vic)
			_hud.show_event("Clean tackle!", 1.0)
		elif off <= CONTEST_GOOD_HW:
			def.knock_loose(vic, _loose_dir(vic), KNOCK_LOOSE_SPEED)
			_hud.show_event("Ball loose!", 1.0)
		elif off >= foul_off:
			# Wildly mistimed — a clumsy challenge gives away a foul.
			def.begin_tackle_cooldown(AIPlayer.TACKLE_COOLDOWN)
			foul = true
		else:
			def.miss_tackle()
			_hud.show_event("Missed!", 1.0)
	var foul_team := vic.team if vic != null else 0
	var foul_pos  := vic.global_position if vic != null else Vector2.ZERO
	# Unfreeze the world first, so a foul's set-piece can re-freeze everyone
	# cleanly (otherwise the contest teardown would unfreeze it straight after).
	_end_human_contest()
	if foul:
		_on_tackle_foul(foul_team, foul_pos)


func _end_human_contest() -> void:
	_contest_active = false
	for t in _team_a + _team_b:
		(t as AIPlayer).frozen = false
	_contest_defender = null
	_contest_victim   = null
	_hud.hide_tackle_meter()
	_hud.clear_status()


## AI defenders tackle automatically: an in-range eligible defender commits with a
## small per-frame chance, then a seeded roll decides the outcome (the human plays
## the timing minigame for the same odds instead).
func _ai_tackles() -> void:
	var victim := _current_carrier()
	if victim == null or victim._tackle_immunity > 0.0:
		return
	var defenders: Array = _team_b if victim.team == 0 else _team_a
	for t in defenders:
		var d := t as AIPlayer
		if d.is_human_controlled or not d.can_tackle():
			continue
		if d.global_position.distance_to(victim.global_position) > TACKLE_REACH:
			continue
		if _rng.randf() > AI_TACKLE_CHANCE:
			continue
		_ai_attempt_tackle(d, victim)
		return


func _ai_attempt_tackle(defender: AIPlayer, victim: AIPlayer) -> void:
	var roll := _rng.randf()
	if roll < AI_PERFECT_CHANCE:
		defender.steal_from(victim)
	elif roll < AI_SUCCESS_CHANCE:
		defender.knock_loose(victim, _loose_dir(victim), KNOCK_LOOSE_SPEED)
	else:
		# Failed tackle — usually just a missed challenge, only occasionally a foul
		# (and a little more often when coming from behind).
		var foul_chance := AI_FOUL_BEHIND if not defender.is_legal_tackle_angle(victim) else AI_FOUL_FRONT
		if _rng.randf() < foul_chance:
			defender.begin_tackle_cooldown(AIPlayer.TACKLE_COOLDOWN)
			_on_tackle_foul(victim.team, victim.global_position)
		else:
			defender.miss_tackle()


## A spilled-ball direction: forward of the carrier with a little seeded scatter.
func _loose_dir(victim: AIPlayer) -> Vector2:
	return victim.facing.rotated(_rng.randf_range(-0.9, 0.9))


# ── Ball chaser assignment ────────────────────────────────────────────────────

func _update_ball_chasers() -> void:
	_assign_chaser(_team_a, true)
	_assign_chaser(_team_b, false)


func _assign_chaser(team: Array, skip_human: bool) -> void:
	# Clear all chaser flags first.
	for t in team:
		var ai := t as AIPlayer
		if not (skip_human and ai.is_human_controlled):
			ai.is_ball_chaser = false

	# If any team member is carrying the ball, everyone else should support — no chaser needed.
	for t in team:
		if (t as AIPlayer).is_carrying:
			return

	# Ball is loose — designate the closest eligible AI as chaser. The keeper is
	# never the chaser; it holds its line and only gathers balls that come to it.
	var chaser: AIPlayer = null
	var best_dist := INF
	for t in team:
		var ai := t as AIPlayer
		if skip_human and ai.is_human_controlled:
			continue
		if ai.is_keeper:
			continue
		var d := ai.global_position.distance_to(_ball.global_position)
		if d < best_dist:
			best_dist = d
			chaser    = ai
	if chaser:
		chaser.is_ball_chaser = true


# ── Shot blocking (charge-down) ──────────────────────────────────────────────────
# A goal attempt is driven in low and hard (see Ball.release_kick). A defender can
# *charge it down* only in the first instant of flight, while it is still beside the
# shooter — after that it has cleared the close defenders and is the keeper's to
# stop (see _check_keeper_save). Without this window a low shot stayed blockable for
# its whole trajectory, so the packed defence made goals impossible. Point attempts
# are lofted above head height, so they sail over and are never charged down here.
const SHOT_BLOCK_HEIGHT := 24.0   # ball must be below this (arc px) to be charged down
const SHOT_BLOCK_RADIUS := 20.0   # how close a body must be to the ball to charge it
const BLOCK_WINDOW      := 0.18   # seconds after the kick a goal shot can be charged down
const BLOCK_ALIGN       := 0.5    # the blocker must be roughly in front of the shot line

var _goal_flight := 0.0   # seconds the current goal attempt has been in flight

func _check_shot_block(delta: float) -> void:
	if _ball.ball_state != Ball.State.FLYING or not _ball.is_goal_attempt:
		_goal_flight = 0.0
		return
	_goal_flight += delta
	if _goal_flight > BLOCK_WINDOW:
		return   # past the charge-down window — only the keeper can stop it now
	if _ball.height > SHOT_BLOCK_HEIGHT:
		return
	var vdir := _ball.velocity.normalized()
	for t in _all_players():
		var ai := t as AIPlayer
		# The keeper does not charge down — they make a save at the line instead.
		if ai == _ball.shooter or ai.is_keeper:
			continue
		var to_ai := ai.global_position - _ball.global_position
		if to_ai.length() > SHOT_BLOCK_RADIUS + AIPlayer.PLAYER_RADIUS:
			continue
		# Only a body in front of the ball, in the shot's line, charges it down.
		if to_ai.length() > 0.01 and vdir.dot(to_ai.normalized()) < BLOCK_ALIGN:
			continue
		# Charged down — the ball cannons off the blocker and spills loose.
		var n := -to_ai
		n = n.normalized() if n.length() > 0.01 else -vdir
		_ball.velocity        = n * KNOCK_LOOSE_SPEED
		_ball.is_goal_attempt = false
		_ball.shooter         = null
		_ball.last_touch_team = ai.team
		_ball.height          = 0.0
		_ball.vertical_speed  = 0.0
		_add_shake(FOUL_SHAKE)
		_hud.show_event("Blocked!", 1.0)
		return


# ── Goalkeeper save ──────────────────────────────────────────────────────────────
# Once a low goal attempt reaches the goal mouth it is the keeper's to stop. The
# save is a single seeded roll (deterministic — see CLAUDE.md) whose odds depend on
# how close the keeper is to where the ball is crossing: a shot straight at the
# keeper is nearly always saved, one placed into the far corner usually beats them.
# This is what makes placement (and the keeper's positioning) decide goals.
const KEEPER_SAVE_TRIGGER := 70.0   # ball within this of the goal line → resolve the save
const KEEPER_SAVE_SPAN    := 95.0   # keeper-to-ball gap over which save odds fall to the floor
const KEEPER_SAVE_MAX     := 0.85   # best save chance (shot right at the keeper)
const KEEPER_SAVE_MIN     := 0.08   # floor save chance (perfectly placed corner)

var _save_rolled := false   # at most one save attempt per shot

func _check_keeper_save() -> void:
	if _ball.ball_state != Ball.State.FLYING or not _ball.is_goal_attempt:
		_save_rolled = false
		return
	if _save_rolled or _ball.height > SHOT_BLOCK_HEIGHT:
		return
	var goal_sign := signf(_ball.velocity.x)
	if goal_sign == 0.0:
		return
	var bx := _ball.global_position.x
	var by := _ball.global_position.y
	if absf(bx - goal_sign * HALF_LENGTH) > KEEPER_SAVE_TRIGGER:
		return   # not at the goal mouth yet
	if absf(by) >= GOAL_HW + 6.0:
		return   # not on target — let _check_scoring rule it wide
	# The keeper defending the goal the ball is heading toward.
	var keeper := (_team_a if goal_sign < 0.0 else _team_b)[0] as AIPlayer
	var gap := absf(keeper.global_position.y - by)
	var closeness := clampf(1.0 - gap / KEEPER_SAVE_SPAN, 0.0, 1.0)
	var chance := lerpf(KEEPER_SAVE_MIN, KEEPER_SAVE_MAX, closeness)
	_save_rolled = true
	if _rng.randf() >= chance:
		return   # beaten — the ball runs on to _check_scoring for the goal
	# Saved — the keeper parries the ball back out, away from goal.
	var out := Vector2(-goal_sign, signf(by) * 0.4).normalized()
	_ball.velocity        = out * KNOCK_LOOSE_SPEED
	_ball.is_goal_attempt = false
	_ball.shooter         = null
	_ball.last_touch_team = keeper.team
	_ball.height          = 0.0
	_ball.vertical_speed  = 0.0
	_add_shake(FOUL_SHAKE)
	_hud.show_event("Save!", 1.0)


# ── Scoring ────────────────────────────────────────────────────────────────────

func _check_scoring() -> void:
	if _ball.ball_state != Ball.State.FLYING:
		return
	var bx := _ball.global_position.x
	var by := _ball.global_position.y
	if abs(by) >= GOAL_HW:
		return  # outside posts
	if bx < -HALF_LENGTH:
		# Away (team 1) attacks the left goal.
		if _square_ball(1):
			_award_square_ball(0)
		else:
			_score_for_away()
	elif bx > HALF_LENGTH:
		# Home (team 0) attacks the right goal.
		if _square_ball(0):
			_award_square_ball(1)
		else:
			_score_for_home()


func _score_for_home() -> void:
	if _ball.is_goal_attempt:
		_home_goals += 1
		_credit_scorer(_ball.shooter, true)
		_hud.update_score(_home_goals, _home_points, _away_goals, _away_points)
		_hud.show_event("GOAL!  Home %d-%02d" % [_home_goals, _home_points])
		_celebrate_goal(1)   # away keeper restarts
	else:
		_home_points += 1
		_credit_scorer(_ball.shooter, false)
		_hud.update_score(_home_goals, _home_points, _away_goals, _away_points)
		_hud.show_event("Point!  Home %d-%02d" % [_home_goals, _home_points])
		if _crowd_audio:
			_crowd_audio.react_score(false)
		_award_kickout(1)


func _score_for_away() -> void:
	if _ball.is_goal_attempt:
		_away_goals += 1
		_credit_scorer(_ball.shooter, true)
		_hud.update_score(_home_goals, _home_points, _away_goals, _away_points)
		_hud.show_event("GOAL!  Away %d-%02d" % [_away_goals, _away_points])
		_celebrate_goal(0)   # home keeper restarts
	else:
		_away_points += 1
		_credit_scorer(_ball.shooter, false)
		_hud.update_score(_home_goals, _home_points, _away_goals, _away_points)
		_hud.show_event("Point!  Away %d-%02d" % [_away_goals, _away_points])
		if _crowd_audio:
			_crowd_audio.react_score(false)
		_award_kickout(0)


## A goal: jolt the camera, cheer the crowd, then roll the slow-motion replay.
## The kickout to `kickout_team` is awarded once the replay finishes.
func _celebrate_goal(kickout_team: int) -> void:
	_add_shake(GOAL_SHAKE)
	if _crowd_audio:
		_crowd_audio.react_score(true)
	_start_replay(kickout_team)


## Record that `scorer` registered a goal or a point (for the full-time panel).
func _credit_scorer(scorer: Node2D, is_goal: bool) -> void:
	if scorer == null or not (scorer is AIPlayer):
		return
	var tally: Vector2i = _scorers.get(scorer, Vector2i.ZERO)
	if is_goal:
		tally.x += 1
	else:
		tally.y += 1
	_scorers[scorer] = tally


# ── Out of bounds ──────────────────────────────────────────────────────────────

func _check_out_of_bounds() -> void:
	# A carried ball counts as out the moment the carrier crosses a line — this is
	# what stops an AI dribbling off the pitch with no whistle and forcing a manual
	# restart. last_touch_team is the carrier's team, so the awards resolve the
	# same as a loose ball that went out off them.
	var carried := _ball.ball_state == Ball.State.CARRIED
	var bp: Vector2
	if carried:
		if _ball.carrier == null:
			return
		bp = _ball.carrier.global_position
	else:
		bp = _ball.global_position

	# Sideline — thrown/kicked in by the team that did NOT put it out.
	if abs(bp.y) > HALF_WIDTH:
		var spot := Vector2(clampf(bp.x, -HALF_LENGTH, HALF_LENGTH), signf(bp.y) * HALF_WIDTH)
		_award_sideline(_other_team(_ball.last_touch_team), spot)
		return

	# Crossed an end line outside the posts.
	if abs(bp.x) > HALF_LENGTH and abs(bp.y) >= GOAL_HW:
		var end_sign      := signf(bp.x)
		var defending     := 1 if end_sign > 0 else 0   # team defending that goal
		var attacking     := _other_team(defending)
		if _ball.last_touch_team == defending:
			# Defender put it over their own end line → 45 to the attackers.
			_award_45(attacking, end_sign, bp.y)
		else:
			# Attacker shot wide → kickout to the defending keeper.
			_award_kickout(defending)


# ── Restart / reset ──────────────────────────────────────────────────────────--

## Freeze or unfreeze every player at once (used to stop play dead at half-time).
func _freeze_all(on: bool) -> void:
	for t in _team_a + _team_b:
		(t as AIPlayer).frozen = on


## Send both teams back to their formation spots and drop the ball on the centre
## spot for a fresh contest — the second-half restart.
func _reset_to_centre() -> void:
	for t in _team_a + _team_b:
		var ai := t as AIPlayer
		ai.reset_for_restart(ai.home_position)
	_ball.carrier         = null
	_ball.ball_state      = Ball.State.FREE
	_ball.velocity        = Vector2.ZERO
	_ball.global_position = Vector2.ZERO
	_ball.height          = 0.0
	_ball.vertical_speed  = 0.0
	_ball.last_touch_team = -1
	_ball.shooter         = null


# ── Match clock ────────────────────────────────────────────────────────────────

func _update_clock_display() -> void:
	var t    := minf(_match_time, HALF_DURATION)
	var mins := int(t) / 60
	var secs := int(t) % 60
	_hud.set_clock("H%d  %02d:%02d" % [_half, mins, secs])


func _on_half_over() -> void:
	_clock_frozen = true
	_match_time   = HALF_DURATION
	_update_clock_display()
	if _half == 1:
		# Stop play dead for the interval: end any tackle contest, freeze everyone,
		# and kill the ball so a shot in flight can't sneak in during the break.
		if _contest_active:
			_end_human_contest()
		_halftime_pause = true
		_freeze_all(true)
		_ball.ball_state      = Ball.State.FREE
		_ball.carrier         = null
		_ball.velocity        = Vector2.ZERO
		_ball.global_position = Vector2.ZERO   # park it safely in-bounds for the break
		_ball.height          = 0.0
		_ball.vertical_speed  = 0.0
		_hud.show_event("HALF TIME", 3.0)
		await get_tree().create_timer(3.5).timeout
		_half       = 2
		_match_time = 0.0
		_reset_to_centre()
		# TODO: teams swap ends at half-time
		_freeze_all(false)
		_halftime_pause = false
		_clock_frozen = false
	else:
		_hud.show_event("FULL TIME", 3.0)
		_hud.show_scoreboard(
			_home_goals, _home_points, _away_goals, _away_points, _top_scorers()
		)
		await get_tree().create_timer(9.0).timeout
		GameManager.return_to_main_menu()


# ── HUD updates ────────────────────────────────────────────────────────────────

func _update_power_bar() -> void:
	if _controlled and _controlled.is_human_controlled:
		var p := _controlled.windup_power()
		if p >= 0.0:
			_hud.set_power(p)
			return
	_hud.hide_power()


# ── Events ─────────────────────────────────────────────────────────────────────

## Steps violation — free kick to the opposition at the spot.
func _on_foul(pos: Vector2, team: int) -> void:
	_hud.show_event("Steps!", 1.5)
	_award_free(_other_team(team), pos)


## Illegal tackle — penalty if it happened in the large square the fouled team
## is attacking, otherwise a free kick at the spot.
func _on_tackle_foul(fouled_team: int, pos: Vector2) -> void:
	if _crowd_audio:
		_crowd_audio.react_foul()
	var attack_sign := signf(_attack_goal_x(fouled_team))
	if _in_large_square(pos, attack_sign):
		# A cynical foul denying a goal chance in the square — straight red.
		_hud.show_card(true)
		_add_shake(FOUL_SHAKE)
		_award_penalty(fouled_team)
	else:
		# A clumsy illegal challenge — yellow card and a free.
		_hud.show_card(false)
		_hud.show_event("Free — illegal tackle", 1.5)
		_award_free(fouled_team, pos)


# ── Referee awards ───────────────────────────────────────────────────────────--

func _award_free(team: int, pos: Vector2) -> void:
	var spot := _clamp_to_pitch(pos)
	_award_set_piece("Free kick", spot, _nearest_player(team, spot))


func _award_penalty(team: int) -> void:
	var goal_x := _attack_goal_x(team)
	var spot   := Vector2(goal_x - signf(goal_x) * PENALTY_DIST, 0.0)
	_award_set_piece("Penalty!", spot, _nearest_player(team, spot))


func _award_45(team: int, end_sign: float, y: float) -> void:
	var spot := Vector2(end_sign * FORTY_FIVE_X, clampf(y, -HALF_WIDTH + 40.0, HALF_WIDTH - 40.0))
	_award_set_piece("45", spot, _nearest_player(team, spot))


func _award_sideline(team: int, spot: Vector2) -> void:
	_award_set_piece("Sideline ball", spot, _nearest_player(team, spot))


func _award_kickout(team: int) -> void:
	# The conceding/defending keeper restarts from their small square.
	var roster: Array = _team_a if team == 0 else _team_b
	var keeper := roster[0] as AIPlayer
	_award_set_piece("Kickout", keeper.home_position, keeper)


func _award_square_ball(defending_team: int) -> void:
	# Free out to the defenders from the front of their large square (20 m line).
	var s    := signf(_defend_goal_x(defending_team))
	var spot := Vector2(s * (HALF_LENGTH - 260.0), 0.0)   # 20 m line
	_hud.show_event("Square ball!", 1.5)
	_award_set_piece("Free out", spot, _nearest_player(defending_team, spot))


# ── Set-piece framework ─────────────────────────────────────────────────────--

## Stop play, place the ball with `taker`, freeze everyone, and force the
## opposition to stand back. A SET_PIECE_COUNTDOWN runs before anyone may act;
## once it ends play is armed and the taker holds the ball until they kick it:
##  • human's team → hand control to the taker (they can aim & kick but not move);
##  • opposition   → an AI takes the kick the moment the countdown ends.
## Play resumes (everyone unfreezes) the moment the taker releases the ball.
func _award_set_piece(label: String, spot: Vector2, taker: AIPlayer) -> void:
	if _contest_active:
		_end_human_contest()   # a whistle ends any in-progress tackle contest
	_play_state   = Play.SET_PIECE
	_sp_timer     = 0.0
	_sp_countdown = SET_PIECE_COUNTDOWN
	_sp_taker     = taker
	_sp_label     = label

	for t in _team_a + _team_b:
		var ai := t as AIPlayer
		ai.cancel_windup()
		ai.is_carrying        = false
		ai.is_set_piece_taker = false
		ai.set_piece_locked   = false
		ai.frozen             = true

	taker.global_position = spot
	_give_ball_to(taker, spot)
	taker.is_set_piece_taker = true
	taker.set_piece_locked   = true   # can aim during the countdown, but not yet kick

	# Opposition must retreat the regulation distance from the ball.
	_push_opponents_back(taker.team, spot)
	# Clear anyone (either team) overlapping the taker's new spot, so a player who
	# was standing where the ball is placed — e.g. whoever just gave away a steps
	# free — is nudged off instead of jittering against the taker's body.
	_separate_from_taker(taker)

	if taker.team == 0:
		_set_set_piece_controller(taker)
	_hud.set_status("%s — %d" % [label, int(SET_PIECE_COUNTDOWN)])
	_hud.hide_power()


func _tick_set_piece(delta: float) -> void:
	_sp_timer += delta
	if _sp_taker == null:
		_resume_play()
		return

	# Keep the held ball glued to the taker (it normally tracks the carrier in
	# Ball._physics_process, which also runs, but this guards placement).
	if _sp_taker.is_carrying:
		_ball.global_position = _sp_taker.global_position

	# Phase 1 — the ball is placed and a 3-second countdown runs. Nobody may act.
	if _sp_countdown > 0.0:
		_sp_countdown -= delta
		var secs := maxi(1, int(ceil(_sp_countdown)))
		_hud.set_status("%s — %d" % [_sp_label, secs])
		if _sp_countdown <= 0.0:
			_arm_set_piece()
		return

	# Phase 2 — countdown done, play is armed.
	if _sp_taker.is_carrying:
		if not _sp_taker.is_human_controlled:
			_sp_taker.take_set_piece()   # AI taker kicks now
		else:
			_update_power_bar()          # human may be charging a shot
	else:
		# The taker has kicked/passed → play is live again.
		_resume_play()


## End the countdown: free the taker to kick and update the on-screen prompt.
func _arm_set_piece() -> void:
	_sp_countdown = 0.0
	if _sp_taker == null:
		return
	_sp_taker.set_piece_locked = false
	if _sp_taker.team == 0:
		_hud.set_status("%s — aim & kick" % _sp_label)
	else:
		_hud.set_status(_sp_label)


func _resume_play() -> void:
	_play_state = Play.LIVE
	_hud.clear_status()
	_hud.hide_power()
	for t in _team_a + _team_b:
		var ai := t as AIPlayer
		ai.frozen             = false
		ai.is_set_piece_taker = false
		ai.set_piece_locked   = false
	if _sp_taker:
		# Grace period so the restart isn't tackled the instant play resumes.
		_sp_taker._tackle_immunity = AIPlayer.TACKLE_IMMUNITY
	_sp_taker = null


## Make `taker` the human-controlled player for a set piece they're taking.
func _set_set_piece_controller(taker: AIPlayer) -> void:
	if _controlled and _controlled != taker:
		_controlled.is_human_controlled = false
		_controlled.is_selected         = false
	taker.is_human_controlled = true
	taker.is_selected         = true
	_controlled = taker


## Shove every opponent of `taker_team` out to SET_PIECE_RETREAT from the ball.
func _push_opponents_back(taker_team: int, spot: Vector2) -> void:
	var opp: Array = _team_b if taker_team == 0 else _team_a
	for t in opp:
		var ai := t as AIPlayer
		var off := ai.global_position - spot
		var d := off.length()
		if d < SET_PIECE_RETREAT:
			var dir := off.normalized() if d > 0.01 else Vector2.UP
			ai.global_position = _clamp_to_pitch(spot + dir * SET_PIECE_RETREAT)


## Push any player overlapping the taker out to a clear gap, so a teammate (or the
## fouler) standing on the set-piece spot doesn't fight the taker's collision body.
func _separate_from_taker(taker: AIPlayer) -> void:
	var min_d := AIPlayer.PLAYER_RADIUS * 2.4
	for t in _team_a + _team_b:
		var ai := t as AIPlayer
		if ai == taker:
			continue
		var off := ai.global_position - taker.global_position
		var d := off.length()
		if d < min_d:
			var dir := off.normalized() if d > 0.01 else Vector2.UP
			ai.global_position = _clamp_to_pitch(taker.global_position + dir * min_d)


## Strip possession from everyone and give the ball to `taker` at `spot`.
func _give_ball_to(taker: AIPlayer, spot: Vector2) -> void:
	for t in _team_a + _team_b:
		var ai := t as AIPlayer
		ai.is_carrying  = false
		ai.steps_taken  = 0.0
		ai._carry_timer = 0.0
	taker.is_carrying      = true
	taker.steps_taken      = 0.0
	taker.has_bounced      = false
	taker._tackle_immunity = AIPlayer.TACKLE_IMMUNITY
	_ball.global_position  = spot
	_ball.pick_up(taker)


# ── Referee geometry helpers ────────────────────────────────────────────────--

func _other_team(team: int) -> int:
	return 0 if team == 1 else 1


## Goal x-coordinate the given team attacks.
func _attack_goal_x(team: int) -> float:
	return HALF_LENGTH if team == 0 else -HALF_LENGTH


## Goal x-coordinate the given team defends.
func _defend_goal_x(team: int) -> float:
	return -HALF_LENGTH if team == 0 else HALF_LENGTH


## True if any player of `attacking_team` is inside the small square they attack
## (a square ball — score is disallowed).
func _square_ball(attacking_team: int) -> bool:
	var s: float    = signf(_attack_goal_x(attacking_team))
	var roster: Array = _team_a if attacking_team == 0 else _team_b
	for t in roster:
		if _in_small_square((t as AIPlayer).global_position, s):
			return true
	return false


func _in_small_square(pos: Vector2, goal_sign: float) -> bool:
	return pos.x * goal_sign >= HALF_LENGTH - SMALL_SQ_DEPTH and absf(pos.y) <= SMALL_SQ_HW


func _in_large_square(pos: Vector2, goal_sign: float) -> bool:
	return pos.x * goal_sign >= HALF_LENGTH - LARGE_SQ_DEPTH and absf(pos.y) <= LARGE_SQ_HW


func _clamp_to_pitch(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, -HALF_LENGTH + 20.0, HALF_LENGTH - 20.0),
		clampf(pos.y, -HALF_WIDTH + 20.0, HALF_WIDTH - 20.0)
	)


func _nearest_player(team: int, spot: Vector2) -> AIPlayer:
	var roster: Array = _team_a if team == 0 else _team_b
	var best: AIPlayer = roster[0]
	var best_dist := INF
	for t in roster:
		var ai := t as AIPlayer
		var d := ai.global_position.distance_to(spot)
		if d < best_dist:
			best_dist = d
			best      = ai
	return best


func _all_players() -> Array:
	return _team_a + _team_b


# ── Live HUD indicators (possession + stamina) ─────────────────────────────────--

func _update_hud_indicators() -> void:
	var carrier := _current_carrier()
	_hud.set_possession(carrier.team if carrier else -1)
	if _controlled:
		_hud.set_stamina(_controlled.stamina)


# ── Camera shake ────────────────────────────────────────────────────────────────

## Request a shake of at least `mag` pixels (the strongest pending request wins).
func _add_shake(mag: float) -> void:
	_shake_mag = maxf(_shake_mag, mag)


## Bleed the shake off each frame, jittering the camera offset while it lasts.
func _update_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_mag <= 0.0:
		_camera.offset = Vector2.ZERO
		return
	_shake_mag = maxf(0.0, _shake_mag - SHAKE_DECAY * delta)
	_camera.offset = Vector2(
		_fx_rng.randf_range(-_shake_mag, _shake_mag),
		_fx_rng.randf_range(-_shake_mag, _shake_mag)
	)


# ── Slow-motion goal replay ──────────────────────────────────────────────────────

## Each LIVE physics frame, snapshot the ball + every player into a ring buffer so
## the last ~2 seconds can be replayed in slow motion after a goal.
func _record_frame() -> void:
	var positions := PackedVector2Array()
	var facings   := PackedVector2Array()
	for t in _all_players():
		var ai := t as AIPlayer
		positions.append(ai.global_position)
		facings.append(ai.facing)
	_replay_frames.append({
		"ball":   _ball.global_position,
		"height": _ball.height,
		"pos":    positions,
		"fac":    facings,
	})
	if _replay_frames.size() > REPLAY_FRAMES:
		_replay_frames.pop_front()


## Freeze the world and start playing the recorded buffer back at REPLAY_SPEED.
func _start_replay(kickout_team: int) -> void:
	_pending_kickout_team = kickout_team
	if _replay_frames.size() < 8:
		_award_kickout(kickout_team)   # not enough footage — skip straight to the kickout
		return
	_play_state = Play.REPLAY
	_replay_pos = 0.0
	_replay_dt  = maxf(get_physics_process_delta_time(), 0.0001)
	_ball.replay_frozen = true
	for t in _all_players():
		(t as AIPlayer).replay = true
	_hud.set_status("REPLAY")


func _tick_replay(delta: float) -> void:
	var n := _replay_frames.size()
	# Advance through the buffer at REPLAY_SPEED relative to how it was recorded.
	_replay_pos += (delta / _replay_dt) * REPLAY_SPEED
	if n == 0 or _replay_pos >= float(n - 1):
		_finish_replay()
		return
	_apply_replay_frame(_replay_frames[int(_replay_pos)])


func _apply_replay_frame(frame: Dictionary) -> void:
	_ball.global_position = frame["ball"]
	_ball.height          = frame["height"]
	_ball.queue_redraw()
	var positions: PackedVector2Array = frame["pos"]
	var facings:   PackedVector2Array = frame["fac"]
	var players := _all_players()
	for i in players.size():
		var ai := players[i] as AIPlayer
		ai.global_position = positions[i]
		ai.facing          = facings[i]
		ai.queue_redraw()


func _finish_replay() -> void:
	_ball.replay_frozen = false
	for t in _all_players():
		(t as AIPlayer).replay = false
	_replay_frames.clear()
	_hud.clear_status()
	_award_kickout(_pending_kickout_team)


# ── Full-time top scorers ────────────────────────────────────────────────────────

## Scorers sorted by weight (goal = 3, point = 1), best first, capped at five.
func _top_scorers() -> Array:
	var entries: Array = []
	for p in _scorers:
		var tally: Vector2i = _scorers[p]
		var ai := p as AIPlayer
		entries.append({
			"team":   ai.team,
			"jersey": ai.jersey,
			"goals":  tally.x,
			"points": tally.y,
		})
	entries.sort_custom(func(a, b):
		return (a["goals"] * 3 + a["points"]) > (b["goals"] * 3 + b["points"]))
	return entries.slice(0, 5)
