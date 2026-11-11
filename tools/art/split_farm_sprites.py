"""Mechanical extraction of approved-layout RGBA artwork; no runtime source sheet.
Every plant exports a 256px canvas, root at (128,240); icons128px.
"""
from pathlib import Path
import json
from collections import deque
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sheet=Image.open(ROOT/'art_source/farm/crops-toned-sheet-v1.png').convert('RGBA')
out=ROOT/'art/props/farm_crops';out.mkdir(parents=True,exist_ok=True)
report={}
for row,crop in enumerate(['carrot','potato','herb']):
 for col in range(4):
  tile=sheet.crop((col*sheet.width//4,row*sheet.height//3,(col+1)*sheet.width//4,(row+1)*sheet.height//3))
  alpha=tile.getchannel('A')
  # Discard disconnected nearly transparent edge dust from the keyed reference.
  alpha=alpha.point(lambda a:0 if a<96 else a)
  # Keep the primary connected object; discard other-cell fragments and alpha dust.
  pixels=alpha.load();seen=set();largest=[]
  for y in range(tile.height):
   for x in range(tile.width):
    if pixels[x,y]<96 or (x,y) in seen:continue
    component=[];pending=deque([(x,y)]);seen.add((x,y))
    while pending:
     u,v=pending.popleft();component.append((u,v))
     for dx,dy in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]:
      n=(u+dx,v+dy)
      if 0<=n[0]<tile.width and 0<=n[1]<tile.height and n not in seen and pixels[n[0],n[1]]>=96:seen.add(n);pending.append(n)
    if len(component)>len(largest):largest=component
  clean=Image.new('L',tile.size);mask=clean.load()
  for x,y in largest:mask[x,y]=pixels[x,y]
  alpha=clean
  tile.putalpha(alpha)
  box=alpha.getbbox()
  tile=tile.crop(box)
  is_icon=col==3
  size=128 if is_icon else 256
  limit=112 if is_icon else [132,180,220][col]
  factor=min(limit/tile.height,(size-24)/tile.width)
  tile=tile.resize((round(tile.width*factor),round(tile.height*factor)),Image.Resampling.LANCZOS)
  target=Image.new('RGBA',(size,size))
  if is_icon:pos=((size-tile.width)//2,(size-tile.height)//2)
  else:
   a=tile.getchannel('A');xs=[]
   for y in range(max(0,tile.height-8),tile.height):
    xs.extend(x for x in range(tile.width) if a.getpixel((x,y))>128)
   root=sum(xs)/len(xs) if xs else tile.width/2
   # Root centering can shift an asymmetric canopy beyond the canvas.
   # Fit BOTH sides around the root before compositing, never clip the leaves.
   fit=min(1.0,116/max(root,1),116/max(tile.width-root,1))
   if fit<1:
    tile=tile.resize((max(1,round(tile.width*fit)),max(1,round(tile.height*fit))),Image.Resampling.LANCZOS)
    root*=fit
   pos=(round(128-root),240-tile.height)
  target.alpha_composite(tile,pos)
  name=f'{crop}_icon.png' if is_icon else f'{crop}_stage_{col+1}.png'
  target.save(out/name,optimize=True)
  report[name]={'size':size,'root':[128,240] if not is_icon else None,'bytes':(out/name).stat().st_size}
(out/'sprites.json').write_text(json.dumps(report,indent=2)+'\n')
print('12 RGBA files;',sum(x['bytes'] for x in report.values()),'PNG bytes')
