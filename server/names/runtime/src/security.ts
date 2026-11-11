// Per-account shared storage budget: works across Nakama runtime VMs/replicas.
// Infrastructure policy only; no game rules or client-provided identity/state.
var RPC_BUDGET_COLLECTION = "zorx_rpc_budget_v1";
function rpcLimits(ctx: nkruntime.Context): {burst: number; refill: number; audit: number} {
    var burst = Number(ctx.env.ZORX_RPC_BURST || "20");
    var refill = Number(ctx.env.ZORX_RPC_REFILL || "5");
    var audit = Number(ctx.env.ZORX_RPC_AUDIT_THRESHOLD || "8");
    if (!isFinite(burst) || burst < 1 || burst > 1000 || Math.floor(burst) !== burst || !isFinite(refill) || refill < 0.01 || refill > 1000 || !isFinite(audit) || audit < 1 || audit > 1000 || Math.floor(audit) !== audit) { throw Error("Invalid RPC limits"); }
    return {burst: burst, refill: refill, audit: audit};
}
function rpcBudget(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, rpc: string, rejection: string | null): string {
    var uid = nameUser(ctx);
    var limits = rpcLimits(ctx);
    for (var attempt = 0; attempt < 3; attempt++) {
        var old: nkruntime.StorageObject | null;
        var value: any;
        try {
            old = nameObject(nk, RPC_BUDGET_COLLECTION, "shared", uid);
            var now = Date.now();
            value = old ? old.value : {v: 1, tokens: limits.burst, at: now, rejects: 0, window: now};
            if (value.v !== 1 || typeof value.tokens !== "number" || !isFinite(value.tokens) || typeof value.at !== "number" || typeof value.rejects !== "number" || typeof value.window !== "number") { return "unavailable"; }
            // Backward clock steps never manufacture tokens. NTP remains an ops requirement.
            now = Math.max(now, value.at);
            value.tokens = Math.min(limits.burst, value.tokens + (now - value.at) * limits.refill / 1000);
            value.at = now;
            if (now - value.window >= 300000) { value.window = now; value.rejects = 0; }
            var denied = !rejection && value.tokens < 1;
            if (!rejection && !denied) { value.tokens -= 1; }
            if (rejection || denied) { value.rejects += 1; }
            try {
                nk.multiUpdate(null, [{collection: RPC_BUDGET_COLLECTION, key: "shared", userId: uid,
                    value: value, version: old ? old.version : "*", permissionRead: 0, permissionWrite: 0}], null, null, false);
            } catch (_) { continue; } // bounded reread/CAS; never an unbounded hot retry
            if ((rejection || denied) && value.rejects % limits.audit === 0) {
                // Do not log raw names, commands, request IDs, device IDs, IPs or tokens.
                logger.warn("zorx rpc rejected actor=" + nk.sha256Hash(uid).slice(0, 12) + " rpc=" + rpc + " reason=" + (denied ? "rate_limited" : rejection) + " count=" + value.rejects);
            }
            return denied ? "rate_limited" : "ok";
        } catch (_) { return "unavailable"; }
    }
    return "rate_limited"; // contention also fails closed
}
function rpcDispatch(rpc: string, handler: nkruntime.RpcFunction, ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
        nameUser(ctx);
        if (!googleAccountAllowed(ctx, nk)) { return nameResult("google_login_required"); }
        var gate = rpcBudget(ctx, logger, nk, rpc, null);
        if (gate !== "ok") { return nameResult(gate); }
        if (typeof payload !== "string" || payload.length > (rpc === "zorx_diagnostics_v1" ? 98304 : rpc === "zorx_feedback_v1" ? 8192 : 4096)) {
            rpcBudget(ctx, logger, nk, rpc, "invalid_payload");
            if(rpc === "zorx_profile_command_v1")securityObserve(ctx,nk,"invalid_payload","other");
            return nameResult("invalid_payload");
        }
        var response: string;
        try { response = handler(ctx, logger, nk, payload) as string; }
        catch (_) { response = nameResult("unavailable"); }
        try {
            var result = JSON.parse(response);
            if (result.ok === false) {
                var code = typeof result.error === "string" && /^[a-z_]{1,40}$/.test(result.error) ? result.error : "unavailable";
                rpcBudget(ctx, logger, nk, rpc, code);
                if(rpc === "zorx_profile_command_v1")securityObserve(ctx,nk,code,securityCommand(payload));
            }
        } catch (_) { return nameResult("unavailable"); }
        return response;
}

// Nakama extracts top-level callback keys; registered callbacks cannot be closures.
var nameGetGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_name_get_v1", nameGet, ctx, logger, nk, payload); };
var nameClaimGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_name_claim_v1", nameClaim, ctx, logger, nk, payload); };
var profileGetGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_profile_get_v1", profileGet, ctx, logger, nk, payload); };
var profileCommandGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_profile_command_v1", profileCommand, ctx, logger, nk, payload); };
