"""Replace legacy armor catalog with native heavy/light/cloth; explicit one-to-one save aliases.
One-time migration: it rebuilds every non-weapon entry (it would drop the off-hand shields). To only rename
the pieces use tools/items/armor_names.py."""
from pathlib import Path
import json,sys
sys.path.insert(0,str(Path(__file__).resolve().parent));import armor_names
ROOT=Path(__file__).resolve().parents[2]
def read(p):return json.loads((ROOT/p).read_text())
def write(p,d):(ROOT/p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
c=read('data/items/catalog.json');old={k:v for k,v in c['items'].items() if v['slot']!='weapon'};c['items']={k:v for k,v in c['items'].items() if v['slot']=='weapon'}
families={'obsidian':('อัศวินดำ','obsidian_gold'),'royal':('ราชันสุริยะ','royal_gold'),'ash':('อัศวินเถ้า','ash_steel')}
slots={'head':('hat','หมวก','HP'),'shirt':('shirt','เสื้อเกราะ','DEF'),'pants':('pants','กางเกง','HP'),'arms':('armband','ปลอกแขน','DEF'),'shoes':('shoes','รองเท้า','DEF')}
sets=read('data/items/sets.json');previous_sets=sets['sets'];sets['sets']={}
for family,(label,heavy) in families.items():
 for kind,style in [('heavy',heavy),('light',family+'_leather'),('cloth',family+'_cloth')]:
  set_id='armor_'+style
  bonuses=previous_sets.get(set_id,previous_sets.get('armor_dark_knight_01' if family=='obsidian' else 'armor_gilded_sentinel_01' if family=='royal' else 'armor_white_blue_aegis_01',{})).get('bonuses',[])
  set_en,set_th=armor_names.set_names(family,kind);sets['sets'][set_id]={'name':set_en,'name_th':set_th,'bonuses':bonuses}
  for part,(slot,name,stat) in slots.items():
   identity='armor_'+style+'_'+slot
   en,th=armor_names.piece_names(family,slot,kind) # English name, Thai kept (tools/items/armor_names.py)
   c['items'][identity]={'asset_id':identity,'name':en,'name_th':th,'slot':slot,'set':set_id,'drop_level':1,'armor_class':kind,'main_stat':stat,'asset_path':'res://art/armor/'+style+'/'+part+'.glb','icon_path':'res://art/armor/'+style+'/icon-'+part+'.png','source_style':style}
legacy_family={'scout':'ash_steel','knight':'obsidian_gold','sentinel':'royal_gold','aegis':'ash_steel'}
aliases={identity:'armor_'+legacy_family[identity.split('_')[0]]+'_'+row['slot'] for identity,row in old.items() if identity.split('_')[0] in legacy_family}
existing=ROOT/'data/items/armor_migration.json'
if existing.exists():aliases={**json.loads(existing.read_text()).get('aliases',{}),**aliases}
# Explicit constants also resolve new-player legacy starter references.
write('data/items/armor_migration.json',{'version':2,'aliases':aliases,'allowed_armor':{k:v['slot'] for k,v in c['items'].items() if v.get('armor_class')},'plain_slots':{slot:'armor_ash_steel_'+slot for slot in ['hat','shirt','pants','armband','shoes']}})
sets['starter_armor_sets']=['armor_obsidian_gold','armor_royal_gold','armor_ash_steel'];write('data/items/catalog.json',c);write('data/items/sets.json',sets)
t=read('data/items/equipment_tuning.json');m=t['mobility'];m['set_classes']={r['set']:r['armor_class'] for r in c['items'].values() if 'armor_class'in r};m['armor_penalties']['cloth']=.05
m['base_move_multiplier']=1.0 # No unapproved global speed cut; class/weapon penalties apply.
t['armor']={'class_base_multipliers':{'heavy':{'HP':1.0,'DEF':1.0},'light':{'HP':.7,'DEF':.6},'cloth':{'HP':.4,'DEF':.25}}};write('data/items/equipment_tuning.json',t)
