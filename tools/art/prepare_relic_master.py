#!/usr/bin/env python3
"""Native Godot geometry + read-only FBX data-map extraction; no Blender dependency."""
import argparse,hashlib,io,json,struct,subprocess,sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/skills'))
from shrink_skills import Glb

def embedded_videos(source):
    data=source.read_bytes();assert data.startswith(b'Kaydara FBX Binary')
    wide=struct.unpack_from('<I',data,23)[0]>=7500;header='<QQQB' if wide else '<IIIB';size=25 if wide else 13
    def node(offset):
        end,count,plen,nlen=struct.unpack_from(header,data,offset)
        if not end:return None,offset+size
        pos=offset+size;name=data[pos:pos+nlen].decode();pos+=nlen;props=[]
        for _ in range(count):
            t=chr(data[pos]);pos+=1
            if t in 'SR':
                length=struct.unpack_from('<I',data,pos)[0];pos+=4;value=data[pos:pos+length];pos+=length
                props.append(value.decode(errors='replace') if t=='S' else value)
            elif t in 'YCFDIL':
                fmt={'Y':'h','C':'?','F':'f','D':'d','I':'i','L':'q'}[t];props.append(struct.unpack_from('<'+fmt,data,pos)[0]);pos+=struct.calcsize(fmt)
            elif t in 'fdlibc':
                _,_,length=struct.unpack_from('<III',data,pos);pos+=12+length;props.append(None)
            else:raise ValueError('Unknown FBX property '+t)
        children=[]
        while pos<end-size:
            child,nxt=node(pos)
            if child is None:break
            children.append(child);pos=nxt
        return (name,props,children),end
    pos=27
    def walk(row):
        name,props,children=row
        if name=='Video':
            fields={c[0]:c[1] for c in children}
            filename=fields.get('RelativeFilename',fields.get('Filename',['']))[0]
            content=fields.get('Content',[None])[0]
            if isinstance(content,bytes):yield filename,content
        for child in children:yield from walk(child)
    while pos<len(data)-size:
        row,pos=node(pos)
        if row is None:break
        yield from walk(row)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--use-existing-export',action='store_true');args=ap.parse_args()
    source=ROOT.parent.parent/'assets/relic_master.fbx';before=hashlib.sha256(source.read_bytes()).hexdigest()
    if not args.use_existing_export:subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(ROOT),'--script','res://tools/art/prepare_relic_master.gd'],check=True,timeout=120)
    asset=ROOT/'art/npcs/relic_master/relic_master.glb'
    subprocess.run([sys.executable,str(ROOT/'tools/art/apply_texture_budget.py'),str(asset)],check=True)
    original=ROOT/'art_source/npcs/relic_master';original.mkdir(parents=True,exist_ok=True)
    maps={}
    for filename,content in embedded_videos(source):
        for role in ['roughness','metallic']:
            if role in filename.lower():
                (original/(role+'.png')).write_bytes(content);image=Image.open(io.BytesIO(content)).convert('L');image.thumbnail((512,512),Image.Resampling.LANCZOS);maps[role]=image
    assert set(maps)=={'roughness','metallic'},'Original MR maps must be recovered before acceptance'
    assert maps['roughness'].size==maps['metallic'].size
    packed=Image.merge('RGB',(Image.new('L',maps['roughness'].size,255),maps['roughness'],maps['metallic']));buf=io.BytesIO();packed.save(buf,format='PNG',optimize=True)
    g=Glb(asset);image=len(g.j['images']);g.j['images'].append({'name':'relic_master_mr','mimeType':'image/png','bufferView':0});g.new_images[image]=(buf.getvalue(),'image/png')
    texture=len(g.j['textures']);g.j['textures'].append({'source':image})
    for material in g.j['materials']:
        material['pbrMetallicRoughness'].update(metallicRoughnessTexture={'index':texture},metallicFactor=0.35,roughnessFactor=1)
        if 'normalTexture' in material:material['normalTexture']['scale']=1
    tmp=asset.with_suffix('.tmp.glb');g.save(tmp);tmp.replace(asset)
    report=json.loads((asset.parent/'asset.json').read_text());report.update(source_bytes=source.stat().st_size,source_sha256=before,glb_bytes=asset.stat().st_size,texture_budget={'color':1024,'normal':512,'metallic_roughness':512},materials='Original embedded MR restored(G=roughness,B=metallic), normal1, muted metallic0.35')
    (asset.parent/'asset.json').write_text(json.dumps(report,indent=2)+'\n')
    assert hashlib.sha256(source.read_bytes()).hexdigest()==before
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
