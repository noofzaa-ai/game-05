// Best-effort telemetry only. Rejection/authorization never depends on collection.
var SECURITY_EVENTS="zorx_security_events_v1";
var securityCollectorId="", securityLookupAt=0, securityWindow=0, securitySent=0;
var SECURITY_REASONS=["protected_write","protected_delete","item_not_owned","invalid_payload","invalid_command","invalid_count","unknown_command","not_available_here","request_id_reused","revision_conflict"];
function securityCommand(payload:string):string {
 try{var p=JSON.parse(payload),t=p.command&&p.command.type;
 var allowed=["mall_buy","storage_item","storage_material","upgrade","shop_buy","shop_sell","shop_sell_material","shop_sell_batch","refine","equip","unequip","discard","discard_material","repair","repair_all","upgrade_camp","upgrade_facility","appearance","randomize_appearance","enhance","upgrade_tier"];
 return allowed.indexOf(t)>=0?t:"other";}catch(_){return "other";}
}
function securityObserve(ctx:nkruntime.Context,nk:nkruntime.Nakama,reason:string,command:string):void {
 if(!ctx.userId || SECURITY_REASONS.indexOf(reason)<0)return;
 // Fixed global budget per runtime VM; collector independently caps memory and rate.
 var now=Date.now(),second=Math.floor(now/1000);
 if(securityWindow!==second){securityWindow=second;securitySent=0;}
 if(++securitySent>50)return;
 try{
  if(!securityLookupAt || now-securityLookupAt>60000){
   securityLookupAt=now;
   var matches=nk.matchList(1,true,"private-security-events",0,0);
   securityCollectorId=matches.length?matches[0].matchId:"";
  }
  if(securityCollectorId)nk.matchSignal(securityCollectorId,JSON.stringify({user:ctx.userId,reason:reason,command:command}));
 }catch(_){securityCollectorId="";}
}
var securityInit:nkruntime.MatchInitFunction<any>=function(_c,_l,nk){return {state:{instance:nk.uuidv4(),pending:{},size:0,last:0,second:0,received:0,dropped:0},tickRate:1,label:"private-security-events"};};
var securityJoinAttempt:nkruntime.MatchJoinAttemptFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state,accept:false,rejectMessage:"Private"};};
var securityJoin:nkruntime.MatchJoinFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state};};
var securityLeave:nkruntime.MatchLeaveFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state};};
var securitySignal:nkruntime.MatchSignalFunction<any>=function(ctx,_l,_n,_d,_t,state,data){
 // Only runtime matchSignal calls; never trust player-originated signals.
 if(!data || data.length>512)return {state:state,data:""};
 var now=Date.now(),second=Math.floor(now/1000);
 if(state.second!==second){state.second=second;state.received=0;}
 if(++state.received>100){state.dropped++;return {state:state,data:""};}
 try{var e=JSON.parse(data);
 if(!/^[a-f0-9-]{36}$/.test(e.user)||e.user===SYSTEM_OWNER||SECURITY_REASONS.indexOf(e.reason)<0||!(/^[a-z_]{1,32}$/).test(e.command))return {state:state,data:""};
 var minute=Math.floor(now/60000)*60000,key=String(minute)+"|"+e.user+"|"+e.reason+"|"+e.command+"|"+state.instance;
 var row=state.pending[key];
 if(!row){if(state.size>=256){state.dropped++;return {state:state,data:""};}row={user:e.user,reason:e.reason,command:e.command,at:minute,first:now,last:now,count:0};state.pending[key]=row;state.size++;}
 row.last=now;row.count=Math.min(100000,row.count+1);
 }catch(_){}return {state:state,data:""};
};
function securityFlush(nk:nkruntime.Nakama,state:any,all:boolean):void {
 var minute=Math.floor(Date.now()/60000)*60000,keys=Object.keys(state.pending).filter(function(k){return all||state.pending[k].at<minute;});
 // Single bounded storage batch off the request path. Retry retained rows next tick.
 if(keys.length){nk.storageWrite(keys.map(function(k){return {collection:SECURITY_EVENTS,key:k,userId:SYSTEM_OWNER,value:state.pending[k],permissionRead:0,permissionWrite:0};}));keys.forEach(function(k){delete state.pending[k];state.size--;});}
}
var securityLoop:nkruntime.MatchLoopFunction<any>=function(_c,logger,nk,_d,_t,state){
 try{securityFlush(nk,state,false);var minute=Math.floor(Date.now()/60000);if(state.last!==minute){state.last=minute;
 nk.sqlExec("DELETE FROM storage WHERE collection=$1 AND user_id=$2::uuid AND key < $3",[SECURITY_EVENTS,SYSTEM_OWNER,String((minute-43200)*60000)]);
 if(state.dropped){logger.warn("Security telemetry capacity exceeded; omitted="+state.dropped);state.dropped=0;}
 }}catch(_){if(_t%60===0)logger.warn("Security telemetry persistence unavailable");}return {state:state};
};
var securityTerminate:nkruntime.MatchTerminateFunction<any>=function(_c,logger,nk,_d,_t,state){try{securityFlush(nk,state,true);}catch(_){logger.warn("Security telemetry shutdown flush unavailable");}return {state:state};};
function adminSecurity(nk:nkruntime.Nakama,p:any):string {
 var since=Date.now()-(p.range==="30d"?30:p.range==="7d"?7:1)*86400000;
 var target=typeof p.target==="string"&&/^[a-f0-9-]{36}$/.test(p.target)?p.target:"";
 if(target){var events=nk.sqlQuery("SELECT value->>'reason' AS reason,value->>'command' AS command,SUM((value->>'count')::int)::int AS count,MIN((value->>'first')::bigint)::bigint AS first,MAX((value->>'last')::bigint)::bigint AS last FROM storage WHERE collection=$1 AND user_id=$2::uuid AND key >= $3 AND value->>'user'=$4 GROUP BY 1,2 ORDER BY last DESC LIMIT 100",[SECURITY_EVENTS,SYSTEM_OWNER,String(since),target]);return JSON.stringify({ok:true,events:events});}
 var cursor=typeof p.cursor==="string"&&/^[a-f0-9-]{36}$/.test(p.cursor)?p.cursor:SYSTEM_OWNER;
 var rows=nk.sqlQuery("SELECT s.value->>'user' AS id,n.value->>'name' AS name,SUM(CASE WHEN s.value->>'reason'<>'revision_conflict' THEN (s.value->>'count')::int ELSE 0 END)::int AS signals,SUM(CASE WHEN s.value->>'reason'='revision_conflict' THEN (s.value->>'count')::int ELSE 0 END)::int AS conflicts,MAX((s.value->>'last')::bigint)::bigint AS last,string_agg(DISTINCT s.value->>'reason', ', ') AS reasons FROM storage s LEFT JOIN storage n ON n.user_id=(s.value->>'user')::uuid AND n.collection=$5 AND n.key=$6 WHERE s.collection=$1 AND s.user_id=$2::uuid AND s.key >= $3 AND s.value->>'user'>$4 GROUP BY 1,2 HAVING SUM(CASE WHEN s.value->>'reason'<>'revision_conflict' THEN (s.value->>'count')::int ELSE 0 END)>0 ORDER BY 1 LIMIT 51",[SECURITY_EVENTS,SYSTEM_OWNER,String(since),cursor,CHARACTER_COLLECTION,CHARACTER_NAME_KEY]);
 var more=rows.length>50;if(more)rows.pop();return JSON.stringify({ok:true,users:rows,next:more?rows[rows.length-1].id:null,time:Date.now()});
}
