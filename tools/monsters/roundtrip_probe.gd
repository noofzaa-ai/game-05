extends SceneTree
func _init():
	var src="C:/Users/wanwi/orca/workspaces/game05/game-05/art/monsters/goblin_chief/goblin_chief.glb"
	var state=GLTFState.new(); var doc=GLTFDocument.new()
	var err=doc.append_from_file(src,state)
	print("read ",err," meshes ",state.get_meshes().size()," nodes ",state.get_nodes().size()," skins ",state.get_skins().size())
	for m in state.get_meshes():
		var im:ImporterMesh=m.mesh
		print(" mesh ",m.resource_name," surfaces ",im.get_surface_count()," tris ",im.get_surface_arrays(0)[Mesh.ARRAY_INDEX].size()/3, " arrays has: ", im.get_surface_arrays(0).map(func(x): return x!=null and x.size()>0))
	err=doc.write_to_filesystem(state,"C:/Users/wanwi/orca/workspaces/game05/game-05/build/gob_probe/chief_rt.glb")
	print("write ",err)
	quit()
