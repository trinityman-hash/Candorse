extends RefCounted
class_name KeyframeTrack
## Module G: "build this once, generically, not per-layer-type." Any
## property on any layer (video, text, 3D object, light) subscribes to
## an instance of this rather than each layer type rolling its own
## interpolation logic.

enum Property { POSITION, SCALE, ROTATION, OPACITY, CUSTOM }
enum Easing { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT, STEP }

class Key:
	var time: float = 0.0
	var value = null # Variant: float, Vector3, Color component, etc.
	var easing: int = Easing.LINEAR

var property: int = Property.POSITION
var custom_property_name: String = "" # used when property == CUSTOM
var keys: Array = [] # Array[Key], kept sorted by time

func add_key(time: float, value, easing: int = Easing.LINEAR) -> void:
	var k := Key.new()
	k.time = time
	k.value = value
	k.easing = easing
	keys.append(k)
	keys.sort_custom(func(a, b): return a.time < b.time)

func remove_key_at(time: float, tolerance: float = 0.001) -> void:
	for i in range(keys.size() - 1, -1, -1):
		if absf(keys[i].time - time) <= tolerance:
			keys.remove_at(i)

func evaluate(time: float):
	if keys.is_empty():
		return null
	if time <= keys[0].time:
		return keys[0].value
	if time >= keys[-1].time:
		return keys[-1].value
	for i in range(keys.size() - 1):
		var a: Key = keys[i]
		var b: Key = keys[i + 1]
		if time >= a.time and time <= b.time:
			var t := (time - a.time) / (b.time - a.time) if b.time > a.time else 0.0
			t = _apply_easing(t, a.easing)
			return _lerp_value(a.value, b.value, t)
	return keys[-1].value

func _apply_easing(t: float, easing: int) -> float:
	match easing:
		Easing.EASE_IN:
			return t * t
		Easing.EASE_OUT:
			return 1.0 - (1.0 - t) * (1.0 - t)
		Easing.EASE_IN_OUT:
			return t * t * (3.0 - 2.0 * t)
		Easing.STEP:
			return 0.0 if t < 1.0 else 1.0
		_:
			return t # LINEAR

func _lerp_value(a, b, t: float):
	# Handles the property types Module G needs to cover; extend match
	# arms as new layer types adopt this system, don't fork the class.
	if a is float or a is int:
		return lerpf(a, b, t)
	elif a is Vector3:
		return a.lerp(b, t)
	elif a is Vector2:
		return a.lerp(b, t)
	elif a is Color:
		return a.lerp(b, t)
	elif a is Quaternion:
		return a.slerp(b, t)
	else:
		return b if t >= 1.0 else a
