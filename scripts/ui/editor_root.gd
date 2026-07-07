extends Control
## Root controller for editor_main.tscn. Wires the one explicit bridge
## between the two Module I surfaces: TimelineUI's "Enter Scene" button
## and SceneRoamUI's activation. This is intentionally the only coupling
## point between the 2D and 3D control schemes.

@onready var _timeline_ui = $TimelineUI
@onready var _scene_roam_ui = $SceneRoamUI
@onready var _timeline_stage = $TimelineStage

func _ready() -> void:
	_timeline_ui.enter_scene_requested.connect(_on_enter_scene_requested)
	_scene_roam_ui.exited_scene_mode.connect(_on_exited_scene_mode)

func _on_enter_scene_requested() -> void:
	var camera = _timeline_stage.get_node("SubViewport/TimelineCamera")
	var track_root = _timeline_stage.get_node("SubViewport/TrackRoot")
	_scene_roam_ui.enter_scene_mode(camera, track_root)
	_timeline_ui.visible = false

func _on_exited_scene_mode() -> void:
	_timeline_ui.visible = true
