extends Control
class_name TimelineTrackStrip
## Module A/I: renders one track's clips as draggable strips beneath the
## label row in timeline_ui.gd. Body drag = reposition (move_clip).
## Left/right edge drag (~EDGE_GRAB_PX hit zone) = trim in/out. Both
## preview locally during the gesture (moving the Panel node directly,
## never touching TimelineData mid-drag) and commit exactly once on
## release — so undo/redo gets one entry per gesture, not one per
## drag-frame. Snap increments are computed in timeline-seconds
## (SNAP_SECONDS), never raw pixel deltas, per Module A's explicit rule.
##
## This widget never mutates mesh transforms or anything in the 3D stage
## directly — it only ever calls TimelineData methods. TrackStageController
## and video_track_mesh.gd pick up the resulting track_changed signal on
## their own.

const PIXELS_PER_SECOND := 40.0
const SNAP_SECONDS := 0.1
const EDGE_GRAB_PX := 10.0
const CLIP_HEIGHT := 36.0
const PLAYHEAD_COLOR := Color(1.0, 0.35, 0.35, 0.9)

@export var track_id: int = -1

var _panels: Dictionary = {} # clip_id -> Panel

var _dragging_clip_id: int = -1
var _drag_mode: String = "" # "move" | "trim_left" | "trim_right"
var _drag_start_mouse_x: float = 0.0
var _clip_snapshot: Dictionary = {} # {in_point, out_point, start_time} at drag begin
var _pending_value: float = 0.0 # the snapped candidate value, applied on release

func _ready() -> void:
	custom_minimum_size.y = CLIP_HEIGHT + 8.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	if has_node("/root/TimelineData"):
		var td = get_node("/root/TimelineData")
		td.track_changed.connect(_on_track_changed)
		td.playhead_changed.connect(func(_t): queue_redraw())
	_rebuild()

func _draw() -> void:
	if not has_node("/root/TimelineData"):
		return
	var td = get_node("/root/TimelineData")
	var x := td.playhead_seconds * PIXELS_PER_SECOND
	draw_line(Vector2(x, 0), Vector2(x, size.y), PLAYHEAD_COLOR, 2.0)

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_panels.clear()
	if not has_node("/root/TimelineData"):
		return
	var td = get_node("/root/TimelineData")
	if not td.tracks.has(track_id):
		return
	for clip in td.tracks[track_id].clips:
		_add_clip_panel(clip)
	queue_redraw()

func _add_clip_panel(clip) -> void:
	var panel := Panel.new()
	panel.position = Vector2(clip.start_time * PIXELS_PER_SECOND, 4)
	panel.size = Vector2(max(clip.duration() * PIXELS_PER_SECOND, 4.0), CLIP_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event): _on_clip_gui_input(event, panel, clip.id))
	panel.mouse_default_cursor_shape = Control.CURSOR_HSPLIT

	var label := Label.new()
	label.text = clip.path.get_file() if clip.path != "" else "clip #%d" % clip.id
	label.clip_text = true
	label.size = panel.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	add_child(panel)
	_panels[clip.id] = panel

func _on_track_changed(track) -> void:
	if track.id != track_id or _dragging_clip_id != -1:
		return # don't rebuild out from under an active drag
	_rebuild()

func _on_clip_gui_input(event: InputEvent, panel: Panel, clip_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event, panel, clip_id)
		elif _dragging_clip_id == clip_id:
			_end_drag()
	elif event is InputEventMouseMotion and _dragging_clip_id == clip_id:
		_update_drag(event, panel)

func _begin_drag(event: InputEventMouseButton, panel: Panel, clip_id: int) -> void:
	var td = get_node("/root/TimelineData")
	var clip = td.tracks[track_id].find_clip(clip_id)
	if clip == null:
		return
	_dragging_clip_id = clip_id
	_drag_start_mouse_x = event.global_position.x
	_clip_snapshot = {"in_point": clip.in_point, "out_point": clip.out_point, "start_time": clip.start_time}

	var local_x := event.position.x
	if local_x <= EDGE_GRAB_PX:
		_drag_mode = "trim_left"
	elif local_x >= panel.size.x - EDGE_GRAB_PX:
		_drag_mode = "trim_right"
	else:
		_drag_mode = "move"

func _snap(seconds: float) -> float:
	return round(seconds / SNAP_SECONDS) * SNAP_SECONDS

func _update_drag(event: InputEventMouseMotion, panel: Panel) -> void:
	var delta_sec := _snap((event.global_position.x - _drag_start_mouse_x) / PIXELS_PER_SECOND)
	match _drag_mode:
		"move":
			_pending_value = max(0.0, float(_clip_snapshot["start_time"]) + delta_sec)
			panel.position.x = _pending_value * PIXELS_PER_SECOND
		"trim_left":
			var max_in: float = float(_clip_snapshot["out_point"]) - 0.05
			_pending_value = clamp(float(_clip_snapshot["in_point"]) + delta_sec, 0.0, max_in)
			var applied_delta: float = _pending_value - float(_clip_snapshot["in_point"])
			panel.position.x = max(0.0, (float(_clip_snapshot["start_time"]) + applied_delta) * PIXELS_PER_SECOND)
			panel.size.x = max(4.0, (float(_clip_snapshot["out_point"]) - _pending_value) * PIXELS_PER_SECOND)
		"trim_right":
			var min_out: float = float(_clip_snapshot["in_point"]) + 0.05
			_pending_value = max(min_out, float(_clip_snapshot["out_point"]) + delta_sec)
			panel.size.x = max(4.0, (_pending_value - float(_clip_snapshot["in_point"])) * PIXELS_PER_SECOND)

func _end_drag() -> void:
	if _dragging_clip_id == -1:
		return
	var td = get_node("/root/TimelineData")
	match _drag_mode:
		"move":
			td.move_clip(track_id, _dragging_clip_id, _pending_value)
		"trim_left":
			td.trim_clip_left(track_id, _dragging_clip_id, _pending_value)
		"trim_right":
			td.trim_clip(track_id, _dragging_clip_id, float(_clip_snapshot["in_point"]), _pending_value)
	_dragging_clip_id = -1
	_drag_mode = ""
	_rebuild()
