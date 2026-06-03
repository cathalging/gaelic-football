class_name MatchSprites
extends RefCounted
## Sprite billboard factory for the playable match — PRESENTATION ONLY.
##
## Stage 2 of the 2.5D broadcast view (see PitchProjection): players and the ball
## are drawn as upright billboards instead of flat top-down discs. This helper
## *generates* the placeholder artwork procedurally into an `ImageTexture` so there
## is a real sprite pipeline in place — each match node draws a texture, not a stack
## of primitives. When real art arrives it drops straight in: assign a `Texture2D`
## to `AIPlayer.sprite` / the ball before the node draws and nothing else changes.
##
## Everything here is static, pure and cached by appearance, so the handful of
## textures a match needs (two outfield kits, the keeper kit, the ball) are built
## once and shared. It touches no simulation state.

# Shared placeholder palette.
const SKIN   := Color(0.93, 0.78, 0.62)   # face / forearms
const HAIR   := Color(0.25, 0.18, 0.12)   # head mass above the face
const SHORTS := Color(0.93, 0.93, 0.95)   # off-white shorts
const SOCK   := Color(0.16, 0.16, 0.20)   # socks
const BOOT   := Color(0.10, 0.10, 0.12)   # boots

const BALL_HILITE := Color(0.99, 0.97, 0.90)        # lit side of the leather
const BALL_SHADOW := Color(0.78, 0.72, 0.56)        # shaded side (gives it roundness)
const BALL_RIM    := Color(0.45, 0.32, 0.16)        # dark stitched rim
const BALL_SEAM   := Color(0.42, 0.29, 0.15, 0.70)  # curved panel seams

# Built textures, keyed by appearance so they're generated at most once.
static var _cache: Dictionary = {}


## A player billboard for the given kit. `body` is the jersey colour, `outline` the
## darker trim used around the torso and head. Cached per colour pair.
static func player(body: Color, outline: Color) -> ImageTexture:
	var key := "p:%s:%s" % [body.to_html(), outline.to_html()]
	if _cache.has(key):
		return _cache[key]
	var tex := _build_player(body, outline)
	_cache[key] = tex
	return tex


## The match ball billboard. Cached (one for the whole match).
static func ball() -> ImageTexture:
	if _cache.has("ball"):
		return _cache["ball"]
	var tex := _build_ball()
	_cache["ball"] = tex
	return tex


# ── Figure generation ──────────────────────────────────────────────────────────

## A front-on standing footballer: boots, socks, shorts, a jersey with sleeves and
## a forearm of skin, then a head (hair mass + face). Drawn feet-at-bottom into a
## 44×64 canvas so the draw code can sit the feet on the projected ground.
static func _build_player(body: Color, outline: Color) -> ImageTexture:
	const W := 44
	const H := 64
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var cx := 22.0

	# Legs — socks then boots at the very bottom.
	_rect(img, 15, 44, 21, 57, SOCK)
	_rect(img, 23, 44, 29, 57, SOCK)
	_rect(img, 13, 57, 21, 62, BOOT)
	_rect(img, 23, 57, 31, 62, BOOT)

	# Shorts (outline then fill).
	_rect(img, 12, 37, 32, 49, outline)
	_rect(img, 13, 38, 31, 48, SHORTS)

	# Arms — jersey sleeves with a skin forearm below each.
	_rect(img,  9, 22, 14, 35, body)
	_rect(img, 30, 22, 35, 35, body)
	_rect(img,  9, 35, 13, 41, SKIN)
	_rect(img, 31, 35, 35, 41, SKIN)

	# Torso jersey (outline, fill, a lighter shoulder band so it isn't a flat slab).
	_rect(img, 11, 19, 33, 41, outline)
	_rect(img, 13, 21, 31, 40, body)
	_rect(img, 13, 21, 31, 24, body.lightened(0.16))

	# Head — outline disc, hair mass, then the face lower down.
	_disc(img, cx, 13.0, 9.0, outline)
	_disc(img, cx, 12.5, 7.8, HAIR)
	_disc(img, cx, 14.6, 6.5, SKIN)

	return ImageTexture.create_from_image(img)


## A Gaelic football: a shaded leather sphere (highlight top-left → shadow
## bottom-right gives it volume) with the curved panel seams an O'Neills ball reads
## as — a bowed "equator" crossed by two bowed meridians, plus a stitched rim.
static func _build_ball() -> ImageTexture:
	const S := 30
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var c := S * 0.5
	var centre := Vector2(c, c)
	var r := 13.5
	var hl := Vector2(c - 4.0, c - 4.0)   # light comes from the top-left
	# Shaded body — every covered pixel is lit by its nearness to the highlight.
	var x1 := int(ceil(c + r + 1.0))
	var y1 := int(ceil(c + r + 1.0))
	for yy in range(0, y1):
		for xx in range(0, x1):
			var p := Vector2(xx + 0.5, yy + 0.5)
			var cov := clampf(r + 0.5 - p.distance_to(centre), 0.0, 1.0)
			if cov <= 0.0:
				continue
			var lit := clampf(1.0 - p.distance_to(hl) / (r * 1.7), 0.0, 1.0)
			var body := BALL_SHADOW.lerp(BALL_HILITE, lit)
			_paint(img, xx, yy, Color(body.r, body.g, body.b, cov))
	# Curved panel seams (axis-aligned ellipses stay inside the body).
	_seam(img, centre, r * 0.94, r * 0.40)   # bowed equator
	_seam(img, centre, r * 0.46, r * 0.94)   # bowed meridian
	_seam(img, centre, r * 0.80, r * 0.86)   # second, fuller panel line
	_seam(img, centre, r, r, BALL_RIM)        # stitched outer rim
	return ImageTexture.create_from_image(img)


# ── Low-level raster helpers ────────────────────────────────────────────────────

## Alpha-composite `col` over the pixel at (x, y) (skips out-of-bounds).
static func _paint(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var sa := col.a
	if sa <= 0.0:
		return
	if sa >= 1.0:
		img.set_pixel(x, y, col)
		return
	var dst := img.get_pixel(x, y)
	var oa := sa + dst.a * (1.0 - sa)
	if oa <= 0.0:
		return
	var inv := 1.0 / oa
	img.set_pixel(x, y, Color(
		(col.r * sa + dst.r * dst.a * (1.0 - sa)) * inv,
		(col.g * sa + dst.g * dst.a * (1.0 - sa)) * inv,
		(col.b * sa + dst.b * dst.a * (1.0 - sa)) * inv,
		oa))


## Fill the half-open rectangle [x0, x1) × [y0, y1) with `col`.
static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for yy in range(y0, y1):
		for xx in range(x0, x1):
			_paint(img, xx, yy, col)


## Stitch a thin curved seam along the axis-aligned ellipse (rx, ry) about `centre`,
## plotted as a run of small soft dots. With rx, ry ≤ the ball radius the whole curve
## stays inside the body, so seams never spill past the rim.
static func _seam(img: Image, centre: Vector2, rx: float, ry: float, col: Color = BALL_SEAM) -> void:
	var steps := int(maxf(rx, ry) * 6.0) + 10
	for i in steps:
		var a := TAU * float(i) / float(steps)
		_disc(img, centre.x + rx * cos(a), centre.y + ry * sin(a), 0.9, col)


## Fill a disc centred at (cx, cy) of radius `r`, with 1 px of edge coverage AA.
static func _disc(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var x0 := int(floor(cx - r - 1.0))
	var x1 := int(ceil(cx + r + 1.0))
	var y0 := int(floor(cy - r - 1.0))
	var y1 := int(ceil(cy + r + 1.0))
	var centre := Vector2(cx, cy)
	for yy in range(y0, y1):
		for xx in range(x0, x1):
			var d := Vector2(xx + 0.5, yy + 0.5).distance_to(centre)
			var cov := clampf(r + 0.5 - d, 0.0, 1.0)
			if cov > 0.0:
				_paint(img, xx, yy, Color(col.r, col.g, col.b, col.a * cov))
