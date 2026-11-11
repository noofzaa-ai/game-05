// Admission, fencing and persistence only. Godot owns simulation/economy rules.
var ROOM_COLLECTION = "zorx_rooms_v1";
var TICKET_COLLECTION = "zorx_room_tickets_v1";
function roomPayload(payload: string): any {
    if (!payload || payload.length > 4096) { return null; }
    try { var p = JSON.parse(payload); return p && !Array.isArray(p) && p.v === 1 ? p : null; } catch (_) { return null; }
}
function roomEnabled(ctx: nkruntime.Context): boolean {
    return ctx.env.ZORX_ROOM_WS_URL ? /^(wss:\/\/[^\s]+|ws:\/\/127\.0\.0\.1:[0-9]+(?:\/[^\s]*)?)$/.test(ctx.env.ZORX_ROOM_WS_URL) : false;
}
function roomRow(nk: nkruntime.Nakama, room: string): nkruntime.StorageObject | null { return nameObject(nk, ROOM_COLLECTION, room, SYSTEM_OWNER); }
function roomPut(collection: string, key: string, uid: string, value: any, version: string): nkruntime.StorageWriteRequest {
    return {collection: collection, key: key, userId: uid, value: value, version: version, permissionRead: 0, permissionWrite: 0};
}
function roomProfile(nk: nkruntime.Nakama, uid: string): {object: nkruntime.StorageObject; state: ProfileRecord; name: string} | null {
    var object = nameObject(nk, PROFILE_COLLECTION, PROFILE_KEY, uid);
    var state = profileRecord(object);
    var named = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
    if (!object || !state || !named) { return null; }
    return {object: object, state: state, name: named.name};
}
function roomTicket(ctx: nkruntime.Context, nk: nkruntime.Nakama, uid: string, row: nkruntime.StorageObject): string {
    var room = row.value;
    if (room.farm_map === "mummy_ascent" && (uid !== "76f7165a-18c4-4300-9c0d-9996173c6ae9" || room.owner !== uid || room.capacity !== 1)) { return nameResult("forbidden"); }
    if (room.closed || room.expires < Date.now() || !room.members[uid]) { return nameResult("room_expired"); }
    var token = nk.uuidv4().replace(/-/g, "") + nk.uuidv4().replace(/-/g, "");
    var expires = Date.now() + 30000;
    var hash = nk.sha256Hash(token);
    var previous = room.tickets && room.tickets[uid] ? nameObject(nk, TICKET_COLLECTION, room.tickets[uid], SYSTEM_OWNER) : null;
    room.tickets = room.tickets || {}; room.tickets[uid] = hash;
    var deletes: nkruntime.StorageDeleteRequest[] = previous ? [{collection: TICKET_COLLECTION, key: previous.key, userId: SYSTEM_OWNER, version: previous.version}] : [];
    nk.multiUpdate(null, [roomPut(TICKET_COLLECTION, hash, SYSTEM_OWNER,
        {v: 1, room: row.key, uid: uid, slot: room.members[uid], expires: expires}, "*"), roomPut(ROOM_COLLECTION, row.key, SYSTEM_OWNER, room, row.version)], deletes, null, false);
    return JSON.stringify({v: 1, ok: true, room: row.key, player_id: room.members[uid], netfox_room: room.camp === true, companion_pending: !!room.pending_companion, companions: room.companions || [], ticket: token, expires: expires, diagnostic: room.diagnostic === true, diagnostic_seed: room.diagnostic === true ? room.seed : "", url: room.url || ctx.env.ZORX_ROOM_WS_URL});
}
// Persist one visible offer per account; only a completed prior round rolls a new identity.
function companionOffer(nk:nkruntime.Nakama, uid:string):nkruntime.StorageObject {
    var key="companion-offer-"+uid;
    var old=nameObject(nk,ROOM_COLLECTION,key,SYSTEM_OWNER);
    if(old){
        if(!old.value.room)return old;
        var prior=roomRow(nk,old.value.room);
        if(prior && !prior.value.closed && prior.value.expires>Date.now())return old;
    }
    var seed=nk.uuidv4().replace(/-/g,"").slice(0,13);
    nk.multiUpdate(null,[roomPut(ROOM_COLLECTION,key,SYSTEM_OWNER,{v:1,id:"arun",seed:seed,room:""},old?old.version:"*")],null,null,false);
    var result=nameObject(nk,ROOM_COLLECTION,key,SYSTEM_OWNER);
    if(!result)throw Error("offer unavailable");
    return result;
}
var companionDiscover:nkruntime.RpcFunction=function(ctx,_logger,nk,payload){
    var uid=nameUser(ctx),p=roomPayload(payload);
    if(!p || Object.keys(p).length!==1)return nameResult("invalid_payload");
    if(!roomProfile(nk,uid))return nameResult("character_required");
    try{var offer=companionOffer(nk,uid);return JSON.stringify({v:1,ok:true,id:offer.value.id,seed:offer.value.seed});}
    catch(_){return nameResult("conflict");}
};
var companionDiscoverGateway:nkruntime.RpcFunction=function(ctx,logger,nk,payload){return rpcDispatch("zorx_companion_v1",companionDiscover,ctx,logger,nk,payload);};
var roomCreate: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    var uid = nameUser(ctx); var p = roomPayload(payload);
    if (!p || (Object.keys(p).some(function(k) {return ["v", "capacity", "camp", "farm_map", "diagnostic", "companion", "companion_seed"].indexOf(k) < 0;}) || (p.camp !== undefined && p.camp !== true) || (p.farm_map !== undefined && (typeof p.farm_map !== "string" || !/^[a-z0-9_]{1,64}$/.test(p.farm_map) || p.capacity !== 1 || p.camp === true))) || typeof p.capacity !== "number" || p.capacity < 1 || p.capacity > 4 || p.capacity !== Math.floor(p.capacity)) { return nameResult("invalid_payload"); }
    if (p.companion !== undefined && (p.companion !== "arun" || p.camp !== true || p.capacity < 2 || p.diagnostic !== undefined || p.farm_map !== undefined)) {return nameResult("invalid_payload");}
    if (p.farm_map && /^mummy_/.test(p.farm_map) && (p.farm_map !== "mummy_ascent" || uid !== "76f7165a-18c4-4300-9c0d-9996173c6ae9" || p.capacity !== 1 || p.camp === true)) { return nameResult("forbidden"); }
    if (p.diagnostic !== undefined && (p.diagnostic !== true || p.capacity !== 1 || p.camp === true || p.farm_map !== undefined)) {return nameResult("invalid_payload");}
    if (!roomEnabled(ctx)) { return nameResult("not_configured"); }
    if (roomMaintenance(ctx,nk)) {return nameResult("maintenance");}
    try {
        var player = roomProfile(nk, uid); if (!player) { return nameResult("character_required"); }
        if (player.state.active_room) { return nameResult("in_match"); }
        var id = nk.uuidv4().replace(/-/g, ""); var invite = nk.uuidv4().replace(/-/g, ""); var fence = nk.uuidv4().replace(/-/g, "");
        var allocation = roomAllocation(ctx,nk,id); if (!allocation) {return nameResult("room_full");}
        var members: {[key: string]: number} = {}; members[uid] = 1;
        var memberFences: {[key: string]: string} = {}; memberFences[uid] = nk.uuidv4().replace(/-/g, "");
        var offer=p.companion?companionOffer(nk,uid):null;
        if(offer && p.companion_seed !== offer.value.seed)return nameResult("companion_changed");
        var room = {v: 1, diagnostic: p.diagnostic === true, farm_map: p.farm_map || "", camp: p.camp === true, companions: p.companion ? [{id:p.companion,slot:p.capacity,seed:offer!.value.seed}] : [], member_fences: memberFences, owner: uid, capacity: p.capacity, members: members, invite_hash: nk.sha256Hash(invite), fence: fence,
            worker: allocation.worker.id, url: allocation.worker.url, seed: nk.uuidv4().replace(/-/g, "").slice(0, 15), started: false, closed: false, expires: Date.now() + 60000};
        player.state.active_room = {id: id, fence: fence, expires: room.expires, started: false};
        var creationWrites=[allocation.write, roomPut(ROOM_COLLECTION, id, SYSTEM_OWNER, room, "*"), roomPut(PROFILE_COLLECTION, PROFILE_KEY, uid, player.state, player.object.version)];
        if(offer){offer.value.room=id;creationWrites.push(roomPut(ROOM_COLLECTION,offer.key,SYSTEM_OWNER,offer.value,offer.version));}
        nk.multiUpdate(null,creationWrites,null,null,false);
        var row = roomRow(nk, id); if (!row) { return nameResult("unavailable"); }
        var ticket = JSON.parse(roomTicket(ctx, nk, uid, row)); if (ticket.ok) { ticket.invite = invite; }
        return JSON.stringify(ticket);
    } catch (_) { return nameResult("conflict"); }
};
var roomJoin: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    var uid = nameUser(ctx); var p = roomPayload(payload);
    var friendJoin=false;var friendTarget="";
    if(p && Object.keys(p).length===2 && typeof p.friend==="string" && /^[a-f0-9-]{36}$/.test(p.friend)){
        if(!socialFriend(nk,uid,p.friend,0)){return nameResult("not_friends");}
        var friendRoom=socialRoom(nk,p.friend);
        if(!friendRoom || !friendRoom.value.camp || friendRoom.value.owner!==p.friend){return nameResult("room_expired");}
        friendTarget=p.friend;p={v:1,room:friendRoom.key};friendJoin=true;
    }
    if (!p || (Object.keys(p).length !== 2 && Object.keys(p).length !== 3) || typeof p.room !== "string" || !/^[a-f0-9]{32}$/.test(p.room) || (p.invite !== undefined && (typeof p.invite !== "string" || !/^[a-f0-9]{32}$/.test(p.invite)))) { return nameResult("invalid_payload"); }
    if (!roomEnabled(ctx)) { return nameResult("not_configured"); }
    try {
        var row = roomRow(nk, p.room); if (!row || row.value.closed || row.value.expires < Date.now()) { return nameResult("room_expired"); }
        var room = row.value;
        if (room.farm_map === "mummy_ascent" && uid !== room.owner) { return nameResult("forbidden"); }
        if(friendJoin && (!room.camp || room.owner!==friendTarget || !room.members[friendTarget])){return nameResult("room_expired");}
        if (room.members[uid]) { return roomTicket(ctx, nk, uid, row); }
        if (roomMaintenance(ctx,nk)) {return nameResult("maintenance");}
        if (room.started || Object.keys(room.members).length + (room.companions || []).length + (room.pending_companion ? 1 : 0) >= room.capacity) { return nameResult("room_full"); }
        if (!friendJoin && (!p.invite || nk.sha256Hash(p.invite) !== room.invite_hash)) { return nameResult("not_invited"); }
        var player = roomProfile(nk, uid); if (!player) { return nameResult("character_required"); }
        if (player.state.active_room) { return nameResult("in_match"); }
        var occupied = Object.keys(room.members).map(function(id) {return room.members[id];}).concat((room.companions || []).map(function(c:any){return c.slot;}));
        if(room.pending_companion)occupied.push(room.pending_companion.slot);
        var slot = 1; while (occupied.indexOf(slot) >= 0) {slot++;}
        room.members[uid] = slot;
        room.member_fences = room.member_fences || {}; room.member_fences[uid] = nk.uuidv4().replace(/-/g, "");
        player.state.active_room = {id: p.room, fence: room.fence, expires: room.expires, started: false};
        nk.multiUpdate(null, [roomPut(ROOM_COLLECTION, p.room, SYSTEM_OWNER, room, row.version), roomPut(PROFILE_COLLECTION, PROFILE_KEY, uid, player.state, player.object.version)], null, null, false);
        var updated = roomRow(nk, p.room); return updated ? roomTicket(ctx, nk, uid, updated) : nameResult("unavailable");
    } catch (_) { return nameResult("conflict"); }
};
// Called only with Nakama runtime HTTP-key AND the private worker secret, never a user session.
var roomBackend: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    if (ctx.userId) { throw {code: 7, message: "Private room backend"}; }
    if (!payload || payload.length > 1048576) { return nameResult("invalid_payload"); }
    var p: any; try { p = JSON.parse(payload); } catch (_) { return nameResult("invalid_payload"); }
    if (!p || p.v !== 1 || p.secret !== ctx.env.ZORX_NAMES_TOKEN || !/^[a-f0-9]{32}$/.test(p.room || "")) { return nameResult("unauthorized"); }
    try {
        var row = roomRow(nk, p.room); if (!row) { return nameResult("room_expired"); }
        var room = row.value;
        if (p.worker !== room.worker || !/^[a-f0-9]{32}$/.test(p.process || "")) { return nameResult("unauthorized"); }
        if (room.process && room.process !== p.process) { return nameResult("room_worker_lost"); }
        if (room.closed) { return JSON.stringify({v: 1, ok: p.op === "finish" || (p.op === "member_leave" && !!(room.left || {})[p.member]), closed: true}); }
        if (room.expires < Date.now()) { return nameResult("room_expired"); }
        if (p.op === "redeem") {
            if (!/^[a-f0-9]{64}$/.test(p.ticket || "")) { return nameResult("invalid_payload"); }
            var ticket = nameObject(nk, TICKET_COLLECTION, nk.sha256Hash(p.ticket), SYSTEM_OWNER);
            if (!ticket || ticket.value.room !== p.room || ticket.value.expires < Date.now() || room.members[ticket.value.uid] !== ticket.value.slot) { return nameResult("ticket_invalid"); }
            if (googleLoginRequired(ctx) && nk.accountGetId(ticket.value.uid).disableTime > 0) {return nameResult("account_disabled");}
            var player = roomProfile(nk, ticket.value.uid); if (!player || !player.state.active_room || player.state.active_room.fence !== room.fence) { return nameResult("room_expired"); }
            var claim: nkruntime.StorageWriteRequest[] = [];
            if (!room.process) { room.process = p.process; claim.push(roomPut(ROOM_COLLECTION, p.room, SYSTEM_OWNER, room, row.version)); }
            nk.multiUpdate(null, claim, [{collection: TICKET_COLLECTION, key: ticket.key, userId: SYSTEM_OWNER, version: ticket.version}], null, false);
            var profile = JSON.parse(JSON.stringify(player.state.profile)); profile.name = player.name; profile.created = true;
            return JSON.stringify({v: 1, ok: true, room: p.room, slot: ticket.value.slot, capacity: room.capacity, companions: room.companions || [], pending_companion: room.pending_companion || null, diagnostic: room.diagnostic === true, farm_map: room.farm_map || "", camp: room.camp === true, member_fence: (room.member_fences || {})[ticket.value.uid] || "", started: room.started, seed: room.seed, fence: room.fence, profile: profile});
        }
        if (p.fence !== room.fence || ["camp", "start", "heartbeat", "finish", "member_leave", "companion_accept"].indexOf(p.op) < 0) { return nameResult("unauthorized"); }
        if(p.op==="companion_accept"){
            var pending=room.pending_companion;
            if(!room.camp || room.started || !pending || Date.now()<pending.accept_at)return nameResult("request_expired");
            if(pending.expires && Date.now()>pending.expires){delete room.pending_companion;nk.multiUpdate(null,[roomPut(ROOM_COLLECTION,p.room,SYSTEM_OWNER,room,row.version)],null,null,false);return nameResult("invite_expired");}
            if(Object.keys(room.members).length+(room.companions||[]).length>=room.capacity || Object.keys(room.members).some(function(k){return room.members[k]===pending.slot;}))return nameResult("room_full");
            var descriptor={id:pending.id,slot:pending.slot,seed:pending.seed};
            room.companions=(room.companions||[]).concat([descriptor]);delete room.pending_companion;
            nk.multiUpdate(null,[roomPut(ROOM_COLLECTION,p.room,SYSTEM_OWNER,room,row.version)],null,null,false);
            return JSON.stringify({v:1,ok:true,companion:descriptor});
        }
        if(p.op==="start" && room.pending_companion)return nameResult("party_not_ready");
        if (p.op === "member_leave") {
            if (!room.camp || room.started || typeof p.slot !== "number" || !p.profile || p.profile.v !== 1) {return nameResult("invalid_payload");}
            if ((room.left || {})[p.member]) {return JSON.stringify({v:1,ok:true});}
            var leaving = Object.keys(room.members).filter(function(id) {return room.members[id] === p.slot;})[0];
            if (!leaving || !(room.member_fences || {})[leaving] || room.member_fences[leaving] !== p.member) {return nameResult("not_invited");}
            var departing = roomProfile(nk, leaving);
            if (!departing || !departing.state.active_room || departing.state.active_room.fence !== room.fence) {return nameResult("room_expired");}
            departing.state.profile = p.profile; departing.state.revision += 1; delete departing.state.active_room;
            room.left = room.left || {}; room.left[p.member] = true;
            if (Object.keys(room.left).length > 64) {delete room.left[Object.keys(room.left)[0]];}
            delete room.member_fences[leaving]; delete room.members[leaving];
            var remaining = Object.keys(room.members); room.closed = remaining.length === 0;
            if (room.owner === leaving && remaining.length) {room.owner = remaining.sort(function(a,b){return room.members[a]-room.members[b];})[0];}
            nk.multiUpdate(null,[roomPut(PROFILE_COLLECTION,PROFILE_KEY,leaving,departing.state,departing.object.version),roomPut(ROOM_COLLECTION,p.room,SYSTEM_OWNER,room,row.version)],null,null,false);
            return JSON.stringify({v:1,ok:true});
        }
        var writes: nkruntime.StorageWriteRequest[] = [];
        var ids = Object.keys(room.members);
        if (p.op === "start" && !room.camp && ids.length !== room.capacity) { return nameResult("room_not_ready"); }
        if (p.op === "start" && room.camp) {
            var expected = ids.map(function(id) {return room.members[id];}).concat((room.companions || []).map(function(c:any){return c.slot;})).sort();
            if (!Array.isArray(p.slots) || JSON.stringify(p.slots.slice().sort()) !== JSON.stringify(expected)) {return nameResult("room_not_ready");}
        }
        for (var i = 0; i < ids.length; i++) {
            var uid = ids[i]; var player = roomProfile(nk, uid);
            if (!player || !player.state.active_room || player.state.active_room.fence !== room.fence || player.state.active_room.id !== p.room) { return nameResult("room_expired"); }
            if (p.op === "finish") {
                if (!room.diagnostic && (room.started || (room.camp && p.profiles && p.profiles[String(room.members[uid])]))) {
                    var profile = p.profiles && p.profiles[String(room.members[uid])];
                    if (!profile || profile.v !== 1) { return nameResult("invalid_payload"); }
                    player.state.profile = profile;
                }
                delete player.state.active_room; player.state.revision += 1;
            } else {
                player.state.active_room.expires = Date.now() + 60000;
                player.state.active_room.started = room.started || p.op === "start";
            }
            writes.push(roomPut(PROFILE_COLLECTION, PROFILE_KEY, uid, player.state, player.object.version));
        }
        room.started = room.started || p.op === "start"; room.expires = Date.now() + 60000; room.closed = p.op === "finish";
        writes.push(roomPut(ROOM_COLLECTION, p.room, SYSTEM_OWNER, room, row.version));
        var renewal = roomAllocationRenew(nk,p.room,room,room.closed); if (renewal) {writes.push(renewal);}
        nk.multiUpdate(null, writes, null, null, false);
        return JSON.stringify({v: 1, ok: true});
    } catch (_) { return nameResult("conflict"); }
};
var roomCreateGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_room_create_v1", roomCreate, ctx, logger, nk, payload); };
var roomJoinGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_room_join_v1", roomJoin, ctx, logger, nk, payload); };
var roomCancel: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    var uid = nameUser(ctx); var p = roomPayload(payload);
    if (!p || Object.keys(p).length !== 2 || (p.diagnostic !== true && !/^[a-f0-9]{32}$/.test(p.room || ""))) { return nameResult("invalid_payload"); }
    try {
        if (p.diagnostic === true) {
            var own = roomProfile(nk, uid);
            if (!own || !own.state.active_room) {return JSON.stringify({v:1,ok:true});}
            p.room = own.state.active_room.id;
            var ownedRoom = roomRow(nk,p.room);
            if (!ownedRoom || ownedRoom.value.diagnostic !== true) {return nameResult("in_match");}
        }
        var row = roomRow(nk, p.room); if (!row || !row.value.members[uid]) { return nameResult("not_invited"); }
        var room = row.value; if (room.camp && room.process && !room.closed) {return nameResult("use_room");} if (room.started && !room.diagnostic) { return nameResult("in_match"); }
        if (room.closed && !room.diagnostic) { return JSON.stringify({v: 1, ok: true}); }
        var writes: nkruntime.StorageWriteRequest[] = [];
        Object.keys(room.members).forEach(function(id) {
            var player = roomProfile(nk, id);
            if (player && player.state.active_room && player.state.active_room.fence === room.fence) {
                delete player.state.active_room; player.state.revision += 1;
                writes.push(roomPut(PROFILE_COLLECTION, PROFILE_KEY, id, player.state, player.object.version));
            }
        });
        room.closed = true; writes.push(roomPut(ROOM_COLLECTION, p.room, SYSTEM_OWNER, room, row.version));
        var renewal = roomAllocationRenew(nk,p.room,room,room.closed); if (renewal) {writes.push(renewal);}
        nk.multiUpdate(null, writes, null, null, false);
        return JSON.stringify({v: 1, ok: true});
    } catch (_) { return nameResult("conflict"); }
};
var roomCancelGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_room_cancel_v1", roomCancel, ctx, logger, nk, payload); };
var roomResume: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    var uid = nameUser(ctx); var p = roomPayload(payload);
    if (!p || Object.keys(p).length !== 1) { return nameResult("invalid_payload"); }
    if (!roomEnabled(ctx)) { return nameResult("not_configured"); }
    try {
        var player = roomProfile(nk, uid);
        if (!player || !player.state.active_room) { return nameResult("room_expired"); }
        var row = roomRow(nk, player.state.active_room.id);
        return row ? roomTicket(ctx, nk, uid, row) : nameResult("room_expired");
    } catch (_) { return nameResult("unavailable"); }
};
var roomResumeGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) { return rpcDispatch("zorx_room_resume_v1", roomResume, ctx, logger, nk, payload); };

// Runtime HTTP-key + private worker secret only. Existing rooms may finish during maintenance.
function roomMaintenance(ctx: nkruntime.Context, nk: nkruntime.Nakama): boolean {
    var row = nameObject(nk, ROOM_COLLECTION, "maintenance", SYSTEM_OWNER);
    return ctx.env.ZORX_MAINTENANCE === "true" || !!(row && row.value.enabled === true);
}
var onlineStatus: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    nameUser(ctx); var p = roomPayload(payload);
    if (!p || Object.keys(p).length !== 1) {return nameResult("invalid_payload");}
    return JSON.stringify({v:1,ok:true,maintenance:roomMaintenance(ctx,nk)});
};
var onlineStatusGateway: nkruntime.RpcFunction = function(ctx, logger, nk, payload) {return rpcDispatch("zorx_online_status_v1",onlineStatus,ctx,logger,nk,payload);};
var maintenanceAdmin: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    if (ctx.userId) {throw {code:7,message:"Private administration"};}
    var p = roomPayload(payload);
    if (!p || Object.keys(p).length !== 3 || p.secret !== ctx.env.ZORX_NAMES_TOKEN || typeof p.enabled !== "boolean") {return nameResult("unauthorized");}
    var row = nameObject(nk,ROOM_COLLECTION,"maintenance",SYSTEM_OWNER);
    try {nk.storageWrite([roomPut(ROOM_COLLECTION,"maintenance",SYSTEM_OWNER,{v:1,enabled:p.enabled},row ? row.version : "*")]); return JSON.stringify({v:1,ok:true,maintenance:p.enabled});}
    catch (_) {return nameResult("conflict");}
};

// Static process pool: each identity has a distinct Service/path, never a load-balanced shared WS.
function roomPool(ctx: nkruntime.Context): {id:string;url:string}[] {
    if (!ctx.env.ZORX_ROOM_WORKERS) {return [{id:ctx.env.ZORX_ROOM_WORKER_ID || "staging-0",url:ctx.env.ZORX_ROOM_WS_URL}];}
    var pool = JSON.parse(ctx.env.ZORX_ROOM_WORKERS);
    if (!Array.isArray(pool) || !pool.length || pool.length > 16) {throw Error("Invalid room pool");}
    var seen: {[key:string]:boolean} = {};
    pool.forEach(function(worker) {
        if (!worker || Object.keys(worker).length !== 2 || !/^[a-z0-9-]{1,40}$/.test(worker.id) || seen[worker.id] || !/^(wss:\/\/[^\s]+|ws:\/\/127\.0\.0\.1:[0-9]+(?:\/[^\s]*)?)$/.test(worker.url)) {throw Error("Invalid room worker");} seen[worker.id] = true;
    });
    return pool;
}
function roomAllocation(ctx: nkruntime.Context,nk: nkruntime.Nakama,id:string): any {
    var candidates = roomPool(ctx).map(function(worker) {
        var key = "allocation-"+worker.id;
        var row = nameObject(nk,ROOM_COLLECTION,key,SYSTEM_OWNER);
        var leases = row ? row.value.leases : {};
        Object.keys(leases).forEach(function(room) {if (leases[room].expires < Date.now()) {delete leases[room];}});
        return {worker:worker,key:key,row:row,leases:leases};
    });
    candidates.sort(function(a,b){return Object.keys(a.leases).length-Object.keys(b.leases).length;});
    var selected = candidates[0];
    if (Object.keys(selected.leases).length >= 8) {return null;}
    selected.leases[id] = {expires:Date.now()+60000};
    return {worker:selected.worker,write:roomPut(ROOM_COLLECTION,selected.key,SYSTEM_OWNER,{v:1,leases:selected.leases},selected.row ? selected.row.version : "*")};
}
function roomAllocationRenew(nk:nkruntime.Nakama,id:string,room:any,release:boolean): nkruntime.StorageWriteRequest | null {
    var row = nameObject(nk,ROOM_COLLECTION,"allocation-"+room.worker,SYSTEM_OWNER);
    if (!row || !row.value.leases[id]) {return null;} // legacy rooms before the pool rollout
    var leases = row.value.leases;
    if (release) {delete leases[id];} else {leases[id].expires = room.expires;}
    Object.keys(leases).forEach(function(key){if (leases[key].expires < Date.now()) {delete leases[key];}});
    return roomPut(ROOM_COLLECTION,row.key,SYSTEM_OWNER,{v:1,leases:leases},row.version);
}
