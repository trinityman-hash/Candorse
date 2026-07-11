extends VBoxContainer
class_name SceneObjectPanel
## Module D / Module I: transform + basic property controls for a single
## scene object placed in Roam mode (a LightingRig, an EnvironmentLayer
## fog node, or a runtime-modeled primitive MeshInstance3D).
##
## Deliberately slider-based, same reasoning as ColorGradePanel: a real
## on-screen 3D drag gizmo (translate/rotate/scale arrows/rings hit-
## tested against the mouse/touch ray) is a substantial separate piece
## of viewport-interaction code and is NOT built here — tracked as open
## in docs/ENVIRONMENT_STATUS.md, not silently skipped. What IS real:
## every object placed in the scene can be selected from the object
## list in scene_roam_ui.gd and repositioned/rotated/scaled with exact
## numeric control — strictly more precise than a drag gizmo, if less
## immediate to grab.
##
## No undo/redo yet for object transforms. Scene objects (lights, fog,
## primitives) aren't part of TimelineData's Track model the way video/
## text/audio layers are, so there's no command stack for them to plug
## into without a larger Module D/A integration pass (also tracked in
## docs/ENVIRONMENT_STATUS.md — this includes persistence: nothing
## about a placed object's transform survives a project reload yet
## either). "Reset transform" is the interim undo for this session only.

const _AXIS_NAMES := ["X", "Y", "Z"]

var target: Node3D
var _sliders: Dictionary = {} # "<property>_<axis>" -> HSlider
var _base_transform: Transform3D

signal closed()

func build_for_object(node: Node3D, display_name: String) -> void:
	target = node
	_base_transform = node.transform

	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = display_name
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	_add_header("Position")
	_add_axis_row("Position", "position", -20.0, 20.0)
	_add_header("Rotation (deg)")
	_add_axis_row("Rotation", "rotation_degrees", -180.0, 180.0)
	_add_header("Scale")
	_add_axis_row("Scale", "scale", 0.05, 5.0)

	if target is LightingRig:
		_add_header("Light")
		_add_light_rows(target as LightingRig)

	var button_row := HBoxContainer.new()
	add_child(button_row)
	var reset_btn := Button.new()
	reset_btn.text = "Reset transform"
	reset_btn.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_btn)
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_remove_pressed)
	button_row.add_child(remove_btn)
	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(_on_close_pressed)
	button_row.add_child(close_btn)

func _add_header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	add_child(l)

func _add_axis_row(label_prefix: String, property: String, min_v: float, max_v: float) -> void:
	for i in range(3):
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = "%s %s" % [label_prefix, _AXIS_NAMES[i]]
		label.custom_minimum_size.x = 90
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = min_v
		slider.max_value = max_v
		slider.step = 0.01
		slider.value = (target.get(property) as Vector3)[i]
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v): _on_axis_changed(property, i, v))
		row.add_child(slider)
		_sliders["%s_%d" % [property, i]] = slider

func _on_axis_changed(property: String, axis_i: int, v: float) -> void:
	if not is_instance_valid(target):
		return
	var vec: Vector3 = target.get(property)
	vec[axis_i] = v
	target.set(property, vec)

func _add_light_rows(rig: LightingRig) -> void:
	var energy_row := HBoxContainer.new()
	add_child(energy_row)
	var el := Label.new()
	el.text = "Energy"
	el.custom_minimum_size.x = 90
	energy_row.add_child(el)
	var energy_slider := HSlider.new()
	energy_slider.min_value = 0.0
	energy_slider.max_value = 4.0
	energy_slider.step = 0.01
	energy_slider.value = rig.light.light_energy if rig.light else 1.0
	energy_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	energy_slider.value_changed.connect(func(v): rig.set_energy(v))
	energy_row.add_child(energy_slider)

	var color_row := HBoxContainer.new()
	add_child(color_row)
	var cl := Label.new()
	cl.text = "Color"
	cl.custom_minimum_size.x = 90
	color_row.add_child(cl)
	var color_picker := ColorPickerButton.new()
	color_picker.color = rig.light.light_color if rig.light else Color.WHITE
	color_picker.custom_minimum_size = Vector2(60, 28)
	color_picker.color_changed.connect(func(c): rig.set_color(c))
	color_row.add_child(color_picker)

func _on_reset_pressed() -> void:
	if not is_instance_valid(target):
		return
	target.transform = _base_transform
	_refresh_sliders()

func _refresh_sliders() -> void:
	for key in _sliders.keys():
		var parts := key.rsplit("_", true, 1)
		var property: String = parts[0]
		var axis_i := int(parts[1])
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal((target.get(property) as Vector3)[axis_i])

func _on_remove_pressed() -> void:
	if is_instance_valid(target):
		target.queue_free() # triggers scene_roam_ui's tree_exiting cleanup
	closed.emit()
	queue_free()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
