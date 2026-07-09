extends Node
class_name WaveformGenerator
## Module F: waveform generation for timeline display. Precompute once per
## import, cache the result on disk — never regenerate per-frame or
## per-scroll. Consumers call request_waveform() (async, safe to call
## every frame — it's a no-op once cached or already in flight) and
## listen for waveform_ready, or call get_cached() for a non-blocking
## peek at whatever's already available.
##
## Generation strategy:
## - AudioStreamWAV, FORMAT_8_BITS/FORMAT_16_BITS (uncompressed PCM):
##   decoded directly from stream.data — synchronous, exact, no playback
##   required.
## - Everything else (OggVorbis, MP3, IMA-ADPCM WAV): Godot's script API
##   does not expose decoded PCM for these formats. We route the stream
##   through a dedicated, muted AudioEffectCapture bus and capture real
##   decoded audio during one real-time playback pass. This costs
##   wall-clock time proportional to the clip's duration, but per the
##   caching contract above it only ever runs once per source file — the
##   result is disk-cached exactly like the WAV path. This is genuinely
##   decoded audio, never synthesized/placeholder data.

signal waveform_ready(source_path: String, peaks: PackedFloat32Array)

const CACHE_DIR := "user://waveform_cache/"
const CAPTURE_BUS_NAME := "WaveformCapture"

var _memory_cache: Dictionary = {} # source_path -> PackedFloat32Array
var _in_flight: Dictionary = {} # source_path -> true
var _queue: Array = [] # Array[Dictionary{path, sps}]
var _busy: bool = false

var _capture_bus_idx: int = -1
var _capture_effect: AudioEffectCapture
var _capture_player: AudioStreamPlayer

func _ready() -> void:
	_setup_capture_bus()

func _setup_capture_bus() -> void:
	_capture_bus_idx = AudioServer.get_bus_index(CAPTURE_BUS_NAME)
	if _capture_bus_idx == -1:
		_capture_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_capture_bus_idx)
		AudioServer.set_bus_name(_capture_bus_idx, CAPTURE_BUS_NAME)
	# Muting is the documented, reliable way to make a bus produce no
	# audible output; the effect chain (including AudioEffectCapture)
	## still processes normally while muted, so capture is unaffected.
	AudioServer.set_bus_mute(_capture_bus_idx, true)

	if AudioServer.get_bus_effect_count(_capture_bus_idx) == 0:
		_capture_effect = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_capture_bus_idx, _capture_effect)
	else:
		_capture_effect = AudioServer.get_bus_effect(_capture_bus_idx, 0)

	_capture_player = AudioStreamPlayer.new()
	_capture_player.bus = CAPTURE_BUS_NAME
	add_child(_capture_player)

## Non-blocking peek: returns cached peaks if available, else an empty
## array. Never triggers generation — pair with request_waveform().
func get_cached(source_path: String) -> PackedFloat32Array:
	return _memory_cache.get(source_path, PackedFloat32Array())

## Kicks off generation if not already cached or in flight. Safe to call
## on every _draw — duplicate requests for the same path are no-ops.
## Emits waveform_ready when the result is available (immediately, via
## a deferred call, if it was already cached or disk-cached).
func request_waveform(source_path: String, samples_per_second: int = 20) -> void:
	if source_path == "":
		return
	if _memory_cache.has(source_path):
		call_deferred("emit_signal", "waveform_ready", source_path, _memory_cache[source_path])
		return
	if _in_flight.has(source_path):
		return

	var cache_path := _cache_path_for(source_path)
	if FileAccess.file_exists(cache_path):
		var cached := _load_cached(cache_path)
		if not cached.is_empty():
			_memory_cache[source_path] = cached
			call_deferred("emit_signal", "waveform_ready", source_path, cached)
			return

	_in_flight[source_path] = true
	_queue.append({"path": source_path, "sps": samples_per_second})
	_process_queue()

func _process_queue() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var job: Dictionary = _queue.pop_front()
	var peaks: PackedFloat32Array = await _generate_peaks(job["path"], job["sps"])
	_memory_cache[job["path"]] = peaks
	_save_cache(_cache_path_for(job["path"]), peaks)
	_in_flight.erase(job["path"])
	waveform_ready.emit(job["path"], peaks)
	_busy = false
	_process_queue()

func _cache_path_for(source_path: String) -> String:
	return CACHE_DIR + source_path.md5_text() + ".waveform"

func _generate_peaks(source_path: String, samples_per_second: int) -> PackedFloat32Array:
	var stream: AudioStream = ResourceLoader.load(source_path)
	if stream == null:
		push_warning("WaveformGenerator: could not load '%s'" % source_path)
		return PackedFloat32Array()

	var duration := stream.get_length()
	if duration <= 0.0:
		push_warning("WaveformGenerator: '%s' reports zero/unknown length" % source_path)
		return PackedFloat32Array()

	var bucket_count := maxi(1, int(ceil(duration * samples_per_second)))

	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.format == AudioStreamWAV.FORMAT_8_BITS or wav.format == AudioStreamWAV.FORMAT_16_BITS:
			return _peaks_from_wav_pcm(wav, bucket_count)

	return await _peaks_from_realtime_capture(stream, bucket_count, samples_per_second)

## Exact path: uncompressed WAV exposes raw PCM via .data, so peak
## amplitude per bucket is computed directly from real sample bytes.
func _peaks_from_wav_pcm(stream: AudioStreamWAV, bucket_count: int) -> PackedFloat32Array:
	var peaks := PackedFloat32Array()
	peaks.resize(bucket_count)

	var data := stream.data
	var channels := 2 if stream.stereo else 1
	var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var frame_size := bytes_per_sample * channels
	if frame_size <= 0:
		return peaks
	var total_frames := data.size() / frame_size
	if total_frames <= 0:
		return peaks

	var frames_per_bucket := maxf(1.0, float(total_frames) / float(bucket_count))

	for bucket in range(bucket_count):
		var start_frame := int(floor(bucket * frames_per_bucket))
		var end_frame: int = mini(int(floor((bucket + 1) * frames_per_bucket)), total_frames)
		var peak := 0.0
		for frame in range(start_frame, end_frame):
			var base := frame * frame_size
			for ch in range(channels):
				var off := base + ch * bytes_per_sample
				var amp := 0.0
				if bytes_per_sample == 2:
					amp = absf(float(data.decode_s16(off)) / 32768.0)
				else:
					# WAV 8-bit PCM is unsigned with a 128 bias.
					amp = absf((float(data[off]) - 128.0) / 128.0)
				peak = maxf(peak, amp)
		peaks[bucket] = clampf(peak, 0.0, 1.0)
	return peaks

## Approximate-but-real path for compressed formats (OggVorbis, MP3) and
## IMA-ADPCM WAV, none of which expose decoded PCM through the script
## API. Plays the stream through the muted capture bus once in real time
## and buckets genuinely decoded peak amplitude by playback position.
func _peaks_from_realtime_capture(stream: AudioStream, bucket_count: int, samples_per_second: int) -> PackedFloat32Array:
	var peaks := PackedFloat32Array()
	peaks.resize(bucket_count)

	_capture_effect.clear_buffer()
	_capture_player.stream = stream
	_capture_player.play()

	while _capture_player.playing:
		await get_tree().process_frame
		var available := _capture_effect.get_frames_available()
		if available <= 0:
			continue
		var playback_time := _capture_player.get_playback_position()
		var chunk := _capture_effect.get_buffer(available)
		var peak := 0.0
		for frame in chunk:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		var bucket: int = clampi(int(playback_time * samples_per_second), 0, bucket_count - 1)
		peaks[bucket] = maxf(peaks[bucket], clampf(peak, 0.0, 1.0))

	_capture_effect.clear_buffer()
	_capture_player.stream = null
	return peaks

func _save_cache(path: String, peaks: PackedFloat32Array) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_var(peaks)

func _load_cached(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var v = f.get_var()
		if v is PackedFloat32Array:
			return v
	return PackedFloat32Array()

func invalidate(source_path: String) -> void:
	_memory_cache.erase(source_path)
	var path := _cache_path_for(source_path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
