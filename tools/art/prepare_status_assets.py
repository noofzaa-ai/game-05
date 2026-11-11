import sys,json,io
from pathlib import Path
from PIL import Image
# Run from any directory; source bundles are preserved separately in ex/.
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tools/skills'))
from shrink_skills import Glb
report=[]
for status in ['burn','bleed','freeze','chill','shock','stun']:
    src=root/'ex/status_vfx_review'/status/'effect.glb'
    dest=root/'art/skill_system/status_vfx'/status
    dest.mkdir(parents=True,exist_ok=True)
    g=Glb(src)
    for i in range(len(g.j.get('images',[]))):
        im=Image.open(io.BytesIO(g.image_bytes(i))).convert('RGBA')
        if max(im.size)>128:
            im.thumbnail((128,128),Image.Resampling.LANCZOS)
            buf=io.BytesIO();im.save(buf,format='PNG',optimize=True)
            g.new_images[i]=(buf.getvalue(),'image/png')
    g.save(dest/'effect.glb')
    report.append(dict(status=status,source_bytes=src.stat().st_size,runtime_bytes=(dest/'effect.glb').stat().st_size))
(root/'art/skill_system/status_vfx/import_report.json').write_text(json.dumps(report,indent=2))
print(report)
