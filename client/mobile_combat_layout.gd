extends RefCounted
## One mobile layout for the action overlay and the four-skill HUD. Coordinates relative to attack.
## Large attack lower-right; seven smaller circles curve above and to its left like Boss's reference.
const OFFSETS={"light":Vector2.ZERO,"heavy":Vector2(-51,-51),"dodge":Vector2(-67,0),"guard":Vector2(0,-72)}
const SKILL_OFFSETS=[Vector2(-121,0),Vector2(-116,-52),Vector2(-84,-99),Vector2(-31,-122)]
static func regions(size:Vector2,unit:float=1.0,minimum:float=44.0)->Dictionary:
 # Keep 44CSS circles separate even on the smallest landscape viewport.
 unit=maxf(unit,minimum/44.0)
 var anchor=size-Vector2(56,56)*unit
 var result={}
 for action in OFFSETS:
  var diameter=maxf(minimum,(80.0 if action=="light" else 44.0)*unit)
  result[action]=Rect2(anchor+OFFSETS[action]*unit-Vector2.ONE*diameter*.5,Vector2.ONE*diameter)
 var skills=[]
 for offset in SKILL_OFFSETS:
  skills.append(Rect2(anchor+offset*unit-Vector2.ONE*maxf(minimum,44*unit)*.5,Vector2.ONE*maxf(minimum,44*unit)))
 result.skills=skills
 # Legacy builds only: same small-circle positions, never shown alongside the four-slot HUD.
 result.special=skills[0];result.ultimate=skills[2]
 return result
