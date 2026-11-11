#!/usr/bin/env python3
"""Run bounded independent Godot processes; execute on the target i5 before release."""
import argparse
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import subprocess
import tempfile
import time
ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot',default=os.environ.get('GODOT_BIN','godot'))
    p.add_argument('--rooms',type=int,default=40)
    p.add_argument('--seconds',type=int,default=60)
    p.add_argument('--unpaced',action='store_true',help='Stress benchmark; default runs at real 60 Hz')
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    if not 1<=a.rooms<=128 or not 1<=a.seconds<=3600:p.error('rooms 1..128, seconds 1..3600')
    spec=importlib.util.spec_from_file_location('room_smoke',ROOT/'server/rooms/smoke.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='zorx-load-') as folder:
        root=Path(folder);module.prepare(root)
        before=resource.getrusage(resource.RUSAGE_CHILDREN);started=time.monotonic()
        def worker(count):
            result=subprocess.run([a.godot,'--headless','--path',str(root),'--script','res://server/rooms/load_probe.gd','--',str(count),str(a.seconds*60),"unpaced" if a.unpaced else "paced"],capture_output=True,text=True,timeout=a.seconds*20+120)
            lines=[line for line in result.stdout.splitlines() if line.startswith('LOAD_RESULT=')]
            if result.returncode not in (0,1) or result.stderr or len(lines)!=1:raise RuntimeError('Godot load probe failed; '+result.stderr[:500]+' '+result.stdout[-1000:])
            value=json.loads(lines[0].split('=',1)[1]);value['threshold_pass']=result.returncode==0;return value
        counts=[min(8,a.rooms-i) for i in range(0,a.rooms,8)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(counts)) as pool:reports=list(pool.map(worker,counts))
        elapsed=time.monotonic()-started;after=resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu_seconds=after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime
        # CPU is host-normalized children time; node production CPU still needs kubectl top.
        summary={'machine':platform.platform(),'processor':platform.processor(),'logical_cpus':os.cpu_count(),'rooms':a.rooms,'processes':len(counts),'wall_seconds':elapsed,'cpu_seconds':cpu_seconds,'cpu_percent':cpu_seconds/elapsed/(os.cpu_count() or 1)*100,'workers':reports,'paced':not a.unpaced,'acceptance':'manual steady-state i5 CPU <=70%, real network and restore still required','real_network':False,'threshold_pass':all(r['threshold_pass'] for r in reports)}
        a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(summary,indent=2)+'\n')
        print(json.dumps({k:v for k,v in summary.items() if k!='workers'},indent=2))
        if not summary['threshold_pass']:raise SystemExit(1)
if __name__=='__main__':main()
