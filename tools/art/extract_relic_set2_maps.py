"""Read-only extraction of embedded data maps; does not save/export Blender geometry."""
import bpy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.import_scene.fbx(filepath=str(ROOT.parent.parent/'assets/relic_set2.fbx'))
out=ROOT/'art_source/relic_set2/source_maps';out.mkdir(parents=True,exist_ok=True)
for image in bpy.data.images:
 if image.packed_file and any(role in image.name.lower() for role in ['metallic','roughness']):
  (out/(image.name.replace('/','_')+'.png')).write_bytes(image.packed_file.data)
