extends Node2D
## Crowd — draws simple terraced stands and a speckle of spectators around the
## pitch, purely for atmosphere. Sits behind the pitch (z_index -1) so the playing
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
	z_index = -1
	_rng.seed = 0xC0FFEE   # fixed so the crowd looks the same every match
	queue_redraw()


func _draw() -> void:
	var outer_x := HALF_LENGTH + STAND_GAP + STAND_DEPTH
	var outer_y := HALF_WIDTH + STAND_GAP + STAND_DEPTH

	# Surround (track + grass margin) framing the whole ground.
	draw_rect(Rect2(Vector2(-outer_x, -outer_y), Vector2(outer_x * 2.0, outer_y * 2.0)), C_SURROUND)

	# Four stands. Each is a band of terraces facing the pitch.
	# Top & bottom (run along x).
	_draw_stand_h(-(HALF_WIDTH + STAND_GAP), -1.0)   # top stand, steps upward
	_draw_stand_h( (HALF_WIDTH + STAND_GAP),  1.0)   # bottom stand, steps downward
	# Left & right (run along y).
	_draw_stand_v(-(HALF_LENGTH + STAND_GAP), -1.0)  # left stand, steps left
	_draw_stand_v( (HALF_LENGTH + STAND_GAP),  1.0)  # right stand, steps right


## Horizontal stand along the top/bottom touchline. `dir` -1 = above pitch, +1 = below.
func _draw_stand_h(edge_y: float, dir: float) -> void:
	var x0 := -HALF_LENGTH - STAND_GAP
	var x1 :=  HALF_LENGTH + STAND_GAP
	draw_rect(Rect2(Vector2(x0, minf(edge_y, edge_y + dir * STAND_DEPTH)),
			Vector2(x1 - x0, STAND_DEPTH)), C_STAND)
	var rows := int(STAND_DEPTH / ROW_STEP)
	for r in rows:
		var y := edge_y + dir * (r + 0.5) * ROW_STEP
		draw_line(Vector2(x0, y), Vector2(x1, y), C_STAND_HI, 1.0)
		var x := x0 + SEAT_STEP * 0.5
		while x < x1:
			draw_circle(Vector2(x, y), 2.2, CROWD_COLORS[_rng.randi() % CROWD_COLORS.size()])
			x += SEAT_STEP


## Vertical stand along the left/right end line. `dir` -1 = left of pitch, +1 = right.
func _draw_stand_v(edge_x: float, dir: float) -> void:
	var y0 := -HALF_WIDTH - STAND_GAP
	var y1 :=  HALF_WIDTH + STAND_GAP
	draw_rect(Rect2(Vector2(minf(edge_x, edge_x + dir * STAND_DEPTH), y0),
			Vector2(STAND_DEPTH, y1 - y0)), C_STAND)
	var rows := int(STAND_DEPTH / ROW_STEP)
	for r in rows:
		var x := edge_x + dir * (r + 0.5) * ROW_STEP
		draw_line(Vector2(x, y0), Vector2(x, y1), C_STAND_HI, 1.0)
		var y := y0 + SEAT_STEP * 0.5
		while y < y1:
			draw_circle(Vector2(x, y), 2.2, CROWD_COLORS[_rng.randi() % CROWD_COLORS.size()])
			y += SEAT_STEP
