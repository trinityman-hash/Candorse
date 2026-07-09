extends Resource
class_name ColorGradeState
## Module E: per-track/per-clip color grading parameters — DaVinci-style
## Lift/Gamma/Gain wheels, brightness/contrast/saturation, vignette, a
## generic color matrix (for advanced/scripted grading), per-channel
## tone curves (see hsl_curves.gd), and an optional LUT blend. This
## holds plain data and knows how to push itself onto a
## video_compositor.gdshader ShaderMaterial; it deliberately does NOT
## know about TimelineData, undo/redo, or any UI — callers own wiring
## this into a command-pattern undo entry the same way Module A's other
## mutations work.
##
## NOT implemented in this pass — tracked in docs/COLOR_ENGINE_STATUS.md,
## not silently dropped: the standalone Sharpness slider (needs a
## texel_size uniform derived from the actual decoded frame resolution,
## which is tangled up with the still-undecided Module B decode route).

@export var lift: Vector3 = Vector3.ZERO
@export var gamma: Vector3 = Vector3.ONE
@export var gain: Vector3 = Vector3.ONE

@export var brightness: float = 0.0
@export var contrast: float = 1.0
@export var saturation: float = 1.0

@export var vignette_strength: float = 0.0
@export var vignette_radius: float = 0.75
@export var vignette_softness: float = 0.35

@export var color_matrix_r: Vector4 = Vector4(1, 0, 0, 0)
@export var color_matrix_g: Vector4 = Vector4(0, 1, 0, 0)
@export var color_matrix_b: Vector4 = Vector4(0, 0, 1, 0)

## Master/Red/Green/Blue tone curves. See hsl_curves.gd for the point-
## editing API (add_point/move_point/remove_point/reset_channel) a UI
## curve editor drives; this class only ever reads it back via
## is_identity() / get_texture() when pushing to the shader.
@export var hsl_curves: HSLCurves = HSLCurves.new()

var lut_strength: float = 0.0:
	set(v):
		lut_strength = clampf(v, 0.0, 1.0)

var _lut: LutLoader.LutResult

## Loads and binds a .cube LUT. Returns false (and leaves any previously
## loaded LUT in place) if the file fails to parse — never silently
## swaps in a blank/identity LUT on failure.
func load_lut(path: String) -> bool:
	var result := LutLoader.load_cube_file(path)
	if result == null:
		return false
	_lut = result
	return true

func clear_lut() -> void:
	_lut = null
	lut_strength = 0.0

func has_lut() -> bool:
	return _lut != null

func lut_title() -> String:
	return _lut.title if _lut != null else ""

## Pushes every parameter onto the given material's shader uniforms.
## Safe to call every frame if a caller wants live-preview dragging on a
## color wheel or curve point; ShaderMaterial.set_shader_parameter is
## cheap, and hsl_curves.get_texture() only re-bakes when a curve point
## actually changed (see HSLCurves._dirty).
func apply_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		push_warning("ColorGradeState.apply_to_material: null material")
		return

	mat.set_shader_parameter("lift", lift)
	mat.set_shader_parameter("gamma", gamma)
	mat.set_shader_parameter("gain", gain)
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("vignette_strength", vignette_strength)
	mat.set_shader_parameter("vignette_radius", vignette_radius)
	mat.set_shader_parameter("vignette_softness", vignette_softness)
	mat.set_shader_parameter("color_matrix_r", color_matrix_r)
	mat.set_shader_parameter("color_matrix_g", color_matrix_g)
	mat.set_shader_parameter("color_matrix_b", color_matrix_b)

	if hsl_curves != null and not hsl_curves.is_identity():
		mat.set_shader_parameter("hsl_curve_lut", hsl_curves.get_texture())
		mat.set_shader_parameter("hsl_curves_enabled", true)
	else:
		mat.set_shader_parameter("hsl_curves_enabled", false)

	if _lut != null:
		mat.set_shader_parameter("lut_texture", _lut.texture)
		mat.set_shader_parameter("lut_domain_min", _lut.domain_min)
		mat.set_shader_parameter("lut_domain_max", _lut.domain_max)
		mat.set_shader_parameter("lut_strength", lut_strength)
	else:
		mat.set_shader_parameter("lut_strength", 0.0)

## Resets every parameter to shader defaults (the "no-op" grade).
func reset() -> void:
	lift = Vector3.ZERO
	gamma = Vector3.ONE
	gain = Vector3.ONE
	brightness = 0.0
	contrast = 1.0
	saturation = 1.0
	vignette_strength = 0.0
	vignette_radius = 0.75
	vignette_softness = 0.35
	color_matrix_r = Vector4(1, 0, 0, 0)
	color_matrix_g = Vector4(0, 1, 0, 0)
	color_matrix_b = Vector4(0, 0, 1, 0)
	if hsl_curves != null:
		hsl_curves.reset_all()
	clear_lut()
