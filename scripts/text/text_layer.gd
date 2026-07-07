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

var keyframes: Dictionary = {} # property name -> KeyframeTrack
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

func add_keyframe_track(property_name: String) -> KeyframeTrack:
	var kt := KeyframeTrack.new()
	kt.property = KeyframeTrack.Property.CUSTOM
	kt.custom_property_name = property_name
	keyframes[property_name] = kt
	return kt

func apply_at_time(time: float) -> void:
	for prop_name in keyframes:
		var value = keyframes[prop_name].evaluate(time)
		if value != null:
			set(prop_name, value)

## TODO Phase 2: swap _label for a SurfaceTool-generated extruded mesh via
## runtime_modeler.gd once that pipeline lands, so text can sit in real 3D
## depth and catch lighting/shadows like any other scene geometry.
