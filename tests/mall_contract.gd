extends SceneTree
func _initialize()->void:
 var source=preload("res://data/perf/scenario.gd").new()
 var p=source.profile
 var options=preload("res://logic/cosmetic_options.gd").load_default()
 var commands=preload("res://logic/commands.gd")
 var state={"profile":p,"rules":source.rules,"camp":source.camp,"location":"camp","cosmetics":options}
 var rng=RandomNumberGenerator.new()
 p.mall_owned=[];p.diamonds=9999
 var old_gold=p.stash.gold
 var denied=commands.apply(state,{"type":"appearance","part":"fashion","choice":"purple"},rng)
 assert(not denied.ok)
 for row in [["fashion","purple",150],["fashion_hat","cat",50],["fashion_back","angel_wings",100]]:
  var before=p.diamonds
  var result=commands.apply(state,{"type":"mall_buy","part":row[0],"choice":row[1]},rng)
  assert(result.ok)
  assert(p.diamonds==before-row[2])
  assert(not commands.apply(state,{"type":"mall_buy","part":row[0],"choice":row[1]},rng).ok)
  assert(p.diamonds==before-row[2])
  assert(commands.apply(state,{"type":"appearance","part":row[0],"choice":row[1]},rng).ok)
 assert(p.stash.gold==old_gold)
 var loaded=preload("res://logic/profile.gd").from_dict(p.to_dict(),source.rules,source.camp)
 assert(loaded.diamonds==p.diamonds and loaded.mall_owned==p.mall_owned)
 var legacy=p.to_dict();legacy.erase("diamonds");legacy.erase("mall_owned")
 loaded=preload("res://logic/profile.gd").from_dict(legacy,source.rules,source.camp)
 assert(loaded.diamonds==9999)
 assert(preload("res://logic/mall.gd").owns(loaded,"fashion","purple"))
 p.diamonds=0
 assert(not commands.apply(state,{"type":"mall_buy","part":"fashion","choice":"red"},rng).ok)
 state.location="stage"
 assert(not commands.apply(state,{"type":"mall_buy","part":"fashion","choice":"red"},rng).ok)
 assert(load("res://client/look_panel.gd")!=null)
 assert(load("res://client/characters/studio05_character_model.gd")!=null)
 var runner=preload("res://server/profile/runner.gd").new()
 var request={"v":1,"state":null,"seed":"123456789abcdef","name":"","command":null}
 var first:Dictionary=runner.execute(request)
 assert(first.ok and first.profile.diamonds==9999)
 request.state={"profile":first.profile,"rng_state":first.rng_state}
 request.command={"type":"mall_buy","part":"fashion","choice":"purple"}
 var bought:Dictionary=runner.execute(request)
 assert(bought.ok and bought.profile.diamonds==9849)
 request.state={"profile":bought.profile,"rng_state":bought.rng_state};request.command=null
 var readback:Dictionary=runner.execute(request)
 assert(readback.ok and readback.profile.diamonds==9849)
 print("MALL PASS: authoritative debit, no double charge, ownership/equip gate, persistence, one-time migration, no Gold, location and balance rejection")
 quit()
