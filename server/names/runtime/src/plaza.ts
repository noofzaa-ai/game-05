// Social-only authoritative presence. No profile writes, rewards, inventory or gameplay room locks.
var PLAZA_LABEL = "zorx-plaza-v1";
var PLAZA_REGISTRY = "zorx_plaza_v1";
type PlazaState = {players: {[id:string]:any}; empty: number};
var plazaDiscover: nkruntime.RpcFunction = function(ctx, logger, nk, payload) {
    return rpcDispatch("zorx_plaza_v1", function(c, _l, n, p) {
        if(p !== '{"v":1}') {return nameResult("invalid_payload");}
        var player=roomProfile(n,nameUser(c));
        if(!player || player.state.active_room) {return nameResult("in_match");}
        for(var attempt=0;attempt<3;attempt++){
            var registry=nameObject(n,PLAZA_REGISTRY,"current",SYSTEM_OWNER);
            var current=registry&&typeof registry.value.match_id==="string"?n.matchGet(registry.value.match_id):null;
            if(current&&current.label===PLAZA_LABEL&&current.size<24){return JSON.stringify({v:1,ok:true,match:current.matchId,capacity:24});}
            var matches=n.matchList(100,true,PLAZA_LABEL,0,23);
            matches.sort(function(a,b){return a.matchId < b.matchId ? -1 : a.matchId > b.matchId ? 1 : 0;});
            var selected=matches.length?matches[0].matchId:n.matchCreate("zorx_plaza",{});
            try{
                n.storageWrite([roomPut(PLAZA_REGISTRY,"current",SYSTEM_OWNER,{match_id:selected},registry?registry.version:"*")]);
                return JSON.stringify({v:1,ok:true,match:selected,capacity:24});
            }catch(_){/* A concurrent discovery won; reread its canonical channel. Empty orphan expires. */}
        }
        return nameResult("rate_limited");
    },ctx,logger,nk,payload);
};
var plazaInit: nkruntime.MatchInitFunction<PlazaState> = function(){return {state:{players:{},empty:0},tickRate:5,label:PLAZA_LABEL};};

var plazaJoinAttempt: nkruntime.MatchJoinAttemptFunction<PlazaState> = function(ctx,_logger,nk,_dispatcher,_tick,state,presence){
        var player=roomProfile(nk,presence.userId);
        var actorContext:any={userId:presence.userId,env:ctx.env};
        var accept=Object.keys(state.players).length<24 && !state.players[presence.userId] && !!player && !player.state.active_room && googleAccountAllowed(actorContext,nk);
        return {state:state,accept:accept,rejectMessage:"plaza_unavailable"};
    };

var plazaJoin: nkruntime.MatchJoinFunction<PlazaState> = function(_ctx,_logger,nk,_dispatcher,tick,state,presences){
        presences.forEach(function(p){
            if(Object.keys(state.players).length>=24||state.players[p.userId]){_dispatcher.matchKick([p]);return;}
            var player=roomProfile(nk,p.userId);if(!player){return;}
            // Project only visible gear/appearance; never expose stash/vault/currency/receipts.
            state.players[p.userId]={presence:p,id:p.userId,name:player.name,loadout:player.state.profile.loadout,appearance:player.state.profile.appearance,x:0,z:-13,fx:0,fz:-1,speed:0,tick:tick,visible:false,chatTokens:3,chatTick:tick};
        });return {state:state};
    };

var plazaLeave: nkruntime.MatchLeaveFunction<PlazaState> = function(_c,_l,_n,_d,_t,state,presences){
        presences.forEach(function(p){var old=state.players[p.userId];if(old&&old.presence.sessionId===p.sessionId){delete state.players[p.userId];}});return {state:state};
    };

var plazaLoop: nkruntime.MatchLoopFunction<PlazaState> = function(_ctx,_logger,nk,dispatcher,tick,state,messages){
        var handled:{[id:string]:boolean}={},chatted:{[id:string]:boolean}={};
        messages.forEach(function(m){
            var a=state.players[m.sender.userId];
            if(!a||a.presence.sessionId!==m.sender.sessionId){return;}
            if(m.opCode===3){
                if(chatted[a.id]||!a.visible||m.data.byteLength>1024)return;
                chatted[a.id]=true;
                var elapsed=Math.max(0,tick-a.chatTick);a.chatTokens=Math.min(3,a.chatTokens+elapsed/5);a.chatTick=tick;
                if(a.chatTokens<1){dispatcher.broadcastMessage(5,'{"error":"rate_limited"}',[a.presence],null,true);return;}
                // Charge attempts too; malformed chat cannot bypass the per-account budget.
                a.chatTokens-=1;
                try{var chat=JSON.parse(nk.binaryToString(m.data));
                    if(!chat||Object.keys(chat).length!==1||typeof chat.text!=="string")return;
                    var text=chat.text.trim();
                    if(!text||text.replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g,"x").length>160||/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/.test(text))return;
                    // Sender identity comes exclusively from authoritative membership/profile.
                    dispatcher.broadcastMessage(4,JSON.stringify({name:a.name,text:text,at:Date.now()}),null,null,true);
                }catch(_){}return;
            }
            if(handled[a.id]||m.opCode!==1||m.data.byteLength>256){return;}
            handled[a.id]=true;
            try{
                var p=JSON.parse(nk.binaryToString(m.data));
                if(!p||Object.keys(p).length!==5||![p.x,p.z,p.fx,p.fz,p.speed].every(function(v){return typeof v==="number"&&isFinite(v);})||Math.abs(p.x)>12.5||p.z < -32.5||p.z > -12){return;}
                var dx=p.x-a.x,dz=p.z-a.z,dist=Math.sqrt(dx*dx+dz*dz),limit=Math.min(3,Math.max(1,tick-a.tick)*1.8);
                if(a.visible && dist>limit){p.x=a.x+dx*limit/dist;p.z=a.z+dz*limit/dist;}
                a.x=p.x;a.z=p.z;a.fx=Math.max(-1,Math.min(1,p.fx));a.fz=Math.max(-1,Math.min(1,p.fz));a.speed=Math.max(0,Math.min(2,p.speed));a.tick=tick;a.visible=true;
            }catch(_){return;}
        });
        var ids=Object.keys(state.players);
        if(!ids.length){state.empty++;if(state.empty>100){return null;}}else{state.empty=0;}
        var actors=ids.filter(function(id){return state.players[id].visible&&tick-state.players[id].tick<50;}).map(function(id){
            var a=state.players[id];return {id:a.id,name:a.name,x:a.x,z:a.z,fx:a.fx,fz:a.fz,speed:a.speed};
        });
        // Full appearance only once per second; 5Hz movement snapshots stay compact.
        if(tick%5===0){actors.forEach(function(a:any){a.loadout=state.players[a.id].loadout;a.appearance=state.players[a.id].appearance;});}
        if(ids.length){dispatcher.broadcastMessage(2,JSON.stringify({v:1,actors:actors}),null,null,false);}
        return {state:state};
    };

var plazaTerminate: nkruntime.MatchTerminateFunction<PlazaState> = function(_c,_l,_n,_d,_t,state){return {state:state};};

var plazaSignal: nkruntime.MatchSignalFunction<PlazaState> = function(_c,_l,_n,_d,tick,state,data){
    try{var p=JSON.parse(data),a=state.players[p.from],b=state.players[p.target];
        if(p.op==="near_invite" && a && b && a.visible && b.visible && tick-a.tick<25 && tick-b.tick<25 && Math.pow(a.x-b.x,2)+Math.pow(a.z-b.z,2)<=16)return {state:state,data:"near"};
    }catch(_){}
    return {state:state,data:""};
};
