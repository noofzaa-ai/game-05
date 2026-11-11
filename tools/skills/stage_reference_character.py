"""Stage Studio exports for opt-in Godot review. Does not change the production model."""
from pathlib import Path
import json,shutil,hashlib
ROOT=Path(__file__).resolve().parents[2];SOURCE=ROOT.parent/'art/characters/reference-studio';OUT=ROOT/'art/characters/reference-studio';OUT.mkdir(parents=True,exist_ok=True)
source=SOURCE/'reference_studio.glb';shutil.copy2(source,OUT/source.name)
meta={}
for name,row in json.loads((SOURCE/'animation_report.json').read_text()).items():
 meta[name]={'length':row['duration_s'],'loop':name.startswith(('Stand','Pose','Walk','Run'))}
(OUT/'reference_studio.json').write_text(json.dumps(meta,indent=2)+'\n')
(OUT/'staging.json').write_text(json.dumps({'enabled_by_default':False,'height_m':1.35,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'clips':list(meta),'scope':'Opt-in local character adapter; no account, inventory, gameplay, or production model migration.'},indent=2)+'\n')
