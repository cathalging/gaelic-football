extends Node2D
## Pitch — draws the full GAA pitch surface, markings, and goals.
## Scale ~13 px/m. Edit constants to resize without touching draw logic.
## Drawing order matters: surface → stripes → markings → rectangles → goals.

# Pitch half-extents, centred on origin. (~140 m × 86 m at 13 px/m.)
const HALF_LENGTH := 900.0   # goal-to-goal
const HALF_WIDTH  := 560.0   # sideline-to-sideline

# GAA goal: 6.5 m wide (±42 px from centre) and ~2.2 m net depth behind end line.
const GOAL_HW    := 58.0
const GOAL_DEPTH := 28.0

# Distances (px) from each end line where cross-lines are drawn:
# 13 m, 20 m, 45 m, 65 m — the four standard Gaelic football lines.
const LINES_FROM_END: Array[float] = [170.0, 260.0, 585.0, 845.0]

# Small rectangle: 14 m wide × 4.5 m deep, centred on the goal.
const SMALL_SQ_DEPTH := 58.0
const SMALL_SQ_HW    := 91.0
# Large rectangle: 19 m wide × 13 m deep (front edge sits on the 13 m line).
const LARGE_SQ_DEPTH := 170.0
const LARGE_SQ_HW    := 124.0

const STRIPE_W   := 130.0
const LINE_W     := 3.0
const POST_R     := 6.0

const C_GRASS    := Color(0.161, 0.502, 0.196)
const C_STRIPE   := Color(0.141, 0.451, 0.173)
const C_LINE     := Color(1.0, 1.0, 1.0, 0.92)
const C_NET      := Color(0.9, 0.9, 0.85, 0.35)
const C_POST     := Color(1.0, 1.0, 1.0)
const C_CROSSBAR := Color(1.0, 0.82, 0.25, 0.95)  # warm bar — matches the ball's over-bar ring


func _draw() -> void:
	_draw_surface()
	_draw_stripes()
	_draw_markings()
	_draw_rectangles(-HALF_LENGTH,  1.0)   # left goal area
	_draw_rectangles( HALF_LENGTH, -1.0)   # right goal area
	_draw_goals(-HALF_LENGTH,  1.0)   # left goal, mouth faces right (+x)
	_draw_goals( HALF_LENGTH, -1.0)   # right goal, mouth faces left (−x)


func _draw_surface() -> void:
	draw_rect(
		Rect2(Vector2(-HALF_LENGTH, -HALF_WIDTH), Vector2(HALF_LENGTH * 2.0, HALF_WIDTH * 2.0)),
		C_GRASS
	)


func _draw_stripes() -> void:
	var x := -HALF_LENGTH
	var on := false
	while x < HALF_LENGTH:
		if on:
			draw_rect(
				Rect2(Vector2(x, -HALF_WIDTH), Vector2(STRIPE_W, HALF_WIDTH * 2.0)),
				C_STRIPE
			)
		x += STRIPE_W
		on = !on


func _draw_markings() -> void:
	# Pitch boundary
	draw_rect(
		Rect2(Vector2(-HALF_LENGTH, -HALF_WIDTH), Vector2(HALF_LENGTH * 2.0, HALF_WIDTH * 2.0)),
		C_LINE, false, LINE_W
	)
	# Halfway line (Gaelic football has no centre circle).
	_vline(0.0)
	# Symmetric cross-lines from each end (13 m, 20 m, 45 m, 65 m).
	for dist in LINES_FROM_END:
		_vline(-HALF_LENGTH + dist)
		_vline( HALF_LENGTH - dist)


func _vline(x: float) -> void:
	draw_line(Vector2(x, -HALF_WIDTH), Vector2(x, HALF_WIDTH), C_LINE, LINE_W)


## Draw the small and large rectangles in front of one goal.
## end_x is the goal/end-line x; facing +1 means the field lies toward +x.
func _draw_rectangles(end_x: float, facing: float) -> void:
	_rect_open_to_field(end_x, facing, LARGE_SQ_DEPTH, LARGE_SQ_HW)
	_rect_open_to_field(end_x, facing, SMALL_SQ_DEPTH, SMALL_SQ_HW)


## Three sides of a goal-area rectangle (the goal line itself is the fourth side).
func _rect_open_to_field(end_x: float, facing: float, depth: float, hw: float) -> void:
	var front_x := end_x + facing * depth
	draw_line(Vector2(end_x, -hw),   Vector2(front_x, -hw), C_LINE, LINE_W)  # top side
	draw_line(Vector2(front_x, -hw), Vector2(front_x,  hw), C_LINE, LINE_W)  # front edge
	draw_line(Vector2(front_x,  hw), Vector2(end_x,    hw), C_LINE, LINE_W)  # bottom side


func _draw_goals(end_x: float, facing: float) -> void:
	# facing: +1 = mouth opens toward +x (right), −1 = toward −x (left).
	var net_back_x := end_x - facing * GOAL_DEPTH
	var top         := Vector2(end_x, -GOAL_HW)
	var bot         := Vector2(end_x,  GOAL_HW)
	var back_top    := Vector2(net_back_x, -GOAL_HW)
	var back_bot    := Vector2(net_back_x,  GOAL_HW)

	# Net fill (semi-transparent)
	draw_rect(
		Rect2(Vector2(minf(end_x, net_back_x), -GOAL_HW), Vector2(GOAL_DEPTH, GOAL_HW * 2.0)),
		C_NET
	)

	# Net side and back frame (three sides; mouth is open on the field side)
	draw_line(top,      back_top, C_LINE, LINE_W)
	draw_line(back_top, back_bot, C_LINE, LINE_W)
	draw_line(back_bot, bot,      C_LINE, LINE_W)

	# Crossbar (goal mouth) — drawn in a warm colour that matches the ball's over-bar
	# ring, so "ball over the bar between these posts = point" reads at a glance.
	draw_line(top, bot, C_CROSSBAR, LINE_W * 2.5)

	# Posts — drawn last so they sit on top of all lines
	draw_circle(top, POST_R, C_POST)
	draw_circle(bot, POST_R, C_POST)
