// Nakama bridge only: authentication, bounded transport and atomic storage.
// Character name rules and canonicalization live in Godot Profile/name_rules.gd.
var NAME_REGISTRY = "zorx_name_registry_v1";
var CHARACTER_COLLECTION = "zorx_character_v1";
var CHARACTER_NAME_KEY = "display_name";
var SYSTEM_OWNER = "00000000-0000-0000-0000-000000000000";

type NameRecord = {v: number; name: string; canonical: string; hash: string};
type ValidatedName = {v: number; ok: boolean; name?: string; canonical?: string; error?: string};

function nameResult(error: string): string {
    return JSON.stringify({v: 1, ok: false, error: error});
}
function nameSuccess(name: string | null): string {
    return JSON.stringify({v: 1, ok: true, name: name});
}
function nameUser(ctx: nkruntime.Context): string {
    if (!ctx.userId) { throw {code: 16, message: "Unauthenticated"}; }
    return ctx.userId;
}
function namePayload(payload: string, claim: boolean): {[key: string]: any} | null {
    if (!payload || payload.length > 1024) { return null; }
    try {
        var value = JSON.parse(payload);
        if (!value || Array.isArray(value) || value.v !== 1 || Object.keys(value).length !== (claim ? 2 : 1)) { return null; }
        if (claim && typeof value.name !== "string") { return null; }
        return value;
    } catch (_) { return null; }
}
function nameObject(nk: nkruntime.Nakama, collection: string, key: string, userId: string): nkruntime.StorageObject | null {
    var objects = nk.storageRead([{collection: collection, key: key, userId: userId}]);
    return objects.length ? objects[0] : null;
}
function nameRecord(object: nkruntime.StorageObject | null): NameRecord | null {
    if (!object) { return null; }
    var value = object.value;
    if (value.v !== 1 || typeof value.name !== "string" || typeof value.canonical !== "string" || typeof value.hash !== "string" || !/^[a-f0-9]{64}$/.test(value.hash)) {
        throw new Error("Invalid authoritative name record");
    }
    return value as NameRecord;
}
function nameValidate(ctx: nkruntime.Context, nk: nkruntime.Nakama, payload: string): ValidatedName {
    var response = nk.httpRequest(ctx.env.ZORX_NAMES_URL + "/validate-name", "post", {
        "Authorization": "Bearer " + ctx.env.ZORX_NAMES_TOKEN,
        "Content-Type": "application/json"
    }, payload, 2000, false);
    if (response.code !== 200 || response.body.length > 2048) { throw new Error("Validator unavailable"); }
    var result = JSON.parse(response.body) as ValidatedName;
    if (result.v !== 1 || typeof result.ok !== "boolean") { throw new Error("Validator contract"); }
    if (result.ok && (typeof result.name !== "string" || typeof result.canonical !== "string" || !result.name || !result.canonical)) { throw new Error("Validator contract"); }
    return result;
}

var nameGet: nkruntime.RpcFunction = function(ctx, _logger, nk, payload): string {
    var uid = nameUser(ctx);
    if (!namePayload(payload, false)) { return nameResult("invalid_payload"); }
    try {
        var current = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
        return nameSuccess(current ? current.name : null);
    } catch (_) { return nameResult("unavailable"); }
};

var nameClaim: nkruntime.RpcFunction = function(ctx, _logger, nk, payload): string {
    var uid = nameUser(ctx);
    if (!namePayload(payload, true)) { return nameResult("invalid_payload"); }
    var validated: ValidatedName;
    try { validated = nameValidate(ctx, nk, payload); }
    catch (_) { return nameResult("unavailable"); }
    if (!validated.ok) {
        var allowed = ["too_short", "too_long", "bad_characters", "invalid_payload"];
        return nameResult(allowed.indexOf(validated.error || "") >= 0 ? validated.error! : "unavailable");
    }
    var wanted = validated.name!;
    var canonical = validated.canonical!;
    var hash = nk.sha256Hash(canonical);
    try {
        var currentObject = nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid);
        var current = nameRecord(currentObject);
        var target = nameObject(nk, NAME_REGISTRY, hash, SYSTEM_OWNER);
        if (target && target.value.owner_id !== uid) { return nameResult("name_taken"); }
        var previous: nkruntime.StorageObject | null = null;
        if (current) {
            previous = current.hash === hash ? target : nameObject(nk, NAME_REGISTRY, current.hash, SYSTEM_OWNER);
            if (!previous || previous.value.owner_id !== uid) { return nameResult("unavailable"); }
            if (current.hash === hash && current.name === wanted) { return nameSuccess(current.name); }
        }
        var writes: nkruntime.StorageWriteRequest[] = [{
            collection: CHARACTER_COLLECTION, key: CHARACTER_NAME_KEY, userId: uid,
            value: {v: 1, name: wanted, canonical: canonical, hash: hash},
            version: currentObject ? currentObject.version : "*", permissionRead: 0, permissionWrite: 0
        }];
        if (!target) {
            writes.push({collection: NAME_REGISTRY, key: hash, userId: SYSTEM_OWNER,
                value: {v: 1, owner_id: uid}, version: "*", permissionRead: 0, permissionWrite: 0});
        }
        var deletes: nkruntime.StorageDeleteRequest[] = [];
        if (current && current.hash !== hash && previous) {
            deletes.push({collection: NAME_REGISTRY, key: current.hash, userId: SYSTEM_OWNER, version: previous.version});
        }
        // One DB transaction: reserve new name, update owner, release old name.
        // CAS on the account record serializes concurrent requests from the same user.
        nk.multiUpdate(null, writes, deletes, null, false);
        return nameSuccess(wanted);
    } catch (_) {
        // A simultaneous caller may have won. Never retry a rename over newer data.
        try {
            var winner = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
            var registry = nameObject(nk, NAME_REGISTRY, hash, SYSTEM_OWNER);
            if (winner && registry && registry.value.owner_id === uid && winner.hash === hash && winner.name === wanted) { return nameSuccess(wanted); }
            if (registry && registry.value.owner_id !== uid) { return nameResult("name_taken"); }
        } catch (_) { return nameResult("unavailable"); }
        return nameResult("conflict");
    }
};

function protectNameCollections(objects: {collection?: string}[]): void {
    for (var i = 0; i < objects.length; i++) {
        if (objects[i].collection === GUEST_BUDGET || objects[i].collection === SECURITY_EVENTS || objects[i].collection === ADMIN_METRICS || objects[i].collection === PLAZA_REGISTRY || objects[i].collection === FEEDBACK_COLLECTION || objects[i].collection === FEEDBACK_QUOTA || objects[i].collection === PRESENCE_COLLECTION || objects[i].collection === ADMIN_AUDIT || objects[i].collection === NAME_REGISTRY || objects[i].collection === CHARACTER_COLLECTION || objects[i].collection === PROFILE_COLLECTION || objects[i].collection === RPC_BUDGET_COLLECTION || objects[i].collection === ROOM_COLLECTION || objects[i].collection === TICKET_COLLECTION) {
            throw {code: 7, message: "Authoritative name storage is server-only"};
        }
    }
}
var nameBeforeWrite: nkruntime.BeforeHookFunction<nkruntime.WriteStorageObjectsRequest> = function(ctx, _logger, nk, data) {
    try { protectNameCollections(data.objects || []); } catch(e) { securityObserve(ctx,nk,"protected_write","storage_write"); throw e; }
    return data;
};
var nameBeforeDelete: nkruntime.BeforeHookFunction<nkruntime.DeleteStorageObjectsRequest> = function(ctx, _logger, nk, data) {
    try { protectNameCollections(data.objectIds || []); } catch(e) { securityObserve(ctx,nk,"protected_delete","storage_delete"); throw e; }
    return data;
};

var InitModule: nkruntime.InitModule = function(ctx, logger, nk, initializer): void {
    if (!/^http:\/\/name-validator:8051$/.test(ctx.env.ZORX_NAMES_URL || "") || (ctx.env.ZORX_NAMES_TOKEN || "").length < 32) {
        throw new Error("Name validator configuration is missing");
    }
    rpcLimits(ctx);
    // Nakama extracts registrations directly from InitModule AST.
    // Disallow creating AND authenticating guest/device identities at the public API.
    initializer.registerBeforeAuthenticateDevice(googleOnlyAuthentication);
    initializer.registerBeforeAuthenticateCustom(guestAuthentication);
    initializer.registerBeforeAuthenticateEmail(googleOnlyAuthentication);
    initializer.registerBeforeAuthenticateApple(googleOnlyAuthentication);
    initializer.registerBeforeAuthenticateFacebook(googleOnlyAuthentication);
    initializer.registerBeforeAuthenticateFacebookInstantGame(googleOnlyAuthentication);
    initializer.registerBeforeAuthenticateGameCenter(googleOnlyAuthentication);
    initializer.registerBeforeAuthenticateSteam(googleOnlyAuthentication);
    // Do not let a player remove the identity required for all subsequent gameplay RPCs.
    initializer.registerBeforeUnlinkGoogle(googleOnlyAuthentication);
    initializer.registerBeforeWriteStorageObjects(nameBeforeWrite);
    initializer.registerBeforeDeleteStorageObjects(nameBeforeDelete);
    initializer.registerRpc("zorx_name_get_v1", nameGetGateway);
    initializer.registerRpc("zorx_name_claim_v1", nameClaimGateway);
    initializer.registerRpc("zorx_profile_get_v1", profileGetGateway);
    initializer.registerRpc("zorx_profile_command_v1", profileCommandGateway);
    initializer.registerRpc("zorx_room_create_v1", roomCreateGateway);
    initializer.registerRpc("zorx_companion_v1", companionDiscoverGateway);
    initializer.registerRpc("zorx_room_join_v1", roomJoinGateway);
    initializer.registerRpc("zorx_room_backend_v1", roomBackend);
    initializer.registerRpc("zorx_room_cancel_v1", roomCancelGateway);
    initializer.registerRpc("zorx_room_resume_v1", roomResumeGateway);
    initializer.registerRpc("zorx_social_v1", socialGateway);
    initializer.registerRpc("zorx_plaza_v1", plazaDiscover);
    initializer.registerMatch("zorx_plaza", {matchInit:plazaInit,matchJoinAttempt:plazaJoinAttempt,matchJoin:plazaJoin,matchLeave:plazaLeave,matchLoop:plazaLoop,matchTerminate:plazaTerminate,matchSignal:plazaSignal});
    initializer.registerRpc("zorx_online_status_v1", onlineStatusGateway);
    initializer.registerRpc("zorx_maintenance_admin_v1", maintenanceAdmin);
    initializer.registerRpc("zorx_admin_v1", adminGateway);
    initializer.registerRpc("zorx_feedback_v1", feedbackGateway);
    initializer.registerRpc("zorx_diagnostics_v1", diagnosticsGateway);
    initializer.registerMatch("zorx_admin_metrics",{matchInit:metricsInit,matchJoinAttempt:metricsJoinAttempt,matchJoin:metricsJoin,matchLeave:metricsLeave,matchLoop:metricsLoop,matchTerminate:metricsTerminate,matchSignal:metricsSignal});
    nk.matchCreate("zorx_admin_metrics",{});
    initializer.registerMatch("zorx_security_events",{matchInit:securityInit,matchJoinAttempt:securityJoinAttempt,matchJoin:securityJoin,matchLeave:securityLeave,matchLoop:securityLoop,matchTerminate:securityTerminate,matchSignal:securitySignal});
    nk.matchCreate("zorx_security_events",{});
    logger.info("zorx name/profile/room RPC v1 registered");
};
