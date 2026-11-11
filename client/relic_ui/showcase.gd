extends SubViewportContainer
## Own isolated world, rendered only on selection/resize. No extra per-frame camera or light work.
var _viewport:SubViewport
var _actor:Node3D
var _model_path=""
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;stretch=true
	_viewport=SubViewport.new();_viewport.size=Vector2i(512,512);_viewport.transparent_bg=true;_viewport.own_world_3d=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(_viewport)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(0,0,0,0)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("e6d7af");env.environment.ambient_light_energy=.8;_viewport.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);sun.light_color=Color("ffe3a7");sun.light_energy=1.7;_viewport.add_child(sun)
	var rim=DirectionalLight3D.new();rim.rotation_degrees=Vector3(-20,145,0);rim.light_color=Color("a7d1c2");rim.light_energy=.7;_viewport.add_child(rim)
	_actor=Node3D.new();_viewport.add_child(_actor)
	var pedestal=MeshInstance3D.new();var stone=SurfaceTool.new();stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices=[]
	for row in 3:
		var ring=[]
		for i in 9:
			var radius=[.10,.125,.12][row]*(1.0+sin(i*14.2)*.08)
			ring.append(Vector3(cos(i*TAU/9)*radius,[-.012,-.026,-.06][row],sin(i*TAU/9)*radius))
		vertices.append(ring)
	for row in 2:
		for i in 9:
			var j=(i+1)%9;stone.set_color(Color("595b51").lightened(sin(i*7.2)*.12))
			for v in [vertices[row][i],vertices[row+1][i],vertices[row][j],vertices[row][j],vertices[row+1][i],vertices[row+1][j]]:stone.add_vertex(v)
	for i in 9:
		stone.set_color(Color("666555").lightened(sin(i*5.3)*.08))
		for v in [Vector3(0,-.012,0),vertices[0][(i+1)%9],vertices[0][i]]:stone.add_vertex(v)
	stone.generate_normals();pedestal.mesh=stone.commit()
	var mat=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=1;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;pedestal.material_override=mat;_viewport.add_child(pedestal)
	var ring=MeshInstance3D.new();var disc=CylinderMesh.new();disc.top_radius=.060;disc.bottom_radius=.060;disc.height=.002;disc.radial_segments=24;ring.mesh=disc;ring.position.y=-.008
	var light_mat=StandardMaterial3D.new();light_mat.albedo_color=Color("6b5b36");light_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;ring.material_override=light_mat;_viewport.add_child(ring)
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.27;camera.position=Vector3(.045,.16,.43);_viewport.add_child(camera);camera.look_at(Vector3(0,.066,0));camera.current=true
	resized.connect(_refresh)
func show_item(path:String)->void:
	if not is_instance_valid(_actor) or path==_model_path:return
	_model_path=path
	for child in _actor.get_children():_actor.remove_child(child);child.queue_free()
	if not path.is_empty() and ResourceLoader.exists(path):
		var model=load(path).instantiate();_actor.add_child(model);model.position.y=.018;model.rotation_degrees.y=-8
	_refresh()
func _refresh()->void:
	if _viewport!=null:_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
