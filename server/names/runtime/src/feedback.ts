// Player feedback is server-owned; only the existing private admin boundary can read it.
var FEEDBACK_COLLECTION = "zorx_feedback_v1";
var FEEDBACK_QUOTA = "zorx_feedback_quota_v1";
var feedbackSubmit: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    var uid = nameUser(ctx), p:any;
    try { p = JSON.parse(payload); } catch (_) { return nameResult("invalid_payload"); }
    if (!p || Array.isArray(p) || Object.keys(p).sort().join(",") !== "message,platform,request_id,v,version" || p.v !== 1 ||
        typeof p.message !== "string" || p.message.trim().length < 3 || p.message.length > 2000 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(p.message) ||
        typeof p.request_id !== "string" || !/^[a-f0-9]{32}$/.test(p.request_id) ||
        ["web","native"].indexOf(p.platform) < 0 || typeof p.version !== "string" || !/^[a-zA-Z0-9._+-]{1,80}$/.test(p.version)) {
        return nameResult("invalid_payload");
    }
    var key = nk.sha256Hash(uid + ":" + p.request_id), message=p.message.trim();
    var previous = nameObject(nk, FEEDBACK_COLLECTION, key, SYSTEM_OWNER);
    if (previous) {
        return previous.value.player_id === uid && previous.value.message === message && previous.value.version === p.version && previous.value.platform === p.platform ?
            JSON.stringify({v:1,ok:true,id:key}) : nameResult("request_id_reused");
    }
    var name = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
    if (!name) { return nameResult("character_required"); }
    var quota = nameObject(nk, FEEDBACK_QUOTA, "submit", uid), now=Date.now();
    if (quota && Number(quota.value.next_at) > now) { return nameResult("rate_limited"); }
    try {
        nk.multiUpdate(null,[
            {collection:FEEDBACK_COLLECTION,key:key,userId:SYSTEM_OWNER,version:"*",permissionRead:0,permissionWrite:0,
             value:{v:1,id:key,at:now,player_id:uid,name:name.name,message:message,version:p.version,platform:p.platform}},
            {collection:FEEDBACK_QUOTA,key:"submit",userId:uid,version:quota ? quota.version : "*",permissionRead:0,permissionWrite:0,value:{v:1,next_at:now+60000}}
        ],null,null,false);
        return JSON.stringify({v:1,ok:true,id:key});
    } catch (_) {
        var saved = nameObject(nk, FEEDBACK_COLLECTION, key, SYSTEM_OWNER);
        if (saved && saved.value.player_id === uid && saved.value.message === message && saved.value.version === p.version && saved.value.platform === p.platform) { return JSON.stringify({v:1,ok:true,id:key}); }
        return nameResult("unavailable");
    }
};
var feedbackGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) {
    return rpcDispatch("zorx_feedback_v1",feedbackSubmit,ctx,logger,nk,payload);
};
function adminFeedback(nk:nkruntime.Nakama, p:any):string {
    var cursor=typeof p.cursor==="string" ? p.cursor : "";
    if (cursor && !/^[0-9]{1,16}:[a-f0-9]{64}$/.test(cursor)) { return nameResult("invalid_payload"); }
    var parts=cursor.split(":"), at=cursor ? Number(parts[0]) : 9007199254740991, id=cursor ? parts[1] : "";
    if(!isFinite(at) || at > 9007199254740991) { return nameResult("invalid_payload"); }
    var rows=nk.sqlQuery("SELECT key AS id, (value->>'at')::bigint AS at, value->>'player_id' AS player_id, value->>'name' AS name, value->>'message' AS message, value->>'version' AS version, value->>'platform' AS platform FROM storage WHERE collection=$1 AND user_id=$2::uuid AND ((value->>'at')::bigint < $3 OR ((value->>'at')::bigint=$3 AND key<$4)) ORDER BY (value->>'at')::bigint DESC, key DESC LIMIT 31",[FEEDBACK_COLLECTION,SYSTEM_OWNER,at,id]);
    var more=rows.length>30;if(more){rows.pop();}
    return JSON.stringify({v:1,ok:true,feedback:rows,next:more ? String(rows[rows.length-1].at)+":"+rows[rows.length-1].id : null});
}
