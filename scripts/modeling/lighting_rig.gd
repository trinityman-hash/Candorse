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
var keyframes: Dictionary = {} # property name -> KeyframeTrack (Module G integration)

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
	var kt := KeyframeTrack.new()
	kt.property = KeyframeTrack.Property.CUSTOM
	kt.custom_property_name = property_name
	keyframes[property_name] = kt
	return kt

func apply_at_time(time: float) -> void:
	for prop_name in keyframes:
		var value = keyframes[prop_name].evaluate(time)
		if value == null:
			continue
		match prop_name:
			"energy":
				set_energy(value)
			"color":
				set_color(value)
			_:
				set(prop_name, value)

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
