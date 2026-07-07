extends Node3D
class_name EnvironmentLayer
## Module D: particle/fog nodes as optional environment layers, animated
## independent of video content — the mechanism behind "surroundings
## become the animation." Sits alongside video quads in the scene graph,
## not baked into any single track.

enum Kind { PARTICLES, FOG, BOTH }

@export var kind: Kind = Kind.PARTICLES
@export var fog_density: float = 0.02
@export var fog_color: Color = Color(0.5, 0.55, 0.65)
@export var particle_amount: int = 64
@export var particle_texture: Texture2D

var _particles: GPUParticles3D
var _fog_env: WorldEnvironment

func _ready() -> void:
	if kind == Kind.PARTICLES or kind == Kind.BOTH:
		_build_particles()
	if kind == Kind.FOG or kind == Kind.BOTH:
		_build_fog()

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

func _build_fog() -> void:
	# Fog here is scoped to this layer's WorldEnvironment override rather
	# than the whole SubViewport's environment, so multiple environment
	# layers with different densities can coexist without fighting over a
	# single global fog setting.
	_fog_env = WorldEnvironment.new()
	var env := Environment.new()
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	_fog_env.environment = env
	add_child(_fog_env)

func set_intensity(t: float) -> void:
	## Single 0-1 handle for keyframing "how much environment" is present
	## at a given timeline moment (Module G integration point).
	if _particles:
		_particles.amount_ratio = clampf(t, 0.0, 1.0)
	if _fog_env and _fog_env.environment:
		_fog_env.environment.fog_density = fog_density * clampf(t, 0.0, 1.0)
