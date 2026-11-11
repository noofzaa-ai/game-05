extends RefCounted
## Diamond Mall fashion. Ownership is COUNTED (Boss 2026-11-11, docs/tech/per_card_gear_plan.md): every
## purchase adds one "part:id" entry to Profile.mall_owned, and one copy dresses exactly one class card at a
## time (Profile.card_fashion). Buy 2 to dress 2 cards. A part worn per card (CARD_PARTS) can be bought up to
## one copy per class card; other parts (hats, deferred) stay a single unlock.
## Legacy: Profile.appearance fashion is the old account-wide look and is not counted against copies.
const Options=preload("res://logic/cosmetic_options.gd")
const CardDeck=preload("res://logic/card_deck.gd")
const CARD_PARTS: Array[String] = ["fashion", "fashion_back"]  ## hats stay deferred (CLAUDE.md 2026-10-23)

static func config()->Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmetics/mall.json"))

static func owns(profile,part:String,id:String)->bool:
 return id=="none" or part+":"+id in profile.mall_owned

## How many copies of the piece the account has bought.
static func owned_count(profile,part:String,id:String)->int:
 return profile.mall_owned.count(part+":"+id)

## The most copies worth having: one per class card for card-worn parts, else one.
static func max_copies(part:String)->int:
 return CardDeck.classes().size() if part in CARD_PARTS else 1

## Class cards wearing the piece now.
static func cards_wearing(profile,part:String,id:String)->Array:
 var cards:=[]
 for card in profile.card_fashion:
  if str(profile.card_fashion[card].get(part,"none"))==id: cards.append(card)
 return cards

## Copies bought but not worn by any card.
static func free_copies(profile,part:String,id:String)->int:
 return owned_count(profile,part,id)-cards_wearing(profile,part,id).size()

static func buy(profile,options,part:String,id:String)->Dictionary:
 var prices:Dictionary=config().prices
 if options==null or not prices.has(part) or id=="none" or options.entry(part,id).is_empty():return {"ok":false,"reason":"invalid_cosmetic"}
 if owned_count(profile,part,id)>=max_copies(part):return {"ok":false,"reason":"already_owned"}
 var price:=int(prices[part])
 if profile.diamonds<price:return {"ok":false,"reason":"not_enough_diamonds"}
 profile.diamonds-=price
 profile.mall_owned.append(part+":"+id)
 return {"ok":true,"owned":owned_count(profile,part,id)}

## Dresses class card `card` in piece `id` of `part` ("none" takes it off). The card's old piece frees its
## copy. Refused when every copy is already worn by another card ("no_free_copy").
static func wear_on_card(profile,options,card:String,part:String,id:String)->Dictionary:
 if not profile.card_deck.get("cards",{}).has(card):return {"ok":false,"reason":"invalid_card"}
 if not part in CARD_PARTS or options==null:return {"ok":false,"reason":"invalid_cosmetic"}
 if id!="none" and options.entry(part,id).is_empty():return {"ok":false,"reason":"invalid_cosmetic"}
 var worn:Dictionary=profile.card_fashion.get(card,{})
 if str(worn.get(part,"none"))==id:return {"ok":true}
 if id!="none":
  if owned_count(profile,part,id)<1:return {"ok":false,"reason":"cosmetic_not_owned"}
  if free_copies(profile,part,id)<1:return {"ok":false,"reason":"no_free_copy"}
 worn[part]=id
 if id=="none":worn.erase(part)
 if worn.is_empty():profile.card_fashion.erase(card)
 else:profile.card_fashion[card]=worn
 return {"ok":true}

## The fashion a card wears: {part: id} for every CARD_PARTS part ("none" when bare).
static func card_look(profile,card:String)->Dictionary:
 var look:={}
 for part in CARD_PARTS: look[part]=str(profile.card_fashion.get(card,{}).get(part,"none"))
 return look
