extends Node
class_name ExportManager
## Module H. Render-to-texture the timeline SubViewport at target
## resolution/fps, feed frames to the same native encode path chosen in
## Module B (symmetry: whatever decodes in should encode out).

signal export_progress(fraction: float)
signal export_finished(output_path: String)
signal export_failed(reason: String)

enum Resolution { R480P, R720P, R1080P, R4K }
enum Codec { H264, H265 }

const RESOLUTIONS := {
	Resolution.R480P: Vector2i(854, 480),
	Resolution.R720P: Vector2i(1280, 720),
	Resolution.R1080P: Vector2i(1920, 1080),
	Resolution.R4K: Vector2i(3840, 2160),
}

@export var resolution: int = Resolution.R1080P
@export var fps: int = 30
@export var codec: int = Codec.H264
@export var output_path: String = "user://export.mp4"

var _is_exporting: bool = false
var _stage_viewport: SubViewport
var _total_frames: int = 0
var _current_frame: int = 0

func start_export(stage_viewport: SubViewport, duration_seconds: float) -> void:
	if _is_exporting:
		push_warning("ExportManager: export already in progress")
		return
	_stage_viewport = stage_viewport
	_total_frames = int(duration_seconds * fps)
	_current_frame = 0
	_is_exporting = true

	var target_size: Vector2i = RESOLUTIONS[resolution]
	_stage_viewport.size = target_size
	_stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Background thread so we don't block the UI thread (Module H
	# requirement). Godot 4 WorkerThreadPool covers the "don't block UI"
	# goal without needing a raw Thread here.
	WorkerThreadPool.add_task(_run_export_loop)

func _run_export_loop() -> void:
	# TODO: this must call into whichever native encode path Module B's
	# decode route implies (AVFoundation/MediaCodec encoder for route 1,
	# an FFmpeg encode invocation for route 2) — feeding it a frame grabbed
	# from _stage_viewport.get_texture().get_image() each tick, at `fps`
	# cadence. Left as a stub until Module B's route decision is locked in,
	# since this pipeline is the encode-side mirror of that choice.
	for i in range(_total_frames):
		if not _is_exporting:
			break
		_current_frame = i
		call_deferred("_emit_progress", float(i) / _total_frames)
		# Placeholder: real loop would await the viewport's next frame,
		# grab get_texture().get_image(), and hand it to the encoder here.
	call_deferred("_finish_export")

func _emit_progress(fraction: float) -> void:
	export_progress.emit(fraction)

func _finish_export() -> void:
	_is_exporting = false
	export_finished.emit(output_path)

func cancel_export() -> void:
	_is_exporting = false

## Direct share intents (Module H) are platform-specific — wire these via
## a small GDExtension or OS.shell_open once export produces a real file;
## no-op stub until then.
func share_output() -> void:
	if FileAccess.file_exists(output_path):
		OS.shell_show_in_file_manager(output_path)
