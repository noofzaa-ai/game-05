#!/usr/bin/env python3
"""Known-cause native actual-room diagnostics test. Not a Web performance benchmark."""
import asyncio,json,os,subprocess,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
async def proxy(reader,writer):
    remote_r,remote_w=await asyncio.open_connection('127.0.0.1',8061)
    async def copy(r,w):
        try:
            while True:
                data=await r.read(65536)
                if not data:break
                await asyncio.sleep(.08)
                w.write(data);await w.drain()
        except (ConnectionError,asyncio.CancelledError):pass
        finally:w.close()
    await asyncio.gather(copy(reader,remote_w),copy(remote_r,writer))
async def serve():
    s=await asyncio.start_server(proxy,'127.0.0.1',8062)
    async with s:await s.serve_forever()
def main():
    out=ROOT/'build/flight-recorder';out.mkdir(exist_ok=True)
    threading.Thread(target=lambda:asyncio.run(serve()),daemon=True).start()
    for case in ['direct','delayed']:
        env=dict(os.environ,ZORX_DIAGNOSTIC_REPORT_FILE=str(out/(case+'.json')))
        if case=='delayed':env['ZORX_TEST_ROOM_URL']='ws://127.0.0.1:8062'
        r=subprocess.run(['python3','tools/netcode/migration/check_room.py','--case','diagnostics'],cwd=ROOT,env=env,capture_output=True,text=True,timeout=200)
        (out/(case+'.log')).write_text(r.stdout+r.stderr)
        assert r.returncode==0,r.stdout[-5000:]
        report=json.loads((out/(case+'.json')).read_text())
        def reasons(side):return [i['reason'] for i in report[side].get('incidents',[])]
        assert 'client_schedule_gap' in reasons('client'),reasons('client')
        assert 'worker_schedule_gap' in reasons('worker'),reasons('worker')
        echoes=[e['value']['rtt_ms'] for e in report['client']['live']['events'] if e['kind']=='app_echo' and e['value']['stage']=='receipt']
        assert echoes
        if case=='delayed':assert sorted(echoes)[len(echoes)//2]>=140,echoes
        print(case,'PASS','receipt_app_rtt_ms',echoes,'client',reasons('client'),'worker',reasons('worker'),flush=True)
if __name__=='__main__':main()
