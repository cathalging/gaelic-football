class_name Minimap
extends Control
## Minimap — a small top-down radar in the corner of the HUD showing every player
## and the ball as dots. It reads live positions straight from the match nodes it
## is handed (presentation only — it never mutates anything).

# Source nodes, wired by HUD.setup_minimap (called from match_scene).
var _team_a: Array = []   # Array[AIPlayer] — home (blue)
var _team_b: Array = []   # Array[AIPlayer] — away (red)
var _ball: Node2D = null
var _half_length := 900.0
var _half_width  := 560.0

const C_PANEL := Color(0.04, 0.10, 0.05, 0.78)
const C_BORDER := Color(1.0, 1.0, 1.0, 0.35)
const C_LINE := Color(1.0, 1.0, 1.0, 0.20)
const C_HOME := Color(0.40, 0.62, 1.0)
const C_AWAY := Color(1.0, 0.42, 0.42)
const C_BALL := Color(1.0, 0.95, 0.55)
const C_SELECT := Color(1.0, 0.92, 0.20)

const DOT_R := 3.0
const PAD := 6.0


## Wire the live sources. Safe to call once after the teams are spawned.
func configure(team_a: Array, team_b: Array, ball: Node2D, half_length: float, half_width: float) -> void:
	_team_a = team_a
	_team_b = team_b
	_ball = ball
	_half_length = half_length
	_half_width = half_width


func _process(_delta: float) -> void:
	queue_redraw()


## Map a world position into the minimap's local rectangle (with a little padding).
func _to_map(world: Vector2) -> Vector2:
	var nx := (world.x + _half_length) / (_half_length * 2.0)
	var ny := (world.y + _half_width) / (_half_width * 2.0)
	var inner := size - Vector2(PAD, PAD) * 2.0
	return Vector2(PAD, PAD) + Vector2(clampf(nx, 0.0, 1.0) * inner.x, clampf(ny, 0.0, 1.0) * inner.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), C_BORDER, false, 1.5)
	# Halfway line.
	draw_line(Vector2(size.x * 0.5, PAD), Vector2(size.x * 0.5, size.y - PAD), C_LINE, 1.0)

	for t in _team_a:
		_draw_player(t as Node2D, C_HOME)
	for t in _team_b:
		_draw_player(t as Node2D, C_AWAY)

	if _ball:
		draw_circle(_to_map(_ball.global_position), DOT_R - 0.5, C_BALL)


func _draw_player(p: Node2D, col: Color) -> void:
	if p == null:
		return
	var at := _to_map(p.global_position)
	# The human-controlled player gets a highlight ring so you can find yourself.
	if p.get("is_selected"):
		draw_circle(at, DOT_R + 2.0, C_SELECT)
	draw_circle(at, DOT_R, col)
