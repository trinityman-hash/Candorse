extends Node3D
## PHASE 0 TEST HARNESS — run this before building anything else.
##
## Measures the actual pipeline the app will use in production: each
## VideoStreamPlayer decodes off-screen, and every frame we pull its
## texture and push it into a VideoTrackMesh's shader material — the same
## call path video_track_mesh.gd uses at runtime. This is deliberately NOT
## just timing VideoStreamPlayer's own draw: that would only prove Theora
## decode is fast, not that decode -> GPU texture upload onto N overlapping
## 3D quads holds 60fps (the actual risk called out in the brief, Module B
## / §3 correction table: "the real bottleneck is video decode -> GPU
## texture upload per frame per visible track").
##
## Usage: attach to a Node3D root. Add 3+ VideoStreamPlayer children
## (kept off-screen / not added to a Control tree — they're used purely as
## decoders here, see _ready()). Point each `stream` at a res://test_media/
## *.ogv file. This script builds one VideoTrackMesh per player at
## increasing z_depth and drives it from the corresponding player.

## VideoTrackMesh is a global class_name (scripts/tracks/video_track_mesh.gd)
## so it's referenced directly below — no preload needed.

@export var video_players: Array[VideoStreamPlayer] = []
@export var log_interval_frames: int = 60
## If true, a worst_frame_ms above this many ms counts as a stall in the
## summary line (33ms ~= one dropped frame at 30fps display, 16.6ms at 60fps).
@export var stall_threshold_ms: float = 33.0

var _track_meshes: Array[VideoTrackMesh] = []

var _frame_times: Array[float] = []
var _upload_times: Array[float] = []
var _stall_count: int = 0
var _frame_count: int = 0
var _last_time_usec: int = 0

func _ready() -> void:
	if video_players.is_empty():
		push_error("[Phase0] No video_players assigned — see docs/HOW_TO_RUN_PHASE0.md step 4.")
		return

	for i in video_players.size():
		var vp := video_players[i]
		# VideoStreamPlayer is a Control; we never add it to the scene tree's
		# visible UI. It runs purely as a decoder and we harvest its texture
		# each frame — this is what proves whether route (2) even works
		# headless, which matters because in production the SubViewport/
		# quad is the only thing ever shown, never the player itself.
		vp.expand = true
		vp.visible = false

		var mesh := VideoTrackMesh.new()
		mesh.track_id = i
		mesh.curvable = false # background-track default per §3 correction
		mesh.position = Vector3(0, 0, -0.01 * i) # increasing depth, mirrors track z_depth
		add_child(mesh)
		_track_meshes.append(mesh)

		vp.play()

	_last_time_usec = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	if _track_meshes.is_empty():
		return

	var frame_start := Time.get_ticks_usec()

	# The actual measured operation: pull each decoded frame and push it
	# through the same update_frame_texture() path video_track_mesh.gd
	# exposes for runtime use. This is the GPU upload cost Module B warns
	# about, multiplied by track count.
	var upload_start := Time.get_ticks_usec()
	for i in _track_meshes.size():
		var vp := video_players[i]
		if not vp.is_playing():
			continue
		var tex := vp.get_video_texture()
		if tex:
			_track_meshes[i].update_frame_texture(tex)
	var upload_end := Time.get_ticks_usec()

	var now := frame_start
	var dt := (now - _last_time_usec) / 1000.0 # ms, full frame-to-frame
	_last_time_usec = now
	_frame_times.append(dt)
	_upload_times.append((upload_end - upload_start) / 1000.0)
	if dt > stall_threshold_ms:
		_stall_count += 1
	_frame_count += 1

	if _frame_count % log_interval_frames == 0:
		_report()

func _report() -> void:
	if _frame_times.is_empty():
		return
	var total := 0.0
	var worst := 0.0
	for t in _frame_times:
		total += t
		worst = max(worst, t)
	var avg := total / _frame_times.size()
	var avg_fps := 1000.0 / avg if avg > 0 else 0.0

	var upload_total := 0.0
	for t in _upload_times:
		upload_total += t
	var avg_upload := upload_total / _upload_times.size()

	print("[Phase0] tracks=%d avg_frame_ms=%.2f avg_fps=%.1f worst_frame_ms=%.2f avg_upload_ms=%.2f stalls=%d"
		% [_track_meshes.size(), avg, avg_fps, worst, avg_upload, _stall_count])
	_frame_times.clear()
	_upload_times.clear()

## Interpretation guide (per brief §4 Module B):
## - avg_fps consistently >= 58 AND avg_upload_ms is a small fraction of the
##   ~16.6ms frame budget, with 3 overlapping tracks: route (2) is viable
##   for v1, proceed to Phase 1.
## - avg_upload_ms alone eating most of the frame budget, even if avg_fps
##   looks OK on desktop: still a red flag — desktop GPU upload bandwidth
##   is not representative of mobile, this is exactly what needs on-device
##   validation (see docs/HOW_TO_RUN_PHASE0.md §6).
## - Frequent stalls or avg_fps well under 60: route (2) is not enough on
##   this hardware tier, evaluate route (1) GDExtension bridge before
##   building UI on top of an unstable foundation.
