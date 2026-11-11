// Private service-to-service boundary. A browser/user bearer can never invoke this RPC.
var ADMIN_AUDIT = "zorx_admin_audit_v1";
function adminEmails(ctx: nkruntime.Context): string[] {
    try {var a = JSON.parse(ctx.env.ZORX_ADMIN_EMAILS || "[]"); return Array.isArray(a) ? a.map(function(x:any){return String(x).trim().toLowerCase();}) : [];}
    catch (_) {return [];}
}
var adminGateway: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    if (ctx.userId) {throw {code:7,message:"Private administration"};}
    var p:any;
    try {if (!payload || payload.length > 4096) {return nameResult("invalid_payload");} p=JSON.parse(payload);} catch (_) {return nameResult("invalid_payload");}
    if (!ctx.env.ZORX_ADMIN_TOKEN || ctx.env.ZORX_ADMIN_TOKEN.length < 32 || p.secret !== ctx.env.ZORX_ADMIN_TOKEN ||
        !p.actor || typeof p.actor.email !== "string" || adminEmails(ctx).indexOf(p.actor.email.toLowerCase()) < 0 ||
        !/^[a-f0-9-]{36}$/.test(p.actor.id || "")) {return nameResult("unauthorized");}
    if (p.op === "character") {
        if(typeof p.target!=="string" || !/^[a-f0-9-]{36}$/.test(p.target) || p.target===SYSTEM_OWNER){return nameResult("invalid_action");}
        var object=nameObject(nk,PROFILE_COLLECTION,PROFILE_KEY,p.target);
        if(!object){return JSON.stringify({ok:true,character:null});}
        var record:any=object.value, source:any=record.profile||{}, safe:any={};
        // Explicit presentation projection: never expose RNG, receipts, room fence or tokens.
        ["name","created","camp_level","facility_levels","appearance","bonus_stash_slots","stash","vault","loadout"].forEach(function(k){if(source[k]!==undefined){safe[k]=source[k];}});
        var seen=nameObject(nk,PRESENCE_COLLECTION,"seen",p.target);
        return JSON.stringify({ok:true,character:safe,revision:record.revision,updated_at:object.updateTime,last_seen:seen?seen.value.at:null,in_room:!!record.active_room,time:Date.now()});
    }
    if (p.op === "security") { return adminSecurity(nk,p); }
    if (p.op === "history") { return adminHistory(nk,p); }
    if (p.op === "feedback") { return adminFeedback(nk,p); }
    if (p.op === "status") {
        var began=Date.now();
        var counts=nk.sqlQuery("SELECT COUNT(*)::int AS total, COUNT(*) FILTER (WHERE disable_time > to_timestamp(0))::int AS banned FROM users WHERE id <> '00000000-0000-0000-0000-000000000000'::uuid")[0];
        var databaseMs=Date.now()-began;
        var worker:any={ok:false};
        try {
            var r=nk.httpRequest("http://room-worker:8051/metrics","post",{"Authorization":"Bearer "+ctx.env.ZORX_NAMES_TOKEN,"Content-Type":"application/json"},JSON.stringify({v:1}),2000,false);
            if(r.code===200 && r.body.length<16384){var raw=JSON.parse(r.body);worker={ok:raw.ok===true};
                ["rooms","players","peers","tick_p95_ms","tick_max_ms","backlog_ms","memory_bytes","uptime_seconds","bytes_in","bytes_out","state_ack_rtt_ms","maintenance"].forEach(function(k){if(typeof raw[k]==="number" || typeof raw[k]==="boolean"){worker[k]=raw[k];}});}
        }catch(_){}
        return JSON.stringify({ok:true,total:counts.total,banned:counts.banned,database_ms:databaseMs,worker:worker,time:Date.now()});
    }
    if(p.op === "users") {
        var cursor=typeof p.cursor === "string" && /^[a-f0-9-]{36}$/.test(p.cursor) ? p.cursor : SYSTEM_OWNER;
        var q=typeof p.search === "string" ? p.search.trim().slice(0,80) : "";
        var rows=nk.sqlQuery("SELECT u.id::text, u.username, u.display_name, EXTRACT(EPOCH FROM u.create_time)::bigint AS created_at, (u.disable_time > to_timestamp(0)) AS banned, s.value->>'name' AS character_name FROM users u LEFT JOIN storage s ON s.user_id=u.id AND s.collection=$4 AND s.key=$5 WHERE u.id > $1::uuid AND ($2='' OR u.username ILIKE $3 OR u.display_name ILIKE $3 OR s.value->>'name' ILIKE $3 OR u.id::text=$2) ORDER BY u.id LIMIT 31",[cursor,q,q.replace(/[\\%_]/g,"\\$&")+"%",CHARACTER_COLLECTION,CHARACTER_NAME_KEY]);
        var more=rows.length>30;if(more){rows.pop();}
        return JSON.stringify({ok:true,users:rows,next:more ? rows[rows.length-1].id : null});
    }
    if(p.op === "audit") {
        var page=nk.storageList(SYSTEM_OWNER,ADMIN_AUDIT,30,typeof p.cursor==="string" ? p.cursor : undefined);
        return JSON.stringify({ok:true,events:(page.objects || []).map(function(o){return o.value;}),next:page.cursor||null});
    }
    if(p.op === "ban" || p.op === "unban") {
        if(!/^[a-f0-9-]{36}$/.test(p.target||"") || (p.target===p.actor.id || p.target===SYSTEM_OWNER) || typeof p.reason!=="string" || p.reason.trim().length<3 || p.reason.length>200){return nameResult("invalid_action");}
        try{nk.accountGetId(p.target);}catch(_){return nameResult("user_not_found");}
        var key=nk.uuidv4();var event:any={id:key,at:Date.now(),actor:p.actor.email,target:p.target,action:p.op,reason:p.reason.trim(),status:"requested"};
        // Persist intent before changing access; fail closed when audit storage fails.
        nk.storageWrite([{collection:ADMIN_AUDIT,key:key,userId:SYSTEM_OWNER,value:event,permissionRead:0,permissionWrite:0}]);
        try{if(p.op==="ban"){nk.usersBanId([p.target]);}else{nk.usersUnbanId([p.target]);}event.status="completed";}
        catch(_){event.status="failed";}
        nk.storageWrite([{collection:ADMIN_AUDIT,key:key,userId:SYSTEM_OWNER,value:event,permissionRead:0,permissionWrite:0}]);
        return JSON.stringify({ok:event.status==="completed",error:event.status==="failed" ? "action_failed" : undefined});
    }
    return nameResult("invalid_operation");
};
