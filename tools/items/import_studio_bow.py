#!/usr/bin/env python3
"""Publish unchanged Studio bow + native motion carriers; never rebuild/rebind its rig."""
from pathlib import Path
import argparse, hashlib, json, shutil
GAME=Path(__file__).resolve().parents[2]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--studio-root',type=Path,default=GAME.parent);args=parser.parse_args();source=args.studio_root.resolve()
 files=[('art/items/weapons/bow.glb','art/items/weapons/bow.glb')]
 for name in ['bow_motion','bow_run_motion','bow_dash_motion']:
  for ext in ['glb','json']:files.append((f'art/characters/reference-native/bow/{name}.{ext}',f'art/animations/bow/{name}.{ext}'))
 for src,_ in files:
  if not (source/src).is_file():raise SystemExit('Missing Studio asset: '+src)
 source_meta=json.loads((source/'art/items/weapons/bow.json').read_text())
 for src,dst in files:
  target=GAME/dst;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/src,target)
 meta={**source_meta,'source_status':source_meta['status'],'status':'ready','gameplay_projectile':True,'gameplay_config':'res://data/combat/weapons.json'}
 (GAME/'art/items/weapons/bow.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
 manifest=GAME/'art/items/item_manifest.json';data=json.loads(manifest.read_text());entry={**meta,'category':'weapons','asset_path':'res://art/items/weapons/bow.glb'}
 data['items']=[row for row in data['items'] if row['id']!=entry['id']]+[entry];manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 report={'source':'Studio native bow','rig':'unchanged native hierarchy/weights/rest; no retargeting','files':[{'source':src,'game':dst,'sha256':hashlib.sha256((GAME/dst).read_bytes()).hexdigest()} for src,dst in files]}
 (GAME/'build').mkdir(exist_ok=True);(GAME/'build/studio-bow-import.json').write_text(json.dumps(report,indent=2)+'\n')
 print('Published Studio bow, three native motion carriers and timing metadata. Icon: Godot tools/shots/bow_icon.gd')
if __name__=='__main__':main()
