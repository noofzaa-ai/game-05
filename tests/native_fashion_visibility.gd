extends SceneTree
var failures := 0
var checks := 0
func check(label: String,ok: bool) -> void:
 checks+=1
 if not ok:
  failures+=1
  push_error(label)
func _initialize() -> void:
 await process_frame
 var rules=preload("res://logic/item_rules_loader.gd").load_default()
 var cosmetics=preload("res://logic/cosmetic_options.gd").load_default()
 check("cosmetic rules valid",cosmetics.is_valid())
 var model=preload("res://client/characters/studio05_character_model.gd").new()
 root.add_child(model)
 check("native model loaded",model.load_model())
 var rng := RandomNumberGenerator.new()
 rng.seed=42
 var loadout=preload("res://logic/loadout.gd").new(rules)
 for slot in ["hat","shirt","pants","armband","shoes"]:
  loadout.equip(preload("res://logic/item_system.gd").create_item(rules,slot,slot,2,rng,"","armor_ash_steel_"+slot))
 var before: Dictionary=loadout.to_dict()
 var appearance := {"fashion":"purple","fashion_back":"angel_wings_black","fashion_display":"on","wear_shirt":"off","wear_pants":"off","wear_shoes":"off"}
 for mode in ["on","off","on"]:
  check("visibility command accepted "+mode,cosmetics.choose(appearance,"fashion_display",mode))
  check("wings kept in selected options "+mode,appearance.fashion_back=="angel_wings_black")
  var looks=preload("res://client/item_assets.gd").looks(loadout,rules.catalog,"")
  looks.appearance=preload("res://client/item_assets.gd").appearance(appearance)
  model.dress(looks)
  for slot in ["shirt","armband","pants","shoes"]:
   var path: String=model._worn.get(slot,{}).get("path","")
   var expected: String=looks.appearance.fashion.get(slot,"") if mode=="on" else looks[slot]
   check("whole outfit source "+mode+slot,path==expected)
  check("combat helmet visibility "+mode,model._worn.get("hat",{}).get("path","")==("" if mode=="on" else looks.hat))
  check("wing model remains visible "+mode,not str(model._worn.get("back",{}).get("path","")).is_empty())
  check("combat ownership unchanged "+mode,loadout.to_dict()==before)
 check("selecting fashion enables display",cosmetics.choose(appearance,"fashion","red") and appearance.fashion_display=="on")
 check("invalid visibility rejected",not cosmetics.choose(appearance,"fashion_display","forged"))
 appearance.fashion_back="teddy_backpack"
 appearance.fashion_display="off"
 model.set_appearance(preload("res://client/item_assets.gd").appearance(appearance))
 check("non-wing fashion back hidden with outfit",model._worn.get("back",{}).get("path","")=="")
 var camp=preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
 var profile=preload("res://logic/profile.gd").new_player(rules,camp,rng)
 profile.appearance={"fashion":"purple","fashion_back":"angel_wings_black","fashion_display":"on"}
 var trip=preload("res://logic/run.gd").start(profile,camp)
 var state := {"profile":profile,"rules":rules,"camp":camp,"run":trip,"location":"stage","cosmetics":cosmetics}
 var before_profile: Dictionary=profile.to_dict().duplicate(true)
 var command_result=preload("res://logic/commands.gd").apply(state,{"type":"appearance","part":"fashion_display","choice":"off"},rng)
 check("visibility allowed mid-stage",command_result.get("ok",false))
 before_profile.appearance.fashion_display="off"
 check("visibility changes only appearance",profile.to_dict()==before_profile)
 command_result=preload("res://logic/commands.gd").apply(state,{"type":"appearance","part":"fashion","choice":"red"},rng)
 check("other outfit changes still restricted in-stage",not command_result.get("ok",false))
 command_result=preload("res://logic/commands.gd").apply(state,{"type":"appearance","part":"fashion_display","choice":"on","gold":999999},rng)
 check("forged extra fields rejected",not command_result.get("ok",false) and profile.to_dict()==before_profile)
 print("NATIVE FASHION VISIBILITY: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
