extends Node3D
class_name TextLayer
## Module G: "Kinetic text presets and text-on-path reuse the Module D
## extrusion pipeline." That pipeline (runtime_modeler.gd) doesn't exist
## until Phase 2, so Phase 1 uses Godot's built-in Label3D as a flat-mode
## stand-in — same track/keyframe integration, swappable renderer later.

@export var text: String = "":
	set(value):
		text = value
		if _label:
			_label.text = value

@export var font_size: int = 48:
	set(value):
		font_size = value
		if _label:
			_label.font_size = value

@export var color: Color = Color.WHITE:
	set(value):
		color = value
		if _label:
			_label.modulate = value

var _keyframes := LayerKeyframes.new() # Module G integration, see layer_keyframes.gd
var _label: Label3D

func _ready() -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = font_size
	_label.modulate = color
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Disabled billboard: in EDIT/orthographic mode text should sit flat in
	# the stack like any other track, not face the camera — that behavior
	# only makes sense once ROAM mode (Phase 2) is in play.
	add_child(_label)
	# Picked up automatically by PlayheadKeyframeDriver — see
	# scripts/keyframe/playhead_keyframe_driver.gd.
	add_to_group("keyframed_layers")

func add_keyframe_track(property_name: String) -> KeyframeTrack:
	return _keyframes.add_track(property_name)

func apply_at_time(time: float) -> void:
	# text/font_size/color are real @export properties with their own
	# setters above, so the default target.set() path in LayerKeyframes
	# handles all of them — no per-property Callable needed here, unlike
	# LightingRig.
	_keyframes.apply_at_time(self, time)

## TODO Phase 2: swap _label for a SurfaceTool-generated extruded mesh via
## runtime_modeler.gd once that pipeline lands, so text can sit in real 3D
## depth and catch lighting/shadows like any other scene geometry.
