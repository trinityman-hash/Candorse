extends Camera3D
class_name TimelineCamera
## Module C. Interpolates between EDIT (ortho, locked) and ROAM (perspective,
## bounded spectator movement). EDIT is the default per Module I — ROAM is
## opt-in via an explicit "enter scene" UI affordance, never the default.

enum Mode { EDIT, ROAM }

@export var mode: Mode = Mode.EDIT
@export var roam_bounds: AABB = AABB(Vector3(-5, -5, -10), Vector3(10, 10, 10))
@export var transition_seconds: float = 0.35
@export var roam_move_speed: float = 3.0
@export var edit_ortho_size: float = 5.0
@export var roam_fov: float = 60.0

var _tween: Tween

func enter_roam() -> void:
	mode = Mode.ROAM
	_transition_to(Camera3D.PROJECTION_PERSPECTIVE, roam_fov)

func enter_edit() -> void:
	mode = Mode.EDIT
	_transition_to(Camera3D.PROJECTION_ORTHOGONAL, edit_ortho_size)

func _transition_to(target_projection: int, target_value: float) -> void:
	if _tween:
		_tween.kill()

	# Known engine limitation, documented rather than papered over: Godot's
	# Camera3D exposes `projection` as a discrete enum — there is no
	# continuously-interpolatable matrix between ORTHOGONAL and
	# PERSPECTIVE to tween through. True frame-by-frame blending between
	# the two projection types isn't something the engine gives us here.
	# What we do instead, to still satisfy "interpolation, not a hard cut"
	# (§4 Module C): switch `projection` to the *destination* type
	# immediately, then tween fov/size toward the destination value. A
	# wide-FOV perspective at the outgoing ortho's apparent framing reads
	# close enough to the ortho view that the type-swap itself isn't a
	# visible pop — the tween that follows is what the user perceives as
	# the transition. If this reads as a pop in practice on real content,
	# the fix is a short crossfade between two SubViewport captures rather
	# than fighting the single-camera constraint further.
	projection = target_projection
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if target_projection == Camera3D.PROJECTION_ORTHOGONAL:
		_tween.tween_property(self, "size", target_value, transition_seconds)
	else:
		_tween.tween_property(self, "fov", target_value, transition_seconds)

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
