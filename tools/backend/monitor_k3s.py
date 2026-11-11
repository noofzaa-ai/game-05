#!/usr/bin/env python3
"""Read-only target-cluster CPU/RAM/pod restart monitor; explicit context required."""
import argparse
import json
from pathlib import Path
import subprocess
import time

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--context',required=True)
    parser.add_argument('--namespace',default='zorx-staging')
    parser.add_argument('--samples',type=int,default=1)
    parser.add_argument('--interval',type=float,default=10)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    if args.samples<1 or args.interval<1:parser.error('samples and interval must be positive')
    def kubectl(*values):return subprocess.check_output(['kubectl','--context',args.context,*values],text=True,timeout=15)
    baseline={};failed=False
    args.report.parent.mkdir(parents=True,exist_ok=True)
    with args.report.open('a') as report:
        for sample in range(args.samples):
            alerts=[]
            try:
                pods=json.loads(kubectl('-n',args.namespace,'get','pods','-o','json'))['items']
                for pod in pods:
                    name=pod['metadata']['name'];status=pod.get('status',{});containers=status.get('containerStatuses',[])
                    restarts=sum(item.get('restartCount',0) for item in containers)
                    if status.get('phase') not in ['Succeeded','Running'] or (status.get('phase')=='Running' and (not containers or not all(item['ready'] for item in containers))):alerts.append(name+':not_ready')
                    if restarts>baseline.get(name,0):alerts.append(name+':restarted')
                    baseline[name]=restarts
                nodes=kubectl('top','nodes','--no-headers')
                for line in nodes.splitlines():
                    parts=line.split()
                    if len(parts)>=3 and int(parts[2].rstrip('%'))>70:alerts.append(parts[0]+':cpu_above_70_percent')
                row={'time':time.time(),'alerts':alerts,'nodes_top':nodes.strip(),'pods_top':kubectl('-n',args.namespace,'top','pods','--containers','--no-headers').strip(),'pod_count':len(pods)}
            except (OSError,ValueError,subprocess.SubprocessError):row={'time':time.time(),'alerts':['monitor_unavailable']}
            failed|=bool(row['alerts']);report.write(json.dumps(row)+'\n');report.flush();print(json.dumps(row))
            if sample+1<args.samples:time.sleep(args.interval)
    if failed:raise SystemExit(1)
if __name__=='__main__':main()
