extends RefCounted
## Wall-time scopes only. Overlapping parent/child spans are unioned, never added twice.
var spans:Array=[]
var browser_installed:=false
func record(label:String,start_us:int,end_us:int)->void:
 if end_us<start_us:return
 spans.append({"label":label,"start_us":start_us,"end_us":end_us})
 while spans.size()>256:spans.pop_front()
func browser_setup()->void:
 if browser_installed or not OS.has_feature("web"):return
 browser_installed=true
 JavaScriptBridge.eval("""(()=>{if(window.zorxInputWork)return;const s={supported:false,tasks:[]};window.zorxInputWork=s;try{if(typeof PerformanceObserver!=='undefined'&&PerformanceObserver.supportedEntryTypes.includes('longtask')){s.supported=true;new PerformanceObserver(l=>{for(const e of l.getEntries())s.tasks.push({start_ms:e.startTime,duration_ms:e.duration});s.tasks=s.tasks.slice(-16)}).observe({type:'longtask',buffered:true})}}catch(e){}})()""",true)
func gap(start_us:int,end_us:int,read_browser:bool=true)->Dictionary:
 var selected:Array=[];var intervals:Array=[]
 for span in spans:
  var a:=maxi(start_us,int(span.start_us));var b:=mini(end_us,int(span.end_us))
  if b<=a:continue
  selected.append({"label":span.label,"duration_ms":(b-a)/1000.0,"end_age_ms":(end_us-b)/1000.0})
  intervals.append([a,b])
 intervals.sort_custom(func(a,b):return a[0]<b[0])
 var covered:=0;var until:=start_us
 for interval in intervals:
  if interval[1]>until:covered+=int(interval[1])-maxi(until,int(interval[0]));until=int(interval[1])
 selected.sort_custom(func(a,b):return a.duration_ms>b.duration_ms)
 var result:Dictionary={"gap_ms":maxi(0,end_us-start_us)/1000.0,"instrumented_union_ms":covered/1000.0,"outside_instrumented_ms":maxi(0,end_us-start_us-covered)/1000.0,"longest_scopes":selected.slice(0,6),"note":"wall time; scopes may overlap; outside scope is not proof of browser inactivity"}
 if read_browser and OS.has_feature("web"):
  var raw=JavaScriptBridge.eval("JSON.stringify({visibility:document.visibilityState,focused:document.hasFocus(),now_ms:performance.now(),longtask_supported:!!(window.zorxInputWork&&window.zorxInputWork.supported),tasks:window.zorxInputWork?window.zorxInputWork.tasks:[]})",true)
  var browser=JSON.parse_string(str(raw))
  if browser is Dictionary:result["browser_at_resume"]=browser
 return result
