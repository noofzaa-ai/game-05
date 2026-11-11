#!/usr/bin/env python3
"""Publish texture-only rebake to the unchanged <=1000tri runtime geometry."""
import json,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/skills'));from shrink_skills import Glb
out=ROOT/'art/relics/goblin';work=ROOT/'art_source/props/goblin_base/rebake1000'
for name in ['goblin_medallion','goblin_lantern']:
 for role in ['colour','normal','mr']:
  p=out/'baked'/(name+'_'+role+'.png');raw=work/(name+'_'+role+'.npy')
  if raw.exists():values=np.load(raw)
  else:
   # Compatibility for first float-PNG trial: undo Blender's applied sRGB display transform once.
   backup=work/(p.stem+'_float_png_original.png')
   if not backup.exists():backup.write_bytes(p.read_bytes())
   values=np.asarray(Image.open(backup).convert('RGB'),dtype=np.float32)/255
   values=np.where(values<=.04045,values/12.92,((values+.055)/1.055)**2.4)
  im=Image.fromarray(np.uint8(np.clip(values*255+.5,0,255)),'RGB');cap=512 if role=='colour' else 256
  if im.size!=(cap,cap):im=im.resize((cap,cap),Image.Resampling.LANCZOS)
  im.save(p,optimize=True)
 g=Glb(work/(name+'_uv.glb'));g.save(out/'models'/(name+'.glb'))
print('PUBLISHED texture rebake on998tri per relic')

# Retire obsolete shared UV textures outside runtime export; the two baked sets are now referenced.
import shutil
shared=out/'shared'
if shared.exists():
 archive=work/'unbaked_shared';archive.mkdir(exist_ok=True)
 for file in shared.iterdir():
  if file.is_file():shutil.copy2(file,archive/file.name)
 shutil.rmtree(shared)
report=json.loads((out/'runtime.json').read_text())
for name,row in report['models'].items():row['bytes']=(out/'models'/(name+'.glb')).stat().st_size
report.update(geometry='998tri each, fresh per-face UVs with high-source BVH projection; no geometry export from Blender',textures={'colour_each':512,'normal_each':256,'mr_each':256},baked_png_bytes=sum(p.stat().st_size for p in (out/'baked').glob('*.png')),visual_status='Native front/45/side reviewed; user acceptance pending; coarse silhouette remains',pipeline=['prepare_goblin_relic_runtime.py','prepare_relic_rebake.py','bake_relic_surface.py','finish_relic_rebake.py'])
(out/'runtime.json').write_text(json.dumps(report,indent=2)+'\n')
