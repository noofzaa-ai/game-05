// Private bounded diagnostic capture, independent of the 2,000-character feedback UI.
var DIAGNOSTIC_COLLECTION="zorx_diagnostics_v1";
var diagnosticsSubmit:nkruntime.RpcFunction=function(ctx,_logger,nk,payload){
 var uid=nameUser(ctx),p:any;
 try{p=JSON.parse(payload);}catch(_){return nameResult("invalid_payload");}
 if(!p||Array.isArray(p)||Object.keys(p).sort().join(",")!=="data,digest,encoding,raw_bytes,request_id,v"||p.v!==1||p.encoding!=="gzip-base64"||
 typeof p.request_id!=="string"||!/^[a-f0-9]{32}$/.test(p.request_id)||typeof p.data!=="string"||p.data.length<4||p.data.length>87384||p.data.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(p.data)||
 typeof p.raw_bytes!=="number"||p.raw_bytes<2||p.raw_bytes>262144||Math.floor(p.raw_bytes)!==p.raw_bytes||typeof p.digest!=="string"||nk.sha256Hash(p.data)!==p.digest)return nameResult("invalid_payload");
 var quota=nameObject(nk,"zorx_diagnostic_quota_v1","submit",uid),now=Date.now();
 if(quota&&quota.value.request_id===p.request_id)return quota.value.digest===p.digest?JSON.stringify({v:1,ok:true,id:quota.value.id}):nameResult("request_id_reused");
 if(quota&&quota.value.next_at>now)return nameResult("rate_limited");
 var slot=quota?(Number(quota.value.slot)+1)%3:0,key=nk.sha256Hash(uid)+":"+slot;
 var prior=nameObject(nk,DIAGNOSTIC_COLLECTION,key,SYSTEM_OWNER);
 try{
 nk.multiUpdate(null,[{collection:DIAGNOSTIC_COLLECTION,key:key,userId:SYSTEM_OWNER,version:prior?prior.version:"*",permissionRead:0,permissionWrite:0,
 value:{v:1,id:key,at:now,player_id:uid,request_id:p.request_id,encoding:p.encoding,raw_bytes:p.raw_bytes,digest:p.digest,data:p.data}},
 {collection:"zorx_diagnostic_quota_v1",key:"submit",userId:uid,version:quota?quota.version:"*",permissionRead:0,permissionWrite:0,value:{slot:slot,next_at:now+60000,request_id:p.request_id,digest:p.digest,id:key}}],null,null,false);
 return JSON.stringify({v:1,ok:true,id:key});
 }catch(_){return nameResult("unavailable");}
};
var diagnosticsGateway:nkruntime.RpcFunction=function(ctx,logger,nk,payload){return rpcDispatch("zorx_diagnostics_v1",diagnosticsSubmit,ctx,logger,nk,payload);};
