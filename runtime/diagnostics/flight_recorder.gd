extends RefCounted
## Same-clock bounded flight recorder. No network, account data or game mutations.
const WINDOW_MS=30000
const SAMPLE_MS=250
const MAX_EVENTS=768
var enabled:=true
var samples:Array=[]
var events:Array=[]
var incidents:Array=[]
var _next_sample:=0
var _last_trigger:=-30000
var _pending:Dictionary={}
var _previous_counters:Dictionary={}
var recording_us:=0
var records:=0
func record(kind:String,values:Dictionary,now:int=-1)->void:
 if not enabled:return
 var start:=Time.get_ticks_usec()
 if now<0:now=Time.get_ticks_msec()
 events.append({"at_ms":now,"kind":kind,"value":values.duplicate(true)})
 _trim(now);records+=1;recording_us+=Time.get_ticks_usec()-start
func sample(values:Dictionary,counters:Dictionary={},now:int=-1)->void:
 if not enabled:return
 if now<0:now=Time.get_ticks_msec()
 if now<_next_sample:return
 var start:=Time.get_ticks_usec();_next_sample=now+SAMPLE_MS
 var deltas:Dictionary={}
 for key in counters:
  if _previous_counters.has(key) and counters[key]>=_previous_counters[key]:deltas[key]=counters[key]-_previous_counters[key]
 _previous_counters=counters.duplicate()
 samples.append({"at_ms":now,"values":values.duplicate(true),"counter_delta":deltas})
 _trim(now);recording_us+=Time.get_ticks_usec()-start
func trigger(reason:String,values:Dictionary={},now:int=-1)->bool:
 if not enabled:return false
 if now<0:now=Time.get_ticks_msec()
 if not _pending.is_empty() or now-_last_trigger<30000:return false
 _last_trigger=now
 _pending={"reason":reason,"at_ms":now,"values":values.duplicate(true),"before":snapshot(now)}
 return true
func advance(now:int=-1)->bool:
 if now<0:now=Time.get_ticks_msec()
 if _pending.is_empty() or now-int(_pending.at_ms)<2000:return false
 _pending["after"]=snapshot(now);incidents.append(_pending);_pending={}
 while incidents.size()>3:incidents.pop_front()
 return true
func snapshot(now:int=-1)->Dictionary:
 if now<0:now=Time.get_ticks_msec()
 _trim(now)
 var distributions:Dictionary={}
 for row in samples:
  for key in row.values:
   var value=row.values[key]
   if typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)):
    if not distributions.has(key):distributions[key]=[]
    distributions[key].append(float(value))
 var stats:Dictionary={}
 for key in distributions:
  var values:Array=distributions[key];values.sort()
  stats[key]={"n":values.size(),"p50":values[floori((values.size()-1)*.5)],"p95":values[ceili((values.size()-1)*.95)],"max":values.back()}
 return {"clock":"local_monotonic_ms","at_ms":now,"window_ms":WINDOW_MS,"samples":samples.duplicate(true),"events":events.duplicate(true),"stats":stats,"overhead_us":recording_us,"records":records}
func export_data(now:int=-1)->Dictionary:
 return {"live":snapshot(now),"incidents":incidents.duplicate(true),"pending":not _pending.is_empty(),"availability":"absent metric means unmeasured; counter_delta omitted after reset"}
func _trim(now:int)->void:
 while samples.size()>128 or (not samples.is_empty() and int(samples[0].at_ms)<now-WINDOW_MS):samples.pop_front()
 while events.size()>MAX_EVENTS or (not events.is_empty() and int(events[0].at_ms)<now-WINDOW_MS):events.pop_front()
