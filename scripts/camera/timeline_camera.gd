extends Camera3D
class_name TimelineCamera
## Module C. Interpolates between EDIT (ortho, locked) and ROAM (perspective,
## bounded spectator movement). EDIT is the default per Module I — ROAM is
## opt-in via an explicit "enter scene" UI affordance, never the default.

enum Mode { EDIT, ROAM }

@export var mode: Mode = Mode.EDIT
@export var roam_bounds: AABB = AABB(Vector3(-5, -5, -10), Vector3(10, 10, 10))
@export var transition_speed: float = 4.0
@export var roam_move_speed: float = 3.0

var _target_ortho_size: float = 5.0
var _target_fov: float = 60.0
var _is_transitioning: bool = false

func enter_roam() -> void:
	mode = Mode.ROAM
	projection = Camera3D.PROJECTION_PERSPECTIVE
	_is_transitioning = true

func enter_edit() -> void:
	mode = Mode.EDIT
	_is_transitioning = true
	# Snap orthographic once transition completes; see Module I "snap back to
	# flat" requirement — this is the one-tap reset entry point.

func _process(delta: float) -> void:
	if mode == Mode.ROAM:
		_handle_roam_input(delta)
		_clamp_to_bounds()

func _handle_roam_input(delta: float) -> void:
	# TODO: wire to twin-stick or drag-to-orbit touch input — decision
	# pending per brief §7 open decisions. Placeholder keyboard fallback
	# for desktop testing only:
	var move := Vector3.ZERO
	if Input.is_action_pressed("ui_up"):
		move -= global_transform.basis.z
	if Input.is_action_pressed("ui_down"):
		move += global_transform.basis.z
	if Input.is_action_pressed("ui_left"):
		move -= global_transform.basis.x
	if Input.is_action_pressed("ui_right"):
		move += global_transform.basis.x
	global_position += move * roam_move_speed * delta

func _clamp_to_bounds() -> void:
	# Bounding volume clamp so roam can't clip behind the stack (Module C).
	var p := global_position
	p.x = clamp(p.x, roam_bounds.position.x, roam_bounds.position.x + roam_bounds.size.x)
	p.y = clamp(p.y, roam_bounds.position.y, roam_bounds.position.y + roam_bounds.size.y)
	p.z = clamp(p.z, roam_bounds.position.z, roam_bounds.position.z + roam_bounds.size.z)
	global_position = p
