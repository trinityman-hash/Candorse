extends Control
## Module I: this is the "Timeline/Trim UI" surface — 2D, familiar,
## CapCut-like. Never mixes 3D roam controls into this scene. The
## "Enter Scene" button below is the ONLY bridge to Phase 2's
## Scene/Roam UI — everything else stays flat here by design.
##
## Phase 1 scope: play/pause, scrub, add/remove track, import media,
## trim in/out, split, ripple-delete, drag-reorder, undo/redo, transitions.
## Module E addition: per-track color grading panel toggle.
## All of it mutates TimelineData, never touches TimelineStage nodes
## directly (Module A single-source-of-truth rule).

signal enter_scene_requested()

@onready var _play_button: Button = %PlayButton
@onready var _scrub_bar: HSlider = %ScrubBar
@onready var _track_list: VBoxContainer = %TrackList
@onready var _add_track_button: Button = %AddTrackButton
@onready var _enter_scene_button: Button = %EnterSceneButton
@onready var _undo_button: Button = %UndoButton
@onready var _redo_button: Button = %RedoButton

var _is_playing: bool = false
var _file_dialog: FileDialog
var _pending_import_track_id: int = -1

## Media import has no real duration probe until Module B's decode route
## lands — this is an explicit placeholder length, not a guess at real
## media duration. Trim handles let the user shorten it immediately;
## there's no way to know the true source length without decoding it.
const PLACEHOLDER_IMPORT_DURATION := 5.0
## Module E: default crossfade length applied by the "Add Transition"
## button. TimelineData.set_transition_duration() clamps this against
## actual available overlap, so this is a request, not a guarantee.
const DEFAULT_TRANSITION_DURATION := 0.5

func _ready() -> void:
	if not has_node("/root/TimelineData"):
		push_warning("TimelineUI: TimelineData autoload not found — check project.godot [autoload]")
		return
	var td = get_node("/root/TimelineData")
	td.track_added.connect(_on_track_added)
	td.track_removed.connect(_on_track_removed)
	td.history_changed.connect(_on_history_changed)
	_add_track_button.pressed.connect(_on_add_track_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_scrub_bar.value_changed.connect(_on_scrub_changed)
	_enter_scene_button.pressed.connect(func(): enter_scene_requested.emit())
	_undo_button.pressed.connect(func(): get_node("/root/TimelineData").undo())
	_redo_button.pressed.connect(func(): get_node("/root/TimelineData").redo())
	_on_history_changed() # sync initial disabled state

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_on_media_file_selected)
	add_child(_file_dialog)
	# NOTE (mobile-first, brief §1): Godot's FileDialog with
	# ACCESS_FILESYSTEM works reliably on desktop, which is what this is
	# being authored/tested against right now. Its behavior on exported
	# Android/iOS builds is genuinely uncertain — mobile OSes generally
	# require going through their own document picker (Storage Access
	# Framework on Android, UIDocumentPickerViewController on iOS) rather
	# than raw filesystem browsing, and Godot's mobile support for this
	# has changed across versions. Don't assume this works unmodified on
	# a real device; verify on the target export template and swap to a
	# native picker (likely another GDExtension bridge, similar in spirit
	# to Module B's decode bridge) if FileDialog doesn't behave.

func _on_history_changed() -> void:
	var td = get_node("/root/TimelineData")
	_undo_button.disabled = not td.can_undo()
	_redo_button.disabled = not td.can_redo()

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

	if track.kind == "text":
		# Text tracks have no file to import — the equivalent action is
		# typing content, per the interim "clip.path holds the literal
		# text string" mapping documented in track_stage_controller.gd.
		var text_input := LineEdit.new()
		text_input.placeholder_text = "Type text..."
		text_input.custom_minimum_size.x = 160
		header.add_child(text_input)

		var add_text_btn := Button.new()
		add_text_btn.text = "Add Text Clip"
		add_text_btn.pressed.connect(func(): _add_text_clip(track.id, text_input.text))
		header.add_child(add_text_btn)
	else:
		var import_btn := Button.new()
		import_btn.text = "Import Media"
		import_btn.pressed.connect(func(): _open_media_import(track.id, track.kind))
		header.add_child(import_btn)

	var split_btn := Button.new()
	split_btn.text = "Split"
	split_btn.tooltip_text = "Split the clip under the playhead into two clips"
	split_btn.pressed.connect(func(): _split_at_playhead(track.id))
	header.add_child(split_btn)

	var transition_btn := Button.new()
	transition_btn.text = "Add Transition"
	transition_btn.tooltip_text = "Crossfade the clip under the playhead in from the previous clip on this track"
	transition_btn.pressed.connect(func(): _add_transition_at_playhead(track.id))
	header.add_child(transition_btn)

	var ripple_delete_btn := Button.new()
	ripple_delete_btn.text = "Ripple Delete"
	ripple_delete_btn.tooltip_text = "Remove the clip under the playhead and shift later clips left"
	ripple_delete_btn.pressed.connect(func(): _ripple_delete_at_playhead(track.id))
	header.add_child(ripple_delete_btn)

	# Grading applies to a track's video_track_mesh material (Module E) —
	# audio has no mesh and text is font-to-mesh geometry with its own
	# material path, so the button only appears where it does something.
	if track.kind != "audio" and track.kind != "text":
		var grade_btn := Button.new()
		grade_btn.text = "Grade"
		grade_btn.tooltip_text = "Open color grading controls for this track"
		grade_btn.pressed.connect(func(): _toggle_grade_panel(container, track.id))
		header.add_child(grade_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove Track"
	remove_btn.pressed.connect(func():
		get_node("/root/TimelineData").remove_track(track.id)
	)
	header.add_child(remove_btn)

	var strip := TimelineTrackStrip.new()
	strip.track_id = track.id
	container.add_child(strip)

	return container

func _toggle_grade_panel(container: VBoxContainer, track_id: int) -> void:
	for child in container.get_children():
		if child is ColorGradePanel:
			# Closing via re-clicking Grade should still commit the session
			# the same way the panel's own "Done" button does — there's
			# only one exit path, not two divergent ones.
			get_node("/root/TimelineData").commit_color_grade_edit(track_id)
			child.queue_free()
			return
	var panel := ColorGradePanel.new()
	container.add_child(panel)
	panel.build_for_track(track_id)

func _open_media_import(track_id: int, kind: String) -> void:
	_pending_import_track_id = track_id
	match kind:
		"audio":
			_file_dialog.filters = PackedStringArray(["*.ogg, *.wav ; Audio Files"])
		"overlay", "sticker":
			_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.svg ; Image Files"])
		_: # video
			_file_dialog.filters = PackedStringArray(["*.ogv, *.mp4, *.webm ; Video Files"])
	_file_dialog.popup_centered_ratio(0.8)

func _on_media_file_selected(path: String) -> void:
	if _pending_import_track_id == -1:
		return
	_append_clip(_pending_import_track_id, path, PLACEHOLDER_IMPORT_DURATION)
	_pending_import_track_id = -1

func _add_text_clip(track_id: int, text: String) -> void:
	if text.strip_edges() == "":
		push_warning("TimelineUI: empty text, not adding a clip")
		return
	_append_clip(track_id, text, PLACEHOLDER_IMPORT_DURATION)

## Shared "append after the last existing clip on this track" logic used
## by both media import and text-clip creation.
func _append_clip(track_id: int, path_or_text: String, duration: float) -> void:
	var td = get_node("/root/TimelineData")
	var existing_end := 0.0
	if td.tracks.has(track_id):
		for clip in td.tracks[track_id].clips:
			existing_end = max(existing_end, clip.start_time + clip.duration())
	td.add_clip(track_id, path_or_text, 0.0, duration, existing_end)

func _split_at_playhead(track_id: int) -> void:
	var td = get_node("/root/TimelineData")
	var clip = td.find_clip_at(track_id)
	if clip == null:
		push_warning("TimelineUI: no clip under playhead on track %d to split" % track_id)
		return
	td.split_clip(track_id, clip.id, td.playhead_seconds)

func _add_transition_at_playhead(track_id: int) -> void:
	var td = get_node("/root/TimelineData")
	var clip = td.find_clip_at(track_id)
	if clip == null:
		push_warning("TimelineUI: no clip under playhead on track %d to add a transition to" % track_id)
		return
	var track = td.tracks[track_id]
	if track.find_previous_clip(clip.id) == null:
		push_warning("TimelineUI: clip under playhead has no previous clip on track %d — nothing to crossfade from" % track_id)
		return
	td.set_transition_duration(track_id, clip.id, DEFAULT_TRANSITION_DURATION)

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
