// Transport/storage orchestration only. Godot Commands.apply owns all game rules.
var PROFILE_COLLECTION = "zorx_profile_v1";
var PROFILE_KEY = "camp";
type ProfileRecord = {v: number; revision: number; profile: {[key: string]: any}; rng_state: string; receipts: any[]; active_room?: {id: string; fence: string; expires: number; started: boolean}};
function profilePayload(payload: string, command: boolean): any {
    if (!payload || payload.length > 4096) { return null; }
    try {
        var p = JSON.parse(payload);
        if (!p || Array.isArray(p) || p.v !== 1 || Object.keys(p).length !== (command ? 4 : 1)) { return null; }
        if (command && (typeof p.request_id !== "string" || !/^[a-zA-Z0-9_-]{16,64}$/.test(p.request_id) || typeof p.revision !== "number" || p.revision < 1 || p.revision > 2147483646 || Math.floor(p.revision) !== p.revision || !p.command || Array.isArray(p.command) || typeof p.command !== "object")) { return null; }
        return p;
    } catch (_) { return null; }
}
function profileRecord(object: nkruntime.StorageObject | null): ProfileRecord | null {
    if (!object) { return null; }
    var p = object.value;
    if (p.v !== 1 || typeof p.revision !== "number" || p.revision < 1 || Math.floor(p.revision) !== p.revision || !p.profile || typeof p.rng_state !== "string" || !Array.isArray(p.receipts) || p.receipts.length > 32) { throw Error("Invalid authoritative profile"); }
    return p as ProfileRecord;
}
function profileWorker(ctx: nkruntime.Context, nk: nkruntime.Nakama, state: ProfileRecord | null, name: string, command: any, recovery?: boolean): any {
    var response = nk.httpRequest(ctx.env.ZORX_NAMES_URL + (recovery ? "/recover" : "/profile"), "post", {
        "Authorization": "Bearer " + ctx.env.ZORX_NAMES_TOKEN, "Content-Type": "application/json"
    }, JSON.stringify({v: 1, state: state ? {profile: state.profile, rng_state: state.rng_state} : null,
        seed: nk.uuidv4().replace(/-/g, "").slice(0, 15), name: name, command: command}), 2000, false);
    if (response.code !== 200 || response.body.length > 524288) { throw Error("Authority unavailable"); }
    var value = JSON.parse(response.body);
    if (typeof value.ok !== "boolean") { throw Error("Authority contract"); }
    if (value.ok && (!value.profile || typeof value.rng_state !== "string")) { throw Error("Authority contract"); }
    return value;
}
function equipmentTuning(ctx: nkruntime.Context, nk: nkruntime.Nakama): any {
    var response = nk.httpRequest(ctx.env.ZORX_NAMES_URL + "/equipment-config", "post", {
        "Authorization": "Bearer " + ctx.env.ZORX_NAMES_TOKEN, "Content-Type": "application/json"
    }, "{}", 2000, false);
    if (response.code !== 200 || response.body.length > 65536) { throw Error("Equipment tuning unavailable"); }
    var value = JSON.parse(response.body);
    if (!value.ok || value.v !== 1 || !value.refine || !value.upgrade) { throw Error("Equipment tuning invalid"); }
    return {version: 1, refine: value.refine, upgrade: value.upgrade, mobility: value.mobility, armor: value.armor};
}
function profileReply(ctx: nkruntime.Context, nk: nkruntime.Nakama, state: ProfileRecord, name: string, replayed: boolean, applied: number): string {
    // UI receives a snapshot, never storage versions, RNG state or request history.
    var view = JSON.parse(JSON.stringify(state.profile));
    view.name = name; view.created = !!name;
    return JSON.stringify({v: 1, ok: true, revision: state.revision, profile: view, equipment_tuning: equipmentTuning(ctx, nk), replayed: replayed, applied_revision: applied});
}
function profileWrite(nk: nkruntime.Nakama, uid: string, state: ProfileRecord, previous: nkruntime.StorageObject | null): void {
    nk.multiUpdate(null, [{collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: uid, value: state,
        version: previous ? previous.version : "*", permissionRead: 0, permissionWrite: 0}], null, null, false);
}
var profileGet: nkruntime.RpcFunction = function(ctx, _logger, nk, payload): string {
    var uid = nameUser(ctx);
    if (!profilePayload(payload, false)) { return nameResult("invalid_payload"); }
    try {
        var name = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
        var object = nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid);
        var current = profileRecord(object);
        if (!current) {
            var made = profileWorker(ctx, nk, null, name ? name.name : "", null);
            if (!made.ok) { return nameResult("unavailable"); }
            current = {v: 1, revision: 1, profile: made.profile, rng_state: made.rng_state, receipts: []};
            try { profileWrite(nk, uid, current, null); }
            catch (_) { current = profileRecord(nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid)); }
            if (!current) { return nameResult("unavailable"); }
        }
        // Retire the v1 catalog grant through trusted Godot rules, never during an active room.
        var legacyChestIds: {[key: string]: boolean} = {};
        var duplicateChest = false;
        var chestItems = ((current.profile.stash || {}).items || []).concat((current.profile.vault || {}).items || []);
        var equipped = (current.profile.loadout || {}).equipped || {};
        Object.keys(equipped).forEach(function(key) { chestItems.push(equipped[key]); });
        chestItems.forEach(function(item: any) {
            if (typeof item.id === "string" && item.id.indexOf("treasure-") === 0) {
                if (legacyChestIds[item.id]) { duplicateChest = true; }
                legacyChestIds[item.id] = true;
            }
        });
        if (!current.active_room && (duplicateChest || typeof current.profile.diamonds !== "number" || !Array.isArray(current.profile.mall_owned) || current.profile.beta_kit_version === 1 || !(current.profile.starter_weapon_kit_version >= 1) || !(current.profile.starter_armor_kit_version >= 1) || !(current.profile.armor_migration_version >= 2))) {
            var refreshed = profileWorker(ctx, nk, current, name ? name.name : "", null);
            if (!refreshed.ok) { return nameResult("unavailable"); }
            if (refreshed.profile.starter_weapon_kit_version >= 1 && refreshed.profile.starter_armor_kit_version >= 1 && refreshed.profile.armor_migration_version >= 2) {
                current.profile = refreshed.profile; current.rng_state = refreshed.rng_state;
                current.revision += 1;
                try { profileWrite(nk, uid, current, object || nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid)); }
                catch (_) { return nameResult("conflict"); }
            }
        }
        if (current.active_room && current.active_room.expires < Date.now()) {
            var expiredRoom = nameObject(nk, "zorx_rooms_v1", current.active_room.id, SYSTEM_OWNER);
            if (current.active_room.started && !(expiredRoom && expiredRoom.value.diagnostic === true)) {
                var recovered = profileWorker(ctx, nk, current, name ? name.name : "", null, true);
                if (!recovered.ok) { return nameResult("unavailable"); }
                current.profile = recovered.profile; current.rng_state = recovered.rng_state;
            }
            delete current.active_room; current.revision += 1;
            try { profileWrite(nk, uid, current, object || nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid)); }
            catch (_) { return nameResult("conflict"); }
        }
        return profileReply(ctx, nk, current, name ? name.name : "", false, current.revision);
    } catch (_) { return nameResult("unavailable"); }
};
var profileCommand: nkruntime.RpcFunction = function(ctx, _logger, nk, payload): string {
    var uid = nameUser(ctx);
    var p = profilePayload(payload, true);
    if (!p) { return nameResult("invalid_payload"); }
    var fingerprint = nk.sha256Hash(JSON.stringify({revision: p.revision, command: p.command}));
    try {
        var named = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
        var name = named ? named.name : "";
        var object = nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid);
        var current = profileRecord(object);
        if (!current) { return nameResult("profile_required"); }
        if (current.active_room) { return nameResult("in_match"); }
        var replay = function(state: ProfileRecord): string | null {
            for (var i = 0; i < state.receipts.length; i++) {
                var receipt = state.receipts[i];
                if (receipt.id === p.request_id) {
                    if (receipt.hash !== fingerprint) { return nameResult("request_id_reused"); }
                    return profileReply(ctx, nk, state, name, true, receipt.revision);
                }
            }
            return null;
        };
        var existing = replay(current);
        if (existing) { return existing; }
        if (p.revision !== current.revision) { return nameResult("revision_conflict"); }
        var result = profileWorker(ctx, nk, current, name, p.command);
        if (!result.ok) { return JSON.stringify({v: 1, ok: false, error: typeof result.error === "string" ? result.error : "unavailable"}); }
        var next: ProfileRecord = {v: 1, revision: current.revision + 1, profile: result.profile, rng_state: result.rng_state,
            receipts: current.receipts.concat([{id: p.request_id, hash: fingerprint, revision: current.revision + 1}]).slice(-32)};
        try { profileWrite(nk, uid, next, object); }
        catch (_) {
            var winner = profileRecord(nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid));
            if (!winner) { return nameResult("unavailable"); }
            return replay(winner) || nameResult("revision_conflict");
        }
        return profileReply(ctx, nk, next, name, false, next.revision);
    } catch (_) { return nameResult("unavailable"); }
};
