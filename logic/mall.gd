extends RefCounted
const Options=preload("res://logic/cosmetic_options.gd")
static func config()->Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmetics/mall.json"))
static func owns(profile,part:String,id:String)->bool:
 return id=="none" or part+":"+id in profile.mall_owned
static func buy(profile,options,part:String,id:String)->Dictionary:
 var prices:Dictionary=config().prices
 if options==null or not prices.has(part) or options.entry(part,id).is_empty():return {"ok":false,"reason":"invalid_cosmetic"}
 if owns(profile,part,id):return {"ok":false,"reason":"already_owned"}
 var price:=int(prices[part])
 if profile.diamonds<price:return {"ok":false,"reason":"not_enough_diamonds"}
 profile.diamonds-=price
 profile.mall_owned.append(part+":"+id)
 return {"ok":true}
