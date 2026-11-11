#!/usr/bin/env python3
"""Apply assets_spec.md GPU imports. Optional art/ directories restrict scope; defaults: hub/props/maps."""
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[2]
selected=sys.argv[1:]
if selected:
 sources=[]
 for folder in selected:
  directory=(ROOT/folder).resolve()
  if not directory.is_relative_to((ROOT/'art').resolve()) or not directory.is_dir():raise ValueError('Expected existing directory under art/: '+folder)
  sources += sorted(directory.rglob('*.png'))
else:
 sources=sorted((ROOT/'art/npcs').glob('*.png'))
 sources += sorted((ROOT/'art/props').rglob('*.png'))
 sources += sorted((ROOT/'art/maps').rglob('*.png'))
for source in sources:
 path=Path(str(source)+'.import')
 if not path.is_file():raise RuntimeError('Import texture first: '+str(source))
 original=path.read_text()
 s=original
 data_map=any(role in source.stem.lower() for role in ('normal','metallic','roughness','occlusion')) or source.stem.lower().endswith(('_mr','_orm'))
 cap=512 if data_map else 1024
 values={'compress/mode':2,'process/size_limit':cap,'mipmaps/generate':'true','detect_3d/compress_to':0,
         'compress/normal_map':1 if source.stem.endswith('_normal')else 0}
 for key,value in values.items():
  s,count=re.subn(r'(?m)^'+re.escape(key)+r'=.*$',key+'='+str(value),s)
  if count!=1:raise RuntimeError('Missing setting '+key)
 if s != original:
  path.write_text(s)
 # A headless scan can retain embedded-image caches after editing .import parameters.
 # Invalidate only reproducible cache hashes for changed or still non-GPU imports.
 if s != original or 'path.s3tc=' not in s or 'path.etc2=' not in s:
  source.touch()  # Make the cached filesystem scan notice unchanged image bytes.
  for cache in (ROOT/'.godot/imported').glob(source.name+'-*.md5'):
   cache.unlink()
 print(source.name,str(cap)+', GPU compression')
# Format-specific textures must be outside core so phones download only ETC2, PCs S3TC.
if selected:sys.exit(0)
path=ROOT/'tools/web/pack_layout.json';layout=json.loads(path.read_text())
pack=next(p for p in layout['packs']if p['name']=='stages')
for folder in ['res://art/npcs/', 'res://art/maps/']:
 if folder not in pack['include']:pack['include'].append(folder)
path.write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
