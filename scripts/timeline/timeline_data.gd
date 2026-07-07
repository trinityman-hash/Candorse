extends Node
## Autoload singleton: TimelineData
## Single source of truth for the timeline. Per Module A: UI never mutates
## mesh transforms directly — it mutates this model, and scene nodes rebuild
## themselves by listening to the signals below.

signal track_added(track: Track)
signal track_removed(track_id: int)
signal track_changed(track: Track)
signal history_changed()

class Clip:
	var path: String = ""
	var in_point: float = 0.0
	var out_point: float = 0.0
	var start_time: float = 0.0 # position on the track, in timeline-seconds

class Track:
	var id: int = -1
	var kind: String = "video" # video | audio | overlay | text | sticker
	var z_depth: float = 0.0
	var curvable: bool = false
	var clips: Array = [] # Array[Clip]
	var transform := Transform3D()

var tracks: Dictionary = {} # id -> Track
var _next_id: int = 0

# --- Command-pattern undo/redo stack (Module A: min. 30 steps) ---
const MAX_HISTORY := 30
var _undo_stack: Array = []
var _redo_stack: Array = []

func add_track(kind: String) -> Track:
	var t := Track.new()
	t.id = _next_id
	_next_id += 1
	t.kind = kind
	tracks[t.id] = t
	_push_history({"type": "add_track", "id": t.id})
	track_added.emit(t)
	return t

func remove_track(id: int) -> void:
	if not tracks.has(id):
		return
	tracks.erase(id)
	_push_history({"type": "remove_track", "id": id})
	track_removed.emit(id)

func _push_history(entry: Dictionary) -> void:
	_undo_stack.append(entry)
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	_redo_stack.clear()
	history_changed.emit()

func undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(entry)
	# TODO: apply inverse of entry to model, re-emit appropriate signal.
	history_changed.emit()

func redo() -> void:
	if _redo_stack.is_empty():
		return
	var entry: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(entry)
	# TODO: re-apply entry to model.
	history_changed.emit()
