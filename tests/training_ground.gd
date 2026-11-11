extends SceneTree
const Training=preload("res://logic/training_ground.gd")
const Inputs=preload("res://logic/sim_input.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var combat=load("res://logic/combat_data_loader.gd").load_default()
 var world=load("res://logic/sim_world.gd").new();world.half_width=30;world.half_depth=40
 world.add_solid(AABB(Vector3(-40,-1,-50),Vector3(80,1,100)))
 var training=Training.new(world,combat,Vector3.ZERO)
 var build=load("res://logic/skill_build.gd").initial("blade")
 training.configure({"ATK":200,"HP":1000},"blade",build)
 training.step(Inputs.new());assert(not training.enabled)
 assert(training.sim.runs.is_empty() and training.sim.item_rules==null and training.sim.loot_data==null)
 training.sim.bodies[1].position=Training.CENTER+Vector3(0,0,-1)
 training.step(Inputs.new());assert(training.enabled and training.sim.skill_system!=null)
 var input=Inputs.new();input.aim=Vector2(0,-1);input.aim_distance=2;input.skill_slot=0
 training.step(input)
 var status_seen:=false
 for i in range(240):
  training.step(Inputs.new())
  status_seen=status_seen or training.sim.skill_system.targets[903].statuses.has("burn")
 print("TRAINING damage ",training.damage," hits ",training.hits)
 assert(training.hits>0,"Actual skill must hit a dummy")
 assert(training.hits_by_target.size()>=3,"Area skill must hit several separately tracked dummies")
 assert(status_seen,"Actual status applies to a dummy")
 for index in range(5):
  var id:int=Training.DUMMY_IDS[index]
  assert(training.sim.bodies[id].position==Training.dummy_position(index))
  assert(training.sim.fighters[id].hp==training.sim.fighters[id].max_hp())
 training.reset();assert(training.hits==0 and training.damage==0 and training.hits_by_target.is_empty())
 assert(training.sim.skill_system.targets[903].statuses.is_empty())
 assert(training.sim.skill_system.casters[1].cooldowns.is_empty())
 assert(training.sim.fighters[1].energy==training.sim.fighters[1].max_energy())
 training.sim.bodies[1].position=Vector3.ZERO;training.step(Inputs.new())
 assert(not training.enabled and training.sim.skill_system==null)
 input.light=true;input.skill_slot=0;training.step(input)
 assert(training.sim.fighters[1].state==0,"Outside training combat is disabled")
 assert(training.sim.runs.is_empty())
 training.dispose()
 assert(load("res://client/hub.gd")!=null and load("res://client/training_arena.gd")!=null)
 print("TRAINING PASS: five targets, actual skills, no loot/wear/Run, fixed target positions, reset, auto enter/exit, no combat outside")
 quit()
