#!/usr/bin/env python3
"""Render public equipment ConfigMap from the checked-in tuning values. No cluster access."""
import argparse,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args=parser.parse_args()
    tuning=json.loads((ROOT/'data/items/equipment_tuning.json').read_text())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    header="apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: zorx-equipment-tuning\n  namespace: zorx-staging\ndata:\n  equipment_tuning.json: |\n"
    args.output.write_text(header+''.join('    '+line+'\n' for line in json.dumps(tuning,indent=2).splitlines()))
if __name__=='__main__': main()
