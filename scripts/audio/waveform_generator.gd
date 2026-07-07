extends Node
class_name WaveformGenerator
## Module F: waveform generation for timeline display. Precompute once per
## import, cache the result — never regenerate per-frame or per-scroll.

const CACHE_DIR := "user://waveform_cache/"

var _memory_cache: Dictionary = {} # source_path -> PackedFloat32Array (peaks)

func get_waveform(source_path: String, samples_per_second: int = 20) -> PackedFloat32Array:
	if _memory_cache.has(source_path):
		return _memory_cache[source_path]

	var cache_path := _cache_path_for(source_path)
	if FileAccess.file_exists(cache_path):
		var peaks := _load_cached(cache_path)
		_memory_cache[source_path] = peaks
		return peaks

	var peaks := _generate_peaks(source_path, samples_per_second)
	_memory_cache[source_path] = peaks
	_save_cache(cache_path, peaks)
	return peaks

func _cache_path_for(source_path: String) -> String:
	var hash := source_path.md5_text()
	return CACHE_DIR + hash + ".waveform"

func _generate_peaks(source_path: String, samples_per_second: int) -> PackedFloat32Array:
	## TODO: real implementation decodes the audio track (reuse whichever
	## decode route Module B settles on) and computes min/max peak pairs
	## per time bucket. Placeholder returns a flat silence array so the UI
	## has something to render against while the real decode path lands.
	var peaks := PackedFloat32Array()
	var estimated_duration := 10.0 # TODO: read actual duration from source
	var bucket_count := int(estimated_duration * samples_per_second)
	for i in range(bucket_count):
		peaks.append(0.0)
	return peaks

func _save_cache(path: String, peaks: PackedFloat32Array) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_var(peaks)

func _load_cached(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		return f.get_var()
	return PackedFloat32Array()

func invalidate(source_path: String) -> void:
	_memory_cache.erase(source_path)
	var path := _cache_path_for(source_path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
