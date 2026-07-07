extends Node
## PHASE 0 TEST HARNESS — run this before building anything else.
##
## Loads N overlapping video clips onto VideoTrackMesh quads and logs
## frame times to see whether route (2) from Module B (FFmpeg/VideoStream
## decode off render thread -> ImageTexture.update()) holds 60fps on your
## target devices with a 3-track overlapping-clip stress test.
##
## Usage: attach to a scene with 3+ VideoStreamPlayer nodes pointed at
## res://test_media/*.ogv (Godot's native VideoStreamPlayer uses Theora
## by default; swap in a GDExtension-backed VideoStreamPlayback if you
## pick route (1) instead — see native/ios, native/android READMEs).

@export var video_players: Array[VideoStreamPlayer] = []
@export var log_interval_frames: int = 60

var _frame_times: Array[float] = []
var _frame_count: int = 0
var _last_time_usec: int = 0

func _ready() -> void:
	_last_time_usec = Time.get_ticks_usec()
	for vp in video_players:
		vp.play()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_time_usec) / 1000.0 # ms
	_last_time_usec = now
	_frame_times.append(dt)
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
	print("[Phase0] tracks=%d avg_frame_ms=%.2f avg_fps=%.1f worst_frame_ms=%.2f"
		% [video_players.size(), avg, avg_fps, worst])
	_frame_times.clear()

## Interpretation guide (per brief §4 Module B):
## - avg_fps consistently >= 58 with 3 overlapping tracks: route (2) is viable
##   for v1, proceed to Phase 1.
## - Frequent worst_frame_ms spikes (>33ms) or avg_fps well under 60: route (2)
##   is not enough on this hardware tier, evaluate route (1) GDExtension bridge
##   before building UI on top of an unstable foundation.
