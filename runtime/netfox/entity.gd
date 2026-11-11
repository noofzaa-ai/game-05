extends Node3D
var synchronizer
func configure(start:Vector3,visible_peers:Array)->void:
 position=start
 synchronizer=preload("res://runtime/netfox/remote_state.gd").new();synchronizer.name="State";synchronizer.root=self;synchronizer.properties.assign([":position"])
 synchronizer.visibility_filter.default_visibility=false
 for peer in visible_peers:synchronizer.visibility_filter.set_visibility_for(peer,true)
 add_child(synchronizer)
