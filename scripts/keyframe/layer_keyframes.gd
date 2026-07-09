extends RefCounted
class_name LayerKeyframes
## Module G: the per-instance keyframe container every layer type
## (LightingRig, TextLayer, EnvironmentLayer, future layer types) should
## own ONE of, instead of each layer independently re-declaring its own
## `keyframes: Dictionary` + `add_keyframe_track()` + `apply_at_time()`
## trio — which is exactly what LightingRig and TextLayer had each done
## before this existed. KeyframeTrack itself already IS the generic
## per-property interpolator per its own docstring ("build this once,
## generically, not per-layer-type"); this class is the equally-generic
## piece one level up — owning a named set of those tracks and applying
## all of them to a target object at a given time. Any layer type wires
## this in with a couple of lines instead of duplicating the container.

var tracks: Dictionary = {} # property_name (String) -> KeyframeTrack

func add_track(property_name: String) -> KeyframeTrack:
	var kt := KeyframeTrack.new()
	kt.property = KeyframeTrack.Property.CUSTOM
	kt.custom_property_name = property_name
	tracks[property_name] = kt
	return kt

func remove_track(property_name: String) -> void:
	tracks.erase(property_name)

## Applies every track's value at `time` onto `target`. Most properties
## can go straight through target.set(property_name, value) (works for
## any @export var with a normal or custom setter, e.g. TextLayer's
## `text`/`font_size`/`color`). Some layer types expose the animatable
## quantity only via a plain method rather than a property (e.g.
## LightingRig's `energy`/`color` aren't actual properties on the rig
## itself) — pass a Callable per property name in `setters` for those.
func apply_at_time(target: Object, time: float, setters: Dictionary = {}) -> void:
	for property_name in tracks:
		var value = tracks[property_name].evaluate(time)
		if value == null:
			continue
		if setters.has(property_name):
			setters[property_name].call(value)
		else:
			target.set(property_name, value)
