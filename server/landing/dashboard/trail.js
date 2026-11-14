/* ZORX — Squad of Four Races. A 3D trail of seven stations through a night valley (carved ink-wash look, 2026-11-14).
 * Scroll / swipe / arrows move the camera from station to station. Every model is a procedural three.js mesh.
 * The canvas is transparent: the painted night valley (assets/loading_valley.webp, CSS) is the sky behind it.
 * Repeated scenery (trees, rocks, grass, path stones, plinth columns) is instanced to keep draw calls low on phones.
 * No game scene or sign-in code is changed here; auth.js drives ?play=1 / ?auth= / ?logout=1 through these buttons.
 */
(() => {
  const stage = document.getElementById('trail-stage');
  const visual = document.getElementById('scene-visual');
  const $ = id => document.getElementById(id);
  if (!stage || !visual) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Station copy: English titles, Thai descriptions (same pattern as before). Numbers come from the game data:
  // data/races/*.json (colours, Alliance +8%), data/journeys/goblin_waves.json (12 waves, boss hp_mult 1.7).
  const stations = [
    {name:'The Squad Campfire',ch:'THE FIRST SPARK',tag:'SQUAD OF FOUR RACES',effect:'Pick · Build · Fight',
     description:'ทุกการออกรบเริ่มที่กองไฟ เลือกการ์ดคลาส 3 ใบ จัดเป็นทัพของคุณ แล้วส่งลงสนามให้สู้เอง',x:-10,z:10},
    {name:'Four Races',ch:'THE BANNER HILL',tag:'HUMAN · VIKING · ELF · RUNEBORN',effect:'One race per card',
     description:'มนุษย์ ไวกิ้ง เอลฟ์ และรูนบอร์น การ์ดแต่ละใบมีเผ่าของตัวเอง เผ่ากำหนดพลังติดตัวและท่าอัลติเมตของการ์ดใบนั้น',x:-6,z:0},
    {name:'Four Classes',ch:'THE WEAPON RACK',tag:'SWORD & SHIELD · GREAT SWORD · LONGBOW · MAGIC',effect:'4 class cards',
     description:'ดาบและโล่ยืนรับหน้า ดาบใหญ่ฟันกวาด ธนูยาวยิงจากระยะไกล เวทมนตร์ร่ายพลังจากแนวหลัง คลาสบอกว่าการ์ดทำอะไรในสนาม',x:5,z:-22},
    {name:'Squad Synergy',ch:'THE THREE STONES',tag:'PAIR · TRIO · ALLIANCE',effect:'Alliance: HP +8% · ATK +8%',
     description:'ทัพ 3 ใบได้ซินเนอร์จี 1 อย่างจากเผ่าที่จัด เผ่าเดียวกัน 2 ใบเป็นคู่ 3 ใบเป็นทรีโอ ต่างกันทั้ง 3 เผ่าเป็นพันธมิตร',x:-5,z:-44},
    {name:'Auto-Battle Waves',ch:'THE GOBLIN FIELD',tag:'12 WAVES · NO BUTTONS',effect:'Your squad fights on its own',
     description:'กดออกรบแล้วทัพจะสู้เองทั้งหมด ไม่ต้องกดสกิล เคลียร์สนามเมื่อไหร่ เวฟใหม่ก็มาทันที ผ่านให้ครบ 12 เวฟ',x:5,z:-66},
    {name:'The Goblin Chief',ch:'THE CHIEF’S TOTEM',tag:'WAVE 12 · BOSS',effect:'Boss HP ×1.7',
     description:'เวฟสุดท้ายคือหัวหน้าก็อบลินกับลูกน้องของมัน จัดทัพให้ดีแล้วล้มมันให้ได้',x:-5,z:-88},
    {name:'The FIGHT Gate',ch:'READY TO FIGHT',tag:'PLAY IN YOUR BROWSER',effect:'Sign in · Pick 3 cards · FIGHT!',
     description:'จัดทัพเสร็จแล้วก็ถึงเวลาออกรบ เข้าสู่ระบบแล้วเล่นบนเบราว์เซอร์ได้ทันที',x:5,z:-110}
  ];
  const total = stations.length;
  const canInspect = i => i > 0 && i < total - 1; // the campfire and the gate have nothing to turn over
  const hints = ['SCROLL TO MEET THE FOUR RACES','SCROLL TO THE NEXT STOP','SCROLL TO THE NEXT STOP','SCROLL TO THE NEXT STOP','SCROLL TO THE NEXT STOP','SCROLL TO THE GATE','END OF THE TRAIL · PRESS START'];

  let current = 0, inspecting = false, loggingIn = false, sceneAPI = null;
  let lastScroll = 0, changeTimer, loginTimer, touchStart = null;
  let loginArrived = false, sceneFailed = false;
  const rail = [...document.querySelectorAll('[data-step]')];
  const info = $('info-panel');
  const detailsToggle = $('toggle-relic-details');
  const mobileScene=()=>matchMedia('(max-width:760px),(max-height:520px) and (pointer:coarse)').matches;
  function toggleJourney(open){document.body.classList.toggle('journey-open',open);$('open-journey').setAttribute('aria-expanded',String(open));}
  $('open-journey').addEventListener('click',()=>toggleJourney(true));
  $('close-journey').addEventListener('click',()=>toggleJourney(false));
  document.querySelector('.return-to-stage').addEventListener('click',()=>toggleJourney(false));

  detailsToggle.addEventListener('click',()=>{
    const expanded=detailsToggle.getAttribute('aria-expanded')!=='true';
    info.classList.toggle('details-open',expanded);
    detailsToggle.setAttribute('aria-expanded',String(expanded));
    detailsToggle.setAttribute('aria-label',expanded?'ซ่อนรายละเอียด':'แสดงรายละเอียด');
  });
  const two = n => String(n).padStart(2,'0');

  function setStep(index,force=false) {
    if (inspecting || loggingIn) return;
    const next=Math.min(total-1,Math.max(0,index));
    if(next===current && !force)return;
    current=next;
    info.classList.remove('details-open');detailsToggle.setAttribute('aria-expanded','false');detailsToggle.setAttribute('aria-label','แสดงรายละเอียด');
    const isCamp=current===0, s=stations[current];
    rail.forEach((button,i)=>{
      button.classList.toggle('is-current',i===current);
      if(i===current)button.setAttribute('aria-current','step'); else button.removeAttribute('aria-current');
    });
    info.classList.add('is-switching');
    clearTimeout(changeTimer);
    changeTimer=setTimeout(()=>{
      $('relic-chapter').textContent=isCamp?'PROLOGUE — THE CAMPFIRE':`STOP ${two(current+1)} / ${two(total)} — ${s.ch}`;
      $('relic-name').textContent=s.name;
      $('relic-description').textContent=s.description;
      $('relic-rarity').textContent=s.tag;
      $('relic-effect').textContent=s.effect;
      $('scene-counter').textContent=`SCENE ${two(current+1)} / ${two(total)}`;
      $('relic-hint').textContent=hints[current];
      $('prev-step').disabled=current===0;
      $('next-step').disabled=current===total-1;
      stage.classList.toggle('at-campfire',isCamp);
      stage.classList.toggle('no-inspect',!canInspect(current));
      $('inspect-relic').disabled=!canInspect(current);
      $('inspect-relic').setAttribute('aria-hidden',String(!canInspect(current)));
      info.classList.remove('is-switching');
    },reduce?0:175);
    $('progress-fill').style.width=`${(current+1)*100/total}%`;
    sceneAPI?.setStep(current);
  }
  rail.forEach(b=>b.addEventListener('click',()=>setStep(Number(b.dataset.step))));
  $('prev-step').addEventListener('click',()=>setStep(current-1));
  $('next-step').addEventListener('click',()=>setStep(current+1));

  function centered(){const r=stage.getBoundingClientRect();return r.top<innerHeight*.3&&r.bottom>innerHeight*.7;}
  stage.addEventListener('wheel',e=>{
    if(!centered() || loggingIn || inspecting || Math.abs(e.deltaY)<9 || e.target.closest('button,a,.relic-description')) return;
    if(mobileScene())e.preventDefault();
    const direction=Math.sign(e.deltaY);
    if((direction>0&&current===total-1)||(direction<0&&current===0))return;
    e.preventDefault();
    const now=performance.now();
    if(now-lastScroll>750){lastScroll=now;setStep(current+direction);}
  },{passive:false});
  stage.addEventListener('touchstart',e=>{
    if(inspecting||loggingIn||e.target.closest('button,a,.relic-description'))return;
    touchStart={x:e.touches[0].clientX,y:e.touches[0].clientY};
  },{passive:true});
  stage.addEventListener('touchmove',e=>{
    if(!touchStart||inspecting||loggingIn||!centered())return;
    if(mobileScene())e.preventDefault();
    const dx=touchStart.x-e.touches[0].clientX,dy=touchStart.y-e.touches[0].clientY;
    const dir=Math.sign(dy);
    if(Math.abs(dy)>14&&Math.abs(dy)>Math.abs(dx)*1.2 && current+dir>=0&&current+dir<total){e.preventDefault();}
  },{passive:false});
  stage.addEventListener('touchend',e=>{
    if(!touchStart||inspecting||loggingIn)return;
    const dy=touchStart.y-e.changedTouches[0].clientY,dx=touchStart.x-e.changedTouches[0].clientX;
    if(Math.abs(dy)>48 && Math.abs(dy)>Math.abs(dx)*1.25 && centered())setStep(current+Math.sign(dy));
    touchStart=null;
  },{passive:true});
  stage.addEventListener('keydown',e=>{
    if(e.key==='Escape'){
      if(loggingIn){e.preventDefault();closeLogin();} else if(inspecting){e.preventDefault();closeInspect();}
      return;
    }
    if(loggingIn||inspecting||e.target.closest('button,a,.relic-description'))return;
    if(['ArrowDown','ArrowRight','PageDown'].includes(e.key)){e.preventDefault();setStep(current+1);}
    if(['ArrowUp','ArrowLeft','PageUp'].includes(e.key)){e.preventDefault();setStep(current-1);}
  });
  function openInspect(){
    if(loggingIn||inspecting||!canInspect(current))return;
    inspecting=true;stage.classList.add('is-inspecting');$('inspect-layer').setAttribute('aria-hidden','false');
    const s=stations[current];$('inspect-count').textContent=`STOP ${two(current+1)} / ${two(total)}`;
    $('inspect-name').textContent=s.name;$('inspect-copy').textContent=s.description;
    sceneAPI?.setInspect(true);
    setTimeout(()=>$('close-inspect').focus({preventScroll:true}),300);
  }
  function closeInspect(){if(!inspecting)return;inspecting=false;stage.classList.remove('is-inspecting','is-dragging');$('inspect-layer').setAttribute('aria-hidden','true');sceneAPI?.setInspect(false);$('inspect-relic').focus({preventScroll:true});}
  $('inspect-relic').addEventListener('click',openInspect);$('close-inspect').addEventListener('click',closeInspect);
  function openLogin(){
    if(loggingIn)return;if(inspecting)closeInspect();loggingIn=true;
    stage.dataset.loginAttempt=String(Number(stage.dataset.loginAttempt||0)+1);
    loginArrived=false;stage.classList.add('is-login');$('login-layer').setAttribute('aria-hidden','true');
    if(sceneAPI)sceneAPI.setLogin(true);else if(sceneFailed)arriveAtLogin();
  }
  function arriveAtLogin(){
    if(!loggingIn||loginArrived)return;
    loginArrived=true;
    stage.classList.add('login-revealed');$('login-layer').setAttribute('aria-hidden','false');
    window.dispatchEvent(new Event('zorx:login-ready'));
  }
  function closeLogin(){
    if(!loggingIn)return;clearTimeout(loginTimer);stage.dataset.loginAttempt=String(Number(stage.dataset.loginAttempt||0)+1);loggingIn=false;stage.classList.remove('is-login','login-revealed');$('login-layer').setAttribute('aria-hidden','true');sceneAPI?.setLogin(false);$('start-game').focus({preventScroll:true});
  }
  $('start-game').addEventListener('click',openLogin);$('return-to-trail').addEventListener('click',closeLogin);
  $('google-login').addEventListener('click',()=>{
    const url=window.ZORX_CONFIG?.googleAuthUrl;
    if(typeof url==='string'&&url.trim()){
      try{
        const u=new URL(url.trim(),location.href);
        if(u.protocol==='https:'||(u.protocol==='http:'&&(u.origin===location.origin||['localhost','127.0.0.1'].includes(u.hostname)))){location.assign(u.href);return;}
      }catch(err){console.warn('Invalid Google OAuth URL',err);}
    }
    $('auth-status').textContent='ยังไม่ได้เชื่อม Google OAuth — ตั้งค่า backend login URL ที่ config.js';
  });
  setStep(0,true);

  async function loadThree(){
    let T;
    for(const url of ['https://cdn.jsdelivr.net/npm/three@0.165.0/build/three.module.js','https://unpkg.com/three@0.165.0/build/three.module.js']){
      try{T=await import(url);break;}catch(err){console.warn('Three.js CDN unavailable:',url,err);}
    }
    // Real failure only (no CDN, no WebGL): the painted valley stays as a still backdrop and every flow still works.
    if(!T){sceneFailed=true;if(loggingIn)arriveAtLogin();return;}
    try{createWorld(T);}catch(err){sceneFailed=true;visual.classList.remove('is-ready');visual.querySelector('canvas')?.remove();if(loggingIn)arriveAtLogin();console.error('WebGL scene failed; retaining the painted backdrop',err);}
  }
  const observer=new IntersectionObserver(entries=>{if(entries.some(x=>x.isIntersecting)){observer.disconnect();loadThree();}},{rootMargin:'500px'});observer.observe(stage);

  function createWorld(T){
    const small=matchMedia('(max-width:640px)').matches;
    // Night valley: blue-grey fog, no 3D sky (the painting shows through the transparent canvas).
    const FOG=0x4b5869;
    const scene=new T.Scene();scene.fog=new T.FogExp2(FOG,small?.021:.019);
    const camera=new T.PerspectiveCamera(59,1,.1,240);
    const renderer=new T.WebGLRenderer({antialias:!small,alpha:true,powerPreference:'high-performance'});
    renderer.setClearColor(0x000000,0);
    renderer.setPixelRatio(Math.min(devicePixelRatio||1,small?1.25:1.65));renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.05;
    visual.appendChild(renderer.domElement);visual.classList.add('is-ready');
    // Warm, desaturated, flat-shaded Lambert materials (cheaper than the old Standard/Physical ones on phones).
    const mat=(color,extra={})=>new T.MeshLambertMaterial({color,flatShading:true,...extra});
    const glowMat=(color,i=1)=>new T.MeshLambertMaterial({color,emissive:color,emissiveIntensity:i,flatShading:true});
    const basic=(color,extra={})=>new T.MeshBasicMaterial({color,...extra});
    const C={stone:0x6d6a5f,stoneLite:0x8a8474,stoneDark:0x4a4840,wood:0x6b4a2e,woodDark:0x3d2a1c,cloth:0xb9a888,
      gold:0xc9a05a,goldLite:0xe9c987,iron:0x8b9096,ironDark:0x55595e,leaf:0x435a3a,goblin:0x6f8a4a,goblinDark:0x4d6634,ink:0x2a1c12};
    const M={}; for(const k in C)M[k]=mat(C[k]);
    const RACE={H:0xffc23a,V:0xe0302a,E:0x4fe07a,R:0x3fe6ff}; // data/races/*.json "color"
    const CLASS={ss:0x3f7fa6,gs:0xa8473f,lb:0x5e8f57,mg:0x7b65b0}; // client/card_tokens.gd class colours
    scene.add(new T.HemisphereLight(0x9aa8c2,0x3a3226,1.55));
    const moonLight=new T.DirectionalLight(0xd2dcf2,1.5);moonLight.position.set(-30,45,-60);scene.add(moonLight);
    const fireLight=new T.PointLight(0xff9a45,70,34,1.7);fireLight.position.set(-10,2.2,10);scene.add(fireLight);
    // One warm light follows the station in view (the old trail lit all six at once).
    const focusLight=new T.PointLight(0xffd08a,0,22,1.6);scene.add(focusLight);

    const o=(g,m,x=0,y=0,z=0,parent=scene)=>{const m1=new T.Mesh(g,m);m1.position.set(x,y,z);parent.add(m1);return m1;};
    const G={box:new T.BoxGeometry(1,1,1),ico:new T.IcosahedronGeometry(1,0),cone3:new T.ConeGeometry(1,1,3),cone4:new T.ConeGeometry(1,1,4),
      cone5:new T.ConeGeometry(1,1,5),cone6:new T.ConeGeometry(1,1,6),cyl6:new T.CylinderGeometry(1,1,1,6),cyl8:new T.CylinderGeometry(1,1,1,8),
      cyl12:new T.CylinderGeometry(1,1,1,12),sph:new T.SphereGeometry(1,8,6),oct:new T.OctahedronGeometry(1,0),tor:new T.TorusGeometry(1,.12,5,20)};
    // part(parent, geometry, material, [x,y,z], [sx,sy,sz], [rx,ry,rz])
    const part=(p,g,m,pos=[0,0,0],s=[1,1,1],r=[0,0,0])=>{const a=new T.Mesh(g,m);a.position.set(...pos);a.scale.set(...s);a.rotation.set(...r);p.add(a);return a;};
    const rod=(p,a,b,r,m)=>{const A=new T.Vector3(...a),B=new T.Vector3(...b),d=B.clone().sub(A);const piece=part(p,G.cyl6,m,A.clone().add(B).multiplyScalar(.5).toArray(),[r,d.length(),r]);piece.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),d.normalize());return piece;};
    // Instanced scenery: one draw call per list.
    const dummy=new T.Object3D(),tint=new T.Color();
    function inst(g,m,list){
      const im=new T.InstancedMesh(g,m,list.length);
      list.forEach((it,i)=>{dummy.position.set(...it.p);dummy.scale.set(...(it.s||[1,1,1]));dummy.rotation.set(...(it.r||[0,0,0]));dummy.updateMatrix();im.setMatrixAt(i,dummy.matrix);if(it.c!==undefined)im.setColorAt(i,tint.set(it.c));});
      im.instanceMatrix.needsUpdate=true;if(im.instanceColor)im.instanceColor.needsUpdate=true;scene.add(im);return im;
    }
    const white=()=>mat(0xffffff);
    const canvasTex=(w,h,draw)=>{const c=document.createElement('canvas');c.width=w;c.height=h;const ctx=c.getContext('2d');draw(ctx,w,h);const t=new T.CanvasTexture(c);t.colorSpace=T.SRGBColorSpace;t.userData.redraw=()=>{ctx.clearRect(0,0,w,h);draw(ctx,w,h);t.needsUpdate=true;};return t;};
    const fontTextures=[];
    const glowTex=(color)=>canvasTex(64,64,(ctx)=>{const g=ctx.createRadialGradient(32,32,0,32,32,32);g.addColorStop(0,color);g.addColorStop(.3,color);g.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=g;ctx.fillRect(0,0,64,64);});
    const fireTex=glowTex('rgba(255,150,70,.6)'),goldTex=glowTex('rgba(255,210,120,.55)');
    function glow(x,y,z,size,texture,opacity=1,parent=scene){const m=new T.SpriteMaterial({map:texture,transparent:true,opacity,depthWrite:false,blending:T.AdditiveBlending,fog:false});const s=new T.Sprite(m);s.position.set(x,y,z);s.scale.set(size,size,1);parent.add(s);return s;}

    // ---- Ground, trees, rocks, grass ------------------------------------------------------------------------
    // The ground follows the camera along the trail and fades out far ahead, so the painted horizon shows above it.
    const groundAlpha=canvasTex(8,256,(ctx,w,h)=>{const g=ctx.createLinearGradient(0,0,0,h);g.addColorStop(0,'#000');g.addColorStop(.18,'#fff');g.addColorStop(1,'#fff');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);});
    groundAlpha.colorSpace=T.NoColorSpace;
    const ground=o(new T.PlaneGeometry(260,190),mat(0x4a4636,{transparent:true,alphaMap:groundAlpha,depthWrite:true}),0,-.7,0);ground.rotation.x=-Math.PI/2;
    const rng=(i,k)=>{const v=Math.sin(i*127.1+k*311.7)*43758.5453;return v-Math.floor(v);};
    const treeCols=[0x34452f,0x2f3f2c,0x3b4a33,0x2a3a2e];
    const trunks=[],cones=[];
    const treeN=small?150:220;
    for(let i=0;i<treeN;i++){
      const z=24-(i*13.73)%170,side=i%2?-1:1,x=side*(11+(i*15.71)%37),s=.62+((i*19)%10)*.14,ry=i*.29;
      trunks.push({p:[x,1.0*s-.5,z],s:[.2*s,2.6*s,.2*s]});
      for(let k=0;k<3;k++)cones.push({p:[x,(2.6+k*1.13)*s,z],s:[(1.66-.29*k)*s,3.55*s,(1.66-.29*k)*s],r:[0,ry+k*.29,0],c:treeCols[(i+k)%4]});
    }
    inst(G.cyl6,M.woodDark,trunks);inst(G.cone5,white(),cones);
    const rocks=[];
    for(let i=0;i<150;i++){const z=22-(i*3.73)%164,x=Math.sin(i*23.67)*29;if(Math.abs(x)<5)continue;rocks.push({p:[x,-.51,z],s:[.45+(i%5)*.22,.17+(i%4)*.11,.4+(i%4)*.19],r:[0,i*.42,0],c:i%3===0?C.stoneLite:C.stoneDark});}
    for(let i=0;i<165;i++){const z=18-i*.84,x=2.7+Math.sin(i*.23)*4.0;rocks.push({p:[x,-.52,z],s:[.2+(i%4)*.23,.11,.3+(i%3)*.2],r:[0,i*.7,0],c:i%2?C.stoneLite:C.stone});}
    inst(G.ico,white(),rocks);
    const grassCols=[0x55663f,0x4a5a39,0x637048];
    const grass=[];for(let i=0;i<(small?160:240);i++){const z=21-(i*5.33)%160,x=Math.sin(i*18.91)*30;grass.push({p:[x,-.31,z],s:[.09+(i%4)*.02,.34+(i%5)*.14,.12],r:[0,i*.7,Math.sin(i*3.1)*.3],c:grassCols[i%3]});}
    inst(G.cone3,white(),grass);

    // ---- Station 01: the squad campfire ----------------------------------------------------------------------
    const fire=new T.Group();fire.position.set(-10,0,10);fire.scale.setScalar(1.6);scene.add(fire);
    const ring=[];for(let j=0;j<12;j++){const a=j*Math.PI/6;ring.push({p:[-10+Math.cos(a)*1.45*1.6,-.6,10+Math.sin(a)*1.23*1.6],s:[.8,.42,.6],r:[0,a,0],c:j%3?C.stone:C.stoneLite});}
    for(let j=0;j<8;j++){const a=j*Math.PI/4;ring.push({p:[-10+Math.cos(a)*2.5*1.6,-.6,10+Math.sin(a)*2.45*1.6],s:[.8,.5,.83],r:[0,a,0],c:j%2?C.stone:C.stoneLite});}
    inst(G.ico,white(),ring);
    for(let j=0;j<5;j++){const a=j*Math.PI*2/5;const log=part(fire,G.cyl6,M.wood,[Math.cos(a)*.2,-.15,Math.sin(a)*.25],[.27,2.7,.27]);log.rotation.z=Math.PI/2.9;log.rotation.y=a;}
    const flames=[];
    for(let j=0;j<9;j++){const a=j*2.399,h=1.1+(j%5)*.34;const fl=part(fire,G.cone4,basic([0xff6e2a,0xffc15c,0xffe7a4][j%3],{transparent:true,opacity:.94,depthWrite:false,fog:false}),[Math.cos(a)*.3,h*.42,Math.sin(a)*.3],[.21+(j%3)*.09,h,.21+(j%3)*.09]);flames.push({fl,a,j});}
    const flameGlow=glow(-10,1.9,10,17,fireTex,.6);
    // Embers: one Points object, positions animated on the CPU.
    const EMB=40,embPos=new Float32Array(EMB*3),embGeo=new T.BufferGeometry();embGeo.setAttribute('position',new T.BufferAttribute(embPos,3));
    const embers=new T.Points(embGeo,new T.PointsMaterial({color:0xffb36a,size:.13,transparent:true,opacity:.85,depthWrite:false,fog:false}));embers.frustumCulled=false;scene.add(embers);
    // Three squad members sit around the fire in their class colours (sword & shield, great sword, longbow).
    const squad=[];
    [[CLASS.ss,-1.9,1.2],[CLASS.gs,.2,2.3],[CLASS.lb,1.9,1.0]].forEach(([c,dx,dz],k)=>{
      const g=new T.Group();g.position.set(-10+dx*1.6,0,10+dz*1.6);g.lookAt(-10,0,10);scene.add(g);
      part(g,G.cyl8,mat(C.woodDark),[0,-.2,0],[.55,.6,.55]);
      part(g,G.cyl8,mat(c),[0,.65,0],[.42,1.0,.36]);
      part(g,G.sph,mat(0xf0d2b0),[0,1.55,0],[.42,.42,.42]);
      part(g,G.sph,mat([0x6b3a22,0xd8b25a,0x3a2a22][k]),[0,1.72,-.06],[.45,.32,.45]);
      squad.push(g);
    });
    // Tent, supplies and a trail sign.
    const tent=new T.Group();tent.position.set(-17,-.3,10);scene.add(tent);
    part(tent,G.cone4,mat(0x7b6a52),[0,2.4,0],[3,5.8,3],[0,Math.PI/4,0]);part(tent,G.box,M.woodDark,[0,1.1,2.18],[1.7,2,.15]);
    part(scene,G.box,M.wood,[-7.4,.4,13.4],[1.8,.8,.95]);part(scene,G.box,M.cloth,[-7.4,.9,13.4],[1.9,.13,1.0]);
    part(scene,G.box,M.wood,[-14.2,1.4,6.2],[.24,3.2,.25]);part(scene,G.box,M.wood,[-14.2,2.6,6.2],[2.5,.52,.25]);

    // ---- Stations 02-06: a slowly turning diorama on a floating rock; 07: the FIGHT gate on the ground --------
    const models=[];const hits=[];
    const columns=[];
    function floatingIsland(p){
      part(p,G.ico,M.stone,[0,-.92,0],[1.18,.32,1.1]);
      part(p,G.cyl12,mat(0x5d6b45),[0,-.66,0],[1.05,.06,1.0]);
      part(p,G.cone5,M.stoneDark,[0,-1.55,0],[.95,1.2,.9],[Math.PI,0,0]);
    }
    const letterTex=(ch,bg)=>{const t=canvasTex(128,160,(ctx,w,h)=>{ctx.fillStyle=bg;ctx.fillRect(0,0,w,h);ctx.fillStyle='rgba(0,0,0,.18)';ctx.fillRect(0,h-26,w,26);
      ctx.strokeStyle='#3a2414';ctx.lineWidth=8;ctx.strokeRect(4,4,w-8,h-8);ctx.font="800 92px Taviraj, Georgia, serif";ctx.textAlign='center';ctx.textBaseline='middle';
      ctx.lineWidth=10;ctx.strokeStyle='#3a2414';ctx.strokeText(ch,w/2,h/2-6);ctx.fillStyle='#fff6e0';ctx.fillText(ch,w/2,h/2-6);});fontTextures.push(t);return t;};
    const builders=[
      null,
      // 02 Four race banners (H gold, V red, E green, R blue) with a letter each, so colour is never the only cue.
      g=>{floatingIsland(g);
        const banners=[];
        [['H',RACE.H,'#d9a12c'],['V',RACE.V,'#b8302a'],['E',RACE.E,'#3fa95e'],['R',RACE.R,'#2fa9c4']].forEach(([L,c,bg],k)=>{
          const a=k*Math.PI/2+Math.PI/4,x=Math.cos(a)*.58,z=Math.sin(a)*.58;
          rod(g,[x,-.66,z],[x,.95,z],.035,M.wood);
          const flag=new T.Group();flag.position.set(x,.62,z);flag.rotation.y=-a+Math.PI/2;g.add(flag);
          part(flag,new T.PlaneGeometry(.42,.56),mat(0xffffff,{map:letterTex(L,bg),side:T.DoubleSide}),[.22,0,0]);
          part(flag,G.cyl6,M.wood,[.22,.3,0],[.012,.48,.012],[0,0,Math.PI/2]);
          if(L==='H')part(g,G.oct,glowMat(c,.6),[x,1.04,z],[.07,.11,.07]);
          if(L==='V'){part(g,G.cone4,M.cloth,[x-.06,1.02,z],[.035,.16,.035],[0,0,.5]);part(g,G.cone4,M.cloth,[x+.06,1.02,z],[.035,.16,.035],[0,0,-.5]);}
          if(L==='E')part(g,G.sph,glowMat(c,.5),[x,1.03,z],[.05,.1,.03]);
          if(L==='R')part(g,G.tor,glowMat(c,.8),[x,1.03,z],[.07,.07,.07]);
          banners.push(flag);
        });
        part(g,G.ico,M.stoneLite,[0,-.5,0],[.22,.16,.22]);
        return {banners};},
      // 03 The four class weapons stuck in the rock: sword + shield, great sword, longbow, staff.
      g=>{floatingIsland(g);
        const sw=new T.Group();sw.position.set(-.5,-.66,.15);sw.rotation.z=.12;g.add(sw);
        part(sw,G.box,M.iron,[0,.55,0],[.07,.9,.02]);part(sw,G.box,M.gold,[0,1.02,0],[.3,.05,.06]);part(sw,G.cyl6,M.woodDark,[0,1.17,0],[.03,.24,.03]);part(sw,G.sph,M.gold,[0,1.31,0],[.05,.05,.05]);
        const sh=part(g,G.cyl12,mat(CLASS.ss),[-.72,-.22,.36],[.3,.05,.3],[Math.PI/2,0,.25]);part(g,G.cyl12,M.gold,[-.71,-.22,.39],[.1,.03,.1],[Math.PI/2,0,.25]);
        const gs=new T.Group();gs.position.set(-.08,-.66,-.25);gs.rotation.z=-.08;g.add(gs);
        part(gs,G.box,M.iron,[0,.75,0],[.15,1.4,.035]);part(gs,G.box,mat(CLASS.gs),[0,1.47,0],[.48,.08,.09]);part(gs,G.cyl6,M.woodDark,[0,1.7,0],[.035,.38,.035]);part(gs,G.oct,M.gold,[0,1.92,0],[.06,.07,.06]);
        const bow=new T.Group();bow.position.set(.42,.15,.2);bow.rotation.set(0,-.4,.1);g.add(bow);
        const arc=part(bow,new T.TorusGeometry(.62,.03,4,14,Math.PI*.9),mat(CLASS.lb),[0,0,0],[1,1,1],[0,0,Math.PI/2+Math.PI*.05]);
        rod(bow,[0,.61,0],[0,-.61,0],.006,mat(0xf3e6c8));part(bow,G.box,M.woodDark,[-.62,0,0],[.06,.16,.06]);
        const st=new T.Group();st.position.set(.72,-.66,-.3);st.rotation.z=-.1;g.add(st);
        part(st,G.cyl6,M.wood,[0,.75,0],[.035,1.5,.035]);part(st,G.tor,M.gold,[0,1.55,0],[.11,.11,.11]);
        const orb=part(st,G.ico,glowMat(CLASS.mg,1.1),[0,1.58,0],[.11,.11,.11]);
        return {orb};},
      // 04 Squad synergy: three card-stones (one race each = Alliance) bound by a glowing ring around a centre flame.
      g=>{floatingIsland(g);
        const cards=[];
        [[RACE.H,'H','#d9a12c'],[RACE.V,'V','#b8302a'],[RACE.E,'E','#3fa95e']].forEach(([c,L,bg],k)=>{
          const a=k*Math.PI*2/3,x=Math.cos(a)*.62,z=Math.sin(a)*.62;
          const card=new T.Group();card.position.set(x,-.05,z);card.rotation.y=-a+Math.PI/2;g.add(card);
          part(card,G.box,M.stoneLite,[0,0,0],[.5,.78,.08]);
          part(card,new T.PlaneGeometry(.38,.5),mat(0xffffff,{map:letterTex(L,bg)}),[0,.04,.045]);part(card,new T.PlaneGeometry(.38,.5),mat(0xffffff,{map:letterTex(L,bg)}),[0,.04,-.045],[1,1,1],[0,Math.PI,0]);
          part(g,G.oct,glowMat(c,1),[x,.5,z],[.07,.1,.07]);cards.push(card);
        });
        const bond=part(g,new T.TorusGeometry(.72,.025,4,40),glowMat(0xffd27a,1.2),[0,.5,0],[1,1,1],[Math.PI/2,0,0]);
        const core=part(g,G.oct,glowMat(0xffe0a0,1.4),[0,.2,0],[.16,.28,.16]);
        return {bond,core};},
      // 05 Auto-battle waves: three squad heroes hold the line while goblin waves hop in.
      g=>{floatingIsland(g);
        const gob=[];
        [[CLASS.ss,-.15,.45],[CLASS.gs,.2,.55],[CLASS.mg,.0,.85]].forEach(([c,x,z])=>{
          part(g,G.cyl8,mat(c),[x,-.42,z],[.11,.36,.1]);part(g,G.sph,mat(0xf0d2b0),[x,-.12,z],[.1,.1,.1]);});
        for(let k=0;k<7;k++){const row=k<4?0:1,col=row?k-4:k;const x=(col-(row?1:1.5))*.32,z=-.15-row*.42;
          const b=new T.Group();b.position.set(x,-.6,z);g.add(b);
          part(b,G.cone5,mat(C.goblinDark),[0,.13,0],[.1,.26,.1]);part(b,G.ico,mat(C.goblin),[0,.31,0],[.09,.08,.08]);
          part(b,G.cone3,mat(C.goblin),[-.09,.33,0],[.025,.1,.02],[0,0,1.3]);part(b,G.cone3,mat(C.goblin),[.09,.33,0],[.025,.1,.02],[0,0,-1.3]);
          gob.push({b,k});}
        const flag=new T.Group();flag.position.set(.85,-.66,-.6);g.add(flag);part(flag,G.cyl6,M.wood,[0,.55,0],[.02,1.1,.02]);
        part(flag,new T.PlaneGeometry(.36,.26),mat(0xffffff,{side:T.DoubleSide,map:(()=>{const t=canvasTex(128,96,(ctx,w,h)=>{ctx.fillStyle='#e8d4a6';ctx.fillRect(0,0,w,h);ctx.strokeStyle='#3a2414';ctx.lineWidth=6;ctx.strokeRect(3,3,w-6,h-6);ctx.fillStyle='#3a2414';ctx.font="800 60px Taviraj, Georgia, serif";ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText('12',w/2,h/2+2);});fontTextures.push(t);return t;})()}),[.19,.95,0]);
        return {gob};},
      // 06 The goblin chief's totem: stacked carved blocks, a tusked goblin face, a horn crown and two torches.
      g=>{floatingIsland(g);
        part(g,G.cyl8,M.woodDark,[0,-.45,0],[.34,.42,.34]);
        part(g,G.cyl8,M.wood,[0,-.02,0],[.3,.44,.3]);part(g,G.tor,M.gold,[0,.2,0],[.31,.31,.4],[Math.PI/2,0,0]);
        part(g,G.ico,mat(C.goblin),[0,.5,0],[.36,.32,.32]);
        part(g,G.cone3,mat(C.goblin),[-.42,.55,0],[.08,.34,.06],[0,0,1.25]);part(g,G.cone3,mat(C.goblin),[.42,.55,0],[.08,.34,.06],[0,0,-1.25]);
        const eyes=[part(g,G.sph,glowMat(0xffa23a,1.6),[-.12,.56,.28],[.06,.04,.03]),part(g,G.sph,glowMat(0xffa23a,1.6),[.12,.56,.28],[.06,.04,.03])];
        part(g,G.cone4,M.cloth,[-.1,.34,.27],[.03,.12,.03],[Math.PI,0,0]);part(g,G.cone4,M.cloth,[.1,.34,.27],[.03,.12,.03],[Math.PI,0,0]);
        for(let k=0;k<5;k++){const a=(k-2)*.38;part(g,G.cone4,k%2?M.goldLite:M.cloth,[Math.sin(a)*.26,.88+(k%2?.02:0),Math.cos(a)*.05],[.05,.28+(k%2)*.1,.05],[0,0,-a*.6]);}
        const torches=[];
        for(const s of [-1,1]){rod(g,[s*.75,-.66,.2],[s*.78,.35,.2],.025,M.woodDark);const f=part(g,G.cone4,basic(0xffa040,{transparent:true,opacity:.95,fog:false}),[s*.78,.47,.2],[.06,.2,.06]);torches.push(f);}
        return {eyes,torches};},
      // 07 The FIGHT gate (built on the ground, see below)
      null
    ];
    stations.forEach((s,i)=>{
      if(i===0)return;
      const group=new T.Group();group.position.set(s.x,0,s.z);scene.add(group);
      // Stone columns stand behind and beside each station, never between it and the camera (instanced below).
      if(i<total-1)for(let j=0;j<5;j++){const a=Math.PI*(1.05+j*.235),rad=6+(j%2)*1.3;columns.push({p:[s.x+Math.cos(a)*rad,1.05,s.z+Math.sin(a)*rad],s:[.8,2.9,.85],r:[0,j*.65,0],c:j%2?C.stoneLite:C.stone});columns.push({p:[s.x+Math.cos(a)*rad,2.75,s.z+Math.sin(a)*rad],s:[.8,.32,.9],c:C.stoneDark});}
      if(i===total-1){models.push({group,gate:true});return;}
      const float=new T.Group();float.position.y=4.5;group.add(float);
      const bob=new T.Group();float.add(bob);
      const turner=new T.Group();bob.add(turner);
      const art=new T.Group();art.scale.setScalar(2.75);turner.add(art);
      const extra=builders[i](art)||{};
      const hit=o(new T.SphereGeometry(2.7,10,8),basic(0,{visible:false}),0,0,0,bob);hit.userData.station=i;hits.push(hit);
      const halo=glow(0,0,0,9,goldTex,.35,float);
      models.push({group,bob,turner,halo,extra,dragAngle:0});
    });
    inst(G.box,white(),columns.filter((c,k)=>k%2===0));inst(G.ico,white(),columns.filter((c,k)=>k%2===1));
    // The FIGHT gate: a carved timber arch with a parchment plaque, torches and a warm portal the sign-in flight enters.
    const gs=stations[total-1];
    const gate=new T.Group();gate.position.set(gs.x,0,gs.z-2);scene.add(gate);
    part(gate,G.box,M.stoneLite,[-3.3,.0,0],[2.1,1.4,2.0]);part(gate,G.box,M.stoneLite,[3.3,.0,0],[2.1,1.4,2.0]);
    part(gate,G.box,M.wood,[-3.2,4.1,0],[1.3,7.4,1.2]);part(gate,G.box,M.wood,[3.2,4.1,0],[1.3,7.4,1.2]);
    part(gate,G.box,M.woodDark,[0,7.8,0],[8.6,1.0,1.5]);part(gate,G.box,M.wood,[0,8.5,0],[9.6,.5,1.8]);
    for(const s of [-1,1]){part(gate,G.cone4,M.woodDark,[s*4.6,9.0,0],[.5,1.2,.5],[0,0,-s*.5]);}
    const plaqueTex=canvasTex(512,160,(ctx,w,h)=>{ctx.fillStyle='#e9d6a8';ctx.fillRect(0,0,w,h);const g=ctx.createLinearGradient(0,0,0,h);g.addColorStop(0,'rgba(255,255,255,.25)');g.addColorStop(1,'rgba(90,52,32,.25)');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);
      ctx.strokeStyle='#3a2414';ctx.lineWidth=14;ctx.strokeRect(7,7,w-14,h-14);ctx.strokeStyle='#c9a05a';ctx.lineWidth=5;ctx.strokeRect(22,22,w-44,h-44);
      ctx.fillStyle='#3a2414';ctx.font="800 104px Taviraj, Georgia, serif";ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText('FIGHT!',w/2,h/2+6);});fontTextures.push(plaqueTex);
    part(gate,new T.PlaneGeometry(4.6,1.44),mat(0xffffff,{map:plaqueTex}),[0,6.6,.78]);
    part(gate,G.box,M.woodDark,[0,6.6,.7],[4.9,1.7,.12]);
    const portalTex=canvasTex(64,128,(ctx,w,h)=>{const g=ctx.createRadialGradient(32,80,4,32,70,70);g.addColorStop(0,'rgba(255,240,200,1)');g.addColorStop(.45,'rgba(255,190,90,.75)');g.addColorStop(1,'rgba(255,140,60,.08)');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);});
    const portal=part(gate,new T.PlaneGeometry(5.1,6.0),basic(0xffffff,{map:portalTex,transparent:true,opacity:.5,depthWrite:false,side:T.DoubleSide,blending:T.AdditiveBlending,fog:false}),[0,3.75,0]);
    const gateFlames=[];
    for(const s of [-1,1]){rod(gate,[s*4.3,-.6,1.3],[s*4.3,3.2,1.3],.12,M.woodDark);gateFlames.push(part(gate,G.cone4,basic(0xffa040,{transparent:true,opacity:.95,fog:false}),[s*4.3,3.65,1.3],[.3,.95,.3]));glow(gs.x+s*4.3,3.7,gs.z-2+1.3,4.5,fireTex,.6);}
    const gateGlow=glow(gs.x,4,gs.z-2.3,13,goldTex,.4);
    if(document.fonts&&document.fonts.ready)document.fonts.ready.then(()=>fontTextures.forEach(t=>t.userData.redraw()));

    // ---- Camera poses -----------------------------------------------------------------------------------------
    const campPose=small
      ? {pos:[-3.2,5.4,19.5],look:[-9.9,1.2,10.3],fov:60}
      : {pos:[-1.9,5.1,20],look:[-9.9,1.45,10.4],fov:54};
    const stationPose=s=>small
      ? {pos:[s.x+1.4,6.4,s.z+18],look:[s.x,1.3,s.z-1],fov:62}
      : {pos:[s.x+2,6.3,s.z+19],look:[s.x+5.6,4.3,s.z-1.2],fov:56};
    const gatePose=s=>small
      ? {pos:[s.x+1.2,4.6,s.z+19],look:[s.x,3.6,s.z-2],fov:62}
      : {pos:[s.x+2.5,4.8,s.z+19],look:[s.x+6.2,4.6,s.z-2],fov:56};
    const poses=stations.map((s,i)=>i===0?campPose:i===total-1?gatePose(s):stationPose(s));
    const inspectPose=s=>({pos:[s.x+3.8,6,s.z+10],look:[s.x,4.5,s.z],fov:small?47:43});
    const loginPose={pos:[gs.x,3.9,gs.z+1.5],look:[gs.x,3.9,gs.z-14],fov:46};
    const cameraLook=new T.Vector3(...poses[current].look),wantedPos=new T.Vector3(...poses[current].pos),wantedLook=new T.Vector3(...poses[current].look);
    camera.position.copy(wantedPos);camera.lookAt(cameraLook);
    let fovTarget=poses[current].fov;
    const setPose=pose=>{wantedPos.set(...pose.pos);wantedLook.set(...pose.look);fovTarget=pose.fov;};
    let loginArrivalPending=false;
    sceneAPI={setStep:i=>setPose(poses[i]),setInspect:on=>setPose(on?inspectPose(stations[current]):poses[current]),setLogin:on=>{setPose(on?loginPose:poses[current]);loginArrivalPending=on;}};
    if(loggingIn)sceneAPI.setLogin(true);
    const resize=()=>{const r=visual.getBoundingClientRect();if(!r.width||!r.height)return;renderer.setSize(Math.round(r.width),Math.round(r.height),false);camera.aspect=r.width/r.height;camera.updateProjectionMatrix();};
    window.addEventListener('resize',resize,{passive:true});new ResizeObserver(resize).observe(visual);resize();
    // ---- Pointer: tap the station item to inspect; drag to turn it while inspecting ----------------------------
    const raycaster=new T.Raycaster(),pointer=new T.Vector2();
    const getHit=e=>{const rect=renderer.domElement.getBoundingClientRect();pointer.set((e.clientX-rect.left)/rect.width*2-1,-(e.clientY-rect.top)/rect.height*2+1);raycaster.setFromCamera(pointer,camera);return raycaster.intersectObjects(hits,false)[0];};
    const modelAt=i=>models[i-1];
    let drag=null;
    renderer.domElement.addEventListener('pointerdown',e=>{
      if(loggingIn)return;
      const hit=getHit(e);
      if(!inspecting && (!canInspect(current) || !hit || hit.object.userData.station!==current))return;
      drag={id:e.pointerId,x:e.clientX,y:e.clientY,moved:false};
      if(inspecting){renderer.domElement.setPointerCapture(e.pointerId);stage.classList.add('is-dragging');}
    });
    renderer.domElement.addEventListener('pointermove',e=>{
      if(!drag||drag.id!==e.pointerId)return;
      const dx=e.clientX-drag.x,dy=e.clientY-drag.y;
      if(Math.abs(dx)+Math.abs(dy)>3)drag.moved=true;
      if(inspecting){const m=modelAt(current);m.dragAngle+=dx*.012;m.turner.rotation.x=Math.max(-.62,Math.min(.62,m.turner.rotation.x+dy*.003));}
      drag.x=e.clientX;drag.y=e.clientY;
    });
    renderer.domElement.addEventListener('pointerup',e=>{
      if(!drag||drag.id!==e.pointerId)return;
      if(!drag.moved&&!inspecting){openInspect();}
      drag=null;stage.classList.remove('is-dragging');
    });
    renderer.domElement.addEventListener('pointercancel',()=>{drag=null;stage.classList.remove('is-dragging');});
    // ---- Frame loop -------------------------------------------------------------------------------------------
    let then=performance.now(),time=0,isVisible=true;
    new IntersectionObserver(es=>{isVisible=es[0]?.isIntersecting??false;}).observe(stage);
    const tmp=new T.Vector3();
    function tick(now){
      requestAnimationFrame(tick);if(!isVisible||document.hidden){then=now;return;}
      const dt=Math.min(.05,(now-then)/1000);then=now;time+=dt;
      const easing=reduce?1:1-Math.exp(-dt*(loggingIn?1.3:1.7));
      camera.position.lerp(wantedPos,easing);cameraLook.lerp(wantedLook,easing);camera.lookAt(cameraLook);
      camera.fov+=(fovTarget-camera.fov)*easing;camera.updateProjectionMatrix();
      if(loggingIn&&loginArrivalPending&&camera.position.distanceTo(wantedPos)<2.5&&cameraLook.distanceTo(wantedLook)<2.5&&Math.abs(camera.fov-fovTarget)<.8){
        loginArrivalPending=false;arriveAtLogin();
      }
      // The ground slides with the camera (it is one flat colour) so its far, faded edge always sits ahead.
      ground.position.z=camera.position.z-60;
      const t=reduce?0:time;
      models.forEach((m,k)=>{
        const i=k+1;
        m.group.visible=(current!==0||loggingIn||i===1)&&Math.abs(m.group.position.z-camera.position.z)<80;
        if(!m.group.visible||m.gate)return;
        const focus=i===current;
        m.bob.position.y=Math.sin(t*1.2+i)*.24;
        m.turner.rotation.y=t*.28+m.dragAngle-.5;
        m.halo.material.opacity=focus?.36+.06*Math.sin(t*3+i):.14;
        const x=m.extra;
        if(x.banners)x.banners.forEach((f,j)=>{f.rotation.z=Math.sin(t*2.2+j)*.06;});
        if(x.orb)x.orb.rotation.y=t*1.5;
        if(x.bond){x.bond.rotation.z=t*.6;x.core.rotation.y=t*1.2;x.core.position.y=.2+Math.sin(t*2)*.05;}
        if(x.gob)x.gob.forEach(({b,k:j})=>{const ph=(t*1.6+j*.37)%1;b.position.y=-.6+Math.abs(Math.sin(ph*Math.PI))*.12;});
        if(x.eyes){const e=.9+.6*Math.abs(Math.sin(t*2.4));x.eyes.forEach(m2=>m2.material.emissiveIntensity=e);x.torches.forEach((f,j)=>{f.scale.y=.2*(.85+.2*Math.sin(t*9+j*2));});}
      });
      const cur=current>0&&current<total-1?stations[current]:null;
      if(cur){focusLight.position.set(cur.x+1.5,6.5,cur.z+3.5);focusLight.intensity+=((inspecting?26:18)-focusLight.intensity)*Math.min(1,dt*3);}
      else focusLight.intensity*=Math.max(0,1-dt*3);
      // Campfire
      for(let j=0;j<EMB;j++){const a=j*2.39997,life=(t*.22+j*.074)%1;embPos[j*3]=-10+Math.cos(a+t*.7)*(.4+life*2.1);embPos[j*3+1]=.65+life*6;embPos[j*3+2]=10+Math.sin(a+t*.4)*(.5+life*.85);}
      embGeo.attributes.position.needsUpdate=true;
      flames.forEach(({fl,a,j})=>{fl.scale.y=(1.1+(j%5)*.34)*(.82+.17*Math.sin(t*8+a)+.1*Math.cos(t*5+j));fl.rotation.z=Math.sin(t*4+a)*.2;});
      flameGlow.material.opacity=.55+Math.sin(t*7)*.08;fireLight.intensity=70+Math.sin(t*8)*9;
      // Gate
      portal.material.opacity=.42+.1*Math.sin(t*2.2);gateGlow.material.opacity=.32+.08*Math.sin(t*2.2);
      gateFlames.forEach((f,j)=>{f.scale.y=.95*(.85+.18*Math.sin(t*9+j*2));});
      renderer.render(scene,camera);
    }
    requestAnimationFrame(tick);
  }
})();
