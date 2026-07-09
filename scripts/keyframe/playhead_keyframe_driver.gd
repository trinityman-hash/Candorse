extends Node
## Module G: drives every keyframed layer (LightingRig, TextLayer,
## EnvironmentLayer, and any future layer type that implements
## apply_at_time(time) and joins the "keyframed_layers" group) from the
## single TimelineData playhead. This was the actual missing piece —
## the keyframe data structures (KeyframeTrack, LayerKeyframes) and each
## layer's own apply_at_time() already existed, but nothing was ever
## calling apply_at_time() as the playhead moved, so nothing animated.
##
## Deliberately generic: this node knows nothing about LightingRig,
## TextLayer, etc. by name. Any node that adds itself to the
## "keyframed_layers" group and defines apply_at_time(time: float) is
## picked up automatically via call_group — new layer types don't
## require touching this file, consistent with Module G's "build once,
## generically" requirement.

func _ready() -> void:
	if has_node("/root/TimelineData"):
		get_node("/root/TimelineData").playhead_changed.connect(_on_playhead_changed)
	else:
		push_warning("PlayheadKeyframeDriver: TimelineData autoload not found")

func _on_playhead_changed(time: float) -> void:
	get_tree().call_group("keyframed_layers", "apply_at_time", time)
