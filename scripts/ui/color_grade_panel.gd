extends VBoxContainer
class_name ColorGradePanel
## Module E / Module I: slider-based UI for ColorGradeState (Lift/Gamma/
## Gain, brightness/contrast/saturation, vignette, LUT blend).
##
## Deliberately built as labeled sliders rather than a graphical circular
## color wheel — a real wheel needs a custom-drawn Control with puck hit
## testing and 2D hue/luma math, which is a separate, larger piece of UI
## work (tracked in docs/COLOR_ENGINE_STATUS.md, not silently skipped).
## Every parameter the shader exposes has a slider here; nothing is a
## reduced feature set, just a different input widget than a wheel.
##
## Editing model: dragging a slider mutates the track's ColorGradeState
## directly and calls TimelineData.notify_color_grade_changed() every
## tick for live preview — same "continuous input bypasses the undo
## stack" pattern TimelineData.set_playhead() uses. The whole grading
## session becomes exactly one undo/redo entry: begin_color_grade_edit()
## is called in build_for_track() (panel open), commit_color_grade_edit()
## in _on_close_pressed() (panel close/Done).

const _AXIS_NAMES := ["R", "G", "B"]

var track_id: int = -1
var _grade: ColorGradeState
var _sliders: Dictionary = {} # param name, or "param_<axis>" for Vector3 -> HSlider
var _lut_label: Label
var _lut_strength_slider: HSlider
var _file_dialog: FileDialog

signal closed()

func build_for_track(p_track_id: int) -> void:
	if not has_node("/root/TimelineData"):
		push_warning("ColorGradePanel: TimelineData autoload not found")
		return
	track_id = p_track_id
	var td = get_node("/root/TimelineData")
	_grade = td.get_or_create_color_grade(track_id)
	if _grade == null:
		push_warning("ColorGradePanel: unknown track_id %d" % track_id)
		return
	td.begin_color_grade_edit(track_id)

	add_theme_constant_override("separation", 4)

	_add_header("Lift / gamma / gain")
	_add_vector3_row("Lift", "lift", -1.0, 1.0)
	_add_vector3_row("Gamma", "gamma", 0.1, 4.0)
	_add_vector3_row("Gain", "gain", 0.0, 2.0)

	_add_header("Basic")
	_add_scalar_row("Brightness", "brightness", -1.0, 1.0)
	_add_scalar_row("Contrast", "contrast", 0.0, 4.0)
	_add_scalar_row("Saturation", "saturation", 0.0, 4.0)

	_add_header("Vignette")
	_add_scalar_row("Strength", "vignette_strength", 0.0, 1.0)
	_add_scalar_row("Radius", "vignette_radius", 0.0, 1.5)
	_add_scalar_row("Softness", "vignette_softness", 0.0, 1.0)

	_add_lut_section()

	var button_row := HBoxContainer.new()
	add_child(button_row)
	var reset_btn := Button.new()
	reset_btn.text = "Reset grade"
	reset_btn.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_btn)
	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(_on_close_pressed)
	button_row.add_child(close_btn)

func _add_header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	add_child(l)

func _add_vector3_row(label_text: String, param: String, min_v: float, max_v: float) -> void:
	for axis_i in range(3):
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = "%s %s" % [label_text, _AXIS_NAMES[axis_i]]
		label.custom_minimum_size.x = 90
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = min_v
		slider.max_value = max_v
		slider.step = 0.01
		slider.value = (_grade.get(param) as Vector3)[axis_i]
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v): _on_vector3_axis_changed(param, axis_i, v))
		row.add_child(slider)
		_sliders["%s_%d" % [param, axis_i]] = slider

func _add_scalar_row(label_text: String, param: String, min_v: float, max_v: float) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.01
	slider.value = _grade.get(param)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): _on_scalar_changed(param, v))
	row.add_child(slider)
	_sliders[param] = slider

func _add_lut_section() -> void:
	_add_header("LUT")
	var row := HBoxContainer.new()
	add_child(row)
	_lut_label = Label.new()
	_lut_label.text = _grade.lut_title() if _grade.has_lut() else "(none)"
	_lut_label.custom_minimum_size.x = 110
	_lut_label.clip_text = true
	row.add_child(_lut_label)
	var load_btn := Button.new()
	load_btn.text = "Load .cube"
	load_btn.pressed.connect(_on_load_lut_pressed)
	row.add_child(load_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_clear_lut_pressed)
	row.add_child(clear_btn)

	var strength_row := HBoxContainer.new()
	add_child(strength_row)
	var sl := Label.new()
	sl.text = "LUT mix"
	sl.custom_minimum_size.x = 90
	strength_row.add_child(sl)
	_lut_strength_slider = HSlider.new()
	_lut_strength_slider.min_value = 0.0
	_lut_strength_slider.max_value = 1.0
	_lut_strength_slider.step = 0.01
	_lut_strength_slider.value = _grade.lut_strength
	_lut_strength_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_lut_strength_slider.value_changed.connect(_on_lut_strength_changed)
	strength_row.add_child(_lut_strength_slider)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.cube ; 3D LUT files"])
	_file_dialog.file_selected.connect(_on_lut_file_selected)
	add_child(_file_dialog)

func _on_vector3_axis_changed(param: String, axis_i: int, v: float) -> void:
	var vec: Vector3 = _grade.get(param)
	vec[axis_i] = v
	_grade.set(param, vec)
	_notify_live()

func _on_scalar_changed(param: String, v: float) -> void:
	_grade.set(param, v)
	_notify_live()

func _on_lut_strength_changed(v: float) -> void:
	_grade.lut_strength = v
	_notify_live()

func _on_load_lut_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.8)

func _on_lut_file_selected(path: String) -> void:
	if _grade.load_lut(path):
		_lut_label.text = _grade.lut_title() if _grade.lut_title() != "" else path.get_file()
	else:
		# LutLoader already push_error()'d the specific reason (bad header,
		# wrong size, LUT_1D, etc) — this just surfaces that the load
		# overall failed without inventing a friendlier message that would
		# hide which of those it actually was.
		push_warning("ColorGradePanel: failed to load LUT '%s'" % path)
	_notify_live()

func _on_clear_lut_pressed() -> void:
	_grade.clear_lut()
	_lut_label.text = "(none)"
	_lut_strength_slider.set_value_no_signal(0.0)
	_notify_live()

func _on_reset_pressed() -> void:
	_grade.reset()
	_refresh_sliders_from_grade()
	_lut_label.text = "(none)"
	_notify_live()

func _refresh_sliders_from_grade() -> void:
	for key in _sliders.keys():
		var slider: HSlider = _sliders[key]
		if key.ends_with("_0") or key.ends_with("_1") or key.ends_with("_2"):
			var parts := key.rsplit("_", true, 1)
			var param: String = parts[0]
			var axis_i := int(parts[1])
			slider.set_value_no_signal((_grade.get(param) as Vector3)[axis_i])
		else:
			slider.set_value_no_signal(_grade.get(key))
	_lut_strength_slider.set_value_no_signal(_grade.lut_strength)

func _notify_live() -> void:
	get_node("/root/TimelineData").notify_color_grade_changed(track_id)

func _on_close_pressed() -> void:
	get_node("/root/TimelineData").commit_color_grade_edit(track_id)
	closed.emit()
	queue_free()
