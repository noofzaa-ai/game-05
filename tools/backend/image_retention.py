#!/usr/bin/env python3
"""Digest-aware Zorx-only retention. Default report; registry blob GC is a separate maintenance operation."""
import argparse,datetime as dt,fnmatch,json,re,subprocess,urllib.request,urllib.error,urllib.parse
from pathlib import Path

ACCEPT='application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'
SINGLE={'application/vnd.docker.distribution.manifest.v2+json','application/vnd.oci.image.manifest.v1+json'}

def created_time(value):
 try:return dt.datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()
 except (ValueError,TypeError,AttributeError):return None

def workload_refs(doc):
 refs=set()
 def walk(x):
  if isinstance(x,dict):
   for k,v in x.items():
    if k=='image' and isinstance(v,str):refs.add(v)
    elif k=='imageID' and isinstance(v,str):refs.add(v.removeprefix('docker-pullable://'))
    else:walk(v)
  elif isinstance(x,list):
   for v in x:walk(v)
 walk(doc);return refs

def plan(records,refs,policy,now):
 protected=set()
 for row in records:
  for alias in policy['registry_aliases']:
   if alias+'/'+row['repository']+':'+row['tag'] in refs or alias+'/'+row['repository']+'@'+row['digest'] in refs:protected.add((row['repository'],row['digest']))
 for repo in policy['repositories']:
  groups={}
  for row in records:
   if row['repository']==repo:groups.setdefault(row['digest'],[]).append(row)
  newest=sorted(groups,key=lambda d:max((r['created'] if r.get('created') is not None else float('-inf')) for r in groups[d]),reverse=True)
  protected.update((repo,d) for d in newest[:policy['keep_latest']])
 unsupported={r['repository'] for r in records if r.get('media_type') not in SINGLE}
 result=[]
 for row in records:
  reason='expired'
  if row['repository'] in unsupported:reason='unsupported-manifest-repository-keep'
  elif (row['repository'],row['digest']) in protected:reason='live-or-rollback-or-latest'
  elif any(fnmatch.fnmatchcase(row['tag'],p) for p in policy['keep_tag_patterns']):reason='pinned-tag'
  elif row.get('media_type') not in SINGLE:reason='unsupported-manifest-keep'
  elif row.get('created') is None:reason='unknown-age-keep'
  elif now-row['created']<policy['minimum_age_days']*86400:reason='recent'
  result.append({**row,'reason':reason})
 # Registry DELETE is by digest: if any alias tag is retained, protect all aliases.
 retained={(r['repository'],r['digest']) for r in result if r['reason']!='expired'}
 for r in result:
  if r['reason']=='expired' and (r['repository'],r['digest']) in retained:r['reason']='shared-with-kept-tag'
 return result

class Registry:
 def __init__(self,url):self.url=url.rstrip('/')
 def request(self,path,method='GET'):
  req=urllib.request.Request(self.url+path,method=method,headers={'Accept':ACCEPT,'User-Agent':'zorx-retention/1.0'})
  with urllib.request.urlopen(req,timeout=20) as r:
   if method=='DELETE' and r.status!=202:raise RuntimeError('Registry did not accept manifest deletion')
   return r.headers,json.load(r) if method=='GET' else None
 def records(self,repositories):
  result=[]
  for repo in repositories:
   try:_,listing=self.request('/v2/'+repo+'/tags/list')
   except urllib.error.HTTPError as e:
    if e.code==404:continue
    raise
   for tag in listing.get('tags') or []:
    headers,manifest=self.request('/v2/'+repo+'/manifests/'+urllib.parse.quote(tag,safe=''))
    digest=headers.get('Docker-Content-Digest')
    if not digest or not re.fullmatch(r'sha256:[0-9a-f]{64}',digest):raise ValueError('Manifest without digest; abort cleanup')
    media=manifest.get('mediaType',headers.get_content_type())
    created=None
    if media in SINGLE:
     config_digest=manifest['config']['digest']
     if not re.fullmatch(r'sha256:[0-9a-f]{64}',config_digest):raise ValueError('Invalid config digest')
     _,config=self.request('/v2/'+repo+'/blobs/'+config_digest);created=created_time(config.get('created'))
    result.append(dict(repository=repo,tag=tag,digest=digest,media_type=media,created=created))
  return result

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--registry',default='http://127.0.0.1:30500')
 p.add_argument('--policy',type=Path,default=Path(__file__).with_name('image_retention_policy.json'))
 p.add_argument('--apply',action='store_true')
 args=p.parse_args();policy=json.loads(args.policy.read_text())
 if not policy['repositories'] or any(not re.fullmatch(r'zorx-[a-z0-9][a-z0-9._-]*',r) for r in policy['repositories']):raise ValueError('Zorx-only repository allowlist required')
 if policy['keep_latest']<3 or policy['minimum_age_days']<7:raise ValueError('Retention safety floors:3 releases,7days')
 # Fail closed: no cleanup when live/rollback enumeration fails, across ALL namespaces.
 raw=subprocess.check_output(['kubectl','get','pods,deployments,statefulsets,daemonsets,replicasets,jobs,cronjobs','-A','-o','json'],timeout=30)
 refs=workload_refs(json.loads(raw))
 registry=Registry(args.registry);records=registry.records(policy['repositories'])
 planned=plan(records,refs,policy,dt.datetime.now(dt.timezone.utc).timestamp())
 candidates=sorted({(r['repository'],r['digest']) for r in planned if r['reason']=='expired'})
 print(json.dumps({'at':dt.datetime.now(dt.timezone.utc).isoformat(),'scanned_tags':len(records),'candidates':len(candidates),'policy':policy,'images':planned},indent=2))
 if args.apply:
  if not policy.get('apply_enabled'):raise RuntimeError('Apply disabled by policy; review report and registry maintenance approval first')
  # Re-enumerate immediately before mutation; fail closed if any workload references changed.
  again=subprocess.check_output(['kubectl','get','pods,deployments,statefulsets,daemonsets,replicasets,jobs,cronjobs','-A','-o','json'],timeout=30)
  if workload_refs(json.loads(again))!=refs:raise RuntimeError('Workloads changed; rerun report')
  for repo,digest in candidates:registry.request('/v2/'+repo+'/manifests/'+digest,'DELETE')
  print('Deleted manifest references:',len(candidates),'; blob storage reclamation requires separate offline/read-only GC')

if __name__=='__main__':main()
