const vm=require('vm'),fs=require('fs'),crypto=require('crypto'),assert=require('assert');
const scope={};vm.createContext(scope);vm.runInContext(fs.readFileSync('../../../build/names-runtime/index.js','utf8'),scope);
let now=100000;scope.Date={now:()=>now};const storage=new Map();
const key=x=>[x.collection,x.userId,x.key].join('/');
const nk={sha256Hash:s=>crypto.createHash('sha256').update(s).digest('hex'),storageRead:xs=>xs.map(x=>storage.get(key(x))).filter(Boolean),multiUpdate:(_,xs)=>{for(const x of xs){assert.equal(x.permissionRead,0);assert.equal(x.permissionWrite,0);storage.set(key(x),{value:x.value,version:String(now)});}}};
const user={userId:'owner'};let serial=0;
function request(){const data=Buffer.from('opaque compressed bytes').toString('base64');return {v:1,encoding:'gzip-base64',request_id:(++serial).toString(16).padStart(32,'0'),raw_bytes:200,data,digest:nk.sha256Hash(data)};}
const submit=(p,ctx=user)=>JSON.parse(scope.diagnosticsSubmit(ctx,{},nk,JSON.stringify(p)));
let p=request();assert(submit(p).ok);assert(submit(p).ok);
assert.equal(submit({...p,digest:'bad'}).error,'invalid_payload');
assert.equal(submit(request()).error,'rate_limited');assert.throws(()=>submit(p,{}));
for(let i=0;i<6;i++){now+=60001;assert(submit(request()).ok);}
assert.equal([...storage.keys()].filter(k=>k.startsWith('zorx_diagnostics_v1/')).length,3);
let bad=request();bad.data='x'.repeat(90000);bad.digest=nk.sha256Hash(bad.data);assert.equal(submit(bad).error,'invalid_payload');
bad=request();bad.raw_bytes=262145;assert.equal(submit(bad).error,'invalid_payload');
bad=request();bad.player_id='forged';assert.equal(submit(bad).error,'invalid_payload');
now+=60001;assert(submit(request(),{userId:'second'}).ok);assert.equal([...storage.keys()].filter(k=>k.startsWith('zorx_diagnostics_v1/')).length,4);
console.log('DIAGNOSTIC AUTH/OWNER/BOUNDS/QUOTA/IDEMPOTENCE/RETENTION PASS');
