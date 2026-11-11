#!/usr/bin/env python3
"""Read a private flight report via authorized SSH, bounded decode, same-clock analysis."""
import argparse,base64,hashlib,json,shlex,subprocess,zlib
from pathlib import Path

def decode(row):
    text=row['data'];assert len(text)<=87384 and hashlib.sha256(text.encode()).hexdigest()==row['digest']
    zipped=base64.b64decode(text,validate=True);assert len(zipped)<=65536
    obj=zlib.decompressobj(31);raw=obj.decompress(zipped,262145)
    assert len(raw)<=262144 and obj.eof and not obj.unconsumed_tail and not obj.unused_data
    assert len(raw)==row['raw_bytes'];return json.loads(raw)

def analyze(report):
    out={'reference':report.get('reference'),'build':report.get('build'),'worker_capture_status':report.get('worker_capture_status'),'sides':{}}
    for side in ['client','worker']:
        r=report.get(side,{});live=r.get('live',{});ev=live.get('events',[])
        out['sides'][side]={'samples':len(live.get('samples',[])),'events':len(ev),'stats':live.get('stats',{}),'incidents':[x.get('reason') for x in r.get('incidents',[])],'clock':live.get('clock'),'overhead_us':live.get('overhead_us')}
    ce=report.get('client',{}).get('live',{}).get('events',[]);we=report.get('worker',{}).get('live',{}).get('events',[])
    rows=[]
    for cap in [e for e in ce if e['kind']=='capture'][-30:]:
        tick=cap['value']['input_tick'];epoch=cap['value'].get('epoch');r={'input_tick':tick,'epoch':epoch}
        def find(events,kind,field='input_tick',lower=False):
            return next((e for e in events if e['kind']==kind and e['value'].get('epoch',epoch)==epoch and (e['value'].get(field,-1)>=tick if lower else e['value'].get(field)==tick)),None)
        sent=find(ce,'wire_send');received=find(we,'inbox');used=find(we,'input_used');ack=find(ce,'metadata','input_ack',True);render=find(ce,'present',lower=True)
        if sent:r['capture_to_queue_ms']=sent['at_ms']-cap['at_ms']
        if used and received:r['worker_receipt_to_use_ms']=used['at_ms']-received['at_ms']
        if ack and sent:r['queue_to_ack_observed_ms']=ack['at_ms']-sent['at_ms']
        if render:r['capture_to_local_present_ms']=render['at_ms']-cap['at_ms']
        rows.append(r)
    out['input_trace']=rows
    out['clock_warning']='No subtraction across machines. queue_to_ack includes network+worker+client scheduling; queue means RPC enqueue, not NIC transmit.'
    return out

def main():
    p=argparse.ArgumentParser();p.add_argument('--player',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    import re
    assert re.fullmatch(r'[a-f0-9-]{36}',a.player)
    sql="BEGIN READ ONLY; SELECT value FROM storage WHERE collection='zorx_diagnostics_v1' AND value->>'player_id'='"+a.player+"' ORDER BY update_time DESC LIMIT 1; ROLLBACK;"
    cmd=shlex.join(['kubectl','-n','zorx-staging','exec','-i','postgres-0','-c','postgres','--','sh','-c','exec psql -U "$POSTGRES_USER" -d nakama -At -v ON_ERROR_STOP=1'])
    r=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','UserKnownHostsFile=/tmp/zorx-release-known-hosts','wiyazard@100.78.133.27',cmd],input=sql,text=True,capture_output=True,check=True,timeout=30)
    rows=[json.loads(x) for x in r.stdout.splitlines() if x.startswith('{')]
    if not rows:raise SystemExit('No diagnostic report for this player yet')
    report=decode(rows[0]);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(analyze(report),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
