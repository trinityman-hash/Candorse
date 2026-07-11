extends Control
## Module I: "Scene/Roam UI" — the second of the two clearly separated
## surfaces. Only visible after the user explicitly taps "Enter Scene"
## from the flat Timeline/Trim UI. Never blended with 2D trim controls
## on screen simultaneously (this Control is hidden by default).
##
## Module D addition: an object list + per-object transform panel, so
## lights/fog/primitives placed in the scene can actually be selected
## and moved/rotated/scaled/relit after being added — previously "Add
## Light"/"Add Fog"/"Add Primitive" dropped objects at the origin with
## no way to reposition them at all. See scene_object_panel.gd and
## docs/ENVIRONMENT_STATUS.md for exactly what this does and doesn't
## cover (no viewport drag gizmo, no undo/redo, no sculpting — none of
## that is silently missing, all tracked there).

signal exited_scene_mode()

@onready var _exit_button: Button = %ExitSceneButton
@onready var _add_light_button: Button = %AddLightButton
@onready var _add_fog_button: Button = %AddFogButton
@onready var _add_primitive_button: Button = %AddPrimitiveButton
@onready var _snap_flat_button: Button = %SnapFlatButton
@onready var _object_panel_host: VBoxContainer = %ObjectPanelHost

var timeline_camera: TimelineCamera
var track_root: Node3D # SubViewport's TrackRoot, environment nodes get parented here

var _scene_objects: Array = [] # Array[Dictionary] {node: Node3D, label: String}
var _object_list_container: VBoxContainer
var _active_panel: SceneObjectPanel
var _next_object_index: int = 0

func _ready() -> void:
	visible = false
	_exit_button.pressed.connect(_on_exit_pressed)
	_add_light_button.pressed.connect(_on_add_light_pressed)
	_add_fog_button.pressed.connect(_on_add_fog_pressed)
	_add_primitive_button.pressed.connect(_on_add_primitive_pressed)
	_snap_flat_button.pressed.connect(_on_snap_flat_pressed)

	# The list of "tap to select" buttons lives as the first child of
	# _object_panel_host; the active SceneObjectPanel (if any) gets
	# appended after it by _select_object(). Kept as one host container
	# rather than two side-by-side ones so the panel appears directly
	# under the object you just tapped, not in a disconnected region.
	_object_list_container = VBoxContainer.new()
	_object_panel_host.add_child(_object_list_container)

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
	if not track_root:
		return
	var rigs := LightingRig.build_default_rig(track_root)
	var rig_labels := ["Key light", "Fill light", "Rim light"]
	for i in rigs.size():
		_register_object(rigs[i], rig_labels[i] if i < rig_labels.size() else "Light")

func _on_add_fog_pressed() -> void:
	if not track_root:
		return
	var env := EnvironmentLayer.new()
	env.kind = EnvironmentLayer.Kind.FOG
	track_root.add_child(env)
	_register_object(env, "Fog")

func _on_add_primitive_pressed() -> void:
	if not track_root:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = RuntimeModeler.make_cube()
	mesh_instance.set_surface_override_material(0, RuntimeModeler.default_material())
	track_root.add_child(mesh_instance)
	_register_object(mesh_instance, "Primitive")

## Adds a spawned node to the selectable object list. Every "Add ___"
## handler above MUST call this — an object that exists in the 3D scene
## but never got registered here would be unmovable and unremovable
## from this panel, a silent dead end for the user.
func _register_object(node: Node3D, label: String) -> void:
	_next_object_index += 1
	var display_label := "%s %d" % [label, _next_object_index]
	_scene_objects.append({"node": node, "label": display_label})
	# If the node is freed by any path (its own Remove button, or any
	# future code), the list entry cleans itself up instead of the list
	# pointing at a freed object.
	node.tree_exiting.connect(_on_object_freed.bind(node))
	_rebuild_object_list()
	_select_object(node, display_label)

func _on_object_freed(node: Node3D) -> void:
	for i in range(_scene_objects.size() - 1, -1, -1):
		if _scene_objects[i]["node"] == node:
			_scene_objects.remove_at(i)
	if _active_panel and _active_panel.target == node:
		_active_panel.queue_free()
		_active_panel = null
	_rebuild_object_list()

func _rebuild_object_list() -> void:
	for child in _object_list_container.get_children():
		child.queue_free()
	for entry in _scene_objects:
		var row := HBoxContainer.new()
		_object_list_container.add_child(row)
		var btn := Button.new()
		btn.text = entry["label"]
		var node: Node3D = entry["node"]
		var label: String = entry["label"]
		btn.pressed.connect(_select_object.bind(node, label))
		row.add_child(btn)

func _select_object(node: Node3D, label: String) -> void:
	if not is_instance_valid(node):
		return
	if _active_panel:
		_active_panel.queue_free()
		_active_panel = null
	var panel := SceneObjectPanel.new()
	_object_panel_host.add_child(panel)
	panel.build_for_object(node, label)
	panel.closed.connect(func(): _active_panel = null)
	_active_panel = panel
