/* ZORX V4 — Campfire prologue + six relics / seven continuous forest stations.
 * All models are procedural Three.js meshes. No existing game scene or OAuth implementation is modified.
 */
(() => {
  const stage = document.getElementById('trail-stage');
  const visual = document.getElementById('scene-visual');
  const $ = id => document.getElementById(id);
  if (!stage || !visual) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const relics = [
    {name:'Ancient Core',file:'ancient-core',ch:'THE FIRST LIGHT',rarity:'LEGENDARY RELIC',effect:'Power +15%',color:0x69dcff,description:'เศษเสี้ยวพลังจากยุคโบราณ แก่นผลึกที่ส่องนำทางนักสำรวจผ่านความมืด',x:-6,z:0},
    {name:'Phoenix Feather',file:'phoenix-feather',ch:'THE EMBER GROVE',rarity:'EPIC RELIC',effect:'Second Chance',color:0xff9f4b,description:'ขนนกเพลิงในตำนาน เปลวไฟอ่อนโยนที่อาจมอบโอกาสให้คุณลุกขึ้นสู้อีกครั้ง',x:5,z:-22},
    {name:'Rune of Growth',file:'rune-of-growth',ch:'THE OVERGROWN SHRINE',rarity:'RARE RELIC',effect:'Harvest +20%',color:0x90ee73,description:'ศิลารูนที่หลับใหลท่ามกลางรากไม้ เพิ่มพลังแห่งการเก็บเกี่ยวและฟื้นฟูหมู่บ้าน',x:-5,z:-44},
    {name:'Guardian Stone',file:'guardian-stone',ch:'THE ANCIENT WATCH',rarity:'EPIC RELIC',effect:'Camp Defense +10%',color:0x64b7ff,description:'ผู้พิทักษ์หินตัวน้อยที่เคยเฝ้าเมืองเก่า ช่วยคุ้มครองแคมป์ระหว่างการเดินทาง',x:5,z:-66},
    {name:'Shadow Crystal',file:'shadow-crystal',ch:'THE FORGOTTEN VEIL',rarity:'LEGENDARY RELIC',effect:'Critical Rate +8%',color:0xbd6aff,description:'ผลึกที่ดูดกลืนแสงจันทร์ และปลดปล่อยพลังลึกลับให้กับผู้ที่กล้าเข้ามาใกล้',x:-5,z:-88},
    {name:'Sun Totem',file:'sun-totem',ch:'THE DAWN GATE',rarity:'MYTHIC RELIC',effect:'All Stats +5%',color:0xffd16d,description:'ตราแห่งรุ่งอรุณที่รอคอยนักสำรวจ ณ ปลายทางของป่า และจุดเริ่มต้นของการผจญภัย',x:5,z:-110}
  ];
  const camp = {name:'The Campfire',ch:'THE FIRST SPARK',rarity:'YOUR HOME IN THE WILDLANDS',effect:'Explore · Fight · Loot · Rebuild',description:'การเดินทางทุกครั้งเริ่มต้นจากกองไฟเล็ก ๆ ออกสำรวจดินแดนลึกลับ ค้นหา Relic แล้วกลับมาพัฒนาแคมป์ของคุณ'};
  const total = relics.length + 1; // Scene 01 is Campfire; Scenes 02–07 are relics.

  let current = 0, inspecting = false, loggingIn = false, sceneAPI = null;
  let lastScroll = 0, changeTimer, loginTimer, touchStart = null;
  let loginArrived = false, sceneFailed = false;
  const rail = [...document.querySelectorAll('[data-step]')];
  const fallback = $('fallback-image');
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
    detailsToggle.setAttribute('aria-label',expanded?'ซ่อนรายละเอียด Relic':'แสดงรายละเอียด Relic');
  });

  function setStep(index,force=false) {
    if (inspecting || loggingIn) return;
    const next=Math.min(total-1,Math.max(0,index));
    if(next===current && !force)return;
    current=next;
    info.classList.remove('details-open');detailsToggle.setAttribute('aria-expanded','false');detailsToggle.setAttribute('aria-label','แสดงรายละเอียด Relic');
    const isCamp=current===0;
    const r=isCamp?camp:relics[current-1];
    rail.forEach((button,i)=>{
      button.classList.toggle('is-current',i===current);
      if(i===current)button.setAttribute('aria-current','step'); else button.removeAttribute('aria-current');
    });
    info.classList.add('is-switching');
    clearTimeout(changeTimer);
    changeTimer=setTimeout(()=>{
      $('relic-chapter').textContent=isCamp?'PROLOGUE — THE CAMPFIRE':`RELIC ${String(current).padStart(2,'0')} / 0${relics.length} — ${r.ch}`;
      $('relic-name').textContent=r.name;
      $('relic-description').textContent=r.description;
      $('relic-rarity').textContent=r.rarity;
      $('relic-effect').textContent=r.effect;
      $('scene-counter').textContent=`SCENE ${String(current+1).padStart(2,'0')} / 0${total}`;
      $('relic-hint').textContent=current===0?'SCROLL TO FIND THE FIRST RELIC':current===total-1?'END OF THE RELIC TRAIL':'SCROLL TO NEXT RELIC';
      $('prev-step').disabled=current===0;
      $('next-step').disabled=current===total-1;
      stage.classList.toggle('at-campfire',isCamp);
      $('inspect-relic').disabled=isCamp;
      $('inspect-relic').setAttribute('aria-hidden',String(isCamp));
      if (!isCamp) { fallback.src=`assets/${r.file}.webp`; fallback.alt=r.name; }
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
    if(loggingIn||inspecting||current===0)return;
    inspecting=true;stage.classList.add('is-inspecting');$('inspect-layer').setAttribute('aria-hidden','false');
    const r=relics[current-1];$('inspect-count').textContent=`RELIC ${String(current).padStart(2,'0')} / 0${relics.length}`;
    $('inspect-name').textContent=r.name;$('inspect-copy').textContent=r.description;
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
    // Carved ink-wash look (2026-11-14): the painted night valley replaces the low-poly 3D forest. Taking the
    // existing no-WebGL path keeps every flow (stations, inspect, login arrival) and loads no CDN script.
    if(document.documentElement.dataset.scene==='painted'){sceneFailed=true;if(loggingIn)arriveAtLogin();return;}
    let T;
    for(const url of ['https://cdn.jsdelivr.net/npm/three@0.165.0/build/three.module.js','https://unpkg.com/three@0.165.0/build/three.module.js']){
      try{T=await import(url);break;}catch(err){console.warn('Three.js CDN unavailable:',url,err);}
    }
    if(!T){sceneFailed=true;if(loggingIn)arriveAtLogin();return;}
    try{createWorld(T);}catch(err){sceneFailed=true;if(loggingIn)arriveAtLogin();console.error('WebGL scene failed; retaining visual fallback',err);}
  }
  const observer=new IntersectionObserver(entries=>{if(entries.some(x=>x.isIntersecting)){observer.disconnect();loadThree();}},{rootMargin:'500px'});observer.observe(stage);

  function createWorld(T){
    const small=matchMedia('(max-width:640px)').matches;
    const scene=new T.Scene();scene.background=new T.Color(0x050d21);scene.fog=new T.FogExp2(0x0b1b36,.013);
    const camera=new T.PerspectiveCamera(59,1,.1,330);
    const renderer=new T.WebGLRenderer({antialias:!small,powerPreference:'high-performance'});
    renderer.setPixelRatio(Math.min(devicePixelRatio||1,small?1.25:1.65));renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.22;
    visual.appendChild(renderer.domElement);visual.classList.add('is-ready');
    const mat=(color,extra={})=>new T.MeshStandardMaterial({color,roughness:.72,metalness:.05,flatShading:true,...extra});
    const basic=color=>new T.MeshBasicMaterial({color});
    const stone=mat(0x27354b),stoneLite=mat(0x39455b),stoneDark=mat(0x172238),wood=mat(0x201b1c),grass=[mat(0x0b1b29),mat(0x0d2430),mat(0x122938)],treeMats=[mat(0x091629),mat(0x0a1c2d),mat(0x101e30),mat(0x0b2331)];
    const gold=mat(0xd6a54c,{metalness:.56,roughness:.38}),lightGold=mat(0xffd58c,{metalness:.36,roughness:.32});
    const boxG=new T.BoxGeometry(1,1,1),icoG=new T.IcosahedronGeometry(1,0);
    const o=(g,m,x=0,y=0,z=0,parent=scene)=>{const m1=new T.Mesh(g,m);m1.position.set(x,y,z);parent.add(m1);return m1;};
    const bx=(x,y,z,w,h,d,m,parent=scene)=>{const a=o(boxG,m,x,y,z,parent);a.scale.set(w,h,d);return a;};
    const ico=(x,y,z,w,h,d,m,parent=scene)=>{const a=o(icoG,m,x,y,z,parent);a.scale.set(w,h,d);return a;};
    const cyl=(rt,rb,h,s,m,x,y,z,parent=scene)=>o(new T.CylinderGeometry(rt,rb,h,s),m,x,y,z,parent);
    const gem=(size,m,x=0,y=0,z=0,parent=scene)=>o(new T.OctahedronGeometry(size,0),m,x,y,z,parent);
    const emissive=(c,intensity=.8)=>mat(c,{emissive:c,emissiveIntensity:intensity,roughness:.29,metalness:.2});
    const cool=emissive(0x66dfff,1.6),orange=emissive(0xff6938,1.55),green=emissive(0x71e971,1.5),blue=emissive(0x67b9ff,1.8),purple=emissive(0xa659ff,1.5),sun=emissive(0xffc24e,1.8);
    scene.add(new T.HemisphereLight(0x688cc6,0x081022,1.5));
    const moonLight=new T.DirectionalLight(0xc4d4ff,1.3);moonLight.position.set(-22,40,-130);scene.add(moonLight);
    const fireLight=new T.PointLight(0xff963d,85,40,1.7);fireLight.position.set(-10,2,10);scene.add(fireLight);
    const dimRim=new T.DirectionalLight(0x4565a0,.65);dimRim.position.set(14,10,-20);scene.add(dimRim);
    const tex=(color)=>{const c=document.createElement('canvas');c.width=c.height=128;const ctx=c.getContext('2d');const grd=ctx.createRadialGradient(64,64,0,64,64,64);grd.addColorStop(0,color);grd.addColorStop(.25,color);grd.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=grd;ctx.fillRect(0,0,128,128);return new T.CanvasTexture(c);};
    const glowTex={cyan:tex('rgba(70,198,250,.6)'),fire:tex('rgba(255,143,61,.62)'),green:tex('rgba(92,232,114,.55)'),blue:tex('rgba(92,155,250,.6)'),purple:tex('rgba(170,70,255,.64)'),sun:tex('rgba(255,199,72,.65)'),moon:tex('rgba(196,215,255,.6)')};
    function glow(x,y,z,size,texture,opacity=1,parent=scene){const m=new T.SpriteMaterial({map:texture,transparent:true,opacity,depthWrite:false,blending:T.AdditiveBlending});const spr=new T.Sprite(m);spr.position.set(x,y,z);spr.scale.set(size,size,1);parent.add(spr);return spr;}
    // Moon, stars and an unbroken forest. Camera genuinely travels across 130 world units.
    const moon=o(new T.SphereGeometry(6.3,20,14),basic(0xeaf1ff),-28,27,-175);
    glow(-28,27,-176,35,glowTex.moon,.5);
    const pts=[];for(let i=0;i<400;i++){const a=Math.sin(i*78.11),b=Math.sin(i*321.13);pts.push(a*115,13+Math.abs(b)*50,-185+Math.abs(Math.sin(i*19.7))*75);}
    const pg=new T.BufferGeometry();pg.setAttribute('position',new T.Float32BufferAttribute(pts,3));scene.add(new T.Points(pg,new T.PointsMaterial({color:0xa5b9df,size:.16,transparent:true,opacity:.83})));
    o(new T.PlaneGeometry(300,360),mat(0x071629),0,-.7,-58).rotation.x=-Math.PI/2;
    for(let i=0;i<45;i++){const x=(i-22)*7.7,z=-160-(i%4)*8,h=14+((i*17)%12);o(new T.ConeGeometry(5+(i%5),h,3),basic(i%3===0?0x071323:0x091629),x,h*.43-1,z);}
    function tree(x,z,s,i){const group=new T.Group();group.position.set(x,0,z);scene.add(group);cyl(.13*s,.25*s,2.6*s,5,wood,0,1.0*s,0,group);for(let k=0;k<3;k++){const cone=o(new T.ConeGeometry((1.66-.29*k)*s,3.55*s,5),treeMats[(i+k)%treeMats.length],0,(2.6+k*1.13)*s,0,group);cone.rotation.y=(i+k)*.29;}}
    for(let i=0;i<(small?180:260);i++){
      const z=22-(i*13.73)%168,side=i%2?-1:1,x=side*(11+(i*15.71)%37);
      tree(x,z,.62+((i*19)%10)*.14,i);
    }
    for(let i=0;i<170;i++){const z=20-(i*3.73)%164,x=Math.sin(i*23.67)*29;if(Math.abs(x)<5)continue;
      const rock=ico(x,-.51,z,.45+(i%5)*.22,.17+(i%4)*.11,.4+(i%4)*.19,i%3===0?stoneLite:stoneDark);rock.rotation.y=i*.42;
    }
    for(let i=0;i<260;i++){const z=21-(i*5.33)%160,x=Math.sin(i*18.91)*30;
      const g=o(new T.ConeGeometry(.18,.85,3),grass[i%3],x,-.31,z);g.scale.set(.5+(i%4)*.12,.4+(i%5)*.16,.7);g.rotation.z=Math.sin(i*3.1)*.3;
    }
    // Campfire at the trailhead, log rings and the little ranger tent.
    const fire=new T.Group();fire.position.set(-10,0,10);fire.scale.setScalar(1.60);scene.add(fire);
    for(let j=0;j<12;j++){const a=j*Math.PI/6;ico(Math.cos(a)*1.45,-.41,Math.sin(a)*1.23,.52,.26,.38,j%3?stone:stoneLite,fire);}
    for(let j=0;j<5;j++){const a=j*Math.PI*2/5;const log=cyl(.24,.3,2.7,6,wood,Math.cos(a)*.2,-.15,Math.sin(a)*.25,fire);log.rotation.z=Math.PI/2.9;log.rotation.y=a;}
    const flames=[];
    for(let j=0;j<12;j++){const a=j*2.399,h=1.1+(j%5)*.34;const m=new T.MeshBasicMaterial({color:[0xff6e2a,0xffc15c,0xffe7a4][j%3],transparent:true,opacity:.94,depthWrite:false});const fl=o(new T.ConeGeometry(.21+(j%3)*.09,h,4),m,Math.cos(a)*.3,h*.42,Math.sin(a)*.3,fire);fl.rotation.z=Math.sin(a)*.2;flames.push({fl,a,j});}
    const flameGlow=glow(-10,1.75,10,20,glowTex.fire,.67);
    const embers=[];
    for(let j=0;j<45;j++){
      const a=j*2.39997;
      const dot=o(new T.SphereGeometry(j%5===0?.08:.035,4,3),new T.MeshBasicMaterial({color:j%3?0xffa75a:0xffe3a2,transparent:true,opacity:.8,depthWrite:false}),-10,1,10);
      embers.push({dot,a,j});
    }
    for(let j=0;j<8;j++){
      const a=j*Math.PI/4;
      const pebble=ico(-10+Math.cos(a)*2.5,-.45,10+Math.sin(a)*2.45,.5,.31,.52,j%2?stone:stoneLite);pebble.rotation.y=a;
    }
    // Sparse camping props: a stump seat, stacked provisions, and a wooden trail sign.
    for(let j=0;j<3;j++){ const stump=cyl(.66,.78,.60,7,wood,-14+j*1.3,.0,14.5+j*.5);stump.rotation.y=j*.6; }
    bx(-7.4,.4,13.4,1.8,.8,.95,wood);bx(-7.4,.9,13.4,1.9,.13,1.0,stoneLite);
    bx(-5.9,1.4,7.0,.24,3.2,.25,wood);bx(-5.9,2.6,7.0,2.5,.52,.25,wood);
    const tent=new T.Group();tent.position.set(-17,-.3,10);scene.add(tent);
    o(new T.ConeGeometry(3,5.8,4),mat(0x252b3b),0,2.4,0,tent).rotation.y=Math.PI/4;bx(0,1.1,2.18,1.7,2,.15,stoneDark,tent);
    bx(-17,-.1,16,1.7,1.3,1.3,wood);
    // Separate shrine landmarks at each relic station, connected by a winding cobbled path.
    const orbiting=[];
    const relicModels=[];
    relics.forEach((r,i)=>{
      const group=new T.Group();group.position.set(r.x,4.5,r.z);scene.add(group);
      const bobGroup=new T.Group();group.add(bobGroup);
      const turner=new T.Group();bobGroup.add(turner);
      const thisGlow=[glowTex.cyan,glowTex.fire,glowTex.green,glowTex.blue,glowTex.purple,glowTex.sun][i];
      const halo=glow(0,0,0,9,thisGlow,.52,group);
      const l=new T.PointLight(r.color,10,20,2);l.position.set(r.x,5.3,r.z);scene.add(l);
      const ring=o(new T.TorusGeometry(2.06,.023,5,60),mat(r.color,{emissive:r.color,emissiveIntensity:.9,transparent:true,opacity:.32}),0,0,0,bobGroup);ring.rotation.x=.2;
      const ring2=o(new T.TorusGeometry(2.30,.019,4,48),mat(r.color,{emissive:r.color,emissiveIntensity:.8,transparent:true,opacity:.23}),0,0,0,bobGroup);ring2.rotation.y=.72;
      // V4: restored the richer six designs from the first Relic Archive.
      // Each artifact is made of layered gold/stone/clusters instead of a generic octahedron.
      {
      const artifact=new T.Group();turner.add(artifact);artifact.scale.setScalar(2.42);
      const THREE=T;
      function craftMat(c,roughness=.6,metalness=.08){return new THREE.MeshStandardMaterial({color:c,roughness,metalness,flatShading:true})}
      const gold=craftMat(0xc59a54,.34,.64), goldLight=craftMat(0xf2ce80,.25,.52), bronze=craftMat(0x665039,.62,.3);
      const stone=craftMat(0x536457,.96,.02),stoneLite=craftMat(0x839188,.91,.01),stoneDark=craftMat(0x33403a,.99,0),moss=craftMat(0x5d844d,.9,0);
      const crystalMat=c=>new THREE.MeshPhysicalMaterial({color:c,metalness:.04,roughness:.15,transmission:.08,thickness:.6,flatShading:true,emissive:c,emissiveIntensity:.5});
      const glowing=c=>new THREE.MeshStandardMaterial({color:c,roughness:.24,metalness:.1,emissive:c,emissiveIntensity:1.18,flatShading:true});
      const mat=craftMat;
      function addMesh(parent,geometry,material,pos=[0,0,0],rot=[0,0,0],scale=[1,1,1]){const m=new THREE.Mesh(geometry,material);m.position.set(...pos);m.rotation.set(...rot);m.scale.set(...scale);parent.add(m);return m;}
      function box(p,w,h,d,m,x=0,y=0,z=0){return addMesh(p,new THREE.BoxGeometry(w,h,d),m,[x,y,z]);}
      function cyl(p,rt,rb,h,m,x=0,y=0,z=0,seg=8){return addMesh(p,new THREE.CylinderGeometry(rt,rb,h,seg),m,[x,y,z]);}
      function ico(p,r,m,x=0,y=0,z=0,detail=0){return addMesh(p,new THREE.IcosahedronGeometry(r,detail),m,[x,y,z]);}
      function torus(p,r,t,m,x=0,y=0,z=0,segments=10){return addMesh(p,new THREE.TorusGeometry(r,t,5,segments),m,[x,y,z]);}
      function cone(p,r,h,m,x=0,y=0,z=0,n=5){return addMesh(p,new THREE.ConeGeometry(r,h,n),m,[x,y,z]);}
      function diamond(p,m,x,y,z,sx=.3,sy=.55,sz=.3){return addMesh(p,new THREE.OctahedronGeometry(1),m,[x,y,z],[0,0,0],[sx,sy,sz]);}
      function rodBetween(p,a,b,r,m,sides=6){const a3=new THREE.Vector3(...a),b3=new THREE.Vector3(...b),dir=b3.clone().sub(a3),mid=a3.clone().add(b3).multiplyScalar(.5);let piece=addMesh(p,new THREE.CylinderGeometry(r,r,dir.length(),sides),m,mid.toArray());piece.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),dir.normalize());return piece;}
      function halo(p,color,r=.45,y=0){const ring=torus(p,r,.013,new THREE.MeshBasicMaterial({color,transparent:true,opacity:.65,depthWrite:false}),0,y,0,50);ring.rotation.x=Math.PI*.43;return ring;}
      function sprout(p,x,y,z,angle,mat){return addMesh(p,new THREE.SphereGeometry(.13,5,3),mat,[x,y,z],[0,0,angle],[.7,1.55,.35]);}
  function buildCore(g){
    cyl(g,.39,.43,.16,gold,0,-.62,0,8);cyl(g,.26,.34,.2,bronze,0,-.48,0,8);
    diamond(g,crystalMat(0x7ceefa),0,.15,0,.47,.81,.44);
    diamond(g,glowing(0x6dfaff),0,.19,.33,.12,.24,.06);
    for(let i=0;i<4;i++){let a=i*Math.PI/2;const x=Math.sin(a)*.38,z=Math.cos(a)*.38;
      rodBetween(g,[x,-.47,z],[x*1.2,.36,z*1.2],.075,gold);
      diamond(g,goldLight,x*1.2,.34,z*1.2,.10,.18,.10);
    }
    for(let i=0;i<4;i++){let a=i*2.4;diamond(g,crystalMat(0x8eeaff),Math.sin(a)*.7,.3+Math.sin(i*3)*.3,Math.cos(a)*.28,.07,.14,.07)}
    halo(g,0x8bf6f2,.68,.16);
  }
  function buildFeather(g){
    rodBetween(g,[-.12,-.73,0],[.09,.78,0],.045,goldLight);
    const shades=[0xee5b30,0xfc8131,0xffad3d,0xffcc65];
    for(let i=0;i<7;i++){
      const yy=-.29+i*.17, w=.33*(1-i/10);
      for(const sign of [-1,1]){
        let shard=cone(g,w,.58,glowing(shades[(i+(sign>0?1:0))%4]),sign*.17,yy,0,3);
        shard.rotation.z=sign*(-1.07+ i*.028);
        shard.scale.z=.27;
      }
    }
    diamond(g,glowing(0xffdf7b),.06,.8,0,.08,.24,.07);
    diamond(g,crystalMat(0xff733c),-.16,-.65,.11,.14,.18,.10);
    for(let i=0;i<7;i++){ico(g,.035,glowing(0xffb75a),Math.sin(i*4)*.59,.15+Math.sin(i*5)*.65,-.1,0)}
    halo(g,0xff884e,.53,.0);
  }
  function buildGrowth(g){
    let slab=box(g,.85,1.35,.34,stone,.02,-.03,0);slab.rotation.z=-.08;
    box(g,.73,1.18,.09,stoneLite,.02,-.03,.18).rotation.z=-.08;
    const green=glowing(0x8af46a);
    rodBetween(g,[0,-.47,.251],[0,.44,.251],.034,green);
    sprout(g,-.18,.17,.25,-.8,green);sprout(g,.19,.34,.25,.8,green);
    sprout(g,-.24,-.17,.26,-.78,green);sprout(g,.22,-.07,.26,.76,green);
    for(let i=0;i<6;i++){const a=i*2.12;ico(g,.13,moss,Math.sin(a)*.47,-.58+Math.sin(i)*.32,Math.cos(a)*.16);if(i%2===0)sprout(g,Math.sin(a)*.44,.5-Math.abs(Math.cos(a))*.2,Math.cos(a)*.2,(i%3-1)*.65,mat(0x6ca34b));}
    halo(g,0x6df096,.64,.1);
  }
  function buildGuardian(g){
    box(g,.81,.71,.49,stoneLite,0,-.29,0);
    box(g,.88,.5,.56,stone,0,.32,0);
    box(g,.77,.11,.57,stoneDark,0,.04,.01);
    for(let s of [-1,1]){
      box(g,.35,.57,.42,stone,s*.52,-.34,.03).rotation.z=s*.13;
      box(g,.3,.22,.5,stoneDark,s*.28,-.76,.08);
      cone(g,.21,.49,stoneLite,s*.39,.80,0,4).rotation.z=-s*.25;
      box(g,.14,.07,.11,glowing(0x65d3fb),s*.18,.28,.295);
    }
    diamond(g,glowing(0x51d5ff),0,-.27,.31,.22,.32,.12);
    diamond(g,crystalMat(0x60c6ff),0,.83,0,.18,.25,.2);
    halo(g,0x8ecbff,.7,-.34);
  }
  function buildShadow(g){
    const dark=crystalMat(0x7c37a8),bright=crystalMat(0xbf61ef);
    diamond(g,dark,0,.02,0,.46,.86,.42);diamond(g,bright,0,.03,.34,.16,.45,.10);
    const side=[[-.43,-.29,.04,.32,.55], [.4,-.37,.14,.27,.43],[-.24,-.5,.4,.2,.38],[.35,-.52,-.32,.2,.34]];
    side.forEach(([x,y,z,w,h],i)=>{const d=diamond(g,i%2?bright:dark,x,y,z,w,h,w);d.rotation.z=x*1.3;});
    for(let i=0;i<4;i++)diamond(g,glowing(0xce7aff),Math.sin(i*1.7)*.65,Math.cos(i*2.7)*.45,.15,.045,.08,.05);
    halo(g,0xa35dff,.68,-.10);
    const r2=halo(g,0x8c56d8,.78,.18);r2.rotation.y=.7;
  }
  function buildSun(g){
    cyl(g,.32,.42,.21,stoneLite,0,-.67,0,8);
    box(g,.68,.22,.53,stoneLite,0,-.53,0);
    cyl(g,.38,.35,.22,gold,0,.08,0,12).rotation.x=Math.PI/2;
    torus(g,.48,.11,gold,0,.07,.14,13);
    const core=ico(g,.32,glowing(0xffce4b),0,.08,.20,1);core.scale.z=.55;
    for(let i=0;i<10;i++){let a=i*Math.PI/5;
      const ray=diamond(g,goldLight,Math.sin(a)*.61,.08+Math.cos(a)*.61,0,.13,.23,.09);ray.rotation.z=-a;}
    for(let s of [-1,1]){let wing=box(g,.29,.17,.3,gold,s*.6,-.47,0);wing.rotation.z=s*.5;}
    halo(g,0xffd46c,.76,.09);
  }
  function buildCompass(g){
    let ring=torus(g,.60,.065,goldLight,0,.02,0,12);
    let ring2=torus(g,.40,.045,gold,0,.02,.03,12);ring2.rotation.y=.40;
    for(let i=0;i<8;i++){const a=i*Math.PI/4;let d=diamond(g,i%2?gold:goldLight,Math.sin(a)*.71,Math.cos(a)*.71,.01,.10,.20,.06);d.rotation.z=-a;}
    diamond(g,crystalMat(0x7cceec),0,.02,.17,.27,.49,.2);
    diamond(g,glowing(0xc6f8ff),0,.03,.35,.09,.17,.05);
    let r=halo(g,0x98d9ff,.82,0);r.rotation.x=.32;r.rotation.y=.3;
    cyl(g,.20,.25,.12,bronze,0,-.79,0,8);
    rodBetween(g,[0,-.71,0],[0,-.52,0],.07,gold);
  }
      [buildCore,buildFeather,buildGrowth,buildGuardian,buildShadow,buildSun][i](artifact);
      // Decorative golden mounts and floating fragments repeat the V1's jewelry vocabulary.
      if(i===0 || i===3 || i===5){
        for(let j=0;j<4;j++){const a=j*Math.PI/2;const bead=diamond(artifact,goldLight,Math.cos(a)*.83,-.7,Math.sin(a)*.6,.075,.1,.07);bead.rotation.y=a;}
      }
      }
      // An invisible hit sphere lets pointer users select the collectible reliably.
      const hit=o(new T.SphereGeometry(2.65,16,12),new T.MeshBasicMaterial({visible:false}),0,0,0,bobGroup);
      hit.userData.relicIndex=i;
      const sparks=[];
      for(let j=0;j<12;j++){
        const a=j*2.399;
        const speck=gem(j%3===0?.075:.045,new T.MeshBasicMaterial({color:r.color,transparent:true,opacity:.85}),Math.cos(a)*2.6,Math.sin(a)*1.6,Math.sin(a*1.6)*1.9,group);
        sparks.push({obj:speck,phase:a,j});
      }
      relicModels.push({group,bobGroup,turner,ring,ring2,halo,light:l,sparks,hit,dragAngle:0});
      // Shrine columns and luminous weeds are grounded at each location.
      for(let j=0;j<5;j++){
        const a=j*Math.PI*2/5,rad=6+(j%2)*1.3;
        const sx=r.x+Math.cos(a)*rad,sz=r.z+Math.sin(a)*rad;
        const column=bx(sx,1.05,sz,.8,2.9,.85,j%2?stoneLite:stone);column.rotation.y=j*.65;
        ico(sx,2.75,sz,.8,.32,.9,stoneDark);
      }
      const groundRune=o(new T.TorusGeometry(3.3,.08,5,48),mat(r.color,{emissive:r.color,emissiveIntensity:.45,transparent:true,opacity:.38}),r.x,-.55,r.z);groundRune.rotation.x=Math.PI/2;
    });
    // Small rocks on the trail create motion parallax between relic stops.
    for(let i=0;i<165;i++){const z=18-i*.84,x=2.7+Math.sin(i*.23)*4.0;
      const p=ico(x,-.52,z,.2+(i%4)*.23,.11,.3+(i%3)*.2,i%2?stoneLite:stone);p.rotation.y=i*.7;
    }
    // An ancient portal beyond the sixth relic becomes the login transition target.
    const portal=new T.Group();portal.position.set(5,0,-123);scene.add(portal);
    bx(-3,3.4,0,1.4,7.7,1.3,stoneLite,portal);bx(3,3.4,0,1.4,7.7,1.3,stoneLite,portal);bx(0,7.15,0,7.2,1.15,1.45,stoneLite,portal);
    const portalCenter=gem(1.8,cool,0,3.8,0,portal);portalCenter.scale.set(.67,1.33,.44);glow(5,4.1,-123,13,glowTex.cyan,.48);

    const campPose=small
      ? {pos:[-3.2,5.4,19.5],look:[-9.9,1.2,10.3],fov:60}
      : {pos:[-1.9,5.1,20],look:[-9.9,1.45,10.4],fov:54};
    const poses=[campPose,...relics.map(r=>small
      ? {pos:[r.x+1.4,6.4,r.z+18],look:[r.x,1.3,r.z-1],fov:62}
      : {pos:[r.x+2,6.3,r.z+19],look:[r.x+5.6,4.3,r.z-1.2],fov:56})];
    const inspectPose=r=>({pos:[r.x+3.8,6,r.z+10],look:[r.x,4.5,r.z],fov:small?47:43});
    const loginPose={pos:[5,4,-117],look:[5,4,-128],fov:46};
    const cameraLook=new T.Vector3(...poses[current].look),wantedPos=new T.Vector3(...poses[current].pos),wantedLook=new T.Vector3(...poses[current].look);
    camera.position.copy(wantedPos);camera.lookAt(cameraLook);
    let fovTarget=poses[current].fov;
    const setPose=pose=>{wantedPos.set(...pose.pos);wantedLook.set(...pose.look);fovTarget=pose.fov;};
    let loginArrivalPending=false;
    sceneAPI={setStep:i=>setPose(poses[i]),setInspect:on=>setPose(on?inspectPose(relics[current-1]):poses[current]),setLogin:on=>{setPose(on?loginPose:poses[current]);loginArrivalPending=on;}};
    if(loggingIn)sceneAPI.setLogin(true);
    const resize=()=>{const r=visual.getBoundingClientRect();if(!r.width||!r.height)return;renderer.setSize(Math.round(r.width),Math.round(r.height),false);camera.aspect=r.width/r.height;camera.updateProjectionMatrix();};
    window.addEventListener('resize',resize,{passive:true});new ResizeObserver(resize).observe(visual);resize();
    const raycaster=new T.Raycaster(),pointer=new T.Vector2();
    const getHit=e=>{const rect=renderer.domElement.getBoundingClientRect();pointer.set((e.clientX-rect.left)/rect.width*2-1,-(e.clientY-rect.top)/rect.height*2+1);raycaster.setFromCamera(pointer,camera);return raycaster.intersectObjects(relicModels.map(m=>m.hit),false)[0];};
    let drag=null;
    renderer.domElement.addEventListener('pointerdown',e=>{
      if(loggingIn)return;
      const hit=getHit(e);
      if(!inspecting && (current===0 || !hit || hit.object.userData.relicIndex!==current-1))return;
      drag={id:e.pointerId,x:e.clientX,y:e.clientY,moved:false};
      if(inspecting){renderer.domElement.setPointerCapture(e.pointerId);stage.classList.add('is-dragging');}
    });
    renderer.domElement.addEventListener('pointermove',e=>{
      if(!drag||drag.id!==e.pointerId)return;
      const dx=e.clientX-drag.x,dy=e.clientY-drag.y;
      if(Math.abs(dx)+Math.abs(dy)>3)drag.moved=true;
      // Drag rotation only in inspection mode. Outside it, touch swiping changes stations.
      if(inspecting){relicModels[current-1].dragAngle+=dx*.012;relicModels[current-1].turner.rotation.x=Math.max(-.62,Math.min(.62,relicModels[current-1].turner.rotation.x+dy*.003));}
      drag.x=e.clientX;drag.y=e.clientY;
    });
    renderer.domElement.addEventListener('pointerup',e=>{
      if(!drag||drag.id!==e.pointerId)return;
      if(!drag.moved&&!inspecting){openInspect();}
      drag=null;stage.classList.remove('is-dragging');
    });
    renderer.domElement.addEventListener('pointercancel',()=>{drag=null;stage.classList.remove('is-dragging');});
    let then=performance.now(),time=0,isVisible=true;
    new IntersectionObserver(es=>{isVisible=es[0]?.isIntersecting??false;}).observe(stage);
    function tick(now){
      requestAnimationFrame(tick);if(!isVisible||document.hidden){then=now;return;}
      const dt=Math.min(.05,(now-then)/1000);then=now;time+=dt;
      const easing=reduce?1:1-Math.exp(-dt*(loggingIn?1.3:1.7));
      camera.position.lerp(wantedPos,easing);cameraLook.lerp(wantedLook,easing);camera.lookAt(cameraLook);
      camera.fov+=(fovTarget-camera.fov)*easing;camera.updateProjectionMatrix();
      if(loggingIn&&loginArrivalPending&&camera.position.distanceTo(wantedPos)<2.5&&cameraLook.distanceTo(wantedLook)<2.5&&Math.abs(camera.fov-fovTarget)<.8){
        // Reveal during the final approach; keep easing smoothly instead of snapping.
        loginArrivalPending=false;arriveAtLogin();
      }
      relicModels.forEach((m,i)=>{
        m.group.visible = current !== 0 || loggingIn; // No visible relic during Campfire intro.
        const focus=i===current-1;
        m.bobGroup.position.y=reduce?0:Math.sin(time*1.2+i)*.24;
        m.turner.rotation.y=(reduce?0:time*.28)+m.dragAngle;
        m.ring.rotation.z=time*.13+i;m.ring2.rotation.x=time*.17+i;
        m.halo.material.opacity=focus?.62+.1*Math.sin(time*3+i):.25+.04*Math.sin(time*2+i);
        m.light.intensity=focus?10+1.3*Math.sin(time*3+i):3.5;
        m.sparks.forEach(({obj,phase,j})=>{
          obj.position.x=Math.cos(phase+time*.4)*(2.35+.15*Math.sin(time+phase));
          obj.position.y=Math.sin(phase*1.7+time*.7)*1.8;
          obj.position.z=Math.sin(phase+time*.4)*1.6;
          obj.material.opacity=.5+.45*(.5+.5*Math.sin(time*3+phase+j));
        });
      });
      embers.forEach(({dot,a,j})=>{
        const lifetime=(time*.22+(j*0.074))%1;
        dot.position.set(-10+Math.cos(a+time*.7)*(0.4+lifetime*2.1),.65+lifetime*6,10+Math.sin(a+time*.4)*(.5+lifetime*.85));
        dot.material.opacity=(1-lifetime)*(.35+.65*Math.sin(j+time*2)**2);
      });
      flames.forEach(({fl,a,j})=>{fl.scale.y=.82+.17*Math.sin(time*8+a)+.1*Math.cos(time*5+j);fl.rotation.z=Math.sin(time*4+a)*.2;});
      flameGlow.material.opacity=.62+Math.sin(time*7)*.09;fireLight.intensity=85+Math.sin(time*8)*10;
      portalCenter.rotation.y=time*.16;
      renderer.render(scene,camera);
    }
    requestAnimationFrame(tick);
  }
})();
