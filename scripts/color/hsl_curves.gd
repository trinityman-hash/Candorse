extends Resource
class_name HSLCurves
## Module E (color/grading slice): per-channel tone curves — the
## "Curves" grading tool, distinct from the Lift/Gamma/Gain wheels
## already implemented in ColorGradeState. Closes the gap tracked in
## docs/COLOR_ENGINE_STATUS.md ("HSL curves per channel").
##
## Four channels: Master, Red, Green, Blue. Each is a Godot `Curve`
## resource a UI curve-editor widget can bind to directly (drag points,
## add/remove anchors) via the add_point/move_point/remove_point API
## below — this class holds no UI code itself, same data/rendering-
## first-then-UI ordering the rest of Module E already follows.
##
## Composition order matches DaVinci/Photoshop: the Master curve is
## evaluated first (reshapes all channels equally, e.g. an S-curve for
## contrast), then the per-channel curve is evaluated on THAT result
## (e.g. pulling blue down in the shadows). Both are pre-baked into one
## 256x1 lookup texture so the shader never evaluates a spline per pixel
## — it does three cheap texture2D fetches instead. Baking only happens
## when a curve is actually edited (mark_dirty), not per frame, so this
## stays free for tracks that never touch it (is_identity() lets
## ColorGradeState skip binding the LUT entirely).

const LUT_RESOLUTION := 256
const CHANNELS := ["master", "red", "green", "blue"]

@export var master_curve: Curve
@export var red_curve: Curve
@export var green_curve: Curve
@export var blue_curve: Curve

var _baked_texture: ImageTexture
var _dirty: bool = true

func _init() -> void:
	# Resources loaded from a .tres will already have these populated;
	# only fill in missing channels so a partially-authored curve set
	# (e.g. hand-written test data) isn't clobbered.
	if master_curve == null:
		master_curve = _identity_curve()
	if red_curve == null:
		red_curve = _identity_curve()
	if green_curve == null:
		green_curve = _identity_curve()
	if blue_curve == null:
		blue_curve = _identity_curve()

static func _identity_curve() -> Curve:
	var c := Curve.new()
	c.clear_points()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(1.0, 1.0))
	c.min_value = 0.0
	c.max_value = 1.0
	return c

## True if every channel is still the default two-point identity line.
## ColorGradeState uses this to skip binding the LUT texture and leave
## hsl_curves_enabled = false, so an untouched curve set costs the
## shader nothing — same "opt-in, zero cost when unused" pattern as
## chroma_key.gdshader.
func is_identity() -> bool:
	return _is_curve_identity(master_curve) and _is_curve_identity(red_curve) \
		and _is_curve_identity(green_curve) and _is_curve_identity(blue_curve)

static func _is_curve_identity(curve: Curve) -> bool:
	if curve == null or curve.point_count != 2:
		return false
	return curve.get_point_position(0).is_equal_approx(Vector2.ZERO) \
		and curve.get_point_position(1).is_equal_approx(Vector2.ONE)

## Marks the bake stale. Called internally by every mutator below;
## exposed publicly too in case a caller edits a Curve resource directly
## (e.g. binding it straight into an editor CurveEdit control) instead
## of going through add_point/move_point/remove_point.
func mark_dirty() -> void:
	_dirty = true

## Re-samples all four curves into the combined lookup texture. Public
## so callers can force an eager bake (e.g. right before export, to
## avoid a first-frame stall on the lazy path in get_texture()), but
## get_texture() is the normal entry point — most callers never need to
## call this directly.
func bake() -> ImageTexture:
	var img := Image.create(LUT_RESOLUTION, 1, false, Image.FORMAT_RGB8)
	for i in range(LUT_RESOLUTION):
		var x := float(i) / float(LUT_RESOLUTION - 1)
		var after_master := clampf(master_curve.sample_baked(x), 0.0, 1.0)
		var r := clampf(red_curve.sample_baked(after_master), 0.0, 1.0)
		var g := clampf(green_curve.sample_baked(after_master), 0.0, 1.0)
		var b := clampf(blue_curve.sample_baked(after_master), 0.0, 1.0)
		img.set_pixel(i, 0, Color(r, g, b))

	if _baked_texture == null:
		_baked_texture = ImageTexture.create_from_image(img)
	else:
		_baked_texture.set_image(img)
	_dirty = false
	return _baked_texture

## The only entry point ColorGradeState needs: returns the current
## lookup texture, re-baking first if any curve changed since the last
## bake. Safe to call every frame — the re-bake only actually runs when
## `_dirty` is set.
func get_texture() -> ImageTexture:
	if _dirty or _baked_texture == null:
		bake()
	return _baked_texture

## Adds a control point to the given channel, clamped into the valid
## [0,1]x[0,1] domain (both axes are normalized: x = input level,
## y = output level). Returns the new point's index, or -1 if `channel`
## isn't one of "master"/"red"/"green"/"blue".
func add_point(channel: String, position: Vector2) -> int:
	var curve := _curve_for(channel)
	if curve == null:
		push_error("HSLCurves.add_point: unknown channel '%s'" % channel)
		return -1
	var clamped := Vector2(clampf(position.x, 0.0, 1.0), clampf(position.y, 0.0, 1.0))
	var idx := curve.add_point(clamped)
	mark_dirty()
	return idx

## Removes a control point. The first and last points on a channel are
## its domain anchors (x=0 and x=1) — removing either would leave
## sample_baked() extrapolating flat past the last real point for any
## pixel value beyond it, silently clipping part of the tonal range.
## Anchors are permanently protected; use reset_channel() to restore a
## channel to its default two-point identity line instead.
func remove_point(channel: String, index: int) -> void:
	var curve := _curve_for(channel)
	if curve == null:
		push_error("HSLCurves.remove_point: unknown channel '%s'" % channel)
		return
	if index <= 0 or index >= curve.point_count - 1:
		push_warning("HSLCurves.remove_point: refusing to remove a domain anchor (first/last point) on '%s'" % channel)
		return
	curve.remove_point(index)
	mark_dirty()

## Moves an existing point to a new (input, output) position, clamped
## into [0,1]x[0,1]. Changing a point's x-offset can re-sort Curve's
## internal point list, so the index passed in may not match the index
## after the move — this returns the point's NEW index; callers tracking
## a selected point for further drags must use the returned value, not
## the one they passed in.
func move_point(channel: String, index: int, new_position: Vector2) -> int:
	var curve := _curve_for(channel)
	if curve == null:
		push_error("HSLCurves.move_point: unknown channel '%s'" % channel)
		return -1
	var clamped := Vector2(clampf(new_position.x, 0.0, 1.0), clampf(new_position.y, 0.0, 1.0))
	var new_index := curve.set_point_offset(index, clamped.x)
	curve.set_point_value(new_index, clamped.y)
	mark_dirty()
	return new_index

## Resets a single channel to its default two-point identity line
## (no-op grade for that channel only — the other three are untouched).
func reset_channel(channel: String) -> void:
	var curve := _curve_for(channel)
	if curve == null:
		push_error("HSLCurves.reset_channel: unknown channel '%s'" % channel)
		return
	curve.clear_points()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	mark_dirty()

## Resets all four channels — the "no-op grade" for the whole curves tool.
func reset_all() -> void:
	for channel in CHANNELS:
		reset_channel(channel)

func _curve_for(channel: String) -> Curve:
	match channel:
		"master": return master_curve
		"red": return red_curve
		"green": return green_curve
		"blue": return blue_curve
		_: return null
