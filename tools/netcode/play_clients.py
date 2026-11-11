#!/usr/bin/env python3
"""Open independent native game accounts for local co-op QA; no backend/image changes."""
import argparse
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--clients', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--delay-ms', type=int, default=75, help='One-way application delay; 75 means ~150ms RTT')
    parser.add_argument('--jitter-ms', type=int, default=10)
    parser.add_argument('--loss', type=float, default=.02)
    args = parser.parse_args()
    if not 0 <= args.delay_ms <= 2000 or not 0 <= args.jitter_ms <= 1000 or not 0 <= args.loss <= .5:
        parser.error('Impairment exceeds supported bounds')
    processes = []
    try:
        for index in range(args.clients):
            command = [args.godot, '--path', str(ROOT), '--windowed', '--resolution', '960x540',
                       '--position', f'{40 + index * 80},{40 + index * 60}', '--',
                       f'--net-account=qa{index + 1}', '--net-debug',
                       f'--net-sim={args.delay_ms},{args.jitter_ms},{args.loss}']
            processes.append(subprocess.Popen(command))
        print('Open เล่นออนไลน์ in the hub in each window; create and copy its invite to the other window.', flush=True)
        while any(process.poll() is None for process in processes): time.sleep(.25)
    except KeyboardInterrupt:
        pass
    finally:
        for process in processes:
            if process.poll() is None: process.terminate()
        for process in processes:
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()

if __name__ == '__main__': main()
