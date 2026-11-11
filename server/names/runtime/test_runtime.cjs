const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const path = require('node:path');
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../../../build/names-runtime/index.js'), 'utf8'), context);
let rows = new Map(), serial = 0, httpCalls = 0, injectCollision = false;
const key = r => [r.collection,r.userId,r.key].join('|');
const copy = r => JSON.parse(JSON.stringify(r));
const nk = {
 sha256Hash: s => crypto.createHash('sha256').update(s).digest('hex'),
 httpRequest(url,method,headers,body,timeout,insecure) {
  httpCalls++;
  assert.equal(url,'http://name-validator:8051/validate-name');
  assert.equal(method,'post'); assert.equal(insecure,false); assert.equal(timeout,2000);
  assert.ok(headers.Authorization.startsWith('Bearer '));
  const name=JSON.parse(body).name.trim();
  return {code:200,body:JSON.stringify({v:1,ok:true,name,canonical:name.toLowerCase()})};
 },
 storageRead: ids => ids.map(i=>rows.get(key(i))).filter(Boolean).map(copy),
 multiUpdate(_accounts,writes,deletes,_wallets,ledger) {
  assert.equal(ledger,false);
  if(injectCollision) {
   injectCollision=false;
   const registry=writes.find(w=>w.collection===context.NAME_REGISTRY);
   rows.set(key(registry),{...copy(registry),value:{v:1,owner_id:'other'},version:String(++serial)});
  }
  for(const w of (writes||[])) {
   const old=rows.get(key(w));
   if(w.version==='*' ? !!old : !old || w.version!==old.version) throw Error('CAS');
   assert.equal(w.permissionRead,0); assert.equal(w.permissionWrite,0);
  }
  for(const d of (deletes||[])) if(rows.get(key(d))?.version!==d.version) throw Error('CAS');
  const next=new Map(rows);
  for(const w of (writes||[])) next.set(key(w),{...copy(w),version:String(++serial)});
  for(const d of (deletes||[])) next.delete(key(d));
  rows=next;
 }
};
const env={ZORX_NAMES_URL:'http://name-validator:8051',ZORX_NAMES_TOKEN:'unit-test-token-'.repeat(4)};
const ctx=id=>({userId:id,env});
const invoke=(id,name)=>JSON.parse(context.nameClaim(ctx(id),{},nk,JSON.stringify({v:1,name})));
assert.throws(()=>context.nameClaim({env},{},nk,'{"v":1,"name":"Hero"}'), e=>e.code===16);
assert.equal(httpCalls,0);
assert.equal(JSON.parse(context.nameClaim(ctx('u1'),{},nk,'{"v":1,"name":"Hero","user_id":"u2"}')).error,'invalid_payload');
assert.equal(httpCalls,0);
assert.equal(invoke('u1',' Hero ').name,'Hero');
assert.equal(invoke('u2','hero').error,'name_taken');
assert.equal(rows.size,2);
assert.equal(invoke('u1','Hero').ok,true); assert.equal(rows.size,2);
assert.equal(JSON.parse(context.nameGet(ctx('u1'),{},nk,'{"v":1}')).name,'Hero');
assert.equal(JSON.parse(context.nameGet(ctx('u2'),{},nk,'{"v":1}')).name,null);
assert.equal(invoke('u1','New Name').ok,true); assert.equal(rows.size,2);
assert.equal(invoke('u2','Hero').ok,true); assert.equal(rows.size,4);
assert.equal(invoke('u1','new name').name,'new name'); assert.equal(rows.size,4);
injectCollision=true;
assert.equal(invoke('u3','Race').error,'name_taken');
assert.equal(JSON.parse(context.nameGet(ctx('u3'),{},nk,'{"v":1}')).name,null);
const originalHttp=nk.httpRequest;
nk.httpRequest=()=>{throw Error('private detail must not escape');};
const failure=JSON.parse(context.nameClaim(ctx('u1'),{},nk,'{"v":1,"name":"Valid"}'));
assert.equal(failure.error,'unavailable'); assert.ok(!JSON.stringify(failure).includes('private'));
nk.httpRequest=originalHttp;
const rpcs=[];
const authHooks = {};
const initializer = {registerRpc:id=>rpcs.push(id),registerBeforeWriteStorageObjects:()=>{},registerBeforeDeleteStorageObjects:()=>{}};
for (const method of ['Device','Custom','Email','Apple','Facebook','FacebookInstantGame','GameCenter','Steam']) {
 initializer['registerBeforeAuthenticate'+method] = hook => {authHooks[method]=hook;};
}
initializer.registerBeforeUnlinkGoogle = hook => {authHooks.UnlinkGoogle=hook;};
context.InitModule({env},{info:()=>{}},nk,initializer);
for (const hook of Object.values(authHooks)) {
 assert.throws(()=>hook({env:{ZORX_REQUIRE_GOOGLE:'1'}},{},nk,{}),e=>e.code===7);
 assert.doesNotThrow(()=>hook({env:{}},{},nk,{}));
}
const googleCtx={userId:'google-test',env:{...env,ZORX_REQUIRE_GOOGLE:'1'}};
nk.accountGetId=()=>({user:{googleId:''}});
assert.equal(context.googleAccountAllowed(googleCtx,nk),false);
assert.equal(JSON.parse(context.rpcDispatch('probe',()=>'{"ok":true}',googleCtx,{},nk,'{}')).error,'google_login_required');
nk.accountGetId=()=>({user:{googleId:'verified-google-sub'}});
assert.equal(context.googleAccountAllowed(googleCtx,nk),true);
assert.equal(JSON.parse(context.rpcDispatch('probe',()=>'{"ok":true}',googleCtx,{},nk,'{}')).ok,true);
nk.accountGetId=()=>({disableTime:123,user:{googleId:'verified-google-sub'}});
assert.equal(context.googleAccountAllowed(googleCtx,nk),false);
nk.accountGetId=()=>({user:{googleId:'verified-google-sub'}});
console.log('PASS Google-only auth hooks, banned account and legacy unlinked-session RPC rejection');
assert.deepEqual(rpcs,['zorx_name_get_v1','zorx_name_claim_v1','zorx_profile_get_v1','zorx_profile_command_v1','zorx_room_create_v1','zorx_room_join_v1','zorx_room_backend_v1','zorx_room_cancel_v1','zorx_room_resume_v1','zorx_social_v1','zorx_online_status_v1','zorx_maintenance_admin_v1','zorx_admin_v1','zorx_feedback_v1']);
assert.throws(()=>context.InitModule({env:{}},{},nk,{}));
console.log('PASS runtime auth, no spoofed IDs, case-insensitive duplicates, idempotence, private storage, atomic rename/release, collision rollback, safe failures, initialization');

assert.throws(()=>context.nameBeforeWrite(ctx('u1'),{},nk,{objects:[{collection:context.CHARACTER_COLLECTION}]}), e=>e.code===7);
assert.throws(()=>context.nameBeforeWrite(ctx('u1'),{},nk,{objects:[{collection:context.NAME_REGISTRY}]}), e=>e.code===7);
assert.throws(()=>context.nameBeforeDelete(ctx('u1'),{},nk,{objectIds:[{collection:context.CHARACTER_COLLECTION}]}), e=>e.code===7);
assert.doesNotThrow(()=>context.nameBeforeWrite(ctx('u1'),{},nk,{objects:[{collection:'unrelated'}]}));
console.log('PASS API hooks reject direct client creation/deletion in authoritative collections');

// Profile transport/CAS tests use a mock authority; real rules are tested in Godot/stack.
let privateCalls=0, failProfile=false, collideProfile=false;
nk.uuidv4=()=>crypto.randomUUID();
const nameHttp=nk.httpRequest;
nk.httpRequest=(url,method,headers,body,timeout,insecure)=>{
 if(!url.endsWith('/profile')) return nameHttp(url,method,headers,body,timeout,insecure);
 privateCalls++;
 if(failProfile) throw Error('offline-private-secret');
 const p=JSON.parse(body);
 assert.deepEqual(Object.keys(p).sort(),['command','name','seed','state','v']);
 if(p.command?.type==='invalid') return {code:200,body:JSON.stringify({ok:false,error:'invalid_command'})};
 return {code:200,body:JSON.stringify({v:1,ok:true,profile:{name:p.name,created:!!p.name,marker:(p.state?.profile.marker||0)+(p.command?1:0)},rng_state:'123',result:{ok:true}})};
};
const getProfile=id=>JSON.parse(context.profileGet(ctx(id),{},nk,'{"v":1}'));
const callProfile=(id,p)=>JSON.parse(context.profileCommand(ctx(id),{},nk,JSON.stringify(p)));
const req=(revision,id='request_id_00000001',type='anything')=>({v:1,revision,request_id:id,command:{type}});
assert.throws(()=>context.profileGet({env},{},nk,'{"v":1}'),e=>e.code===16);
assert.equal(callProfile('not-yet',req(1)).error,'profile_required');
assert.equal(getProfile('p1').revision,1);
assert.equal(getProfile('p1').revision,1);
let out=callProfile('p1',req(1));assert.equal(out.revision,2);assert.equal(out.profile.marker,1);
assert.equal(out.rng_state,undefined);assert.equal(out.receipts,undefined);
out=callProfile('p1',req(1));assert.equal(out.replayed,true);assert.equal(out.revision,2);
assert.equal(callProfile('p1',req(2)).error,'request_id_reused');
assert.equal(callProfile('p1',req(1,'request_id_00000002')).error,'revision_conflict');
assert.equal(callProfile('p1',{...req(2),profile:{gold:999}}).error,'invalid_payload');
assert.equal(callProfile('p1',{...req(2),user_id:'p2'}).error,'invalid_payload');
assert.equal(callProfile('p1',{...req(2),revision:true}).error,'invalid_payload');
assert.equal(callProfile('p1',req(2,'request_id_00000002','invalid')).error,'invalid_command');
assert.equal(getProfile('p1').revision,2);
assert.equal(getProfile('p2').profile.marker,0);
failProfile=true;
assert.equal(callProfile('p1',req(2,'request_id_00000002')).error,'unavailable');
assert.equal(getProfile('p1').revision,2);
failProfile=false;
for(let i=2;i<40;i++) assert.equal(callProfile('p1',req(i,'request_id_'+String(i).padStart(10,'0'))).ok,true);
assert.equal(rows.get([context.PROFILE_COLLECTION,'p1',context.PROFILE_KEY].join('|')).value.receipts.length,32);
assert.equal(callProfile('p1',req(1)).error,'revision_conflict');
assert.throws(()=>context.nameBeforeWrite(ctx('p1'),{},nk,{objects:[{collection:context.PROFILE_COLLECTION}]}),e=>e.code===7);
assert.throws(()=>context.nameBeforeDelete(ctx('p1'),{},nk,{objectIds:[{collection:context.PROFILE_COLLECTION}]}),e=>e.code===7);
console.log('PASS profile auth, server-only initialization, identity isolation, CAS revisions, idempotent retry, request ID misuse, payload injection, failure rollback, bounded receipts and protected storage');

// Gate must be registered around every public RPC, not just one runtime VM.
const gateway=(rpc,handler)=>(ctx,logger,nk,payload)=>context.rpcDispatch(rpc,handler,ctx,logger,nk,payload);
let mockNow=1000000;vm.runInContext('Date.now = function(){return '+mockNow+';}',context);
const securityCtx=id=>({userId:id,env:{...env,ZORX_RPC_BURST:'3',ZORX_RPC_REFILL:'1',ZORX_RPC_AUDIT_THRESHOLD:'2'}});
let invoked=0;const warnings=[];const logger={warn:s=>warnings.push(s)};
const guarded=gateway('test_rpc',()=>{invoked++;return '{"v":1,"ok":true}';});
for(let i=0;i<3;i++) assert.equal(JSON.parse(guarded(securityCtx('gate1'),logger,nk,'{}')).ok,true);
assert.equal(JSON.parse(guarded(securityCtx('gate1'),logger,nk,'{}')).error,'rate_limited');assert.equal(invoked,3);
const secondVmGuard=gateway('test_rpc',()=>'{"v":1,"ok":true}');
assert.equal(JSON.parse(secondVmGuard(securityCtx('gate1'),logger,nk,'{}')).error,'rate_limited');
assert.equal(JSON.parse(secondVmGuard(securityCtx('gate2'),logger,nk,'{}')).ok,true);
assert.equal(warnings.length,1);assert.ok(!warnings[0].includes('gate1'));assert.ok(warnings[0].includes('rate_limited'));
vm.runInContext('Date.now = function(){return 1001000;}',context);
assert.equal(JSON.parse(guarded(securityCtx('gate1'),logger,nk,'{}')).ok,true);
assert.equal(JSON.parse(guarded(securityCtx('gate1'),logger,nk,'{}')).error,'rate_limited');
vm.runInContext('Date.now = function(){return 1;}',context);
assert.equal(JSON.parse(guarded(securityCtx('gate1'),logger,nk,'{}')).error,'rate_limited');
const guardedBad=gateway('bad_rpc',()=>'{"v":1,"ok":false,"error":"item_not_owned"}');
assert.equal(JSON.parse(guardedBad(securityCtx('bad1'),logger,nk,'{}')).error,'item_not_owned');
assert.equal(JSON.parse(guardedBad(securityCtx('bad1'),logger,nk,'{}')).error,'item_not_owned');
assert.ok(warnings.some(w=>w.includes('item_not_owned')));
assert.equal(JSON.parse(guarded(securityCtx('large1'),logger,nk,'x'.repeat(4097))).error,'invalid_payload');
const savedMulti=nk.multiUpdate;nk.multiUpdate=()=>{throw Error('CAS contention');};
assert.equal(JSON.parse(guarded(securityCtx('contention'),logger,nk,'{}')).error,'rate_limited');nk.multiUpdate=savedMulti;
assert.throws(()=>context.nameBeforeWrite(ctx('gate1'),{},nk,{objects:[{collection:context.RPC_BUDGET_COLLECTION}]}),e=>e.code===7);
assert.throws(()=>context.nameBeforeDelete(ctx('gate1'),{},nk,{objectIds:[{collection:context.RPC_BUDGET_COLLECTION}]}),e=>e.code===7);
assert.throws(()=>context.rpcLimits({env:{ZORX_RPC_BURST:'0'}}));
assert.throws(()=>context.rpcLimits({env:{ZORX_RPC_REFILL:'Infinity'}}));
console.log('PASS shared per-account rate gate, independent accounts, VM-independent CAS budget, refill, backward clock, bounded contention, rejection audit, payload bound and protected quota storage');

// Admission/fencing orchestrates trusted state; Godot owns profile content and results.
const roomCtx=id=>({userId:id,env:{...env,ZORX_ROOM_WS_URL:'ws://127.0.0.1:8060'}});
const privateCtx={env:roomCtx('u1').env};
const callRoom=(fn,id,p)=>JSON.parse(context[fn](roomCtx(id),logger,nk,JSON.stringify(p)));
const back=p=>JSON.parse(context.roomBackend(privateCtx,logger,nk,JSON.stringify({v:1,secret:env.ZORX_NAMES_TOKEN,worker:"staging-0",process:"0".repeat(32),...p})));
getProfile('u1');getProfile('u2');
assert.equal(callRoom('roomCreate','u1',{v:1,capacity:2,user_id:'u2'}).error,'invalid_payload');
let created=callRoom('roomCreate','u1',{v:1,capacity:2});assert.equal(created.ok,true,created.error);assert.equal(created.ticket.length,64);
assert.equal(callProfile('u1',req(1,'locked_request_0001')).error,'in_match');
assert.equal(callRoom('roomJoin','u2',{v:1,room:created.room,invite:'0'.repeat(32)}).error,'not_invited');
const joined=callRoom('roomJoin','u2',{v:1,room:created.room,invite:created.invite});assert.equal(joined.ok,true);assert.equal(joined.player_id,2);
assert.equal(callRoom('roomCreate','u1',{v:1,capacity:1}).error,'in_match');
assert.throws(()=>context.roomBackend(roomCtx('u1'),logger,nk,JSON.stringify({v:1,secret:env.ZORX_NAMES_TOKEN,room:created.room,op:'redeem',ticket:created.ticket})),e=>e.code===7);
assert.equal(back({room:created.room,op:'redeem',ticket:created.ticket,secret:'wrong'}).error,'unauthorized');
const admission=back({room:created.room,op:'redeem',ticket:created.ticket});assert.equal(admission.ok,true);assert.equal(admission.slot,1);
assert.equal(back({room:created.room,op:'redeem',ticket:created.ticket}).error,'ticket_invalid');
assert.equal(back({room:created.room,op:'start',fence:admission.fence}).ok,true);
assert.equal(callRoom('roomCancel','u1',{v:1,room:created.room}).error,'in_match');
assert.equal(back({room:created.room,op:'finish',fence:'wrong',profiles:{}}).error,'unauthorized');
assert.equal(back({room:created.room,op:'heartbeat',fence:admission.fence,worker:'other'}).error,'unauthorized');
assert.equal(back({room:created.room,op:'heartbeat',fence:admission.fence,process:'1'.repeat(32)}).error,'room_worker_lost');
assert.equal(back({room:created.room,op:'heartbeat',fence:admission.fence}).ok,true);
const one=copy(rows.get([context.PROFILE_COLLECTION,'u1',context.PROFILE_KEY].join('|')).value.profile);
const two=copy(rows.get([context.PROFILE_COLLECTION,'u2',context.PROFILE_KEY].join('|')).value.profile);
one.v=1;two.v=1;one.marker=123;two.marker=456;
assert.equal(back({room:created.room,op:'finish',fence:admission.fence,profiles:{'1':one,'2':two}}).ok,true);
assert.equal(getProfile('u1').profile.marker,123);assert.equal(getProfile('u2').profile.marker,456);
one.marker=999;
assert.equal(back({room:created.room,op:'finish',fence:admission.fence,profiles:{'1':one,'2':two}}).ok,true);
assert.equal(getProfile('u1').profile.marker,123);
const waiting=callRoom('roomCreate','u1',{v:1,capacity:2});assert.equal(waiting.ok,true);
assert.equal(callRoom('roomCancel','u1',{v:1,room:waiting.room}).ok,true);
assert.equal(rows.get([context.PROFILE_COLLECTION,'u1',context.PROFILE_KEY].join('|')).value.active_room,undefined);
assert.throws(()=>context.nameBeforeWrite(ctx('u1'),{},nk,{objects:[{collection:context.ROOM_COLLECTION}]}),e=>e.code===7);
assert.throws(()=>context.nameBeforeDelete(ctx('u1'),{},nk,{objectIds:[{collection:context.TICKET_COLLECTION}]}),e=>e.code===7);
console.log('PASS room invite/admission, immutable identity/slot, one-use ticket CAS, private backend auth, active-profile fencing, atomic multi-owner settlement, settlement replay and waiting cancellation');

const crash=callRoom('roomCreate','u1',{v:1,capacity:1});assert.equal(crash.ok,true);
const claimed=back({room:crash.room,op:'redeem',ticket:crash.ticket});assert.equal(claimed.ok,true);
assert.equal(back({room:crash.room,op:'start',fence:claimed.fence}).ok,true);
const workerBeforeRecovery=nk.httpRequest;let recoveries=0;
nk.httpRequest=(url,...args)=>{if(url.endsWith('/recover')){recoveries++;return workerBeforeRecovery(url.replace(/\/recover$/,'/profile'),...args);}return workerBeforeRecovery(url,...args);};
vm.runInContext('Date.now = function(){return 10000000;}',context);
assert.equal(getProfile('u1').ok,true);assert.equal(recoveries,1);
assert.equal(getProfile('u1').ok,true);assert.equal(recoveries,1);
assert.equal(back({room:crash.room,op:'finish',fence:claimed.fence,profiles:{'1':one}}).error,'room_expired');
nk.httpRequest=workerBeforeRecovery;
console.log('PASS worker/process fencing and expired started-room recovery execute once and reject stale settlement');

// Camp membership receipts fence old leaves after the same slot is reused.
const campRoom=callRoom('roomCreate','u1',{v:1,capacity:2,camp:true});assert.equal(campRoom.ok,true);
const campOne=back({room:campRoom.room,op:'redeem',ticket:campRoom.ticket});assert.equal(campOne.camp,true);
assert.equal(back({room:campRoom.room,op:'camp',fence:campOne.fence}).ok,true);
const campJoin=callRoom('roomJoin','u2',{v:1,room:campRoom.room,invite:campRoom.invite});assert.equal(campJoin.ok,true);
const campTwo=back({room:campRoom.room,op:'redeem',ticket:campJoin.ticket});assert.equal(campTwo.slot,2);
assert.equal(back({room:campRoom.room,op:'start',fence:campOne.fence,slots:[1]}).error,'room_not_ready');
const leavingProfile=copy(rows.get([context.PROFILE_COLLECTION,'u2',context.PROFILE_KEY].join('|')).value.profile);
assert.equal(back({room:campRoom.room,op:'member_leave',fence:campOne.fence,slot:2,member:'wrong',profile:leavingProfile}).error,'not_invited');
const leave={room:campRoom.room,op:'member_leave',fence:campOne.fence,slot:2,member:campTwo.member_fence,profile:leavingProfile};
assert.equal(back(leave).ok,true);assert.equal(back(leave).ok,true);
const rejoined=callRoom('roomJoin','u2',{v:1,room:campRoom.room,invite:campRoom.invite});assert.equal(rejoined.player_id,2);
assert.equal(back(leave).ok,true);
assert.equal(Object.keys(context.roomRow(nk,campRoom.room).value.members).length,2);
const newTwo=back({room:campRoom.room,op:'redeem',ticket:rejoined.ticket});assert.notEqual(newTwo.member_fence,campTwo.member_fence);
assert.equal(back({room:campRoom.room,op:'finish',fence:campOne.fence,profiles:{'1':one,'2':leavingProfile}}).ok,true);
const poolCtx={env:{ZORX_ROOM_WORKERS:JSON.stringify(Array.from({length:5},(_,i)=>({id:'pool-'+i,url:'wss://example.test/room/pool-'+i})))}};
for(let i=0;i<40;i++){const allocation=context.roomAllocation(poolCtx,nk,'load-'+i);assert.ok(allocation);nk.multiUpdate(null,[allocation.write],null,null,false);}
assert.equal(context.roomAllocation(poolCtx,nk,'load-over-capacity'),null);
console.log('PASS camp membership generations, idempotent save/unlock, reused slot protection and 5x8 process allocation cap');

// M6 public maintenance flag cannot expose private state; admin path needs both boundaries.
assert.throws(()=>context.maintenanceAdmin(ctx('u1'),{},nk,JSON.stringify({v:1,secret:env.ZORX_NAMES_TOKEN,enabled:true})),e=>e.code===7);
assert.equal(JSON.parse(context.maintenanceAdmin({env},{},nk,JSON.stringify({v:1,secret:'wrong',enabled:true}))).error,'unauthorized');
assert.equal(JSON.parse(context.onlineStatus(ctx('u1'),{},nk,'{"v":1}')).maintenance,false);
const maintenanceRow={collection:context.ROOM_COLLECTION,key:'maintenance',userId:context.SYSTEM_OWNER,value:{v:1,enabled:true},version:'*',permissionRead:0,permissionWrite:0};
nk.multiUpdate(null,[maintenanceRow],null,null,false);
assert.equal(JSON.parse(context.onlineStatus(ctx('u1'),{},nk,'{"v":1}')).maintenance,true);
assert.equal(JSON.parse(context.roomCreate(roomCtx('u1'),{},nk,'{"v":1,"capacity":2}')).error,'maintenance');
assert.equal(JSON.parse(context.onlineStatus(ctx('u1'),{},nk,'{"v":1,"secret":true}')).error,'invalid_payload');
assert.equal(context.roomPool({env:{ZORX_ROOM_WORKERS:JSON.stringify([{id:'a',url:'wss://example.test/room/a'},{id:'b',url:'wss://example.test/room/b'}])}}).length,2);
assert.throws(()=>context.roomPool({env:{ZORX_ROOM_WORKERS:JSON.stringify([{id:'a',url:'wss://example.test/room/a'},{id:'a',url:'wss://example.test/room/a'}])}}));
assert.throws(()=>context.roomPool({env:{ZORX_ROOM_WORKERS:'[]'}}));
console.log('PASS maintenance authorization/status/admissions, bounded stable worker pool');

// Admin RPC accepts service identity + separate secret + configured email only.
const adminEnv={...env,ZORX_ADMIN_TOKEN:'a'.repeat(40),ZORX_ADMIN_EMAILS:'["wanwit.phbn@gmail.com"]'};
const adminActor={email:'wanwit.phbn@gmail.com',id:'11111111-1111-4111-8111-111111111111'};
const adminInput={secret:adminEnv.ZORX_ADMIN_TOKEN,actor:adminActor,op:'status'};
const adminCall=(input,n= nk)=>JSON.parse(context.adminGateway({env:adminEnv},{},n,JSON.stringify(input)));
assert.throws(()=>context.adminGateway({env:adminEnv,userId:adminActor.id},{},nk,JSON.stringify(adminInput)),e=>e.code===7);
assert.equal(adminCall({...adminInput,secret:'bad'}).error,'unauthorized');
assert.equal(adminCall({...adminInput,actor:{...adminActor,email:'attacker@example.test'}}).error,'unauthorized');
let banned=[],unbanned=[],auditWrites=[];
const adminNk={...nk,accountGetId:()=>({user:{id:'target'}}),uuidv4:()=>crypto.randomUUID(),storageWrite:objects=>{auditWrites.push(...objects.map(copy));},usersBanId:ids=>banned.push(...ids),usersUnbanId:ids=>unbanned.push(...ids),sqlQuery:(sql,args)=>{assert.ok(!sql.includes("';DROP"));return sql.includes('COUNT(')?[{total:2,banned:1}]:[]},httpRequest:()=>({code:503,body:''}),storageList:()=>({objects:[]})};
assert.equal(adminCall(adminInput,adminNk).total,2);
assert.equal(adminCall({...adminInput,op:'users',search:"';DROP"},adminNk).ok,true);
const target='22222222-2222-4222-8222-222222222222';
assert.equal(adminCall({...adminInput,op:'ban',target:adminActor.id,reason:'self'},adminNk).error,'invalid_action');
assert.equal(adminCall({...adminInput,op:'ban',target,reason:''},adminNk).error,'invalid_action');
assert.equal(adminCall({...adminInput,op:'ban',target,reason:'QA suspend'},adminNk).ok,true);
assert.deepEqual(banned,[target]);assert.equal(auditWrites[0].value.status,'requested');assert.equal(auditWrites[1].value.status,'completed');
assert.equal(adminCall({...adminInput,op:'unban',target,reason:'QA restore'},adminNk).ok,true);assert.deepEqual(unbanned,[target]);
assert.throws(()=>adminCall({...adminInput,op:'ban',target,reason:'QA fail closed'},{...adminNk,storageWrite:()=>{throw Error('down')}}));assert.equal(banned.length,1);
assert.throws(()=>context.protectNameCollections([{collection:context.ADMIN_AUDIT}]),e=>e.code===7);
console.log('PASS private admin authorization, parameterized queries, self-ban prevention, audit-before-action and fail-closed storage');

// Friends can join a waiting owner's camp without receiving its invite secret.
rows.delete([context.ROOM_COLLECTION,context.SYSTEM_OWNER,'maintenance'].join('|'));
const rosterOwner='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',rosterGuest='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',rosterOther='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
for(const id of [rosterOwner,rosterGuest,rosterOther])for(const [collection,k]of [[context.PROFILE_COLLECTION,context.PROFILE_KEY],[context.CHARACTER_COLLECTION,context.CHARACTER_NAME_KEY]]){const record=copy(rows.get([collection,'u1',k].join('|')));record.userId=id;delete record.value.active_room;record.version=String(++serial);rows.set(key(record),record);}
const rosterEnv={...env,ZORX_ROOM_WS_URL:'wss://example.test/room/social',ZORX_ROOM_WORKER_ID:'social-test'};
let mutual=true;
const rosterNk={...nk,sqlQuery:(_sql,ids)=>ids.map(id=>{const player=context.roomProfile(nk,id);const row=player?.state.active_room ? context.roomRow(nk,player.state.active_room.id):null;const r=row?.value||{};return {id,name:player?.name,seen:null,expires:String(r.expires||0),closed:String(r.closed),started:String(r.started),camp:String(r.camp),owner:r.owner,capacity:String(r.capacity),members:JSON.stringify(r.members||{})};}),friendsList:()=>({friends:mutual?[{state:0,user:{userId:rosterOwner,online:false}}]:[]}),storageWrite:objects=>{for(const w of objects)rows.set(key(w),{...copy(w),version:String(++serial)});}};
const rosterCall=(handler,uid,p)=>JSON.parse(context[handler]({env:rosterEnv,userId:uid},{},rosterNk,JSON.stringify({v:1,...p})));
const socialCamp=rosterCall('roomCreate',rosterOwner,{capacity:2,camp:true});assert.equal(socialCamp.ok,true);
let listing=rosterCall('socialRpc',rosterGuest,{op:'list'});assert.equal(listing.friends[0].online,true);assert.equal(listing.friends[0].room.joinable,true);assert.equal(listing.friends[0].room.count,1);assert.equal(JSON.stringify(listing).includes('invite_hash'),false);assert.equal(JSON.stringify(listing).includes(socialCamp.invite),false);
mutual=false;assert.equal(rosterCall('roomJoin',rosterGuest,{friend:rosterOwner}).error,'not_friends');mutual=true;
assert.equal(rosterCall('roomJoin',rosterOther,{room:socialCamp.room}).error,'not_invited');
assert.equal(rosterCall('roomJoin',rosterGuest,{friend:rosterOwner}).ok,true);
assert.equal(rosterCall('roomJoin',rosterOther,{friend:rosterOwner}).error,'room_full');
listing=rosterCall('socialRpc',rosterOther,{op:'list'});assert.equal(listing.friends[0].room.joinable,false);
assert.equal(rosterCall('socialRpc',rosterGuest,{op:'presence'}).ok,true);assert.throws(()=>context.protectNameCollections([{collection:context.PRESENCE_COLLECTION}]),e=>e.code===7);
const campRow=context.roomRow(nk,socialCamp.room);campRow.value.started=true;campRow.value.capacity=4;rows.set(key(campRow),campRow);
assert.equal(rosterCall('roomJoin',rosterOther,{friend:rosterOwner}).error,'room_full');
console.log('PASS friend owner camp join, nonfriend denial, no invite leakage, full/started rechecks and protected presence');

// Authenticated feedback: private storage, server identity/time, bounded text, idempotent retry and CAS quota.
const feedbackUid='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const feedbackName=copy(rows.get([context.CHARACTER_COLLECTION,'u1',context.CHARACTER_NAME_KEY].join('|')));
feedbackName.userId=feedbackUid;rows.set(key(feedbackName),feedbackName);
const feedbackInput={v:1,request_id:'1'.repeat(32),message:'พบปัญหาทดสอบ <script>alert(1)</script>',platform:'web',version:'qa-123'};
const sendFeedback=p=>JSON.parse(context.feedbackSubmit(ctx(feedbackUid),{},nk,JSON.stringify(p)));
const firstFeedback=sendFeedback(feedbackInput);assert.equal(firstFeedback.ok,true);
assert.equal(sendFeedback(feedbackInput).id,firstFeedback.id);
assert.equal(sendFeedback({...feedbackInput,message:'changed text'}).error,'request_id_reused');
assert.equal(sendFeedback({...feedbackInput,request_id:'2'.repeat(32)}).error,'rate_limited');
for(const bad of [{...feedbackInput,player_id:'spoof'},{...feedbackInput,message:'  '},{...feedbackInput,message:'x'.repeat(2001)},{...feedbackInput,version:'<script>'},{...feedbackInput,platform:'spoof'}])assert.equal(sendFeedback(bad).error,'invalid_payload');
assert.throws(()=>context.feedbackSubmit({env},{},nk,JSON.stringify(feedbackInput)),e=>e.code===16);
const savedFeedback=rows.get([context.FEEDBACK_COLLECTION,context.SYSTEM_OWNER,firstFeedback.id].join('|'));
assert.equal(savedFeedback.value.player_id,feedbackUid);assert.equal(savedFeedback.permissionRead,0);assert.equal(savedFeedback.permissionWrite,0);assert.equal(savedFeedback.value.name,feedbackName.value.name);
for(const collection of [context.FEEDBACK_COLLECTION,context.FEEDBACK_QUOTA])assert.throws(()=>context.protectNameCollections([{collection}]),e=>e.code===7);
let feedbackQueries=0;const feedbackAdmin={...adminNk,sqlQuery:(sql,args)=>{feedbackQueries++;assert.ok(sql.includes('LIMIT 31'));assert.equal(args[0],context.FEEDBACK_COLLECTION);assert.equal(args[1],context.SYSTEM_OWNER);return Array.from({length:31},(_,i)=>({id:i.toString(16).padStart(64,'0'),at:Date.now()-i,message:'<script>safe plain text</script>'}));}};
const feed=adminCall({...adminInput,op:'feedback'},feedbackAdmin);assert.equal(feed.feedback.length,30);assert.match(feed.next,/^[0-9]+:[a-f0-9]{64}$/);
assert.equal(adminCall({...adminInput,op:'feedback',cursor:"';DROP"},feedbackAdmin).error,'invalid_payload');assert.equal(feedbackQueries,1);
assert.equal(adminCall({...adminInput,op:'feedback',actor:{...adminActor,email:'attacker@example.test'}},feedbackAdmin).error,'unauthorized');
console.log('PASS player feedback auth, server identity, private storage, bounded input, retry, quota and admin pagination');

const quotaFeedback=rows.get([context.FEEDBACK_QUOTA,feedbackUid,'submit'].join('|'));quotaFeedback.value.next_at=0;
const escapedFeedback={...feedbackInput,request_id:'3'.repeat(32),message:'"'.repeat(2000)};
assert.ok(JSON.stringify(escapedFeedback).length>4096);
assert.equal(JSON.parse(context.feedbackGateway(ctx(feedbackUid),{warn(){}},nk,JSON.stringify(escapedFeedback))).ok,true);
assert.equal(sendFeedback({...feedbackInput,request_id:'4'.repeat(32),message:'invalid\u0000message'}).error,'invalid_payload');

// Catalog cleanup is trusted, CAS-persisted, one-time and deferred during active rooms.
{
 const oldHttp=nk.httpRequest;
 nk.httpRequest=(url,method,headers,body,...rest)=>{
  const p=JSON.parse(body);
  if(url.endsWith('/profile') && p.state?.profile.beta_kit_version===1){
   privateCalls++;
   return {code:200,body:JSON.stringify({v:1,ok:true,profile:{...p.state.profile,beta_kit_version:2},rng_state:p.state.rng_state,result:{ok:true}})};
  }
  return oldHttp(url,method,headers,body,...rest);
 };
 const seed=(id,active=false)=>rows.set([context.PROFILE_COLLECTION,id,context.PROFILE_KEY].join('|'),{collection:context.PROFILE_COLLECTION,userId:id,key:context.PROFILE_KEY,version:'cleanup1',value:{v:1,revision:1,profile:{name:'',created:false,beta_kit_version:1},rng_state:'123',receipts:[],...(active?{active_room:{id:'active',expires:Date.now()+60000}}:{})}});
 seed('cleanup-user');let calls=privateCalls;
 assert.equal(getProfile('cleanup-user').profile.beta_kit_version,2);
 assert.equal(getProfile('cleanup-user').revision,2);
 assert.equal(privateCalls,calls+1);
 seed('cleanup-active',true);calls=privateCalls;
 assert.equal(getProfile('cleanup-active').profile.beta_kit_version,1);assert.equal(privateCalls,calls);
 seed('cleanup-conflict');const oldMulti=nk.multiUpdate;nk.multiUpdate=()=>{throw Error('CAS');};
 assert.equal(getProfile('cleanup-conflict').error,'conflict');nk.multiUpdate=oldMulti;
 assert.equal(rows.get([context.PROFILE_COLLECTION,'cleanup-conflict',context.PROFILE_KEY].join('|')).value.profile.beta_kit_version,1);
 nk.httpRequest=oldHttp;
 console.log('PASS catalog retirement uses trusted authority once with CAS and active-room deferral');
}
