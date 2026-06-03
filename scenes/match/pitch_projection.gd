class_name PitchProjection
extends RefCounted
## Perspective projection for the playable match — PRESENTATION ONLY.
##
## The whole simulation (physics, AI, scoring, referee geometry) runs on a flat
## top-down plane and that never changes. This helper maps a flat world point onto
## a tilted, "watching it on TV" broadcast view so the match *renders* in 2.5D
## while the bodies stay exactly where the sim put them. Each match node applies it
## inside its own `_draw()` (via `draw_set_transform`), and the broadcast camera
## frames the projected ball position — see match_scene.gd.
##
## Flat plane (matches pitch.gd / match_scene.gd):
##   x = goal-to-goal      (−HALF_LENGTH … HALF_LENGTH)  → left ↔ right on screen
##   y = sideline-to-sideline (−HALF_WIDTH … HALF_WIDTH)  → the depth axis
##
## Camera sits on the near touchline, so:
##   near touchline (+y) → bottom of screen, large
##   far  touchline (−y) → top of screen, small
##
## Why the maths stays simple: with this mapping both screen_x and screen_y are
## linear in the depth scale `s`, so a straight world line stays a straight screen
## line. That means the pitch projects to a clean trapezoid and the goalposts to
## true verticals — no curve subdivision anywhere.

# Must match pitch.gd / match_scene.gd.
const HALF_LENGTH := 900.0
const HALF_WIDTH  := 560.0

# ── Tunables (this is the "strong arcade tilt" preset) ──────────────────────────
## Depth scale at the near touchline (foreground) and far touchline (background).
## FAR_SCALE ≈ 0.55 → the far end is just over half the size of the near end.
const NEAR_SCALE := 1.0
const FAR_SCALE  := 0.66
## Screen px spanned from the far sideline to the near sideline. Lower = flatter /
## more foreshortened depth; higher = a taller pitch on screen.
const VSPAN := 780.0
## Screen px of vertical lift per world px of height (ball arc, goalpost height).
## This is what makes a lofted point sail visibly over the crossbar.
const Z_GAIN := 1.35


## 0 at the near touchline (+y), 1 at the far touchline (−y). Deliberately NOT
## clamped, so off-pitch decoration (the crowd/stands) extrapolates outward cleanly.
static func depth_t(world_y: float) -> float:
	return (HALF_WIDTH - world_y) / (2.0 * HALF_WIDTH)


## Depth scale for a given far-ness `t` (perspective: 1/distance).
static func scale_at_t(t: float) -> float:
	var dist := lerpf(1.0, NEAR_SCALE / FAR_SCALE, t)
	dist = maxf(dist, 0.3)   # guard against degenerate / negative far extrapolation
	return NEAR_SCALE / dist


## Depth scale (how big to draw something) at a flat world y.
static func scale_at(world_y: float) -> float:
	return scale_at_t(depth_t(world_y))


## Project a flat world point onto the ground plane of the broadcast view.
static func ground(world: Vector2) -> Vector2:
	var s := scale_at_t(depth_t(world.y))
	var u := (s - FAR_SCALE) / (NEAR_SCALE - FAR_SCALE)   # 1 at near, 0 at far
	var sx := world.x * s
	var sy := lerpf(-VSPAN * 0.5, VSPAN * 0.5, u)
	return Vector2(sx, sy)


## Project a flat world point standing `z` world-px above the ground (ball arc,
## goalpost top, a jumping player) into the broadcast view.
static func at_height(world: Vector2, z: float) -> Vector2:
	return ground(world) - Vector2(0.0, z * scale_at(world.y) * Z_GAIN)


## Screen lift (px, already depth-scaled) for a height `z` at world y. Handy when a
## node already knows its ground transform and only needs the vertical offset.
static func lift(world_y: float, z: float) -> float:
	return z * scale_at(world_y) * Z_GAIN
