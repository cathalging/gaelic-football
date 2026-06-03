extends Node2D
## Crowd — draws simple terraced stands and a speckle of spectators around the
## pitch, purely for atmosphere. Projected through PitchProjection (like the pitch)
## so the stands wrap the tilted playing surface — the far stand reads small and
## high, the near stand large and low. Sits behind the pitch (z_index -2) so the
## surface and its markings always draw on top. Static: drawn once.

# Pitch half-extents (must match pitch.gd / match_scene.gd).
const HALF_LENGTH := 900.0
const HALF_WIDTH  := 560.0

const STAND_DEPTH := 150.0   # how far the terraces extend out from the pitch
const STAND_GAP   := 26.0    # bare strip (sideline/track) between pitch and stand
const ROW_STEP    := 30.0    # spacing between terrace rows
const SEAT_STEP   := 22.0    # spacing between spectators along a row

const C_SURROUND := Color(0.10, 0.30, 0.13)   # darker grass / track surround
const C_STAND    := Color(0.16, 0.17, 0.20)   # concrete terrace
const C_STAND_HI := Color(0.22, 0.23, 0.27)   # lighter step edge

# A handful of jersey colours so the crowd reads as a mixed, speckled mass.
const CROWD_COLORS: Array[Color] = [
	Color(0.85, 0.30, 0.30), Color(0.30, 0.45, 0.85), Color(0.90, 0.85, 0.35),
	Color(0.85, 0.85, 0.88), Color(0.35, 0.70, 0.45), Color(0.55, 0.35, 0.70),
]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = -2   # behind the pitch surface (pitch sits at -1)
	_rng.seed = 0xC0FFEE   # fixed so the crowd looks the same every match
	queue_redraw()


func _g(world: Vector2) -> Vector2:
	return PitchProjection.ground(world)


func _wquad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([_g(a), _g(b), _g(c), _g(d)]), col)


func _draw() -> void:
	var outer_x := HALF_LENGTH + STAND_GAP + STAND_DEPTH
	var outer_y := HALF_WIDTH + STAND_GAP + STAND_DEPTH

	# Surround (track + grass margin) framing the whole ground.
	_wquad(
		Vector2(-outer_x, -outer_y), Vector2(outer_x, -outer_y),
		Vector2( outer_x,  outer_y), Vector2(-outer_x,  outer_y), C_SURROUND)

	# Four stands. Each is a band of terraces facing the pitch.
	# Top & bottom (run along x).
	_draw_stand_h(-(HALF_WIDTH + STAND_GAP), -1.0)   # top stand, steps upward (far)
	_draw_stand_h( (HALF_WIDTH + STAND_GAP),  1.0)   # bottom stand, steps downward (near)
	# Left & right (run along y).
	_draw_stand_v(-(HALF_LENGTH + STAND_GAP), -1.0)  # left stand, steps left
	_draw_stand_v( (HALF_LENGTH + STAND_GAP),  1.0)  # right stand, steps right


## Horizontal stand along the top/bottom touchline. `dir` -1 = above pitch, +1 = below.
func _draw_stand_h(edge_y: float, dir: float) -> void:
	var x0 := -HALF_LENGTH - STAND_GAP
	var x1 :=  HALF_LENGTH + STAND_GAP
	var ye := edge_y + dir * STAND_DEPTH
	_wquad(Vector2(x0, edge_y), Vector2(x1, edge_y), Vector2(x1, ye), Vector2(x0, ye), C_STAND)
	var rows := int(STAND_DEPTH / ROW_STEP)
	for r in rows:
		var y := edge_y + dir * (r + 0.5) * ROW_STEP
		draw_line(_g(Vector2(x0, y)), _g(Vector2(x1, y)), C_STAND_HI, 1.0)
		var x := x0 + SEAT_STEP * 0.5
		while x < x1:
			draw_circle(_g(Vector2(x, y)), 2.2 * PitchProjection.scale_at(y),
					CROWD_COLORS[_rng.randi() % CROWD_COLORS.size()])
			x += SEAT_STEP


## Vertical stand along the left/right end line. `dir` -1 = left of pitch, +1 = right.
func _draw_stand_v(edge_x: float, dir: float) -> void:
	var y0 := -HALF_WIDTH - STAND_GAP
	var y1 :=  HALF_WIDTH + STAND_GAP
	var xe := edge_x + dir * STAND_DEPTH
	_wquad(Vector2(edge_x, y0), Vector2(xe, y0), Vector2(xe, y1), Vector2(edge_x, y1), C_STAND)
	var rows := int(STAND_DEPTH / ROW_STEP)
	for r in rows:
		var x := edge_x + dir * (r + 0.5) * ROW_STEP
		draw_line(_g(Vector2(x, y0)), _g(Vector2(x, y1)), C_STAND_HI, 1.0)
		var y := y0 + SEAT_STEP * 0.5
		while y < y1:
			draw_circle(_g(Vector2(x, y)), 2.2 * PitchProjection.scale_at(y),
					CROWD_COLORS[_rng.randi() % CROWD_COLORS.size()])
			y += SEAT_STEP
