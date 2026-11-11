extends SceneTree
## Regression: dash endpoint inside a wall used to launch the actor onto its 7m top.
const Training=preload("res://logic/training_ground.gd")
const Inputs=preload("res://logic/sim_input.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var world=load("res://logic/sim_world.gd").new();world.half_width=30;world.half_depth=40
 world.add_solid(AABB(Vector3(-60,-1,-60),Vector3(120,1,120)))
 # Training north perimeter and fence, same geometry as the camp runtime.
 world.add_solid(AABB(Vector3(-33.5,-1,-60),Vector3(20,8,58)))
 world.add_solid(AABB(Vector3(-25.25,0,-2.25),Vector3(14.5,1.35,.5)))
 var training=Training.new(world,load("res://logic/combat_data_loader.gd").load_default(),Vector3(-18,0,3))
 var Build=load("res://logic/skill_build.gd")
 for style in ["blade","dagger","spear","hammer","staff","bow"]:
  for skill in ["storm_blades","flame_dash"]:
   var build=Build.initial(style);build.skills[0]={"skill":skill,"shape":"","effect":""}
   training.sim.bodies[1].position=Vector3(-18,0,3);training.configure({"ATK":200,"HP":1000,"STAMINA":1000},style,build)
   training.step(Inputs.new())
   var cast=Inputs.new();cast.aim=Vector2(0,-1);cast.aim_distance=2;cast.skill_slot=0;training.step(cast)
   for i in range(180):
    training.step(Inputs.new())
    assert(training.sim.bodies[1].position.y>=0 and training.sim.bodies[1].position.y<1.6,"Dash must not launch onto north wall or fall through floor")
   assert(training.sim.bodies[1].position.z>=-1.349,"Full body must stay outside north fence")
 # Ordinary jumping remains available, lands naturally; already fallen state recovers.
 training.sim.bodies[1].position=Vector3(-18,0,5);training.reset();training.step(Inputs.new())
 var peak:=0.0
 for i in range(120):
  var frame=Inputs.new();frame.jump=i==1;training.step(frame);peak=maxf(peak,training.sim.bodies[1].position.y)
 assert(peak>1 and peak<1.6 and training.sim.bodies[1].grounded)
 training.sim.bodies[1].position.y=-4;training.sim.bodies[1].velocity.y=-80
 training.step(Inputs.new());assert(training.sim.bodies[1].position.y==0 and training.sim.bodies[1].grounded)
 assert(training.sim.runs.is_empty())
 training.dispose();print("TRAINING FLOOR PASS: 12 dash/fence cases, normal jump/landing, below-floor recovery, no Run/save")
 quit()
