extends Node2D
## Goal fronts — the camera-side (near) uprights, redrawn ABOVE the ball and players.
##
## In the broadcast 2.5D view (see PitchProjection) the goal is seen almost edge-on,
## so its mouth is narrow on screen. The rest of the goal frame is drawn by pitch.gd
## behind play (z −1), which means a shot threaded just inside the near post used to
## be painted *over* that post (the ball sits at z 5) and read as though it had gone
## wide. This overlay redraws only the NEAR upright of each goal at a high z, so a
## ball between the posts is correctly occluded by the post nearest the camera and
## clearly reads as "inside the goal".
##
## The far upright stays behind play (a ball threading the far corner is genuinely in
## front of it, so the existing order is right there). Presentation only — these
## values mirror pitch.gd. Sits at z_index 6 (above the ball at 5) — see MatchScene.tscn.

# Must match pitch.gd.
const HALF_LENGTH := 900.0
const GOAL_HW     := 58.0     # +y side is the touchline nearest the camera (the near post)
const POST_TOP_Z  := 170.0
const POST_R      := 6.0
const LINE_W      := 3.0
const C_POST      := Color(1.0, 1.0, 1.0)


func _draw() -> void:
	# The projection is static (the camera moves, not these world points), so a single
	# draw on entering the tree is enough — nothing here changes frame to frame.
	_near_upright(-HALF_LENGTH)
	_near_upright( HALF_LENGTH)


## The near (camera-side) upright of one goal: a true vertical from the goal line up
## to POST_TOP_Z, with base and apex caps — identical to pitch.gd's, just drawn on top.
func _near_upright(end_x: float) -> void:
	var base_w := Vector2(end_x, GOAL_HW)
	var base := PitchProjection.ground(base_w)
	var apex := PitchProjection.at_height(base_w, POST_TOP_Z)
	draw_line(base, apex, C_POST, LINE_W * 1.6)
	draw_circle(apex, POST_R, C_POST)
	draw_circle(base, POST_R * 0.7, C_POST)
