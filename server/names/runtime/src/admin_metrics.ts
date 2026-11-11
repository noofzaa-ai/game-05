// Minute samples are collected without a browser session and retained for 30 days.
var ADMIN_METRICS="zorx_admin_metrics_v1";
function metricSample(ctx:nkruntime.Context,nk:nkruntime.Nakama):any {
 var now=Date.now(), worker:any={ok:false};
 try {var r=nk.httpRequest("http://room-worker:8051/metrics","post",{"Authorization":"Bearer "+ctx.env.ZORX_NAMES_TOKEN,"Content-Type":"application/json"},'{"v":1}',2000,false);if(r.code===200){var v=JSON.parse(r.body);worker={ok:v.ok===true,players:Number(v.players)||0,rooms:Number(v.rooms)||0};}}catch(_){}
 var row=nk.sqlQuery("SELECT COUNT(*)::int AS active FROM storage WHERE collection=$1 AND key='seen' AND (value->>'at')::bigint >= $2",[PRESENCE_COLLECTION,now-120000])[0];
 return {at:Math.floor(now/60000)*60000,active:Number(row.active)||0,players:worker.ok?worker.players:null,rooms:worker.ok?worker.rooms:null};
}
var metricsInit:nkruntime.MatchInitFunction<any>=function(){return {state:{last:0},tickRate:1,label:"private-admin-metrics"};};
var metricsJoinAttempt:nkruntime.MatchJoinAttemptFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state,accept:false,rejectMessage:"Private"};};
var metricsJoin:nkruntime.MatchJoinFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state};};
var metricsLeave:nkruntime.MatchLeaveFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state};};
var metricsLoop:nkruntime.MatchLoopFunction<any>=function(ctx,logger,nk,_d,_t,state){
 var minute=Math.floor(Date.now()/60000);if(state.last===minute)return {state:state};state.last=minute;
 try{var sample=metricSample(ctx,nk);nk.storageWrite([{collection:ADMIN_METRICS,key:String(sample.at),userId:SYSTEM_OWNER,value:sample,permissionRead:0,permissionWrite:0}]);
 nk.sqlExec("DELETE FROM storage WHERE collection=$1 AND user_id=$2::uuid AND key < $3",[ADMIN_METRICS,SYSTEM_OWNER,String(sample.at-30*86400000)]);
 }catch(e){logger.warn("Admin metric sample unavailable");}return {state:state};
};
var metricsTerminate:nkruntime.MatchTerminateFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state};};
var metricsSignal:nkruntime.MatchSignalFunction<any>=function(_c,_l,_n,_d,_t,state){return {state:state,data:""};};
function adminHistory(nk:nkruntime.Nakama,p:any):string {
 var hours=p.range==="30d"?720:p.range==="7d"?168:24;
 var bucket=hours===24?5:hours===168?60:180;
 var rows=nk.sqlQuery("SELECT (floor((value->>'at')::bigint / $3)*$3)::bigint AS at, AVG((value->>'active')::numeric)::float AS active, MAX((value->>'active')::int)::int AS peak, AVG((value->>'players')::numeric)::float AS players, MAX((value->>'players')::int)::int AS player_peak, COUNT(*)::int AS samples FROM storage WHERE collection=$1 AND user_id=$4::uuid AND key >= $2 GROUP BY 1 ORDER BY 1",[ADMIN_METRICS,String(Date.now()-hours*3600000),bucket*60000,SYSTEM_OWNER]);
 return JSON.stringify({ok:true,points:rows,range:hours,bucket_minutes:bucket,time:Date.now()});
}
