#!/usr/bin/env python3
"""Reject a Web release missing a purchasable hat, even if native files exist."""
from pathlib import Path
import gzip,struct,json,re,sys
root=Path(__file__).resolve().parents[2];folder=Path(sys.argv[1]) if len(sys.argv)>1 else root/'build/web';m=json.loads((folder/'packs.json').read_text());p=next(x for x in m['packs'] if x['name']=='characters' and not x['format'])
b=(folder/p['file']).read_bytes();b=gzip.decompress(b) if b[:2]==b'\x1f\x8b' else b
assert struct.unpack_from('<I',b)[0]==0x43504447
pos=struct.unpack_from('<Q',b,32)[0];count=struct.unpack_from('<I',b,pos)[0];pos+=4;paths={}
for i in range(count):
 n=struct.unpack_from('<I',b,pos)[0];pos+=4;name=b[pos:pos+n].decode().rstrip('\0');pos+=n
 offset,size=struct.unpack_from('<QQ',b,pos);pos+=16+16+4
 paths[name.removeprefix('res://')]=(offset,size)
missing=[]
for row in json.loads((root/'data/cosmetics/fashion_hats.json').read_text())['styles']:
 if row['id']=='none':continue
 name=row['asset_id'].removeprefix('res://')
 if not any(k in paths for k in [name,name+'.remap',name+'.import']):missing.append(row['id'])
expected=sum(row['id']!='none' for row in json.loads((root/'data/cosmetics/fashion_hats.json').read_text())['styles'])
print('Mall pack check:',expected-len(missing),'/',expected,'hats; build',m['build'])
if missing:raise SystemExit('Export omitted Mall hats: '+', '.join(missing))
