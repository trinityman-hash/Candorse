extends Node3D
class_name EnvironmentLayer
## Module D: particle/fog nodes as optional environment layers, animated
## independent of video content — the mechanism behind "surroundings
## become the animation." Sits alongside video quads in the scene graph,
## not baked into any single track.

enum Kind { PARTICLES, FOG, BOTH }

const SHARED_ENV_GROUP := "candorse_shared_world_environment"

@export var kind: Kind = Kind.PARTICLES
@export var fog_density: float = 0.02
@export var fog_color: Color = Color(0.5, 0.55, 0.65)
@export var particle_amount: int = 64
@export var particle_texture: Texture2D

var _particles: GPUParticles3D
var _intensity: float = 1.0

# NOTE on fog: Godot only honors one *active* WorldEnvironment per
# viewport — instancing a separate WorldEnvironment node per
# EnvironmentLayer (the previous approach here) doesn't make multiple
# fog layers "coexist"; it makes them silently fight over which one wins,
# since only one is ever actually applied. Fixed by routing all
# EnvironmentLayer fog contributions through one shared WorldEnvironment
# (found via group lookup, created lazily on first use) and summing each
# layer's density contribution instead of each layer owning its own.
static var _shared_world_env: WorldEnvironment
static var _fog_contributions: Dictionary = {} # layer instance_id -> density

func _ready() -> void:
	if kind == Kind.PARTICLES or kind == Kind.BOTH:
		_build_particles()
	if kind == Kind.FOG or kind == Kind.BOTH:
		_register_fog_contribution()

func _exit_tree() -> void:
	if _fog_contributions.has(get_instance_id()):
		_fog_contributions.erase(get_instance_id())
		_recompute_shared_fog()

func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = particle_amount
	_particles.lifetime = 4.0
	_particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.gravity = Vector3(0, -0.05, 0)
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.3
	_particles.process_material = mat

	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.1, 0.1)
	_particles.draw_pass_1 = draw_mesh

	if particle_texture:
		var mesh_mat := StandardMaterial3D.new()
		mesh_mat.albedo_texture = particle_texture
		mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		draw_mesh.material = mesh_mat

	add_child(_particles)

func _get_or_create_shared_world_env() -> WorldEnvironment:
	if is_instance_valid(_shared_world_env):
		return _shared_world_env

	var tree := get_tree()
	if tree == null:
		return null

	var existing := tree.get_nodes_in_group(SHARED_ENV_GROUP)
	if existing.size() > 0:
		_shared_world_env = existing[0]
		return _shared_world_env

	_shared_world_env = WorldEnvironment.new()
	_shared_world_env.add_to_group(SHARED_ENV_GROUP)
	var env := Environment.new()
	env.fog_enabled = false
	_shared_world_env.environment = env
	# Parented at the tree root so it outlives any single track/layer and
	# stays singular regardless of where individual EnvironmentLayer nodes
	# live in the track stack.
	tree.root.add_child.call_deferred(_shared_world_env)
	return _shared_world_env

func _register_fog_contribution() -> void:
	var shared := _get_or_create_shared_world_env()
	if shared == null:
		return
	_fog_contributions[get_instance_id()] = fog_density * _intensity
	_recompute_shared_fog.call_deferred()

static func _recompute_shared_fog() -> void:
	if not is_instance_valid(_shared_world_env) or _shared_world_env.environment == null:
		return
	var total := 0.0
	for v in _fog_contributions.values():
		total += v
	var env := _shared_world_env.environment
	env.fog_enabled = total > 0.0
	env.fog_density = total
	# Last-set fog_light_color wins for now — genuine per-layer fog color
	# blending would need a custom fog shader rather than Environment's
	# single fog_light_color property; documented simplification, not a
	# silent gap.

func set_intensity(t: float) -> void:
	## Single 0-1 handle for keyframing "how much environment" is present
	## at a given timeline moment (Module G integration point).
	_intensity = clampf(t, 0.0, 1.0)
	if _particles:
		_particles.amount_ratio = _intensity
	if _fog_contributions.has(get_instance_id()):
		_fog_contributions[get_instance_id()] = fog_density * _intensity
		_recompute_shared_fog()
		if is_instance_valid(_shared_world_env) and _shared_world_env.environment:
			_shared_world_env.environment.fog_light_color = fog_color
