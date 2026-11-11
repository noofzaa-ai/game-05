// Public deployments require a linked Google identity. Local/test stacks may omit this flag.
function googleLoginRequired(ctx: nkruntime.Context): boolean {
    return ctx.env.ZORX_REQUIRE_GOOGLE === "1";
}
function googleOnlyAuthentication(ctx: nkruntime.Context, _logger: nkruntime.Logger, _nk: nkruntime.Nakama, data: any): any {
    if (googleLoginRequired(ctx)) { throw {code: 7, message: "google_login_required"}; }
    return data;
}
function googleAccountAllowed(ctx: nkruntime.Context, nk: nkruntime.Nakama): boolean {
    if (!googleLoginRequired(ctx)) { return true; }
    if (!ctx.userId) { return false; }
    try {
        var account = nk.accountGetId(ctx.userId);
        return !(account.disableTime > 0) && !!account.user && ((typeof account.user.googleId === "string" && account.user.googleId.length > 0) || (ctx.env.ZORX_GUEST_ENABLED === "1" && /^zorx_guest_[a-f0-9]{64}$/.test(account.customId || "")));
    } catch (_) { return false; }
}

// Only the CAPTCHA gateway can sign this request. All other custom auth stays closed.
var GUEST_BUDGET = "zorx_guest_budget_v1";
function guestAuthentication(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, data: nkruntime.AuthenticateCustomRequest): any {
    var key=ctx.env.ZORX_GUEST_SECRET || "", a=data.account || {}, v=a.vars || {};
    if(ctx.env.ZORX_GUEST_ENABLED!=="1" || key.length<32 || !/^zorx_guest_[a-f0-9]{64}$/.test(a.id || "") ||
       !/^[a-f0-9]{32}$/.test(v.nonce || "") || !/^\d{13}$/.test(v.at || "") || Math.abs(Date.now()-Number(v.at))>30000) {
        return googleOnlyAuthentication(ctx,logger,nk,data);
    }
    var expected=nk.base64Encode(nk.hmacSha256Hash(a.id+"\n"+v.at+"\n"+v.nonce,key),true);
    var diff=expected.length ^ String(v.proof || "").length;
    for(var i=0;i<expected.length;i++){diff |= expected.charCodeAt(i) ^ String(v.proof || "").charCodeAt(i);}
    if(diff!==0){throw {code:7,message:"guest_proof_required"};}
    // One fixed private record bounds replay state and the quota across all replicas.
    var old=nameObject(nk,GUEST_BUDGET,"gateway",SYSTEM_OWNER), now=Date.now();
    var state:any=old ? old.value : {entries:[]};
    var entries:any[]=(state.entries || []).filter(function(e:any){return e.at>now-60000;});
    if(entries.some(function(e:any){return e.nonce===v.nonce;})){throw {code:7,message:"guest_proof_used"};}
    if(entries.length>=20){throw {code:8,message:"guest_rate_limited"};}
    entries.push({at:now,nonce:v.nonce});
    try{nk.storageWrite([{collection:GUEST_BUDGET,key:"gateway",userId:SYSTEM_OWNER,value:{entries:entries},version:old ? old.version : "*",permissionRead:0,permissionWrite:0}]);}
    catch(_){throw {code:8,message:"guest_rate_limited"};}
    // Do not persist gateway signatures in sessions.
    a.vars={}; data.account=a;
    return data;
}
