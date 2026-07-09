extends Node3D
class_name LightingRig
## Module D: key/fill/rim lighting presets as draggable Light3D nodes users
## can place, color, and animate on the timeline like any other layer.
## Each light is a real scene node — it casts real shadows on video quads
## and modeled geometry alike via the standard Godot renderer, no faked
## "lighting effect" shader trickery.

enum Preset { KEY, FILL, RIM, CUSTOM }

@export var preset: Preset = Preset.KEY:
	set(value):
		preset = value
		_apply_preset_defaults()

var light: Light3D
var _keyframes := LayerKeyframes.new() # Module G integration, see layer_keyframes.gd

const PRESET_DEFAULTS := {
	Preset.KEY: {"energy": 1.2, "color": Color(1.0, 0.96, 0.9), "angle_deg": 45.0},
	Preset.FILL: {"energy": 0.5, "color": Color(0.85, 0.9, 1.0), "angle_deg": -45.0},
	Preset.RIM: {"energy": 0.9, "color": Color(1.0, 1.0, 1.0), "angle_deg": 160.0},
}

func _ready() -> void:
	if not light:
		light = SpotLight3D.new()
		light.shadow_enabled = true
		add_child(light)
	_apply_preset_defaults()
	# Picked up automatically by PlayheadKeyframeDriver — see
	# scripts/keyframe/playhead_keyframe_driver.gd.
	add_to_group("keyframed_layers")

func _apply_preset_defaults() -> void:
	if not light or preset == Preset.CUSTOM:
		return
	var d: Dictionary = PRESET_DEFAULTS.get(preset, {})
	if d.is_empty():
		return
	light.light_energy = d.get("energy", 1.0)
	light.light_color = d.get("color", Color.WHITE)
	rotation_degrees.y = d.get("angle_deg", 0.0)

func set_color(c: Color) -> void:
	if light:
		light.light_color = c

func set_energy(e: float) -> void:
	if light:
		light.light_energy = e

func add_keyframe_track(property_name: String) -> KeyframeTrack:
	return _keyframes.add_track(property_name)

func apply_at_time(time: float) -> void:
	# "energy"/"color" aren't real properties on LightingRig itself (they
	# only exist on the child Light3D via these setter methods), so they
	# need an explicit Callable — everything else falls through to
	# target.set() inside LayerKeyframes.
	_keyframes.apply_at_time(self, time, {
		"energy": set_energy,
		"color": set_color,
	})

## Factory helper for the "enter scene" environment UI (Module I) to spawn
## a full key+fill+rim rig in one call, rather than three manual adds.
static func build_default_rig(parent: Node3D) -> Array:
	var rigs: Array = []
	for preset_val in [Preset.KEY, Preset.FILL, Preset.RIM]:
		var rig := LightingRig.new()
		rig.preset = preset_val
		parent.add_child(rig)
		rigs.append(rig)
	return rigs
