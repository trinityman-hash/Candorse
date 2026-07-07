extends Control
## Module I: "Scene/Roam UI" — the second of the two clearly separated
## surfaces. Only visible after the user explicitly taps "Enter Scene"
## from the flat Timeline/Trim UI. Never blended with 2D trim controls
## on screen simultaneously (this Control is hidden by default).

signal exited_scene_mode()

@onready var _exit_button: Button = %ExitSceneButton
@onready var _add_light_button: Button = %AddLightButton
@onready var _add_fog_button: Button = %AddFogButton
@onready var _add_primitive_button: Button = %AddPrimitiveButton
@onready var _snap_flat_button: Button = %SnapFlatButton

var timeline_camera: TimelineCamera
var track_root: Node3D # SubViewport's TrackRoot, environment nodes get parented here

func _ready() -> void:
	visible = false
	_exit_button.pressed.connect(_on_exit_pressed)
	_add_light_button.pressed.connect(_on_add_light_pressed)
	_add_fog_button.pressed.connect(_on_add_fog_pressed)
	_add_primitive_button.pressed.connect(_on_add_primitive_pressed)
	_snap_flat_button.pressed.connect(_on_snap_flat_pressed)

func enter_scene_mode(camera: TimelineCamera, root: Node3D) -> void:
	timeline_camera = camera
	track_root = root
	visible = true
	timeline_camera.enter_roam()

func _on_exit_pressed() -> void:
	_return_to_edit()

func _on_snap_flat_pressed() -> void:
	## Module I: "snap back to flat" one-tap reset — available on every
	## 3D-only feature, not just the main exit button, so a user who
	## wandered into roam by accident always has an immediate way out.
	_return_to_edit()

func _return_to_edit() -> void:
	if timeline_camera:
		timeline_camera.enter_edit()
	visible = false
	exited_scene_mode.emit()

func _on_add_light_pressed() -> void:
	if track_root:
		LightingRig.build_default_rig(track_root)

func _on_add_fog_pressed() -> void:
	if track_root:
		var env := EnvironmentLayer.new()
		env.kind = EnvironmentLayer.Kind.FOG
		track_root.add_child(env)

func _on_add_primitive_pressed() -> void:
	if track_root:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = RuntimeModeler.make_cube()
		mesh_instance.set_surface_override_material(0, RuntimeModeler.default_material())
		track_root.add_child(mesh_instance)
