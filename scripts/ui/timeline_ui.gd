extends Control
## Module I: this is the "Timeline/Trim UI" surface — 2D, familiar,
## CapCut-like. Never mixes 3D roam controls into this scene. The
## "Enter Scene" button below is the ONLY bridge to Phase 2's
## Scene/Roam UI — everything else stays flat here by design.
##
## Phase 1 scope: play/pause, scrub, add/remove track, trim in/out,
## split, ripple-delete, drag-reorder. All of it mutates TimelineData,
## never touches TimelineStage nodes directly (Module A single-source-
## of-truth rule).

signal enter_scene_requested()

@onready var _play_button: Button = %PlayButton
@onready var _scrub_bar: HSlider = %ScrubBar
@onready var _track_list: VBoxContainer = %TrackList
@onready var _add_track_button: Button = %AddTrackButton
@onready var _enter_scene_button: Button = %EnterSceneButton

var _is_playing: bool = false

func _ready() -> void:
	if not has_node("/root/TimelineData"):
		push_warning("TimelineUI: TimelineData autoload not found — check project.godot [autoload]")
		return
	var td = get_node("/root/TimelineData")
	td.track_added.connect(_on_track_added)
	td.track_removed.connect(_on_track_removed)
	_add_track_button.pressed.connect(_on_add_track_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_scrub_bar.value_changed.connect(_on_scrub_changed)
	_enter_scene_button.pressed.connect(func(): enter_scene_requested.emit())

func _on_add_track_pressed() -> void:
	var td = get_node("/root/TimelineData")
	# Each new track gets its own depth slot so tracks don't stack at the
	# same z and z-fight once instanced in the 3D stage — real depth
	# authoring (drag-to-reorder-in-depth) is future UI work, this just
	# guarantees every track starts visually distinct.
	var next_depth := td.tracks.size() * 0.05
	td.add_track("video", next_depth)

func _on_track_added(track) -> void:
	var row := _build_track_row(track)
	_track_list.add_child(row)

func _on_track_removed(track_id: int) -> void:
	for child in _track_list.get_children():
		if child.get_meta("track_id", -1) == track_id:
			child.queue_free()

func _build_track_row(track) -> Control:
	var container := VBoxContainer.new()
	container.set_meta("track_id", track.id)

	var header := HBoxContainer.new()
	container.add_child(header)

	var label := Label.new()
	label.text = "%s track #%d" % [track.kind.capitalize(), track.id]
	header.add_child(label)

	var add_clip_btn := Button.new()
	add_clip_btn.text = "Add Test Clip"
	add_clip_btn.tooltip_text = "Placeholder clip for layout/interaction testing until media import (Module B) lands"
	add_clip_btn.pressed.connect(func(): _add_test_clip(track.id))
	header.add_child(add_clip_btn)

	var split_btn := Button.new()
	split_btn.text = "Split"
	split_btn.tooltip_text = "Split the clip under the playhead into two clips"
	split_btn.pressed.connect(func(): _split_at_playhead(track.id))
	header.add_child(split_btn)

	var ripple_delete_btn := Button.new()
	ripple_delete_btn.text = "Ripple Delete"
	ripple_delete_btn.tooltip_text = "Remove the clip under the playhead and shift later clips left"
	ripple_delete_btn.pressed.connect(func(): _ripple_delete_at_playhead(track.id))
	header.add_child(ripple_delete_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove Track"
	remove_btn.pressed.connect(func():
		get_node("/root/TimelineData").remove_track(track.id)
	)
	header.add_child(remove_btn)

	var strip := TimelineTrackStrip.new()
	strip.track_id = track.id
	container.add_child(strip)

	# Drag-to-trim (in/out) and drag-to-reposition are handled inside
	# TimelineTrackStrip; nothing left here for Module A's "Phase 1
	# remainder" TODO beyond media import actually producing real clips
	# instead of the placeholder below.
	return container

## Placeholder clip generator so the draggable strip has something to
## interact with before Module B media import exists. Real "Add Clip"
## should open a media picker and call TimelineData.add_clip with an
## actual source path/in/out — this is scoped explicitly to UI/interaction
## testing, not a stand-in for that feature.
func _add_test_clip(track_id: int) -> void:
	var td = get_node("/root/TimelineData")
	var existing_end := 0.0
	if td.tracks.has(track_id):
		for clip in td.tracks[track_id].clips:
			existing_end = max(existing_end, clip.start_time + clip.duration())
	td.add_clip(track_id, "res://test_media/placeholder.ogv", 0.0, 3.0, existing_end)

func _split_at_playhead(track_id: int) -> void:
	var td = get_node("/root/TimelineData")
	var clip = td.find_clip_at(track_id)
	if clip == null:
		push_warning("TimelineUI: no clip under playhead on track %d to split" % track_id)
		return
	td.split_clip(track_id, clip.id, td.playhead_seconds)

func _ripple_delete_at_playhead(track_id: int) -> void:
	var td = get_node("/root/TimelineData")
	var clip = td.find_clip_at(track_id)
	if clip == null:
		push_warning("TimelineUI: no clip under playhead on track %d to remove" % track_id)
		return
	td.remove_clip(track_id, clip.id, true)

func _on_play_pressed() -> void:
	_is_playing = not _is_playing
	_play_button.text = "Pause" if _is_playing else "Play"

func _on_scrub_changed(value: float) -> void:
	get_node("/root/TimelineData").set_playhead(value)
	# video_track_mesh instances and audio playback should subscribe to
	# TimelineData.playhead_changed to seek/resume decode (Module B frame
	# cache) — that consumer side doesn't exist until Module B's route is
	# implemented past the Phase 0 stress-test stub, so it's a listener
	# this signal is ready for, not a gap in this file.

func _process(delta: float) -> void:
	if _is_playing:
		var td = get_node("/root/TimelineData")
		td.set_playhead(td.playhead_seconds + delta)
		_scrub_bar.value = td.playhead_seconds
