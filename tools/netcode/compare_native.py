#!/usr/bin/env python3
"""Compare exact seeded GameSim checkpoints on host Godot and a Linux x86_64 image."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {(name,tick) for name in ('normal','boss','party2','party4') for tick in range(60,1201,60)}


def parse(text):
    result = {}
    for line in text.splitlines():
        match = re.fullmatch(r'NETCODE_HASH (normal|boss|party2|party4) ([0-9]+) ([a-f0-9]{64})',line)
        if match:
            key=(match[1],int(match[2]))
            if key in result: raise ValueError('Duplicate checkpoint')
            result[key]=match[3]
    if set(result) != EXPECTED: raise ValueError('Incomplete checkpoint set: '+str(len(result)))
    return result


def compare_web(native, web_text):
    if 'PROBE_COMPLETE 80' not in web_text: raise ValueError('Web probe has not completed')
    web=parse(web_text)
    return [key for key in sorted(EXPECTED) if native[key] != web[key]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot' if Path('/Applications/Godot.app').exists() else shutil.which('godot'))
    parser.add_argument('--image', default='zorx-godot-probe:4.7.2-amd64')
    parser.add_argument('--output', type=Path, default=ROOT/'build/netcode-comparison')
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--web-output',type=Path,help='Optional saved DOM text from completed Web probe')
    args=parser.parse_args()
    if not args.godot: parser.error('--godot is required')
    args.output.mkdir(parents=True,exist_ok=True)
    docker=['docker','run','--rm','--platform','linux/amd64','--user','10001:10001','--mount','type=bind,source='+str(ROOT)+',target=/project,readonly',args.image]
    commands={'host':[args.godot],'linux-amd64':docker}
    hashes={}
    versions={}
    for name,command in commands.items():
        version=subprocess.run(command+['--version'],capture_output=True,text=True,check=True,timeout=60).stdout.strip()
        if not version.startswith('4.7.2.stable.'): raise ValueError('Wrong Godot version: '+version)
        versions[name]=version
        result=subprocess.run(command+['--headless','--path',str(ROOT) if name=='host' else '/project','--script','res://tests/determinism_probe.gd'],cwd=ROOT,capture_output=True,text=True,timeout=args.timeout)
        (args.output/(name+'.stdout')).write_text(result.stdout)
        (args.output/(name+'.stderr')).write_text(result.stderr)
        if result.returncode or result.stderr.strip(): raise RuntimeError(name+' probe failed; inspect saved stdout/stderr')
        hashes[name]=parse(result.stdout)
    mismatches=[{'scenario':key[0],'tick':key[1],'host':hashes['host'][key],'linux':hashes['linux-amd64'][key]} for key in sorted(EXPECTED) if hashes['host'][key]!=hashes['linux-amd64'][key]]
    image_id=subprocess.run(['docker','image','inspect',args.image,'--format','{{.Id}}'],capture_output=True,text=True,check=True,timeout=30).stdout.strip()
    summary={'godot':versions,'linux_image':image_id,'checkpoints':len(EXPECTED),'matched':len(EXPECTED)-len(mismatches),'mismatches':mismatches,
             'note':'Docker Linux x86_64 may run under emulation on ARM hosts; this is not a native i5 performance test or a Web test.'}
    if args.web_output:
        web_mismatches=compare_web(hashes['host'],args.web_output.read_text())
        summary['web']={'matched':80-len(web_mismatches),'checkpoints':80,'mismatches':[{'scenario':key[0],'tick':key[1]} for key in web_mismatches]}
        print('%d/80 Web checkpoints match'%(80-len(web_mismatches)))
    (args.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('%d/%d exact checkpoints match; evidence: %s'%(summary['matched'],summary['checkpoints'],args.output))
    raise SystemExit(1 if mismatches or (args.web_output and web_mismatches) else 0)


if __name__=='__main__': main()
