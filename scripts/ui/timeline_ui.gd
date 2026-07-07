extends Control
## Module I: this is the "Timeline/Trim UI" surface — 2D, familiar,
## CapCut-like. Never mixes 3D roam controls into this scene (Phase 2
## keeps those on a separate "Scene/Roam UI" entered explicitly).
##
## Phase 1 scope: play/pause, scrub, add/remove track, trim in/out,
## split, ripple-delete, drag-reorder. All of it mutates TimelineData,
## never touches TimelineStage nodes directly (Module A single-source-
## of-truth rule).

@onready var _play_button: Button = %PlayButton
@onready var _scrub_bar: HSlider = %ScrubBar
@onready var _track_list: VBoxContainer = %TrackList
@onready var _add_track_button: Button = %AddTrackButton

var _is_playing: bool = false
var _playhead_seconds: float = 0.0

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

func _on_add_track_pressed() -> void:
	var td = get_node("/root/TimelineData")
	td.add_track("video")

func _on_track_added(track) -> void:
	var row := _build_track_row(track)
	_track_list.add_child(row)

func _on_track_removed(track_id: int) -> void:
	for child in _track_list.get_children():
		if child.get_meta("track_id", -1) == track_id:
			child.queue_free()

func _build_track_row(track) -> Control:
	var row := HBoxContainer.new()
	row.set_meta("track_id", track.id)

	var label := Label.new()
	label.text = "%s track #%d" % [track.kind.capitalize(), track.id]
	row.add_child(label)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func():
		get_node("/root/TimelineData").remove_track(track.id)
	)
	row.add_child(remove_btn)

	# TODO Phase 1 remainder: trim handles (drag in/out), split-at-playhead,
	# ripple-delete, drag-reorder. Snap thresholds must be computed in
	# timeline-seconds, not pixels, per Module A — convert using the
	# scrub bar's seconds-per-pixel ratio, not raw drag deltas.
	return row

func _on_play_pressed() -> void:
	_is_playing = not _is_playing
	_play_button.text = "Pause" if _is_playing else "Play"

func _on_scrub_changed(value: float) -> void:
	_playhead_seconds = value
	# TODO: broadcast playhead position so video_track_mesh instances seek/
	# resume decode at the right frame (ties into Module B frame cache).

func _process(delta: float) -> void:
	if _is_playing:
		_playhead_seconds += delta
		_scrub_bar.value = _playhead_seconds
