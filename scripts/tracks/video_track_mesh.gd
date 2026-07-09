extends MeshInstance3D
class_name VideoTrackMesh
## Represents one Track's visual quad in the 3D stage (Module A/C).
## This node is a VIEW of TimelineData.Track — it never mutates the track
## data itself. Rebuild on track_changed, don't hand-edit transforms here.

@export var track_id: int = -1
@export var curvable: bool = false
@export var subdivisions: int = 1 # per §3 correction: background tracks stay 1x1 quads

var _texture: ImageTexture
var _material: ShaderMaterial
var _transition_material: ShaderMaterial
var _in_transition: bool = false

func _ready() -> void:
	_build_mesh()
	_build_material()
	if has_node("/root/TimelineData"):
		var td = get_node("/root/TimelineData")
		td.track_changed.connect(_on_track_changed)

func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var subdiv: int = subdivisions if curvable else 1
	var size := Vector2(1.0, 1.0) # normalized quad, scaled via transform
	for y in range(subdiv):
		for x in range(subdiv):
			var x0 := -size.x / 2.0 + size.x * float(x) / subdiv
			var x1 := -size.x / 2.0 + size.x * float(x + 1) / subdiv
			var y0 := -size.y / 2.0 + size.y * float(y) / subdiv
			var y1 := -size.y / 2.0 + size.y * float(y + 1) / subdiv
			var u0 := float(x) / subdiv
			var u1 := float(x + 1) / subdiv
			var v0 := 1.0 - float(y) / subdiv
			var v1 := 1.0 - float(y + 1) / subdiv

			st.set_uv(Vector2(u0, v0)); st.add_vertex(Vector3(x0, y0, 0))
			st.set_uv(Vector2(u1, v0)); st.add_vertex(Vector3(x1, y0, 0))
			st.set_uv(Vector2(u1, v1)); st.add_vertex(Vector3(x1, y1, 0))

			st.set_uv(Vector2(u0, v0)); st.add_vertex(Vector3(x0, y0, 0))
			st.set_uv(Vector2(u1, v1)); st.add_vertex(Vector3(x1, y1, 0))
			st.set_uv(Vector2(u0, v1)); st.add_vertex(Vector3(x0, y1, 0))

	st.generate_normals()
	mesh = st.commit()

func _build_material() -> void:
	var shader := load("res://shaders/video_compositor.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader
	set_surface_override_material(0, _material)

## Normal single-clip playback path — pushes one decoded frame in.
## No-op while a transition is active (see enter_transition_mode) so a
## stray frame update mid-crossfade can't stomp the blended material.
func update_frame_texture(tex: Texture2D) -> void:
	if _material and not _in_transition:
		_material.set_shader_parameter("video_texture", tex)

## Module E: swaps this track's material to the crossfade shader for the
## duration of a clip transition (see Clip.transition_duration in
## timeline_data.gd). Caller (the eventual per-frame playhead/decode
## driver — see note below) is responsible for calling
## update_transition_frame() every frame while active and
## exit_transition_mode() once the blend window ends.
##
## NOTE: nothing in this codebase yet actually drives this every frame —
## that driver needs two simultaneously-decoded textures (outgoing clip's
## tail + incoming clip's head) and doesn't exist until Module B's decode
## route is real (still stubbed, see docs/PHASE0_STATUS.md). This method
## and update_transition_frame() are the correct, ready-to-call interface
## for whenever that driver is built — not a hidden gap, an intentional
## seam.
func enter_transition_mode() -> void:
	if _in_transition:
		return
	if not _transition_material:
		var shader := load("res://shaders/transition_crossfade.gdshader")
		_transition_material = ShaderMaterial.new()
		_transition_material.shader = shader
	set_surface_override_material(0, _transition_material)
	_in_transition = true

func update_transition_frame(texture_out: Texture2D, texture_in: Texture2D, blend: float) -> void:
	if not _in_transition or not _transition_material:
		return
	_transition_material.set_shader_parameter("texture_out", texture_out)
	_transition_material.set_shader_parameter("texture_in", texture_in)
	_transition_material.set_shader_parameter("blend", clampf(blend, 0.0, 1.0))

func exit_transition_mode() -> void:
	if not _in_transition:
		return
	set_surface_override_material(0, _material)
	_in_transition = false

func _on_track_changed(track) -> void:
	if track.id != track_id:
		return
	var subdiv_changed := track.curvable != curvable
	curvable = track.curvable
	if subdiv_changed:
		_build_mesh()
