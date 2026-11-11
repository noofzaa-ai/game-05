#!/usr/bin/env python3
"""Render stable one-process Services/WS paths for <=128 rooms. No registry push/apply."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import yaml
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('rooms_deploy',HERE/'deploy.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
def render(image, workers=5, host='zorxapi.daiyooo.com'):
    if not 1<=workers<=16:raise ValueError('workers must be 1..16')
    docs=[];pool=[]
    for index in range(workers):
        ident='room-'+str(index);name='room-worker-'+str(index)
        items=base.render(image,True,host)
        for item in items:
            item=copy.deepcopy(item)
            item['metadata']['name']=name if item['kind']!='Ingress' else 'room-gameplay-'+str(index)
            if item['kind']=='Deployment':
                item['spec']['selector']['matchLabels']={'app':name}
                item['spec']['template']['metadata']['labels']={'app':name}
                item['spec']['template']['spec']['containers'][0]['env'].append({'name':'ZORX_ROOM_WORKER_ID','value':ident})
            elif item['kind']=='Service':item['spec']['selector']={'app':name}
            elif item['kind']=='NetworkPolicy':item['spec']['podSelector']={'matchLabels':{'app':name}}
            elif item['kind']=='Ingress':
                route=item['spec']['rules'][0]['http']['paths'][0];route['path']='/room/'+ident;route['pathType']='Exact';route['backend']['service']['name']=name
            docs.append(item)
        pool.append({'id':ident,'url':'wss://'+host+'/room/'+ident})
    return docs,pool

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--image',required=True);p.add_argument('--workers',type=int,default=5);p.add_argument('--host',default='zorxapi.daiyooo.com');p.add_argument('--output',type=Path,required=True);p.add_argument('--runtime-env-output',type=Path,required=True);a=p.parse_args()
    docs,pool=render(a.image,a.workers,a.host)
    for path in (a.output,a.runtime_env_output):
        path.parent.mkdir(parents=True,exist_ok=True)
        if path.exists():raise FileExistsError(path)
    a.output.write_text(yaml.safe_dump_all(docs,sort_keys=False))
    a.runtime_env_output.write_text(json.dumps(pool,indent=2)+'\n')
    print('Rendered stable worker pool and Nakama runtime env; existing zorx-room-server Secret required. Merge env into runtime config before rollout. No apply performed.')
if __name__=='__main__':main()
