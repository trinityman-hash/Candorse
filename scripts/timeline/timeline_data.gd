extends Node
## Autoload singleton: TimelineData
## Single source of truth for the timeline. Per Module A: UI never mutates
## mesh transforms directly — it mutates this model, and scene nodes rebuild
## themselves by listening to the signals below.
##
## Undo/redo: every mutation is expressed as a Command with do()/undo()
## closures capturing exactly the state needed to invert it. Nothing here
## replays "the type of operation" generically — each command snapshots
## the minimum data to reverse itself. This avoids the classic bug where
## an undo stack stores intent ("removed a track") without enough state
## to actually restore it (previous clips, transform, z_depth, etc).

signal track_added(track: Track)
signal track_removed(track_id: int)
signal track_changed(track: Track)
signal history_changed()
signal playhead_changed(time: float)

class Clip:
	var id: int = -1
	var path: String = ""
	var in_point: float = 0.0
	var out_point: float = 0.0
	var start_time: float = 0.0 # position on the track, in timeline-seconds

	func duration() -> float:
		return out_point - in_point

	func duplicate_clip() -> Clip:
		var c := Clip.new()
		c.id = id
		c.path = path
		c.in_point = in_point
		c.out_point = out_point
		c.start_time = start_time
		return c

class Track:
	var id: int = -1
	var kind: String = "video" # video | audio | overlay | text | sticker
	var z_depth: float = 0.0
	var curvable: bool = false
	var clips: Array = [] # Array[Clip]
	var transform := Transform3D()

	func find_clip(clip_id: int) -> Clip:
		for c in clips:
			if c.id == clip_id:
				return c
		return null

# --- Command pattern: each entry is a Dictionary with `do` and `undo`
# Callables (Godot 4 Callable, zero-arg). Kept as plain Callables rather
# than a Command class hierarchy — the operations below are simple enough
# that a class-per-command would be pure ceremony; revisit if commands grow
# branchy enough to need shared validation logic.
const MAX_HISTORY := 30

var tracks: Dictionary = {} # id -> Track
var _next_track_id: int = 0
var _next_clip_id: int = 0
var playhead_seconds: float = 0.0

var _undo_stack: Array = [] # Array[Dictionary] {do, undo, label}
var _redo_stack: Array = []

## Playhead is NOT part of the undo/redo history — scrubbing shouldn't
## consume/pollute the edit-command stack. It's still routed through this
## autoload (not left local to timeline_ui.gd) because Module A's
## single-source-of-truth rule applies to it too: video_track_mesh
## seek/decode-resume and audio playback both need one authoritative
## playhead to read, not a UI-local variable they can't see.
func set_playhead(time: float) -> void:
	playhead_seconds = max(0.0, time)
	playhead_changed.emit(playhead_seconds)

## Returns the clip on `track_id` whose [start_time, start_time+duration)
## span contains `time` (defaults to the current playhead), or null.
func find_clip_at(track_id: int, time: float = -1.0) -> Clip:
	if not tracks.has(track_id):
		return null
	var t: float = playhead_seconds if time < 0.0 else time
	var track: Track = tracks[track_id]
	for c in track.clips:
		if t >= c.start_time and t < c.start_time + c.duration():
			return c
	return null

# ---------------------------------------------------------------------------
# Track operations
# ---------------------------------------------------------------------------

func add_track(kind: String, z_depth: float = 0.0, curvable: bool = false) -> Track:
	var id := _next_track_id
	_next_track_id += 1

	var do := func():
		var t := Track.new()
		t.id = id
		t.kind = kind
		t.z_depth = z_depth
		t.curvable = curvable
		tracks[id] = t
		track_added.emit(t)

	var undo := func():
		tracks.erase(id)
		track_removed.emit(id)

	_commit(do, undo, "add_track")
	return tracks[id]

func remove_track(id: int) -> void:
	if not tracks.has(id):
		return
	var removed_track: Track = tracks[id]

	var do := func():
		tracks.erase(id)
		track_removed.emit(id)

	var undo := func():
		tracks[id] = removed_track
		track_added.emit(removed_track)

	_commit(do, undo, "remove_track")

# ---------------------------------------------------------------------------
# Clip operations
# ---------------------------------------------------------------------------

## Adds a clip to a track. Returns the new Clip, or null if track_id is invalid.
func add_clip(track_id: int, path: String, in_point: float, out_point: float, start_time: float) -> Clip:
	if not tracks.has(track_id):
		push_warning("TimelineData.add_clip: unknown track_id %d" % track_id)
		return null

	var clip_id := _next_clip_id
	_next_clip_id += 1

	var do := func():
		var c := Clip.new()
		c.id = clip_id
		c.path = path
		c.in_point = in_point
		c.out_point = out_point
		c.start_time = start_time
		tracks[track_id].clips.append(c)
		track_changed.emit(tracks[track_id])

	var undo := func():
		var t: Track = tracks[track_id]
		for i in t.clips.size():
			if t.clips[i].id == clip_id:
				t.clips.remove_at(i)
				break
		track_changed.emit(t)

	_commit(do, undo, "add_clip")
	return tracks[track_id].find_clip(clip_id)

## Removes a clip. If ripple=true, every later clip on the same track shifts
## left by the removed clip's duration (ripple-delete per Module A); if
## false, a gap is left in place (lift-delete).
func remove_clip(track_id: int, clip_id: int, ripple: bool = false) -> void:
	if not tracks.has(track_id):
		return
	var t: Track = tracks[track_id]
	var clip: Clip = t.find_clip(clip_id)
	if clip == null:
		return

	var removed_snapshot := clip.duplicate_clip()
	var duration := clip.duration()
	var shifted: Array = [] # Array[Clip] that get shifted if ripple

	var do := func():
		var track: Track = tracks[track_id]
		for i in track.clips.size():
			if track.clips[i].id == clip_id:
				track.clips.remove_at(i)
				break
		if ripple:
			shifted.clear()
			for c in track.clips:
				if c.start_time > removed_snapshot.start_time:
					shifted.append(c)
					c.start_time -= duration
		track_changed.emit(track)

	var undo := func():
		var track: Track = tracks[track_id]
		if ripple:
			for c in shifted:
				c.start_time += duration
		track.clips.append(removed_snapshot.duplicate_clip())
		track_changed.emit(track)

	_commit(do, undo, "remove_clip")

## Trims a clip's in/out points in place (does not move start_time).
func trim_clip(track_id: int, clip_id: int, new_in: float, new_out: float) -> void:
	if not tracks.has(track_id):
		return
	var clip: Clip = tracks[track_id].find_clip(clip_id)
	if clip == null:
		return
	var old_in := clip.in_point
	var old_out := clip.out_point

	var do := func():
		var c: Clip = tracks[track_id].find_clip(clip_id)
		c.in_point = new_in
		c.out_point = new_out
		track_changed.emit(tracks[track_id])

	var undo := func():
		var c: Clip = tracks[track_id].find_clip(clip_id)
		c.in_point = old_in
		c.out_point = old_out
		track_changed.emit(tracks[track_id])

	_commit(do, undo, "trim_clip")

## Splits a clip at `split_time` (timeline-seconds, absolute) into two
## clips. No-op if split_time isn't strictly inside the clip's span.
func split_clip(track_id: int, clip_id: int, split_time: float) -> void:
	if not tracks.has(track_id):
		return
	var t: Track = tracks[track_id]
	var clip: Clip = t.find_clip(clip_id)
	if clip == null:
		return
	var clip_end := clip.start_time + clip.duration()
	if split_time <= clip.start_time or split_time >= clip_end:
		return

	var split_offset := split_time - clip.start_time
	var original_snapshot := clip.duplicate_clip()
	var new_clip_id := _next_clip_id
	_next_clip_id += 1

	var do := func():
		var c: Clip = tracks[track_id].find_clip(clip_id)
		var right := c.duplicate_clip()
		right.id = new_clip_id
		right.in_point = c.in_point + split_offset
		right.start_time = c.start_time + split_offset
		c.out_point = c.in_point + split_offset
		tracks[track_id].clips.append(right)
		track_changed.emit(tracks[track_id])

	var undo := func():
		var track: Track = tracks[track_id]
		for i in track.clips.size():
			if track.clips[i].id == new_clip_id:
				track.clips.remove_at(i)
				break
		var c: Clip = track.find_clip(clip_id)
		c.in_point = original_snapshot.in_point
		c.out_point = original_snapshot.out_point
		track_changed.emit(track)

	_commit(do, undo, "split_clip")

# ---------------------------------------------------------------------------
# Undo/redo stack
# ---------------------------------------------------------------------------

func _commit(do: Callable, undo: Callable, label: String) -> void:
	do.call()
	_undo_stack.append({"do": do, "undo": undo, "label": label})
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	_redo_stack.clear()
	history_changed.emit()

func undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	entry["undo"].call()
	_redo_stack.append(entry)
	history_changed.emit()

func redo() -> void:
	if _redo_stack.is_empty():
		return
	var entry: Dictionary = _redo_stack.pop_back()
	entry["do"].call()
	_undo_stack.append(entry)
	history_changed.emit()

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()
