extends RefCounted
## Diamond Mall. It sells what data/cosmetics/mall.json "prices" lists (part -> diamonds); every purchase adds
## one "part:id" entry to Profile.mall_owned. The list is empty now: Boss 2026-11-13 removed the old fashion
## pieces (outfits, hats, back items) because they fit the old character model only.
## Old saves: refund_legacy() drops every owned copy of a removed part and pays back its old price
## (mall.json "legacy_refund"). Profile.from_dict calls it on load.
const Options=preload("res://logic/cosmetic_options.gd")

static func config()->Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmetics/mall.json"))

static func owns(profile,part:String,id:String)->bool:
 return id=="none" or part+":"+id in profile.mall_owned

## How many copies of the piece the account has bought.
static func owned_count(profile,part:String,id:String)->int:
 return profile.mall_owned.count(part+":"+id)

## The parts that were sold before and are refunded on load: part -> old price.
static func legacy_prices()->Dictionary:
 return config().get("legacy_refund",{}).get("prices",{})

## Splits a saved mall_owned list: {"kept": entries of parts still sold, "diamonds": refund for the removed
## ones, "refunded": the removed entries}. Every copy is refunded once; an entry of an unknown part is dropped
## without pay (nothing could have been paid for it).
static func refund_legacy(saved_owned:Array)->Dictionary:
 var legacy:=legacy_prices()
 var sold:Dictionary=config().get("prices",{})
 var kept:=[]
 var refunded:=[]
 var diamonds:=0
 for entry in saved_owned:
  var part:=str(entry).get_slice(":",0)
  if sold.has(part):
   kept.append(str(entry))
  elif legacy.has(part):
   refunded.append(str(entry))
   diamonds+=int(legacy[part])
 return {"kept":kept,"diamonds":diamonds,"refunded":refunded}

static func buy(profile,options,part:String,id:String)->Dictionary:
 var prices:Dictionary=config().get("prices",{})
 if options==null or not prices.has(part) or id=="none" or options.entry(part,id).is_empty():return {"ok":false,"reason":"invalid_cosmetic"}
 if owned_count(profile,part,id)>=1:return {"ok":false,"reason":"already_owned"}
 var price:=int(prices[part])
 if profile.diamonds<price:return {"ok":false,"reason":"not_enough_diamonds"}
 profile.diamonds-=price
 profile.mall_owned.append(part+":"+id)
 return {"ok":true,"owned":owned_count(profile,part,id)}
