extends Node
class_name AudioMixer
## Module F: per-track volume envelope (keyframed, not a single fader),
## fade in/out per clip, audio detach from video.

class VolumeKey:
	var time: float
	var value: float # 0.0 - 1.0

class TrackAudioState:
	var track_id: int = -1
	var bus_name: String = ""
	var keys: Array = [] # Array[VolumeKey], sorted by time
	var fade_in: float = 0.0
	var fade_out: float = 0.0
	var detached: bool = false # true once audio is split from its video clip

var _states: Dictionary = {} # track_id -> TrackAudioState

func register_track(track_id: int, bus_name: String = "Master") -> TrackAudioState:
	var s := TrackAudioState.new()
	s.track_id = track_id
	s.bus_name = bus_name
	_states[track_id] = s
	return s

func add_volume_key(track_id: int, time: float, value: float) -> void:
	if not _states.has(track_id):
		return
	var s: TrackAudioState = _states[track_id]
	var k := VolumeKey.new()
	k.time = time
	k.value = clampf(value, 0.0, 1.0)
	s.keys.append(k)
	s.keys.sort_custom(func(a, b): return a.time < b.time)

func evaluate_volume(track_id: int, time: float) -> float:
	## Linear-interpolates between surrounding keys; applies fade in/out
	## envelopes on top. Returns a 0.0-1.0 gain multiplier.
	if not _states.has(track_id):
		return 1.0
	var s: TrackAudioState = _states[track_id]
	var base := _interp_keys(s.keys, time)

	if s.fade_in > 0.0 and time < s.fade_in:
		base *= time / s.fade_in
	if s.fade_out > 0.0:
		# TODO: needs clip duration to compute fade-out window correctly;
		# wire this up once TimelineData.Clip exposes track duration.
		pass

	return base

func _interp_keys(keys: Array, time: float) -> float:
	if keys.is_empty():
		return 1.0
	if time <= keys[0].time:
		return keys[0].value
	if time >= keys[-1].time:
		return keys[-1].value
	for i in range(keys.size() - 1):
		var a: VolumeKey = keys[i]
		var b: VolumeKey = keys[i + 1]
		if time >= a.time and time <= b.time:
			var t := (time - a.time) / (b.time - a.time) if b.time > a.time else 0.0
			return lerpf(a.value, b.value, t)
	return 1.0

func detach_audio(track_id: int) -> void:
	if _states.has(track_id):
		_states[track_id].detached = true
	# TODO: split into a new audio-only Track in TimelineData, positioned
	# identically to the source clip, per Module F "audio detach from video".
