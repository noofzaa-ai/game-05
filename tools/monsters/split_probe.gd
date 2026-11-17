extends SceneTree
func _init():
	for m in ["goblin","goblin_archer","goblin_chief","goblin_knight","goblin_mage"]:
		var s=(load("res://art/monsters/%s/%s.glb"%[m,m]) as PackedScene).instantiate()
		for mi in s.find_children("*","MeshInstance3D",true,false):
			if mi.skin==null or mi.mesh.get_surface_count()==0 or mi.name.begins_with("bow"): continue
			var a=mi.mesh.surface_get_arrays(0)
			var v:PackedVector3Array=a[Mesh.ARRAY_VERTEX]; var idx:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			var parent={}
			var key=func(p): return Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))
			var uf={}
			var find
			find=func(k):
				while uf[k]!=k:
					uf[k]=uf[uf[k]]; k=uf[k]
				return k
			for p in v:
				var k=key.call(p)
				if not uf.has(k): uf[k]=k
			for t in idx.size()/3:
				var k0=find.call(key.call(v[idx[t*3]]))
				for c in [1,2]:
					var k1=find.call(key.call(v[idx[t*3+c]]))
					if k1!=k0: uf[k1]=k0
			var comp={}
			for t in idx.size()/3:
				var r=find.call(key.call(v[idx[t*3]]))
				comp[r]=comp.get(r,0)+1
			var sizes=comp.values(); sizes.sort(); sizes.reverse()
			print(m," ",mi.name," tris=",idx.size()/3," components=",sizes.size()," sizes=",sizes.slice(0,14))
	quit()
