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
	## Duration (timeline-seconds) of the audio this state governs. Needed
	## to compute the fade_out window (fades are anchored to the *end* of
	## playback, so without a known end point there's nothing to fade
	## against). Callers should keep this in sync via set_duration()
	## whenever the underlying clip is trimmed/split (Module A operations).
	var duration: float = 0.0
	var detached: bool = false # true once audio is split from its video clip

var _states: Dictionary = {} # track_id -> TrackAudioState

func register_track(track_id: int, bus_name: String = "Master", duration: float = 0.0) -> TrackAudioState:
	var s := TrackAudioState.new()
	s.track_id = track_id
	s.bus_name = bus_name
	s.duration = duration
	_states[track_id] = s
	return s

## Call after any TimelineData trim/split operation changes this track's
## effective duration, so fade_out keeps anchoring to the real end point.
func set_duration(track_id: int, duration: float) -> void:
	if _states.has(track_id):
		_states[track_id].duration = duration

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
	var gain := _interp_keys(s.keys, time)

	if s.fade_in > 0.0 and time < s.fade_in:
		gain *= clampf(time / s.fade_in, 0.0, 1.0)

	if s.fade_out > 0.0 and s.duration > 0.0:
		var fade_start := s.duration - s.fade_out
		if time > fade_start:
			var t := (s.duration - time) / s.fade_out
			gain *= clampf(t, 0.0, 1.0)

	return gain

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

## Splits this track's audio into an independent audio-only Track in
## TimelineData, positioned identically to the source clip (Module F
## "audio detach from video"). Requires the TimelineData autoload; no-op
## with a warning if it isn't present (keeps this class testable without
## the full autoload graph spun up).
func detach_audio(track_id: int, clip_id: int) -> void:
	if not _states.has(track_id):
		return
	if not has_node("/root/TimelineData"):
		push_warning("AudioMixer.detach_audio: TimelineData autoload not found")
		return
	var td = get_node("/root/TimelineData")
	var source_track = td.tracks.get(track_id)
	if source_track == null:
		return
	var clip = source_track.find_clip(clip_id)
	if clip == null:
		return

	var audio_track = td.add_track("audio", source_track.z_depth)
	td.add_clip(audio_track.id, clip.path, clip.in_point, clip.out_point, clip.start_time)

	_states[track_id].detached = true
	register_track(audio_track.id, _states[track_id].bus_name, clip.duration())
