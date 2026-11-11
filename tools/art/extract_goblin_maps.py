"""Read only FBX data maps, no geometry export."""
import bpy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
for id in ['gobbin_base','gobbin_relic']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.fbx(filepath=str(ROOT.parent.parent/'assets'/f'{id}.fbx'))
 out=ROOT/'art_source/props/goblin_base'/id;out.mkdir(parents=True,exist_ok=True)
 for image in bpy.data.images:
  if image.packed_file and any(role in image.name.lower() for role in ['metallic','roughness']):(out/(image.name.replace('/','_')+'.png')).write_bytes(image.packed_file.data)
