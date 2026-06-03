extends Node2D
## Pitch — draws the full GAA pitch surface, markings, and goals in the tilted
## "broadcast" perspective (see PitchProjection). The pitch geometry is defined in
## the flat world plane exactly as the simulation sees it; every point is run
## through PitchProjection.ground/at_height at draw time, so the surface becomes a
## trapezoid and the goals stand up as true verticals. Scale ~13 px/m.
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

# Goal heights (world px above the ground). The crossbar sits at the ball's own
# crossbar height so "over the bar = point" lines up exactly with the ball's arc;
# the uprights continue above it like real posts.
# Tall uprights: a floated point can sail well above the bar, so the posts must rise
# high enough that you can read whether the ball passed between them.
const CROSSBAR_Z := 30.0     # == Ball.CROSSBAR_HEIGHT
const POST_TOP_Z := 170.0

const C_GRASS    := Color(0.161, 0.502, 0.196)
const C_STRIPE   := Color(0.141, 0.451, 0.173)
const C_LINE     := Color(1.0, 1.0, 1.0, 0.92)
const C_NET      := Color(0.9, 0.9, 0.85, 0.22)
const C_POST     := Color(1.0, 1.0, 1.0)
const C_CROSSBAR := Color(1.0, 0.82, 0.25, 0.95)  # warm bar — matches the ball's over-bar ring


# ── Projection helpers ──────────────────────────────────────────────────────────
# The pitch node sits at the world origin, so a flat world point maps straight
# through the projection with no extra node offset.

func _g(world: Vector2) -> Vector2:
	return PitchProjection.ground(world)


func _h(world: Vector2, z: float) -> Vector2:
	return PitchProjection.at_height(world, z)


## Draw a straight edge between two flat world points (projected).
func _wline(a: Vector2, b: Vector2, col: Color, w: float = LINE_W) -> void:
	draw_line(_g(a), _g(b), col, w)


## Fill a flat-world quad (four world corners, in order) as a projected polygon.
func _wquad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([_g(a), _g(b), _g(c), _g(d)]), col)


func _draw() -> void:
	_draw_surface()
	_draw_stripes()
	_draw_markings()
	_draw_rectangles(-HALF_LENGTH,  1.0)   # left goal area
	_draw_rectangles( HALF_LENGTH, -1.0)   # right goal area
	_draw_goals(-HALF_LENGTH,  1.0)   # left goal, mouth faces right (+x)
	_draw_goals( HALF_LENGTH, -1.0)   # right goal, mouth faces left (−x)


func _draw_surface() -> void:
	_wquad(
		Vector2(-HALF_LENGTH, -HALF_WIDTH), Vector2(HALF_LENGTH, -HALF_WIDTH),
		Vector2( HALF_LENGTH,  HALF_WIDTH), Vector2(-HALF_LENGTH,  HALF_WIDTH),
		C_GRASS)


func _draw_stripes() -> void:
	var x := -HALF_LENGTH
	var on := false
	while x < HALF_LENGTH:
		if on:
			var x1 := minf(x + STRIPE_W, HALF_LENGTH)
			_wquad(
				Vector2(x,  -HALF_WIDTH), Vector2(x1, -HALF_WIDTH),
				Vector2(x1,  HALF_WIDTH), Vector2(x,   HALF_WIDTH),
				C_STRIPE)
		x += STRIPE_W
		on = !on


func _draw_markings() -> void:
	# Pitch boundary
	_wline(Vector2(-HALF_LENGTH, -HALF_WIDTH), Vector2( HALF_LENGTH, -HALF_WIDTH), C_LINE)
	_wline(Vector2( HALF_LENGTH, -HALF_WIDTH), Vector2( HALF_LENGTH,  HALF_WIDTH), C_LINE)
	_wline(Vector2( HALF_LENGTH,  HALF_WIDTH), Vector2(-HALF_LENGTH,  HALF_WIDTH), C_LINE)
	_wline(Vector2(-HALF_LENGTH,  HALF_WIDTH), Vector2(-HALF_LENGTH, -HALF_WIDTH), C_LINE)
	# Halfway line (Gaelic football has no centre circle).
	_vline(0.0)
	# Symmetric cross-lines from each end (13 m, 20 m, 45 m, 65 m).
	for dist in LINES_FROM_END:
		_vline(-HALF_LENGTH + dist)
		_vline( HALF_LENGTH - dist)


func _vline(x: float) -> void:
	_wline(Vector2(x, -HALF_WIDTH), Vector2(x, HALF_WIDTH), C_LINE)


## Draw the small and large rectangles in front of one goal.
## end_x is the goal/end-line x; facing +1 means the field lies toward +x.
func _draw_rectangles(end_x: float, facing: float) -> void:
	_rect_open_to_field(end_x, facing, LARGE_SQ_DEPTH, LARGE_SQ_HW)
	_rect_open_to_field(end_x, facing, SMALL_SQ_DEPTH, SMALL_SQ_HW)


## Three sides of a goal-area rectangle (the goal line itself is the fourth side).
func _rect_open_to_field(end_x: float, facing: float, depth: float, hw: float) -> void:
	var front_x := end_x + facing * depth
	_wline(Vector2(end_x, -hw),   Vector2(front_x, -hw), C_LINE)  # top side
	_wline(Vector2(front_x, -hw), Vector2(front_x,  hw), C_LINE)  # front edge
	_wline(Vector2(front_x,  hw), Vector2(end_x,    hw), C_LINE)  # bottom side


func _draw_goals(end_x: float, facing: float) -> void:
	# facing: +1 = mouth opens toward +x (right), −1 = toward −x (left).
	var net_back_x := end_x - facing * GOAL_DEPTH
	var top_w   := Vector2(end_x, -GOAL_HW)   # base of the near upright
	var bot_w   := Vector2(end_x,  GOAL_HW)   # base of the far upright
	var bt_w    := Vector2(net_back_x, -GOAL_HW)
	var bb_w    := Vector2(net_back_x,  GOAL_HW)

	# Net floor (semi-transparent) — a quad on the ground behind the line.
	_wquad(top_w, bt_w, bb_w, bot_w, C_NET)

	# Back frame of the net, standing up to the crossbar height.
	draw_line(_g(bt_w), _h(bt_w, CROSSBAR_Z), C_NET, LINE_W)
	draw_line(_g(bb_w), _h(bb_w, CROSSBAR_Z), C_NET, LINE_W)
	draw_line(_h(bt_w, CROSSBAR_Z), _h(bb_w, CROSSBAR_Z), C_NET, LINE_W)
	# Net side rails (ground line from front post base to back post base).
	_wline(top_w, bt_w, C_NET)
	_wline(bot_w, bb_w, C_NET)

	# Uprights — true verticals rising from the goal line.
	var top_base := _g(top_w)
	var bot_base := _g(bot_w)
	var top_apex := _h(top_w, POST_TOP_Z)
	var bot_apex := _h(bot_w, POST_TOP_Z)
	var top_bar  := _h(top_w, CROSSBAR_Z)
	var bot_bar  := _h(bot_w, CROSSBAR_Z)

	draw_line(top_base, top_apex, C_POST, LINE_W * 1.6)
	draw_line(bot_base, bot_apex, C_POST, LINE_W * 1.6)

	# Crossbar between the uprights at bar height — warm colour, so "over this bar
	# and between these posts = point" reads at a glance and lines up with the
	# ball's own over-bar ring.
	draw_line(top_bar, bot_bar, C_CROSSBAR, LINE_W * 2.2)

	# Post caps, drawn last so they sit on top.
	draw_circle(top_apex, POST_R, C_POST)
	draw_circle(bot_apex, POST_R, C_POST)
	draw_circle(top_base, POST_R * 0.7, C_POST)
	draw_circle(bot_base, POST_R * 0.7, C_POST)
