extends SceneTree
func _init():
	for p in OS.get_cmdline_user_args():
		var s=(load(p) as PackedScene).instantiate()
		var ap=s.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
		var tot_t=0; var tot_k=0
		for c in ap.get_animation_list():
			var a=ap.get_animation(c); var k=0
			for t in a.get_track_count(): k+=a.track_get_key_count(t)
			print(p.get_file()," ",c," len=%.2f tracks=%d keys=%d"%[a.length,a.get_track_count(),k])
			tot_t+=a.get_track_count(); tot_k+=k
		print(p.get_file()," TOTAL tracks=",tot_t," keys=",tot_k)
		s.free()
	quit()
