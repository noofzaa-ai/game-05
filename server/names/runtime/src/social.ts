// Nakama owns friend relationships and notifications; actor is always the authenticated account.
var PARTY_INVITE_CODE = 501;
var PRESENCE_COLLECTION = "zorx_presence_v1";
function socialRoom(nk:nkruntime.Nakama,uid:string):any {
    var player=roomProfile(nk,uid);
    if(!player || !player.state.active_room)return null;
    var row=roomRow(nk,player.state.active_room.id);
    return row && !row.value.closed && row.value.expires>Date.now() && !!row.value.members[uid] ? row : null;
}
function roomInviteLimit(nk: nkruntime.Nakama,row: nkruntime.StorageObject,target: string): void {
    var room = row.value; room.invited = room.invited || {};
    if (room.invited[target] && Date.now()-room.invited[target] < 10000) {throw Error("invite cooldown");}
    room.invited[target] = Date.now();
    var keys = Object.keys(room.invited); if (keys.length > 64) {delete room.invited[keys[0]];}
    nk.multiUpdate(null,[roomPut(ROOM_COLLECTION,row.key,SYSTEM_OWNER,room,row.version)],null,null,false);
}
function socialName(nk: nkruntime.Nakama, uid: string): string {
    var record = nameRecord(nameObject(nk, CHARACTER_COLLECTION, CHARACTER_NAME_KEY, uid));
    return record ? record.name : "Player";
}
function socialFriend(nk: nkruntime.Nakama, uid: string, target: string, state: number): boolean {
    var cursor: string | undefined;
    for (var page = 0; page < 10; page++) {
        var list = nk.friendsList(uid, 100, state, cursor);
        if ((list.friends || []).some(function(friend) {return friend.user && friend.user.userId === target;})) {return true;}
        if (!list.cursor) {break;} cursor = list.cursor;
    }
    return false;
}
var socialRpc: nkruntime.RpcFunction = function(ctx, _logger, nk, payload) {
    var uid = nameUser(ctx); var p = roomPayload(payload);
    if (!p || typeof p.op !== "string") {return nameResult("invalid_payload");}
    try {
        if(p.op === "presence" && Object.keys(p).length===2){
            nk.storageWrite([{collection:PRESENCE_COLLECTION,key:"seen",userId:uid,value:{at:Date.now()},permissionRead:0,permissionWrite:0}]);
            return JSON.stringify({v:1,ok:true});
        }
        if (p.op === "list" && (Object.keys(p).length === 2 || (Object.keys(p).length === 3 && typeof p.cursor === "string" && p.cursor.length <= 2048))) {
            var page = nk.friendsList(uid, 50, undefined, p.cursor);
            var friends=page.friends || [];
            var ids=friends.map(function(f){return f.user!.userId;});
            var summaries:{[id:string]:any}={};
            if(ids.length){
                // Project only presence/room metadata in one bounded query: never fetch friends' inventories.
                var placeholders=ids.map(function(_id,i){return "$"+(i+1)+"::uuid";}).join(",");
                var rows=nk.sqlQuery("SELECT u.id::text AS id, c.value->>'name' AS name, seen.value->>'at' AS seen, r.value->>'expires' AS expires, r.value->>'closed' AS closed, r.value->>'started' AS started, r.value->>'camp' AS camp, r.value->>'owner' AS owner, r.value->>'capacity' AS capacity, (r.value->'members')::text AS members FROM users u LEFT JOIN storage c ON c.user_id=u.id AND c.collection='zorx_character_v1' AND c.key='display_name' LEFT JOIN storage p ON p.user_id=u.id AND p.collection='zorx_profile_v1' AND p.key='camp' LEFT JOIN storage seen ON seen.user_id=u.id AND seen.collection='zorx_presence_v1' AND seen.key='seen' LEFT JOIN storage r ON r.user_id='00000000-0000-0000-0000-000000000000'::uuid AND r.collection='zorx_rooms_v1' AND r.key=p.value->'active_room'->>'id' WHERE u.id IN ("+placeholders+")",ids);
                rows.forEach(function(r){summaries[r.id]=r;});
            }
            return JSON.stringify({v:1,ok:true,cursor:page.cursor || "",friends:friends.map(function(friend) {
                var id=friend.user!.userId;var info=summaries[id] || {};
                var members=info.members ? JSON.parse(info.members) : {};
                var activeRoom=friend.state===0 && info.closed==="false" && Number(info.expires)>Date.now() && !!members[id];
                var active=friend.state===0 && (activeRoom || Number(info.seen)>Date.now()-75000);
                var count=Object.keys(members).length;var capacity=Number(info.capacity);
                return {id:id,name:info.name || "Player",state:friend.state,online:active || friend.user!.online===true,
                    room:activeRoom ? {count:count,capacity:capacity,started:info.started==="true",
                    joinable:info.camp==="true" && info.started==="false" && info.owner===id && count<capacity} : null};
            })});
        }
        if (p.op === "request" && Object.keys(p).length === 3 && typeof p.name === "string") {
            var validated = nameValidate(ctx,nk,JSON.stringify({v:1,name:p.name}));
            if (!validated.ok) {return nameResult(validated.error || "invalid_payload");}
            var record = nameObject(nk,NAME_REGISTRY,nk.sha256Hash(validated.canonical!),SYSTEM_OWNER);
            if (!record) {return nameResult("player_not_found");}
            var target = record.value.owner_id;
            if (target === uid) {return nameResult("cannot_add_self");}
            nk.friendsAdd(uid,ctx.username || "",[target],[],{});
            return JSON.stringify({v:1,ok:true});
        }
        if ((p.op === "accept" || p.op === "remove") && Object.keys(p).length === 3 && /^[a-f0-9-]{36}$/.test(p.target || "")) {
            if (p.op === "accept") {
                if (!socialFriend(nk,uid,p.target,2)) {return nameResult("request_expired");}
                nk.friendsAdd(uid,ctx.username || "",[p.target],[],{});
            } else {nk.friendsDelete(uid,ctx.username || "",[p.target],[]);}
            return JSON.stringify({v:1,ok:true});
        }
        if(p.op==="invite" && Object.keys(p).length===5 && /^companion:[a-f0-9]{13}$/.test(p.target||"") && /^[a-f0-9]{32}$/.test(p.room||"") && /^[a-f0-9]{32}$/.test(p.invite||"")){
            var cr=roomRow(nk,p.room),offer=companionOffer(nk,uid);
            if(!cr || cr.value.owner!==uid || cr.value.closed || cr.value.started || cr.value.expires<Date.now() || !cr.value.camp || nk.sha256Hash(p.invite)!==cr.value.invite_hash)return nameResult("room_expired");
            if(p.target!=="companion:"+offer.value.seed || (offer.value.room && offer.value.room!==p.room))return nameResult("companion_changed");
            if(cr.value.pending_companion || (cr.value.companions||[]).length)return nameResult("request_expired");
            var used=Object.keys(cr.value.members).map(function(k){return cr!.value.members[k];});
            var slot=2;while(used.indexOf(slot)>=0)slot++;
            if(slot>cr.value.capacity)return nameResult("room_full");
            cr.value.pending_companion={id:"arun",seed:offer.value.seed,slot:slot,accept_at:Date.now()+10000,expires:Date.now()+30000};
            offer.value.room=p.room;
            nk.multiUpdate(null,[roomPut(ROOM_COLLECTION,p.room,SYSTEM_OWNER,cr.value,cr.version),roomPut(ROOM_COLLECTION,offer.key,SYSTEM_OWNER,offer.value,offer.version)],null,null,false);
            return JSON.stringify({v:1,ok:true,pending:true});
        }
        if (p.op === "invite" && (Object.keys(p).length === 5 || Object.keys(p).length === 6) && /^[a-f0-9-]{36}$/.test(p.target || "") && /^[a-f0-9]{32}$/.test(p.room || "") && /^[a-f0-9]{32}$/.test(p.invite || "")) {
            var row = roomRow(nk,p.room);
            if (!row || row.value.closed || row.value.started || row.value.expires < Date.now() || !row.value.camp || row.value.started || !row.value.members[uid] || nk.sha256Hash(p.invite) !== row.value.invite_hash) {return nameResult("room_expired");}
            if (!socialFriend(nk,uid,p.target,0)) {
                if(typeof p.match!=="string" || p.match.length>128 || nk.matchSignal(p.match,JSON.stringify({op:"near_invite",from:uid,target:p.target}))!=="near")return nameResult("not_friends");
            }
            if (Object.keys(row.value.members).length + (row.value.companions || []).length + (row.value.pending_companion ? 1 : 0) >= row.value.capacity) {return nameResult("room_full");}
            roomInviteLimit(nk,row,p.target);
            nk.notificationSend(p.target,"Party invite",{room:p.room,invite:p.invite,name:socialName(nk,uid)},PARTY_INVITE_CODE,uid,true);
            return JSON.stringify({v:1,ok:true});
        }
        if (p.op === "inbox" && (Object.keys(p).length === 2 || (Object.keys(p).length === 3 && typeof p.cursor === "string" && p.cursor.length <= 2048))) {
            var notifications = nk.notificationsList(uid,50,p.cursor);
            return JSON.stringify({v:1,ok:true,cursor:notifications.cursor || "",invites:notifications.notifications.filter(function(n) {return n.code === PARTY_INVITE_CODE;}).map(function(n) {var content = typeof n.content === "string" ? JSON.parse(n.content) : n.content; return {id:n.id,name:content.name,room:content.room,invite:content.invite};})});
        }
        if (p.op === "ack" && Object.keys(p).length === 3 && typeof p.id === "string" && /^[a-f0-9-]{36}$/.test(p.id)) {
            var owned = nk.notificationsGetId([p.id],uid);
            if (!owned.length || owned[0].code !== PARTY_INVITE_CODE) {return nameResult("request_expired");}
            nk.notificationsDelete([{notificationId:p.id,userId:uid}]);
            return JSON.stringify({v:1,ok:true});
        }
        return nameResult("invalid_payload");
    } catch (_) {return nameResult("unavailable");}
};
var socialGateway: nkruntime.RpcFunction = function(ctx,logger,nk,payload) {return rpcDispatch("zorx_social_v1",socialRpc,ctx,logger,nk,payload);};
