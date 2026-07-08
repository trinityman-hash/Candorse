extends Node3D
## Attached to TimelineStage's TrackRoot (scenes/timeline_stage.tscn).
##
## This is the missing glue for Module A: TimelineData is the single
## source of truth, and this node listens to its signals and keeps the 3D
## stage in sync. It never mutates TimelineData itself — strictly a view,
## per the single-source-of-truth rule stated throughout Module A.
##
## Track kind determines what gets instanced:
## - video / overlay / sticker: VideoTrackMesh (textured quad)
## - text: TextLayer (Label3D-based per Phase 1, see text_layer.gd) — NOT
##   a video quad. Text has no video texture to sample; routing it through
##   VideoTrackMesh (the previous behavior here) would try to sample a
##   texture that doesn't exist. Uses the track's first clip's `path`
##   field as literal text content — Track/Clip has no dedicated
##   "text content" field yet, so this is a documented interim mapping,
##   not a hidden hack.
## - audio: no visual node — drives an audio bus only, per Module A.

var _node_by_track_id: Dictionary = {} # track_id -> Node3D (VideoTrackMesh or TextLayer)

func _ready() -> void:
	if not has_node("/root/TimelineData"):
		push_warning("TrackStageController: TimelineData autoload not found")
		return
	var td = get_node("/root/TimelineData")
	td.track_added.connect(_on_track_added)
	td.track_removed.connect(_on_track_removed)
	td.track_changed.connect(_on_track_changed)

	# Sync any tracks that already existed before this node entered the
	# tree (defensive — current scene order has TimelineStage ready before
	# TimelineUI can add tracks, but don't assume that ordering holds
	# forever as the scene grows).
	for track in td.tracks.values():
		_on_track_added(track)

func _on_track_added(track) -> void:
	if _node_by_track_id.has(track.id):
		return

	var node: Node3D
	match track.kind:
		"audio":
			return # no visual node
		"text":
			var text_layer := TextLayer.new()
			text_layer.text = _first_clip_text(track)
			node = text_layer
		_: # video, overlay, sticker
			var track_mesh := VideoTrackMesh.new()
			track_mesh.track_id = track.id
			track_mesh.curvable = track.curvable
			node = track_mesh

	# Negative Z per the multiplane-camera convention used everywhere else
	# in this codebase (decode_stress_test.gd, timeline_camera default
	# transform): higher z_depth values sit further from the default
	# camera position at +Z looking toward -Z.
	node.position = Vector3(0, 0, -track.z_depth)
	add_child(node)
	_node_by_track_id[track.id] = node

func _on_track_changed(track) -> void:
	# Text content lives on the first clip's `path` field per the mapping
	# documented above — if it changes (e.g. a future "edit text" UI action
	# adds/edits the clip), keep the on-stage TextLayer in sync.
	if track.kind != "text" or not _node_by_track_id.has(track.id):
		return
	var node = _node_by_track_id[track.id]
	if node is TextLayer:
		node.text = _first_clip_text(track)

func _first_clip_text(track) -> String:
	if track.clips.is_empty():
		return ""
	return track.clips[0].path

func _on_track_removed(track_id: int) -> void:
	if not _node_by_track_id.has(track_id):
		return
	var node: Node = _node_by_track_id[track_id]
	_node_by_track_id.erase(track_id)
	if is_instance_valid(node):
		node.queue_free()
