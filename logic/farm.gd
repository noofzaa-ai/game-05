extends RefCounted
static func config() -> Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("res://data/camp/farm.json"))
static func unlocked(profile)->bool:
 return profile!=null and profile.camp_level>=int(config().required_level)
static func apply(profile, command: Dictionary, now: int) -> Dictionary:
 var data := config()
 if not unlocked(profile): return {"ok":false,"error":"camp_level_required"}
 if now <= 0: return {"ok":false,"error":"clock_unavailable"}
 var index := int(command.plot)
 if index < 0 or index >= int(data.plots): return {"ok":false,"error":"invalid_plot"}
 var key := str(index)
 var plots: Dictionary = profile.farm.get("plots",{}).duplicate(true)
 var seeds: Dictionary = profile.farm.get("seeds",{}).duplicate(true)
 var produce: Dictionary = profile.farm.get("produce",{}).duplicate(true)
 if command.type == "farm_harvest":
  if not plots.has(key): return {"ok":false,"error":"empty_plot"}
  var planted: Dictionary = plots[key]
  var crop: Dictionary = data.crops.get(planted.crop,{})
  if crop.is_empty() or now < int(planted.planted_at)+int(crop.seconds): return {"ok":false,"error":"not_ready"}
  produce[planted.crop] = int(produce.get(planted.crop,0))+int(crop.yield)
  plots.erase(key)
 else:
  if not data.crops.has(command.crop): return {"ok":false,"error":"invalid_crop"}
  var crop: Dictionary = data.crops[command.crop]
  if command.type == "farm_seed":
   if profile.stash.gold < int(crop.seed_price): return {"ok":false,"error":"not_enough_gold"}
   profile.stash.gold -= int(crop.seed_price)
   seeds[command.crop] = int(seeds.get(command.crop,0))+1
  else:
   if plots.has(key): return {"ok":false,"error":"plot_occupied"}
   if int(seeds.get(command.crop,0))<1: return {"ok":false,"error":"no_seeds"}
   seeds[command.crop] = int(seeds[command.crop])-1
   plots[key] = {"crop":command.crop,"planted_at":now}
 profile.farm = {"plots":plots,"seeds":seeds,"produce":produce}
 return {"ok":true,"changes":["farm"],"result":{}}
