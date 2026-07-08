extends Node3D
## Attached to TimelineStage's TrackRoot (scenes/timeline_stage.tscn).
##
## This is the missing glue for Module A: TimelineData is the single
## source of truth, but until this script existed, nothing actually
## mirrored `tracks` into the 3D scene — timeline_ui.gd only builds the
## flat 2D list row, it never touches TrackRoot. Adding a track via the UI
## had zero visible effect in the SubViewport. This node listens to
## TimelineData's signals and keeps one VideoTrackMesh child per track in
## sync, and does the reverse for track_removed. It never mutates
## TimelineData itself — strictly a view, per the single-source-of-truth
## rule stated throughout Module A.

## global class_name (scripts/tracks/video_track_mesh.gd), no preload needed

var _mesh_by_track_id: Dictionary = {} # track_id -> VideoTrackMesh

func _ready() -> void:
	if not has_node("/root/TimelineData"):
		push_warning("TrackStageController: TimelineData autoload not found")
		return
	var td = get_node("/root/TimelineData")
	td.track_added.connect(_on_track_added)
	td.track_removed.connect(_on_track_removed)

	# Sync any tracks that already existed before this node entered the
	# tree (defensive — current scene order has TimelineStage ready before
	# TimelineUI can add tracks, but don't assume that ordering holds
	# forever as the scene grows).
	for track in td.tracks.values():
		_on_track_added(track)

func _on_track_added(track) -> void:
	if _mesh_by_track_id.has(track.id):
		return
	# Audio tracks (Module A) have no visual mesh — they drive an audio
	# bus only, per the brief's track-kind list.
	if track.kind == "audio":
		return

	var track_mesh := VideoTrackMesh.new()
	track_mesh.track_id = track.id
	track_mesh.curvable = track.curvable
	# Negative Z per the multiplane-camera convention used everywhere else
	# in this codebase (decode_stress_test.gd, timeline_camera default
	# transform): higher z_depth values sit further from the default
	# camera position at +Z looking toward -Z.
	track_mesh.position = Vector3(0, 0, -track.z_depth)
	add_child(track_mesh)
	_mesh_by_track_id[track.id] = track_mesh

func _on_track_removed(track_id: int) -> void:
	if not _mesh_by_track_id.has(track_id):
		return
	var track_mesh: Node = _mesh_by_track_id[track_id]
	_mesh_by_track_id.erase(track_id)
	if is_instance_valid(track_mesh):
		track_mesh.queue_free()
