/* ZORX — Squad of Four Races. A 3D trail of eight stops through a night valley (carved ink-wash look, 2026-11-14).
 * Scroll / swipe / arrows move the camera from stop to stop; the last scroll flies into the sign-in stop (08 LOGIN).
 * The canvas is transparent: the painted night valley (assets/loading_valley.webp, CSS) is the sky behind it.
 * Ink look (v2, 2026-11-14): every prop is drawn with 2-band toon shading and warm paper-tinted shadows plus a
 * bold dark-brown inverted-hull outline whose width is a fraction of the screen height (the game's
 * client/characters/card_ink_hull.gdshader), and a light paper grain. Station props are baked into one mesh per
 * station (vertex colours), so a station costs 2 draw calls (fill + outline) whatever it is made of.
 * The campfire squad are the game's own Studio characters (assets/squad_<race>.glb, built offline by
 * tools/landing/build_landing_squad.mjs), loaded lazily after the first paint, each playing its class idle.
 * No game scene or sign-in code is changed here; auth.js drives ?play=1 / ?auth= / ?logout=1 through these buttons.
 */
(() => {
  const stage = document.getElementById('trail-stage');
  const visual = document.getElementById('scene-visual');
  const $ = id => document.getElementById(id);
  if (!stage || !visual) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Stop copy: English titles, Thai descriptions (same pattern as before). Numbers come from the game data:
  // data/races/*.json (colours, Alliance +8%), data/journeys/goblin_waves.json (12 waves, boss hp_mult 1.7).
  const stations = [
    {name:'The Squad Campfire',ch:'THE FIRST SPARK',tag:'SQUAD OF FOUR RACES',effect:'Pick · Build · Fight',
     description:'ทุกการออกรบเริ่มที่กองไฟ มนุษย์ ไวกิ้ง เอลฟ์ และรูนบอร์น เลือกการ์ดคลาส 3 ใบ จัดเป็นทัพของคุณ แล้วส่งลงสนามให้สู้เอง',x:-10,z:10},
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
     description:'จัดทัพเสร็จแล้วก็ถึงเวลาออกรบ เลื่อนอีกครั้งเพื่อเดินผ่านประตูไปเข้าสู่ระบบ แล้วเล่นบนเบราว์เซอร์ได้ทันที',x:5,z:-110}
  ];
  // The trail has one more stop after the last station: 08 LOGIN, the sign-in flight through the FIGHT gate.
  const total = stations.length;          // station stops (01..07)
  const LOGIN = total;                    // the login stop index (08)
  const stops = total + 1;
  const canInspect = i => i > 0 && i < total - 1; // the campfire and the gate have nothing to turn over
  const hints = ['SCROLL TO MEET THE FOUR RACES','SCROLL TO THE NEXT STOP','SCROLL TO THE NEXT STOP','SCROLL TO THE NEXT STOP','SCROLL TO THE NEXT STOP','SCROLL TO THE GATE','SCROLL ON TO SIGN IN'];

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
  function markRail(i){
    rail.forEach((button,k)=>{
      button.classList.toggle('is-current',k===i);
      if(k===i)button.setAttribute('aria-current','step'); else button.removeAttribute('aria-current');
    });
    $('progress-fill').style.width=`${(i+1)*100/stops}%`;
    $('scene-counter').textContent=i===LOGIN?`SCENE ${two(stops)} / ${two(stops)} — LOGIN`:`SCENE ${two(i+1)} / ${two(stops)}`;
  }

  function setStep(index,force=false) {
    if (inspecting) return;
    if (index>=LOGIN){ openLogin(); return; }
    if (loggingIn){ if(index<LOGIN)closeLogin(index); return; }
    const next=Math.min(total-1,Math.max(0,index));
    if(next===current && !force)return;
    current=next;
    info.classList.remove('details-open');detailsToggle.setAttribute('aria-expanded','false');detailsToggle.setAttribute('aria-label','แสดงรายละเอียด');
    const isCamp=current===0, s=stations[current];
    markRail(current);
    info.classList.add('is-switching');
    clearTimeout(changeTimer);
    changeTimer=setTimeout(()=>{
      $('relic-chapter').textContent=isCamp?'PROLOGUE — THE CAMPFIRE':`STOP ${two(current+1)} / ${two(stops)} — ${s.ch}`;
      $('relic-name').textContent=s.name;
      $('relic-description').textContent=s.description;
      $('relic-rarity').textContent=s.tag;
      $('relic-effect').textContent=s.effect;
      $('relic-hint').textContent=hints[current];
      $('prev-step').disabled=current===0;
      $('next-step').disabled=false; // the last station's "next" is the login stop
      stage.classList.toggle('at-campfire',isCamp);
      stage.classList.toggle('no-inspect',!canInspect(current));
      $('inspect-relic').disabled=!canInspect(current);
      $('inspect-relic').setAttribute('aria-hidden',String(!canInspect(current)));
      info.classList.remove('is-switching');
    },reduce?0:175);
    sceneAPI?.setStep(current);
  }
  rail.forEach(b=>b.addEventListener('click',()=>setStep(Number(b.dataset.step))));
  $('prev-step').addEventListener('click',()=>setStep(current-1));
  $('next-step').addEventListener('click',()=>setStep(current+1));

  function centered(){const r=stage.getBoundingClientRect();return r.top<innerHeight*.3&&r.bottom>innerHeight*.7;}
  // Where the scroll is now: the login stop while signing in, else the station.
  const here=()=>loggingIn?LOGIN:current;
  stage.addEventListener('wheel',e=>{
    if(!centered() || inspecting || Math.abs(e.deltaY)<9 || e.target.closest('button,a,.relic-description,.login-card')) return;
    if(mobileScene())e.preventDefault();
    const direction=Math.sign(e.deltaY);
    if((direction>0&&here()===LOGIN)||(direction<0&&here()===0))return;
    e.preventDefault();
    const now=performance.now();
    if(now-lastScroll>750){lastScroll=now;setStep(here()+direction);}
  },{passive:false});
  stage.addEventListener('touchstart',e=>{
    if(inspecting||e.target.closest('button,a,.relic-description,.login-card'))return;
    touchStart={x:e.touches[0].clientX,y:e.touches[0].clientY};
  },{passive:true});
  stage.addEventListener('touchmove',e=>{
    if(!touchStart||inspecting||!centered())return;
    if(mobileScene())e.preventDefault();
    const dx=touchStart.x-e.touches[0].clientX,dy=touchStart.y-e.touches[0].clientY;
    const dir=Math.sign(dy);
    if(Math.abs(dy)>14&&Math.abs(dy)>Math.abs(dx)*1.2 && here()+dir>=0&&here()+dir<=LOGIN){e.preventDefault();}
  },{passive:false});
  stage.addEventListener('touchend',e=>{
    if(!touchStart||inspecting)return;
    const dy=touchStart.y-e.changedTouches[0].clientY,dx=touchStart.x-e.changedTouches[0].clientX;
    if(Math.abs(dy)>48 && Math.abs(dy)>Math.abs(dx)*1.25 && centered()){const to=here()+Math.sign(dy);if(to>=0&&to<=LOGIN)setStep(to);}
    touchStart=null;
  },{passive:true});
  stage.addEventListener('keydown',e=>{
    if(e.key==='Escape'){
      if(loggingIn){e.preventDefault();closeLogin();} else if(inspecting){e.preventDefault();closeInspect();}
      return;
    }
    if(inspecting||e.target.closest('button,a,.relic-description,.login-card'))return;
    if(['ArrowDown','ArrowRight','PageDown'].includes(e.key)){e.preventDefault();if(here()<LOGIN)setStep(here()+1);}
    if(['ArrowUp','ArrowLeft','PageUp'].includes(e.key)){e.preventDefault();if(here()>0)setStep(here()-1);}
  });
  function openInspect(){
    if(loggingIn||inspecting||!canInspect(current))return;
    inspecting=true;stage.classList.add('is-inspecting');$('inspect-layer').setAttribute('aria-hidden','false');
    const s=stations[current];$('inspect-count').textContent=`STOP ${two(current+1)} / ${two(stops)}`;
    $('inspect-name').textContent=s.name;$('inspect-copy').textContent=s.description;
    sceneAPI?.setInspect(true);
    setTimeout(()=>$('close-inspect').focus({preventScroll:true}),300);
  }
  function closeInspect(){if(!inspecting)return;inspecting=false;stage.classList.remove('is-inspecting','is-dragging');$('inspect-layer').setAttribute('aria-hidden','true');sceneAPI?.setInspect(false);$('inspect-relic').focus({preventScroll:true});}
  $('inspect-relic').addEventListener('click',openInspect);$('close-inspect').addEventListener('click',closeInspect);
  // 08 LOGIN: START GAME, ?play=1, ?auth=… and the last scroll all take this same flight through the FIGHT gate.
  function openLogin(){
    if(loggingIn)return;if(inspecting)closeInspect();loggingIn=true;
    stage.dataset.loginAttempt=String(Number(stage.dataset.loginAttempt||0)+1);
    loginArrived=false;stage.classList.add('is-login');$('login-layer').setAttribute('aria-hidden','true');
    markRail(LOGIN);
    if(sceneAPI)sceneAPI.setLogin(true);else if(sceneFailed)arriveAtLogin();
  }
  function arriveAtLogin(){
    if(!loggingIn||loginArrived)return;
    loginArrived=true;
    stage.classList.add('login-revealed');$('login-layer').setAttribute('aria-hidden','false');
    window.dispatchEvent(new Event('zorx:login-ready'));
  }
  // Back from the login stop: to the stop the visitor scrolled or tapped to (default: where they were).
  function closeLogin(to){
    if(!loggingIn)return;clearTimeout(loginTimer);stage.dataset.loginAttempt=String(Number(stage.dataset.loginAttempt||0)+1);loggingIn=false;stage.classList.remove('is-login','login-revealed');$('login-layer').setAttribute('aria-hidden','true');
    const back=Number.isInteger(to)?Math.min(total-1,Math.max(0,to)):current;
    sceneAPI?.setLogin(false);
    if(back!==current)setStep(back,true);else{markRail(current);sceneAPI?.setStep(current);}
    $('start-game').focus({preventScroll:true});
  }
  $('start-game').addEventListener('click',openLogin);$('return-to-trail').addEventListener('click',()=>closeLogin());
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

  // three.js from the import map in index.html (jsDelivr); unpkg is a fallback for the world only (the squad's
  // glTF loader needs the mapped "three", so without jsDelivr the campfire shows its empty places).
  let squadLoadable=true;
  async function loadThree(){
    let T;
    try{T=await import('three');}catch(err){console.warn('Three.js CDN unavailable: jsdelivr',err);}
    if(!T){squadLoadable=false;try{T=await import('https://unpkg.com/three@0.165.0/build/three.module.min.js');}catch(err){console.warn('Three.js CDN unavailable: unpkg',err);}}
    // Real failure only (no CDN, no WebGL): the painted valley stays as a still backdrop and every flow still works.
    if(!T){sceneFailed=true;if(loggingIn)arriveAtLogin();return;}
    try{createWorld(T);}catch(err){sceneFailed=true;sceneAPI=null;visual.classList.remove('is-ready');visual.querySelector('canvas')?.remove();if(loggingIn)arriveAtLogin();console.error('WebGL scene failed; retaining the painted backdrop',err);}
  }
  const observer=new IntersectionObserver(entries=>{if(entries.some(x=>x.isIntersecting)){observer.disconnect();loadThree();}},{rootMargin:'500px'});observer.observe(stage);

  function createWorld(T){
    const small=matchMedia('(max-width:640px)').matches;
    // Phones (coarse pointer or a small screen): lower pixel ratio, no outline on the far scenery (trees, rocks,
    // columns), fewer trees and embers. Desktop keeps every outline.
    const low=small||matchMedia('(pointer:coarse)').matches;
    // Night valley: blue-grey fog, no 3D sky (the painting shows through the transparent canvas).
    const FOG=0x4b5869;
    const scene=new T.Scene();scene.fog=new T.FogExp2(FOG,small?.021:.019);
    const camera=new T.PerspectiveCamera(59,1,.1,240);
    const renderer=new T.WebGLRenderer({antialias:!low,alpha:true,powerPreference:'high-performance'});
    if(!renderer.getContext())throw new Error('no WebGL context');
    renderer.setClearColor(0x000000,0);
    renderer.setPixelRatio(Math.min(devicePixelRatio||1,low?1.25:1.6));renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.05;
    visual.appendChild(renderer.domElement);visual.classList.add('is-ready');

    // ---- Ink look -----------------------------------------------------------------------------------------------
    // 2-band toon with warm paper-tinted shadows and a light paper grain, injected into Lambert (keeps the scene's
    // lights, fog, instancing, vertex colours and skinning). Port of studio05_toon.gdshader's card_ink branch.
    const INK=new T.Color(0x2a1a10);            // dark brown ink (#2a1a10, a touch lighter than the card ink at night)
    const grainUniform={value:3.0};             // grain cell size in pixels (scaled by pixel ratio in resize())
    const inkCommon=`
      float zxHash(vec2 c){return fract(sin(dot(c,vec2(127.1,311.7)))*43758.5453);}
      float zxGrain(vec2 p){vec2 c=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
        return mix(mix(zxHash(c),zxHash(c+vec2(1,0)),f.x),mix(zxHash(c+vec2(0,1)),zxHash(c+vec2(1,1)),f.x),f.y);}
      uniform float zxGrainPx;`;
    const toonPatch=(shader)=>{
      shader.uniforms.zxGrainPx=grainUniform;
      shader.fragmentShader=shader.fragmentShader.replace('#include <common>','#include <common>\n'+inkCommon).replace('#include <opaque_fragment>',`
        {
          // Two crisp bands from the summed light; the shadow band is a warm paper wash, not grey.
          float lum=dot(outgoingLight,vec3(0.2126,0.7152,0.0722));
          float base=max(dot(diffuseColor.rgb,vec3(0.2126,0.7152,0.0722)),0.02);
          float lit=lum/base;
          float band=smoothstep(0.55,0.62,lit);
          vec3 shade=diffuseColor.rgb*mix(vec3(0.62,0.50,0.44)*0.78,vec3(1.08),band);
          // keep coloured light (the fire's orange, the moon's blue) but flatten its gradient
          vec3 tint=outgoingLight/max(lum,0.0001);
          outgoingLight=mix(shade,shade*clamp(tint,0.0,2.0)*clamp(lum/base,0.6,1.6),0.55)+totalEmissiveRadiance;
          float g=zxGrain(gl_FragCoord.xy/zxGrainPx)*0.6+zxGrain(gl_FragCoord.xy/(zxGrainPx*4.0))*0.4;
          outgoingLight*=1.0-0.07*g;
        }
        #include <opaque_fragment>`);
    };
    const toonKey=()=> 'zx-toon';
    function toonize(m){m.onBeforeCompile=toonPatch;m.customProgramCacheKey=toonKey;return m;}
    // Outline: the same geometry pushed out along its normals by a screen-height fraction, back faces only.
    const lineFraction={value:low?0.0034:0.003};  // of the viewport height (card_ink_hull line_fraction 0.0042 at card scale)
    const viewportH={value:1000};
    function hullMaterial({skinned=false,width=1}={}){
      const m=new T.MeshBasicMaterial({color:INK,side:T.BackSide,fog:true});
      m.onBeforeCompile=sh=>{
        sh.uniforms.zxLine=lineFraction;sh.uniforms.zxViewH=viewportH;sh.uniforms.zxWidth={value:width};
        sh.vertexShader=sh.vertexShader.replace('#include <common>','#include <common>\nuniform float zxLine;uniform float zxViewH;uniform float zxWidth;')
          .replace('#include <begin_vertex>',`#include <begin_vertex>
            #ifndef USE_SKINNING
              vec3 objectNormal=normal;
            #endif`)
          .replace('#include <project_vertex>',`
            #ifdef USE_SKINNING
              // skinned normal (skinnormal_vertex is not in the basic shader without an envmap)
              mat4 zxSkin=mat4(0.0);
              zxSkin+=skinWeight.x*boneMatX;zxSkin+=skinWeight.y*boneMatY;zxSkin+=skinWeight.z*boneMatZ;zxSkin+=skinWeight.w*boneMatW;
              zxSkin=bindMatrixInverse*zxSkin*bindMatrix;
              vec3 zxN=(zxSkin*vec4(objectNormal,0.0)).xyz;
            #else
              vec3 zxN=objectNormal;
            #endif
            #include <project_vertex>
            {
              // push in view space by a fraction of the screen height (perspective: grows with depth)
              mat3 nm=mat3(modelViewMatrix);
              #ifdef USE_INSTANCING
                nm=nm*mat3(instanceMatrix);
              #endif
              vec3 vn=normalize(nm*zxN);
              float depth=max(-mvPosition.z,0.001);
              float units=2.0*zxLine*zxWidth/projectionMatrix[1][1]*depth;
              float px=2.0/(projectionMatrix[1][1]*zxViewH)*depth*1.3; // never thinner than ~1.3 px
              vec3 q=position*9.0;
              float brush=1.0+0.2*sin(q.x*1.7+q.y*2.3)*sin(q.y*1.3-q.z*2.9+1.1);
              mvPosition.xyz+=vn*max(units*brush,px);
              gl_Position=projectionMatrix*mvPosition;
            }`);
      };
      m.customProgramCacheKey=()=>'zx-hull';
      return m;
    }
    const hullStatic=hullMaterial(),hullThin=hullMaterial({width:.7}),hullSkinned=hullMaterial({skinned:true,width:.75});
    // Fills for station props: one toon material, colours in vertex colours (a whole station bakes to one mesh).
    const vcMat=toonize(new T.MeshLambertMaterial({vertexColors:true,flatShading:true}));
    const glowVc=new T.MeshBasicMaterial({vertexColors:true,fog:false,toneMapped:false});
    const mat=(color,extra={})=>toonize(new T.MeshLambertMaterial({color,flatShading:true,...extra}));
    const basic=(color,extra={})=>new T.MeshBasicMaterial({color,...extra});
    const C={stone:0x7d7868,stoneLite:0x9a937f,stoneDark:0x56534a,wood:0x7a5432,woodDark:0x46301f,cloth:0xcbb894,
      gold:0xd2a85c,goldLite:0xecce8c,iron:0x9aa0a6,ironDark:0x5e6268,leaf:0x4a6340,goblin:0x7a9650,goblinDark:0x55703a,ink:0x2a1c12};
    const RACE={H:0xffc23a,V:0xe0302a,E:0x4fe07a,R:0x3fe6ff}; // data/races/*.json "color"
    const CLASS={ss:0x3f7fa6,gs:0xa8473f,lb:0x5e8f57,mg:0x7b65b0}; // client/card_tokens.gd class colours
    scene.add(new T.HemisphereLight(0xa6b2c8,0x40362a,1.7));
    const moonLight=new T.DirectionalLight(0xd8e0f2,1.6);moonLight.position.set(-30,45,-60);scene.add(moonLight);
    const fireLight=new T.PointLight(0xff9a45,70,34,1.7);fireLight.position.set(-10,2.4,10);scene.add(fireLight);
    // One warm light follows the station in view.
    const focusLight=new T.PointLight(0xffd08a,0,22,1.6);scene.add(focusLight);

    const G={box:new T.BoxGeometry(1,1,1),ico:new T.IcosahedronGeometry(1,0),cone3:new T.ConeGeometry(1,1,3),cone4:new T.ConeGeometry(1,1,4),
      cone5:new T.ConeGeometry(1,1,5),cone6:new T.ConeGeometry(1,1,6),cyl6:new T.CylinderGeometry(1,1,1,6),cyl8:new T.CylinderGeometry(1,1,1,8),
      cyl12:new T.CylinderGeometry(1,1,1,12),sph:new T.SphereGeometry(1,8,6),oct:new T.OctahedronGeometry(1,0),tor:new T.TorusGeometry(1,.12,5,20)};
    // ---- Baker: collects parts into one vertex-coloured, flat-shaded geometry per station ------------------------
    // part(parent, geometry, colour, [x,y,z], [sx,sy,sz], [rx,ry,rz]); `parent` is a Bake or an Object3D.
    class Bake{
      constructor(){this.items=[];this.glows=[];this.root=new T.Object3D();}
      add(g,color,pos,s,r,glowing){const o=new T.Object3D();o.position.set(...pos);o.scale.set(...s);o.rotation.set(...r);this.items.push({g,color,o,glowing});return o;}
      build(){
        const lists=[[],[]];
        for(const it of this.items){
          it.o.updateMatrix();const g=it.g.index?it.g.toNonIndexed():it.g.clone();g.applyMatrix4(it.o.matrix);
          for(const k of Object.keys(g.attributes))if(k!=='position')g.deleteAttribute(k);
          g.computeVertexNormals();
          const col=new T.Color(it.color),n=g.attributes.position.count,arr=new Float32Array(n*3);
          for(let i=0;i<n;i++){arr[i*3]=col.r;arr[i*3+1]=col.g;arr[i*3+2]=col.b;}
          g.setAttribute('color',new T.BufferAttribute(arr,3));lists[it.glowing?1:0].push(g);
        }
        const merge=list=>{if(!list.length)return null;let count=0;for(const g of list)count+=g.attributes.position.count;
          const out=new T.BufferGeometry();for(const name of ['position','normal','color']){const a=new Float32Array(count*3);let o=0;for(const g of list){a.set(g.attributes[name].array,o);o+=g.attributes[name].array.length;}out.setAttribute(name,new T.BufferAttribute(a,3));}
          out.computeBoundingSphere();return out;};
        return {solid:merge(lists[0]),glow:merge(lists[1])};
      }
    }
    const part=(p,g,color,pos=[0,0,0],s=[1,1,1],r=[0,0,0],glowing=false)=>{
      if(p instanceof Bake)return p.add(g,color,pos,s,r,glowing);
      const a=new T.Mesh(g,typeof color==='number'?mat(color):color);a.position.set(...pos);a.scale.set(...s);a.rotation.set(...r);p.add(a);return a;};
    const rod=(p,a,b,r,color)=>{const A=new T.Vector3(...a),B=new T.Vector3(...b),d=B.clone().sub(A);const q=new T.Quaternion().setFromUnitVectors(new T.Vector3(0,1,0),d.clone().normalize());const e=new T.Euler().setFromQuaternion(q);return part(p,G.cyl6,color,A.clone().add(B).multiplyScalar(.5).toArray(),[r,d.length(),r],[e.x,e.y,e.z]);};
    // A baked group: fill (toon) + outline (one draw each), glowing parts (unlit) in a third mesh.
    const outlined=[];
    function addBaked(b,parent,{hull=hullStatic}={}){
      const {solid,glow}=b.build();const out={};
      if(solid){out.mesh=new T.Mesh(solid,vcMat);parent.add(out.mesh);if(hull){out.hull=new T.Mesh(solid,hull);parent.add(out.hull);outlined.push(out.hull);}}
      if(glow){out.glow=new T.Mesh(glow,glowVc);parent.add(out.glow);}
      return out;
    }
    // Instanced scenery: one draw call per list (+ one for its outline unless `noHull`).
    const dummy=new T.Object3D(),tint=new T.Color();
    function inst(g,list,{hull=hullStatic,flat=true}={}){
      const fill=toonize(new T.MeshLambertMaterial({color:0xffffff,flatShading:flat}));
      const im=new T.InstancedMesh(g,fill,list.length);
      list.forEach((it,i)=>{dummy.position.set(...it.p);dummy.scale.set(...(it.s||[1,1,1]));dummy.rotation.set(...(it.r||[0,0,0]));dummy.updateMatrix();im.setMatrixAt(i,dummy.matrix);im.setColorAt(i,tint.set(it.c??0xffffff));});
      im.instanceMatrix.needsUpdate=true;if(im.instanceColor)im.instanceColor.needsUpdate=true;scene.add(im);
      if(hull){const h=new T.InstancedMesh(g,hull,list.length);h.instanceMatrix=im.instanceMatrix;scene.add(h);outlined.push(h);}
      return im;
    }
    const canvasTex=(w,h,draw)=>{const c=document.createElement('canvas');c.width=w;c.height=h;const ctx=c.getContext('2d');draw(ctx,w,h);const t=new T.CanvasTexture(c);t.colorSpace=T.SRGBColorSpace;t.userData.redraw=()=>{ctx.clearRect(0,0,w,h);draw(ctx,w,h);t.needsUpdate=true;};return t;};
    const fontTextures=[];
    const glowTex=(color)=>canvasTex(64,64,(ctx)=>{const g=ctx.createRadialGradient(32,32,0,32,32,32);g.addColorStop(0,color);g.addColorStop(.3,color);g.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=g;ctx.fillRect(0,0,64,64);});
    const fireTex=glowTex('rgba(255,150,70,.6)'),goldTex=glowTex('rgba(255,210,120,.55)');
    function glow(x,y,z,size,texture,opacity=1,parent=scene){const m=new T.SpriteMaterial({map:texture,transparent:true,opacity,depthWrite:false,blending:T.AdditiveBlending,fog:false});const s=new T.Sprite(m);s.position.set(x,y,z);s.scale.set(size,size,1);parent.add(s);return s;}

    // ---- Ground, trees, rocks, grass ------------------------------------------------------------------------
    // The ground follows the camera along the trail and fades out far ahead, so the painted horizon shows above it.
    const groundAlpha=canvasTex(8,256,(ctx,w,h)=>{const g=ctx.createLinearGradient(0,0,0,h);g.addColorStop(0,'#000');g.addColorStop(.18,'#fff');g.addColorStop(1,'#fff');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);});
    groundAlpha.colorSpace=T.NoColorSpace;
    const ground=new T.Mesh(new T.PlaneGeometry(260,190),mat(0x4f4a39,{transparent:true,alphaMap:groundAlpha,depthWrite:true}));ground.position.set(0,-.7,0);ground.rotation.x=-Math.PI/2;scene.add(ground);
    const treeCols=[0x3a4c33,0x34452f,0x41513a,0x2f4033];
    const trunks=[],cones=[];
    const treeN=low?140:210;
    for(let i=0;i<treeN;i++){
      const z=24-(i*13.73)%170,side=i%2?-1:1,x=side*(11+(i*15.71)%37),s=.62+((i*19)%10)*.14,ry=i*.29;
      trunks.push({p:[x,1.0*s-.5,z],s:[.2*s,2.6*s,.2*s],c:C.woodDark});
      for(let k=0;k<3;k++)cones.push({p:[x,(2.6+k*1.13)*s,z],s:[(1.66-.29*k)*s,3.55*s,(1.66-.29*k)*s],r:[0,ry+k*.29,0],c:treeCols[(i+k)%4]});
    }
    // Far scenery: outlined on desktop, plain toon on phones (an outline per tree doubles a 600-instance draw).
    inst(G.cyl6,trunks,{hull:low?null:hullThin});inst(G.cone5,cones,{hull:low?null:hullThin});
    const rocks=[];
    for(let i=0;i<150;i++){const z=22-(i*3.73)%164,x=Math.sin(i*23.67)*29;if(Math.abs(x)<5)continue;rocks.push({p:[x,-.51,z],s:[.45+(i%5)*.22,.17+(i%4)*.11,.4+(i%4)*.19],r:[0,i*.42,0],c:i%3===0?C.stoneLite:C.stoneDark});}
    for(let i=0;i<165;i++){const z=18-i*.84,x=2.7+Math.sin(i*.23)*4.0;rocks.push({p:[x,-.52,z],s:[.2+(i%4)*.23,.11,.3+(i%3)*.2],r:[0,i*.7,0],c:i%2?C.stoneLite:C.stone});}
    inst(G.ico,rocks,{hull:low?null:hullThin});
    const grassCols=[0x5d6e45,0x51623f,0x6b784e];
    const grass=[];for(let i=0;i<(low?150:240);i++){const z=21-(i*5.33)%160,x=Math.sin(i*18.91)*30;grass.push({p:[x,-.31,z],s:[.09+(i%4)*.02,.34+(i%5)*.14,.12],r:[0,i*.7,Math.sin(i*3.1)*.3],c:grassCols[i%3]});}
    inst(G.cone3,grass,{hull:null});

    // ---- Stop 01: the squad campfire --------------------------------------------------------------------------
    const FX=-10,FZ=10;
    const campBake=new Bake();
    // Stone rings (inner hearth, outer seats)
    for(let j=0;j<12;j++){const a=j*Math.PI/6;part(campBake,G.ico,j%3?C.stone:C.stoneLite,[FX+Math.cos(a)*1.45*1.6,-.6,FZ+Math.sin(a)*1.23*1.6],[.8,.42,.6],[0,a,0]);}
    for(let j=0;j<8;j++){const a=j*Math.PI/4;part(campBake,G.ico,j%2?C.stone:C.stoneLite,[FX+Math.cos(a)*2.5*1.6+ (j%2?0:0),-.6,FZ+Math.sin(a)*2.45*1.6],[.8,.5,.83],[0,a,0]);}
    // Logs
    for(let j=0;j<5;j++){const a=j*Math.PI*2/5;part(campBake,G.cyl6,C.wood,[FX+Math.cos(a)*.32,-.24,FZ+Math.sin(a)*.4],[.43,4.3,.43],[0,a,Math.PI/2.9]);}
    // Tent, supplies and a trail sign.
    part(campBake,G.cone4,0x8a775c,[-17,2.1,10],[3,5.8,3],[0,Math.PI/4,0]);part(campBake,G.box,C.woodDark,[-17,.8,12.18],[1.7,2,.15]);
    part(campBake,G.box,C.wood,[-16.2,.1,6.4],[1.8,.8,.95],[0,.5,0]);part(campBake,G.box,C.cloth,[-16.2,.56,6.4],[1.9,.13,1.0],[0,.5,0]);
    part(campBake,G.box,C.wood,[-14.6,1.4,5.6],[.24,3.2,.25]);part(campBake,G.box,C.wood,[-14.6,2.6,5.6],[2.5,.52,.25]);
    addBaked(campBake,scene);
    // Flames: unlit, no outline, flicker per frame.
    const fire=new T.Group();fire.position.set(FX,0,FZ);fire.scale.setScalar(1.6);scene.add(fire);
    const flames=[];
    for(let j=0;j<9;j++){const a=j*2.399,h=1.1+(j%5)*.34;const fl=new T.Mesh(G.cone4,basic([0xff6e2a,0xffc15c,0xffe7a4][j%3],{transparent:true,opacity:.94,depthWrite:false,fog:false}));fl.position.set(Math.cos(a)*.3,h*.42,Math.sin(a)*.3);fl.scale.set(.21+(j%3)*.09,h,.21+(j%3)*.09);fire.add(fl);flames.push({fl,a,j});}
    const flameGlow=glow(FX,1.9,FZ,17,fireTex,.6);
    // Embers: one Points object, positions animated on the CPU.
    const EMB=low?28:44,embPos=new Float32Array(EMB*3),embGeo=new T.BufferGeometry();embGeo.setAttribute('position',new T.BufferAttribute(embPos,3));
    const embers=new T.Points(embGeo,new T.PointsMaterial({color:0xffb36a,size:.13,transparent:true,opacity:.85,depthWrite:false,fog:false}));embers.frustumCulled=false;scene.add(embers);
    // The four race characters stand around the fire (loaded after the first paint, see loadSquad()).
    // Until they arrive, four soft ground shadows mark their places.
    // Places: a shallow arc to the screen-left of the fire, every face toward the trail camera.
    // CAM_DIR = the campfire view's direction on the ground (from the fire toward the camera).
    const CAM_DIR=new T.Vector2(.668,.744),LEFT=new T.Vector2(-.744,.668);
    const SQUAD=[
      {race:'runeborn',side:2.5,front:.45},  // Magic
      {race:'elf',     side:3.85,front:.95}, // Longbow
      {race:'viking',  side:5.2,front:.95},  // Great Sword
      {race:'human',   side:6.55,front:.4},  // Sword & Shield
    ];
    const SQUAD_H=2.15; // metres in the trail (the fire ring is the game's campfire at x1.6)
    const shadowTex=canvasTex(64,64,(ctx)=>{const g=ctx.createRadialGradient(32,32,2,32,32,32);g.addColorStop(0,'rgba(20,12,6,.55)');g.addColorStop(1,'rgba(20,12,6,0)');ctx.fillStyle=g;ctx.fillRect(0,0,64,64);});
    const spots=SQUAD.map(s=>{const x=FX+LEFT.x*s.side+CAM_DIR.x*s.front,z=FZ+LEFT.y*s.side+CAM_DIR.y*s.front;const m=new T.Mesh(new T.PlaneGeometry(1.5,1.5),new T.MeshBasicMaterial({map:shadowTex,transparent:true,depthWrite:false}));m.rotation.x=-Math.PI/2;m.position.set(x,-.68,z);scene.add(m);return {x,z};});

    // ---- Stops 02-06: a slowly turning diorama on a floating rock; 07: the FIGHT gate on the ground ---------
    const models=[];const hits=[];
    const columns=[];
    function floatingIsland(p){
      part(p,G.ico,C.stone,[0,-.92,0],[1.18,.32,1.1]);
      part(p,G.cyl12,0x657347,[0,-.66,0],[1.05,.06,1.0]);
      part(p,G.cone5,C.stoneDark,[0,-1.55,0],[.95,1.2,.9],[Math.PI,0,0]);
    }
    const letterTex=(ch,bg)=>{const t=canvasTex(128,160,(ctx,w,h)=>{ctx.fillStyle=bg;ctx.fillRect(0,0,w,h);ctx.fillStyle='rgba(0,0,0,.18)';ctx.fillRect(0,h-26,w,26);
      ctx.strokeStyle='#3a2414';ctx.lineWidth=8;ctx.strokeRect(4,4,w-8,h-8);ctx.font="800 92px Taviraj, Georgia, serif";ctx.textAlign='center';ctx.textBaseline='middle';
      ctx.lineWidth=10;ctx.strokeStyle='#3a2414';ctx.strokeText(ch,w/2,h/2-6);ctx.fillStyle='#fff6e0';ctx.fillText(ch,w/2,h/2-6);});fontTextures.push(t);return t;};
    // Each builder bakes its static parts into `b` and returns the moving / textured parts it added to `g`.
    const builders=[
      null,
      // 02 Four race banners (H gold, V red, E green, R blue) with a letter each, so colour is never the only cue.
      (b,g)=>{floatingIsland(b);
        const banners=[];
        [['H',RACE.H,'#d9a12c'],['V',RACE.V,'#b8302a'],['E',RACE.E,'#3fa95e'],['R',RACE.R,'#2fa9c4']].forEach(([L,c,bg],k)=>{
          const a=k*Math.PI/2+Math.PI/4,x=Math.cos(a)*.58,z=Math.sin(a)*.58;
          rod(b,[x,-.66,z],[x,.95,z],.035,C.wood);
          const flag=new T.Group();flag.position.set(x,.62,z);flag.rotation.y=-a+Math.PI/2;g.add(flag);
          const cloth=new T.Mesh(new T.PlaneGeometry(.42,.56),mat(0xffffff,{map:letterTex(L,bg),side:T.DoubleSide,flatShading:false}));cloth.position.set(.22,0,0);flag.add(cloth);
          const bar=new T.Mesh(G.cyl6,mat(C.wood));bar.position.set(.22,.3,0);bar.scale.set(.012,.48,.012);bar.rotation.z=Math.PI/2;flag.add(bar);
          if(L==='H')part(b,G.oct,c,[x,1.04,z],[.07,.11,.07],[0,0,0],true);
          if(L==='V'){part(b,G.cone4,C.cloth,[x-.06,1.02,z],[.035,.16,.035],[0,0,.5]);part(b,G.cone4,C.cloth,[x+.06,1.02,z],[.035,.16,.035],[0,0,-.5]);}
          if(L==='E')part(b,G.sph,c,[x,1.03,z],[.05,.1,.03],[0,0,0],true);
          if(L==='R')part(b,G.tor,c,[x,1.03,z],[.07,.07,.07],[0,0,0],true);
          banners.push(flag);
        });
        part(b,G.ico,C.stoneLite,[0,-.5,0],[.22,.16,.22]);
        return {banners};},
      // 03 The four class weapons stuck in the rock: sword + shield, great sword, longbow, staff.
      (b,g)=>{floatingIsland(b);
        const tilt=(o,pos,rz)=>{const q=new T.Object3D();q.position.set(...pos);q.rotation.z=rz;q.updateMatrixWorld();return (gg,c,p,s,r=[0,0,0],gl)=>{const loc=new T.Object3D();loc.position.set(...p);loc.scale.set(...s);loc.rotation.set(...r);q.add(loc);q.updateMatrixWorld(true);const m=loc.matrixWorld;const P=new T.Vector3(),Q=new T.Quaternion(),S=new T.Vector3();m.decompose(P,Q,S);const E=new T.Euler().setFromQuaternion(Q);return part(b,gg,c,P.toArray(),S.toArray(),[E.x,E.y,E.z],gl);};};
        const sw=tilt(b,[-.5,-.66,.15],.12);
        sw(G.box,C.iron,[0,.55,0],[.07,.9,.02]);sw(G.box,C.gold,[0,1.02,0],[.3,.05,.06]);sw(G.cyl6,C.woodDark,[0,1.17,0],[.03,.24,.03]);sw(G.sph,C.gold,[0,1.31,0],[.05,.05,.05]);
        part(b,G.cyl12,CLASS.ss,[-.72,-.22,.36],[.3,.05,.3],[Math.PI/2,0,.25]);part(b,G.cyl12,C.gold,[-.71,-.22,.39],[.1,.03,.1],[Math.PI/2,0,.25]);
        const gs=tilt(b,[-.08,-.66,-.25],-.08);
        gs(G.box,C.iron,[0,.75,0],[.15,1.4,.035]);gs(G.box,CLASS.gs,[0,1.47,0],[.48,.08,.09]);gs(G.cyl6,C.woodDark,[0,1.7,0],[.035,.38,.035]);gs(G.oct,C.gold,[0,1.92,0],[.06,.07,.06]);
        const bow=new T.Group();bow.position.set(.42,.15,.2);bow.rotation.set(0,-.4,.1);g.add(bow);
        const arc=new T.Mesh(new T.TorusGeometry(.62,.03,4,14,Math.PI*.9),mat(CLASS.lb));arc.rotation.z=Math.PI/2+Math.PI*.05;bow.add(arc);
        const string=new T.Mesh(G.cyl6,mat(0xf3e6c8));string.scale.set(.006,1.22,.006);bow.add(string);
        const grip=new T.Mesh(G.box,mat(C.woodDark));grip.position.set(-.62,0,0);grip.scale.set(.06,.16,.06);bow.add(grip);
        const st=tilt(b,[.72,-.66,-.3],-.1);
        st(G.cyl6,C.wood,[0,.75,0],[.035,1.5,.035]);st(G.tor,C.gold,[0,1.55,0],[.11,.11,.11]);
        const orb=new T.Mesh(G.ico,new T.MeshBasicMaterial({color:CLASS.mg,fog:false}));orb.position.set(.72+Math.sin(.1)*1.58,-.66+Math.cos(.1)*1.58,-.3);orb.scale.setScalar(.11);g.add(orb);
        return {orb,outline:[arc,string,grip]};},
      // 04 Squad synergy: three card-stones (one race each = Alliance) bound by a glowing ring around a centre flame.
      (b,g)=>{floatingIsland(b);
        [[RACE.H,'H','#d9a12c'],[RACE.V,'V','#b8302a'],[RACE.E,'E','#3fa95e']].forEach(([c,L,bg],k)=>{
          const a=k*Math.PI*2/3,x=Math.cos(a)*.62,z=Math.sin(a)*.62,ry=-a+Math.PI/2;
          part(b,G.box,C.stoneLite,[x,-.05,z],[.5,.78,.08],[0,ry,0]);
          const card=new T.Group();card.position.set(x,-.05,z);card.rotation.y=ry;g.add(card);
          const f1=new T.Mesh(new T.PlaneGeometry(.38,.5),mat(0xffffff,{map:letterTex(L,bg),flatShading:false}));f1.position.set(0,.04,.045);card.add(f1);
          const f2=f1.clone();f2.position.z=-.045;f2.rotation.y=Math.PI;card.add(f2);
          part(b,G.oct,c,[x,.5,z],[.07,.1,.07],[0,0,0],true);
        });
        const bond=new T.Mesh(new T.TorusGeometry(.72,.025,4,40),new T.MeshBasicMaterial({color:0xffd27a,fog:false}));bond.position.y=.5;bond.rotation.x=Math.PI/2;g.add(bond);
        const core=new T.Mesh(G.oct,new T.MeshBasicMaterial({color:0xffe0a0,fog:false}));core.position.y=.2;core.scale.set(.16,.28,.16);g.add(core);
        return {bond,core};},
      // 05 Auto-battle waves: three squad heroes hold the line while goblin waves hop in.
      (b,g)=>{floatingIsland(b);
        [[CLASS.ss,-.15,.45],[CLASS.gs,.2,.55],[CLASS.mg,.0,.85]].forEach(([c,x,z])=>{
          part(b,G.cyl8,c,[x,-.42,z],[.11,.36,.1]);part(b,G.sph,0xf0d2b0,[x,-.12,z],[.1,.1,.1]);});
        // Goblins hop: one baked goblin geometry, instanced (fill + outline = 2 draws for all seven).
        const gb=new Bake();
        part(gb,G.cone5,C.goblinDark,[0,.13,0],[.1,.26,.1]);part(gb,G.ico,C.goblin,[0,.31,0],[.09,.08,.08]);
        part(gb,G.cone3,C.goblin,[-.09,.33,0],[.025,.1,.02],[0,0,1.3]);part(gb,G.cone3,C.goblin,[.09,.33,0],[.025,.1,.02],[0,0,-1.3]);
        const geo=gb.build().solid;
        const gobFill=new T.InstancedMesh(geo,vcMat,7),gobHull=new T.InstancedMesh(geo,hullStatic,7);gobHull.instanceMatrix=gobFill.instanceMatrix;g.add(gobFill);g.add(gobHull);outlined.push(gobHull);
        const gob=[];for(let k=0;k<7;k++){const row=k<4?0:1,col=row?k-4:k;gob.push({x:(col-(row?1:1.5))*.32,z:-.15-row*.42,k});}
        rod(b,[.85,-.66,-.6],[.85,.44,-.6],.02,C.wood);
        const flag=new T.Mesh(new T.PlaneGeometry(.36,.26),mat(0xffffff,{side:T.DoubleSide,flatShading:false,map:(()=>{const t=canvasTex(128,96,(ctx,w,h)=>{ctx.fillStyle='#e8d4a6';ctx.fillRect(0,0,w,h);ctx.strokeStyle='#3a2414';ctx.lineWidth=6;ctx.strokeRect(3,3,w-6,h-6);ctx.fillStyle='#3a2414';ctx.font="800 60px Taviraj, Georgia, serif";ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText('12',w/2,h/2+2);});fontTextures.push(t);return t;})()}));
        flag.position.set(1.04,.29,-.6);g.add(flag);
        return {gob,gobFill};},
      // 06 The goblin chief's totem: stacked carved blocks, a tusked goblin face, a horn crown and two torches.
      (b,g)=>{floatingIsland(b);
        part(b,G.cyl8,C.woodDark,[0,-.45,0],[.34,.42,.34]);
        part(b,G.cyl8,C.wood,[0,-.02,0],[.3,.44,.3]);part(b,G.tor,C.gold,[0,.2,0],[.31,.31,.4],[Math.PI/2,0,0]);
        part(b,G.ico,C.goblin,[0,.5,0],[.36,.32,.32]);
        part(b,G.cone3,C.goblin,[-.42,.55,0],[.08,.34,.06],[0,0,1.25]);part(b,G.cone3,C.goblin,[.42,.55,0],[.08,.34,.06],[0,0,-1.25]);
        part(b,G.cone4,C.cloth,[-.1,.34,.27],[.03,.12,.03],[Math.PI,0,0]);part(b,G.cone4,C.cloth,[.1,.34,.27],[.03,.12,.03],[Math.PI,0,0]);
        for(let k=0;k<5;k++){const a=(k-2)*.38;part(b,G.cone4,k%2?C.goldLite:C.cloth,[Math.sin(a)*.26,.88+(k%2?.02:0),Math.cos(a)*.05],[.05,.28+(k%2)*.1,.05],[0,0,-a*.6]);}
        const eyeMat=new T.MeshBasicMaterial({color:0xffa23a,fog:false});
        const eyes=[[-.12,.56,.28],[.12,.56,.28]].map(p=>{const e=new T.Mesh(G.sph,eyeMat);e.position.set(...p);e.scale.set(.06,.04,.03);g.add(e);return e;});
        const torches=[];
        for(const s of [-1,1]){rod(b,[s*.75,-.66,.2],[s*.78,.35,.2],.025,C.woodDark);const f=new T.Mesh(G.cone4,basic(0xffa040,{transparent:true,opacity:.95,fog:false}));f.position.set(s*.78,.47,.2);f.scale.set(.06,.2,.06);g.add(f);torches.push(f);}
        return {eyeMat,torches};},
      // 07 The FIGHT gate (built on the ground, see below)
      null
    ];
    stations.forEach((s,i)=>{
      if(i===0)return;
      const group=new T.Group();group.position.set(s.x,0,s.z);scene.add(group);
      // Stone columns stand behind and beside each station, never between it and the camera (instanced below).
      if(i<total-1)for(let j=0;j<5;j++){const a=Math.PI*(1.05+j*.235),rad=6+(j%2)*1.3;columns.push({p:[s.x+Math.cos(a)*rad,1.05,s.z+Math.sin(a)*rad],s:[.8,2.9,.85],r:[0,j*.65,0],c:j%2?C.stoneLite:C.stone,cap:false});columns.push({p:[s.x+Math.cos(a)*rad,2.75,s.z+Math.sin(a)*rad],s:[.8,.32,.9],c:C.stoneDark,cap:true});}
      if(i===total-1){models.push({group,gate:true});return;}
      const float=new T.Group();float.position.y=4.5;group.add(float);
      const bob=new T.Group();float.add(bob);
      const turner=new T.Group();bob.add(turner);
      const art=new T.Group();art.scale.setScalar(2.75);turner.add(art);
      const bake=new Bake();
      const extra=builders[i](bake,art)||{};
      addBaked(bake,art);
      // Separate textured / moving parts also get an outline (same hull material, one extra draw each).
      for(const m of [...(extra.outline||[]),...(extra.banners||[]).map(f=>f.children[1])]){const h=new T.Mesh(m.geometry,hullThin);m.add(h);outlined.push(h);}
      const hit=new T.Mesh(new T.SphereGeometry(2.7,10,8),basic(0,{visible:false}));bob.add(hit);hit.userData.station=i;hits.push(hit);
      const halo=glow(0,0,0,9,goldTex,.35,float);
      models.push({group,bob,turner,halo,extra,dragAngle:0});
    });
    inst(G.box,columns.filter(c=>!c.cap));inst(G.ico,columns.filter(c=>c.cap));
    // ---- Stop 07: the FIGHT gate: a carved timber arch with a parchment plaque, torches and a warm portal. ------
    const gs=stations[total-1];
    const gate=new T.Group();gate.position.set(gs.x,0,gs.z-2);scene.add(gate);
    const gb=new Bake();
    part(gb,G.box,C.stoneLite,[-3.3,.0,0],[2.1,1.4,2.0]);part(gb,G.box,C.stoneLite,[3.3,.0,0],[2.1,1.4,2.0]);
    part(gb,G.box,C.wood,[-3.2,4.1,0],[1.3,7.4,1.2]);part(gb,G.box,C.wood,[3.2,4.1,0],[1.3,7.4,1.2]);
    part(gb,G.box,C.woodDark,[0,7.8,0],[8.6,1.0,1.5]);part(gb,G.box,C.wood,[0,8.5,0],[9.6,.5,1.8]);
    for(const s of [-1,1])part(gb,G.cone4,C.woodDark,[s*4.6,9.0,0],[.5,1.2,.5],[0,0,-s*.5]);
    part(gb,G.box,C.woodDark,[0,6.6,.7],[4.9,1.7,.12]);
    for(const s of [-1,1])rod(gb,[s*4.3,-.6,1.3],[s*4.3,3.2,1.3],.12,C.woodDark);
    // Beyond the gate: the sign-in clearing (stop 08) with a stone dais and two lanterns the camera flies to.
    part(gb,G.cyl12,C.stoneLite,[0,-.55,-9],[3.2,.3,3.2]);part(gb,G.cyl12,C.stone,[0,-.3,-9],[2.4,.25,2.4]);
    for(const s of [-1,1]){part(gb,G.box,C.woodDark,[s*3.2,1.2,-8],[.22,3.6,.22]);part(gb,G.box,C.wood,[s*3.2,3.05,-8],[.6,.1,.6]);}
    addBaked(gb,gate);
    const plaqueTex=canvasTex(512,160,(ctx,w,h)=>{ctx.fillStyle='#e9d6a8';ctx.fillRect(0,0,w,h);const g=ctx.createLinearGradient(0,0,0,h);g.addColorStop(0,'rgba(255,255,255,.25)');g.addColorStop(1,'rgba(90,52,32,.25)');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);
      ctx.strokeStyle='#3a2414';ctx.lineWidth=14;ctx.strokeRect(7,7,w-14,h-14);ctx.strokeStyle='#c9a05a';ctx.lineWidth=5;ctx.strokeRect(22,22,w-44,h-44);
      ctx.fillStyle='#3a2414';ctx.font="800 104px Taviraj, Georgia, serif";ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText('FIGHT!',w/2,h/2+6);});fontTextures.push(plaqueTex);
    const plaque=new T.Mesh(new T.PlaneGeometry(4.6,1.44),mat(0xffffff,{map:plaqueTex,flatShading:false}));plaque.position.set(0,6.6,.78);gate.add(plaque);
    const portalTex=canvasTex(64,128,(ctx,w,h)=>{const g=ctx.createRadialGradient(32,80,4,32,70,70);g.addColorStop(0,'rgba(255,240,200,1)');g.addColorStop(.45,'rgba(255,190,90,.75)');g.addColorStop(1,'rgba(255,140,60,.08)');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);});
    const portal=new T.Mesh(new T.PlaneGeometry(5.1,6.0),basic(0xffffff,{map:portalTex,transparent:true,opacity:.5,depthWrite:false,side:T.DoubleSide,blending:T.AdditiveBlending,fog:false}));portal.position.set(0,3.75,0);gate.add(portal);
    const gateFlames=[];
    for(const s of [-1,1]){const f=new T.Mesh(G.cone4,basic(0xffa040,{transparent:true,opacity:.95,fog:false}));f.position.set(s*4.3,3.65,1.3);f.scale.set(.3,.95,.3);gate.add(f);gateFlames.push(f);glow(gs.x+s*4.3,3.7,gs.z-2+1.3,4.5,fireTex,.6);}
    for(const s of [-1,1]){const l=new T.Mesh(G.oct,new T.MeshBasicMaterial({color:0xffc56a,fog:false}));l.position.set(s*3.2,3.35,-8);l.scale.set(.25,.35,.25);gate.add(l);glow(gs.x+s*3.2,3.4,gs.z-10,3.6,fireTex,.55);}
    const gateGlow=glow(gs.x,4,gs.z-2.3,13,goldTex,.4);
    if(document.fonts&&document.fonts.ready)document.fonts.ready.then(()=>fontTextures.forEach(t=>t.userData.redraw()));

    // ---- Camera poses -----------------------------------------------------------------------------------------
    // The campfire view: the fire on the right of the free area, the squad to its left (desktop: the info panel
    // covers the right third; phone portrait: the panel is at the bottom, so the view centres on the group).
    const campAt=(side,dist,y,lookY,fov)=>{const lx=FX+LEFT.x*side,lz=FZ+LEFT.y*side;return {pos:[lx+CAM_DIR.x*dist,y,lz+CAM_DIR.y*dist],look:[lx,lookY,lz],fov};};
    const campPose=small?campAt(3.6,15.5,4.6,1.2,60):campAt(1.4,13,3.3,1.5,44);
    const stationPose=s=>small
      ? {pos:[s.x+1.4,6.4,s.z+18],look:[s.x,1.3,s.z-1],fov:62}
      : {pos:[s.x+2,6.3,s.z+19],look:[s.x+5.6,4.3,s.z-1.2],fov:56};
    const gatePose=s=>small
      ? {pos:[s.x+1.2,4.6,s.z+19],look:[s.x,3.6,s.z-2],fov:62}
      : {pos:[s.x+2.5,4.8,s.z+19],look:[s.x+6.2,4.6,s.z-2],fov:56};
    const poses=stations.map((s,i)=>i===0?campPose:i===total-1?gatePose(s):stationPose(s));
    const inspectPose=s=>({pos:[s.x+3.8,6,s.z+10],look:[s.x,4.5,s.z],fov:small?47:43});
    // Stop 08: through the gate, looking at the sign-in clearing.
    const loginPose={pos:[gs.x,3.9,gs.z+1.5],look:[gs.x,2.6,gs.z-14],fov:46};
    const cameraLook=new T.Vector3(...poses[current].look),wantedPos=new T.Vector3(...poses[current].pos),wantedLook=new T.Vector3(...poses[current].look);
    camera.position.copy(wantedPos);camera.lookAt(cameraLook);
    let fovTarget=poses[current].fov;
    const setPose=pose=>{wantedPos.set(...pose.pos);wantedLook.set(...pose.look);fovTarget=pose.fov;};
    let loginArrivalPending=false;
    sceneAPI={setStep:i=>setPose(poses[i]),setInspect:on=>setPose(on?inspectPose(stations[current]):poses[current]),setLogin:on=>{setPose(on?loginPose:poses[current]);loginArrivalPending=on;}};
    if(loggingIn)sceneAPI.setLogin(true);
    const resize=()=>{const r=visual.getBoundingClientRect();if(!r.width||!r.height)return;renderer.setSize(Math.round(r.width),Math.round(r.height),false);camera.aspect=r.width/r.height;camera.updateProjectionMatrix();
      const pr=renderer.getPixelRatio();viewportH.value=Math.round(r.height*pr);grainUniform.value=3.0*pr;};
    window.addEventListener('resize',resize,{passive:true});new ResizeObserver(resize).observe(visual);resize();

    // ---- The squad: the game's Studio characters (lazy, after the first frame) ----------------------------------
    const squadRoots=[];
    const blink={value:0};
    loadSquad();
    async function loadSquad(){
      await new Promise(r=>requestAnimationFrame(()=>setTimeout(r,reduce?0:120)));
      if(!squadLoadable)return;
      let GLTFLoader,MeshoptDecoder;
      try{({GLTFLoader}=await import('three/addons/loaders/GLTFLoader.js'));({MeshoptDecoder}=await import('three/addons/libs/meshopt_decoder.module.js'));}
      catch(err){console.warn('Squad loader unavailable; the campfire keeps its empty places',err);return;}
      const loader=new GLTFLoader();loader.setMeshoptDecoder(MeshoptDecoder);
      await Promise.all(SQUAD.map((s,k)=>loader.loadAsync(`assets/squad_${s.race}.glb`).then(g=>placeCharacter(g,s,k)).catch(err=>console.warn('squad',s.race,err))));
    }
    // Studio toon port (index.html applyCelShading + eyes/anime-face.js + line-art.js), trimmed to the defaults
    // the cards start with: Classic iris (eye colour turquoise #21b7cf), Anime Soft makeup, auto blink.
    const IRIS=new T.Color(0x21b7cf),SKIN=new T.Color(0xddbfae),HAIR_AB=new T.Color(0x6f657f);
    const studioCel=`
      vec3 celKey=normalize(vec3(-0.45,0.65,0.72));
      float celFacing=dot(normalize(normal),celKey);
      float celShade=1.0-smoothstep(0.10,0.13,celFacing);
      // card ink (studio05_toon.gdshader card_ink): 2 crisp bands, warm paper shadow, light grain
      vec3 zxLit=diffuseColor.rgb*mix(vec3(1.10),vec3(0.90,0.74,0.68)*0.78,celShade);
      // the night: the moon / fire tint the cel colour a little (their summed light, flattened)
      float zxL=dot(outgoingLight,vec3(0.2126,0.7152,0.0722));float zxB=max(dot(diffuseColor.rgb,vec3(0.2126,0.7152,0.0722)),0.02);
      vec3 zxTint=clamp(outgoingLight/max(zxL,0.0001),0.0,2.0);
      outgoingLight=zxLit*mix(vec3(1.0),zxTint,0.35)*clamp(zxL/zxB*0.9,0.72,1.25);`;
    const faceGLSL=`
      float studioStroke(float d,float hw){float aa=clamp(0.5*fwidth(d),0.0002,0.0025);return 1.0-smoothstep(hw-aa,hw+aa,abs(d));}
      float lashTip(vec2 eye,vec2 root,vec2 tip,float rw){vec2 axis=tip-root;float along=dot(eye-root,axis)/dot(axis,axis);float across=length(eye-root-along*axis);float w=rw*(1.0-clamp(along,0.0,1.0));
        return (1.0-smoothstep(w-0.025,w+0.025,across))*smoothstep(-0.15,0.0,along)*(1.0-smoothstep(0.92,1.0,along));}
      vec2 eyeSocketRim(float t){vec2 s[7];s[0]=vec2(0.3580,0.3580);s[1]=vec2(0.3662,0.3508);s[2]=vec2(0.3705,0.3452);s[3]=vec2(0.3718,0.3443);s[4]=vec2(0.3710,0.3452);s[5]=vec2(0.3680,0.3500);s[6]=vec2(0.3620,0.3620);
        float index=clamp(t,0.0,1.0)*6.0;int seg=int(min(floor(index),5.0));float f=index-float(seg);
        vec2 a=s[seg>0?seg-1:0],b=s[seg],c=s[seg+1],d=s[seg+2<6?seg+2:6];
        return b+0.5*f*((c-a)+f*((2.0*a-5.0*b+4.0*c-d)+f*(3.0*(b-c)+d-a)));}
      uniform vec3 irisTint;uniform float studioBlink;varying vec3 vFacePosition;`;
    const faceLayers=`
      {
      float side=abs(vFacePosition.x);
      if(vFacePosition.z>0.015&&side<0.074&&vFacePosition.y>0.334&&vFacePosition.y<0.415){
        float socketT=(side-0.021)/0.0445;float sp=clamp(socketT,0.0,1.0);float sb=mix(0.359,0.361,sp);
        vec2 lid=vec2(2.0*socketT-1.0,(vFacePosition.y-sb)/0.013);
        vec2 rim=(eyeSocketRim(socketT)+(0.001-0.002*sp)-sb)/0.013;rim.x-=0.065*max(0.0,1.0-lid.x*lid.x);
        float blink=clamp(studioBlink,0.0,1.0);float closedLid=mix(rim.y,rim.x,0.24);
        float upper=mix(rim.x,closedLid,blink),lower=mix(rim.y,closedLid,blink);float lh=lid.y-upper;
        float lf=1.0-smoothstep(0.12,0.65,lh);float ls=1.0-smoothstep(0.75,1.15,abs(lid.x));float ol=smoothstep(-0.55,0.95,lid.x);
        float es=smoothstep(-0.15,0.07,lh)*lf*ls;outgoingLight=mix(outgoingLight,mix(vec3(0.61,0.27,0.27),vec3(0.38,0.12,0.15),ol),es*mix(0.24,0.46,ol)*(1.0-0.7*blink));
        float opening=smoothstep(-0.04,0.04,min(1.0-abs(lid.x),min(upper-lid.y,lid.y-lower)))*(1.0-smoothstep(0.96,1.0,blink));
        vec3 eyeColor=vec3(0.96,0.87,0.76);
        vec2 iris=(vec2(side,vFacePosition.y)-vec2(0.04325,0.3585))/0.0123;iris.x*=sign(vFacePosition.x);float radius=length(iris);
        float im=1.0-smoothstep(0.94,1.01,radius);
        vec3 amber=mix(min(irisTint*1.35,vec3(1.0)),irisTint*0.24,smoothstep(-0.72,0.6,iris.y));
        float glint=sin(atan(iris.y,iris.x+0.0001)*19.0)*0.5+0.5;
        amber+=mix(irisTint,vec3(1.0),0.3)*0.37*glint*smoothstep(0.35,0.9,radius)*(1.0-smoothstep(-0.50,0.35,iris.y));
        amber=mix(amber,irisTint*0.20,smoothstep(0.82,0.98,radius));
        float lg=exp(-dot(iris-vec2(0.0,-0.78),iris-vec2(0.0,-0.78))*8.0);amber+=mix(irisTint,vec3(0.95,0.88,0.55),0.54)*lg*0.62;
        float ps=length(iris-vec2(0.0,0.07))/0.35;amber=mix(amber,vec3(0.019,0.012,0.020),1.0-smoothstep(0.87,1.08,ps));
        float sparkle=max(1.0-smoothstep(0.16,0.20,length(iris-vec2(-0.35,0.36))),1.0-smoothstep(0.075,0.12,length(iris-vec2(0.30,-0.30))));
        eyeColor=mix(eyeColor,mix(amber,vec3(1.0,0.93,0.75),sparkle),im);
        eyeColor*=mix(vec3(1.0),vec3(0.72,0.62,0.63),smoothstep(-0.46,-0.06,lh));
        outgoingLight=mix(outgoingLight,eyeColor*mix(0.84,1.0,smoothstep(0.4,0.8,celFacing)),opening);
        float lw=mix(0.14,0.30,smoothstep(0.05,0.86,lid.x));
        float lash=(1.0-smoothstep(lw-0.04,lw+0.04,abs(lid.y-upper)))*(1.0-smoothstep(0.94,1.05,abs(lid.x)));
        float wing=lashTip(lid,vec2(0.70,0.62),vec2(1.20,0.90),0.16);wing=max(wing,lashTip(lid,vec2(0.82,0.47),vec2(1.26,0.61),0.13));wing=max(wing,lashTip(lid,vec2(0.91,0.32),vec2(1.22,0.35),0.10));wing*=1.0-blink;
        float lwl=mix(0.035,0.17,smoothstep(0.64,0.96,lid.x));float ll=(1.0-smoothstep(lwl*0.5,lwl+0.04,abs(lid.y-lower)))*(1.0-smoothstep(0.95,1.025,abs(lid.x)));
        float lo=mix(0.32,0.92,smoothstep(0.42,0.93,lid.x));float linerA=max(max(lash,wing),lo*ll);
        float shutLine=studioStroke(lid.y-closedLid,0.065)*(1.0-smoothstep(0.91,1.02,abs(lid.x)));
        outgoingLight=mix(outgoingLight,vec3(0.042,0.017,0.026),mix(linerA,shutLine,smoothstep(0.62,0.97,blink)));
        float bx=(side-0.039)/0.024;float by=0.386+0.0045*(1.0-bx*bx)-0.00075*bx;
        float brow=(1.0-smoothstep(0.0007,0.0018,abs(vFacePosition.y-by)))*(1.0-smoothstep(0.77,1.0,abs(bx)));
        outgoingLight=mix(outgoingLight,vec3(0.115,0.059,0.078),brow);
      }
      float faceSide=abs(vFacePosition.x);float faceFront=smoothstep(0.045,0.065,vFacePosition.z);
      float mx=vFacePosition.x/0.015;float my=0.311+0.0017*mx*mx;float mouth=studioStroke(vFacePosition.y-my,0.00085)*(1.0-smoothstep(0.62,1.0,abs(mx)));
      float nx=(faceSide-0.011)/0.004;float ny=0.332+0.0019*nx;float nose=studioStroke(vFacePosition.y-ny,0.00065)*(1.0-smoothstep(0.36,1.0,abs(nx)));
      outgoingLight=mix(outgoingLight,vec3(0.26,0.105,0.097),faceFront*max(0.48*mouth,0.36*nose));
      }`;
    const hairInk=`
      {
      float hc=max(length(dFdx(normal)),length(dFdy(normal)));float ci=smoothstep(0.14,0.32,hc);
      float bs=fwidth(celFacing);float bd=abs(celFacing-0.07)/max(bs,0.0001);float bi=(1.0-smoothstep(0.24,0.80,bd))*smoothstep(0.027,0.10,bs);
      vec3 hic=mix(diffuseColor.rgb*0.19,vec3(0.009,0.006,0.018),0.5);
      outgoingLight=mix(outgoingLight,hic,max(ci*0.50,bi*0.52));
      }`;
    const paintGLSL=`uniform bool zxPaint;`;
    function characterMaterial(src,kind){
      // kind: 'face' | 'hair' | 'body'
      const m=new T.MeshLambertMaterial({color:src.color?src.color.clone():new T.Color(1,1,1),map:src.map||null,vertexColors:!!src.vertexColors,side:T.DoubleSide});
      if(src.emissive&&src.emissive.getHex())m.color.lerp(src.emissive,.35); // the Runeborn runes' cyan, kept subtle (RUNE_GLOW)
      const paint=kind==='face'&&!!src.map; // Viking war paint: bare-skin texels take the card skin
      m.onBeforeCompile=sh=>{
        sh.uniforms.irisTint={value:IRIS};sh.uniforms.studioBlink=blink;sh.uniforms.zxGrainPx=grainUniform;
        if(kind==='face'){sh.vertexShader=sh.vertexShader.replace('#include <common>','#include <common>\nvarying vec3 vFacePosition;').replace('#include <begin_vertex>','#include <begin_vertex>\nvFacePosition=position;');}
        let frag=sh.fragmentShader;
        if(paint)frag=frag.replace('#include <map_fragment>',`
          vec4 zxTex=texture2D(map,vMapUv);
          float zxCov=smoothstep(0.02,0.12,length(zxTex.rgb-vec3(0.7231,0.5583,0.4793)));
          diffuseColor.rgb=mix(diffuse,zxTex.rgb,zxCov);`);
        frag=frag.replace('#include <opaque_fragment>',studioCel+(kind==='face'?faceLayers:'')+(kind==='hair'?hairInk:'')+`
          { float g=zxGrain(gl_FragCoord.xy/zxGrainPx)*0.6+zxGrain(gl_FragCoord.xy/(zxGrainPx*4.0))*0.4; outgoingLight*=1.0-0.045*g; }
          #include <opaque_fragment>`);
        sh.fragmentShader=frag.replace('#include <common>','#include <common>\n'+inkCommon+(kind==='face'?faceGLSL:''));
      };
      m.customProgramCacheKey=()=>'zx-char-'+kind+(paint?'-paint':'')+(m.map?'-map':'')+(m.vertexColors?'-vc':'');
      return m;
    }
    function placeCharacter(gltf,s,k){
      const root=new T.Group();const model=gltf.scene;root.add(model);
      const skinned=[];model.traverse(o=>{if(o.isSkinnedMesh)skinned.push(o);});
      for(const o of skinned){
        const label=o.name;const kind=/^Head_Anime/.test(label)?'face':/^Hair_/.test(label)?'hair':'body';
        const srcMat=o.material;
        const isSkin=/skin/i.test(srcMat.name)||kind==='face';
        const color=kind==='hair'?(/^Hair_[AB]/.test(label)?HAIR_AB.clone():new T.Color(1,1,1)):isSkin?SKIN.clone():srcMat.color.clone();
        o.material=characterMaterial({color,map:srcMat.map,vertexColors:!!o.geometry.attributes.color,emissive:srcMat.emissive},kind);
        srcMat.dispose();
        o.frustumCulled=false;
        // Outline: the same skinned geometry, back faces pushed out (not on the rune overlay, it lies on the face).
        if(!/Runeborn_Face/.test(label)){const h=new T.SkinnedMesh(o.geometry,hullSkinned);h.frustumCulled=false;h.bind(o.skeleton,o.bindMatrix);h.name=label+'_StudioInk';o.parent.add(h);outlined.push(h);}
      }
      // Size: the trail is about 1.6x the game's metres around the fire; the squad stands ~2.1 m tall here.
      const mixer=new T.AnimationMixer(model);
      const clip=gltf.animations[0];
      if(clip){const act=mixer.clipAction(clip);act.play();mixer.setTime((k*.73)%clip.duration);root.userData.mixer=mixer;}
      model.updateMatrixWorld(true);
      const box=new T.Box3();for(const o of skinned){o.skeleton.update();}box.setFromObject(model,true);
      const h=box.max.y-box.min.y||1,scale=SQUAD_H/h;
      root.scale.setScalar(scale);
      const sp=spots[k];root.position.set(sp.x,-.62-box.min.y*scale,sp.z);
      // Face between the fire and the trail camera, so the faces read from the campfire view.
      const toFire=new T.Vector2(FX-sp.x,FZ-sp.z).normalize(),toCam=new T.Vector2(campPose.pos[0]-sp.x,campPose.pos[2]-sp.z).normalize();
      const dir=toFire.multiplyScalar(.2).add(toCam.multiplyScalar(.8));
      root.rotation.y=Math.atan2(dir.x,dir.y);
      scene.add(root);squadRoots.push(root);
      spots[k].loaded=true;
    }

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
    // eyes/blink.js: fast close, brief contact, slower opening; next blink 2.8-5.6 s later (16% double blink).
    let blinkAt=1.6;
    const ease=v=>{const t=Math.max(0,Math.min(1,v));return t*t*(3-2*t);};
    const blinkAmount=ms=>ms<0?0:ms<80?ease(ms/80):ms<115?1:1-ease((ms-115)/145);
    const gobM=new T.Object3D();
    const frustum=new T.Frustum(),frustumM=new T.Matrix4(),squadSphere=new T.Sphere(new T.Vector3(),1.6);
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
        if(x.gob){x.gob.forEach(({x:gx,z:gz,k:j})=>{const ph=(t*1.6+j*.37)%1;gobM.position.set(gx,-.6+Math.abs(Math.sin(ph*Math.PI))*.12,gz);gobM.updateMatrix();x.gobFill.setMatrixAt(j,gobM.matrix);});x.gobFill.instanceMatrix.needsUpdate=true;}
        if(x.eyeMat){const e=.75+.25*Math.abs(Math.sin(t*2.4));x.eyeMat.color.setRGB(e,e*.64,e*.23);x.torches.forEach((f,j)=>{f.scale.y=.2*(.85+.2*Math.sin(t*9+j*2));});}
      });
      const cur=current>0&&current<total-1&&!loggingIn?stations[current]:null;
      if(cur){focusLight.position.set(cur.x+1.5,6.5,cur.z+3.5);focusLight.intensity+=((inspecting?26:18)-focusLight.intensity)*Math.min(1,dt*3);}
      else focusLight.intensity*=Math.max(0,1-dt*3);
      // Campfire (and its squad): only animated while it is near the camera.
      const nearFire=Math.abs(camera.position.z-FZ)<70;
      // The squad (~200 k triangles with outlines) only draws when its spot is in view (one sphere per hero;
      // skinned meshes are not frustum-culled by three.js, so this is done here).
      camera.updateMatrixWorld();frustumM.multiplyMatrices(camera.projectionMatrix,camera.matrixWorldInverse);frustum.setFromProjectionMatrix(frustumM);
      if(nearFire){
        for(let j=0;j<EMB;j++){const a=j*2.39997,life=(t*.22+j*.074)%1;embPos[j*3]=FX+Math.cos(a+t*.7)*(.4+life*2.1);embPos[j*3+1]=.65+life*6;embPos[j*3+2]=FZ+Math.sin(a+t*.4)*(.5+life*.85);}
        embGeo.attributes.position.needsUpdate=true;
        flames.forEach(({fl,a,j})=>{fl.scale.y=(1.1+(j%5)*.34)*(.82+.17*Math.sin(t*8+a)+.1*Math.cos(t*5+j));fl.rotation.z=Math.sin(t*4+a)*.2;});
        flameGlow.material.opacity=.55+Math.sin(t*7)*.08;
        fireLight.intensity=70+Math.sin(t*8)*9+Math.sin(t*13.7)*5;
        if(!reduce)squadRoots.forEach(r=>{if(r.visible)r.userData.mixer?.update(dt);});
        blinkAt-=dt;blink.value=reduce?0:blinkAmount(-blinkAt*1000);
        if(blinkAt< -.26)blinkAt=Math.random()<.16?.18:2.8+Math.random()*2.8;
      }
      embers.visible=nearFire;squadRoots.forEach(r=>{squadSphere.center.set(r.position.x,1,r.position.z);r.visible=!loggingIn&&frustum.intersectsSphere(squadSphere);});
      // Gate
      portal.material.opacity=.42+.1*Math.sin(t*2.2);gateGlow.material.opacity=.32+.08*Math.sin(t*2.2);
      gateFlames.forEach((f,j)=>{f.scale.y=.95*(.85+.18*Math.sin(t*9+j*2));});
      renderer.render(scene,camera);
    }
    requestAnimationFrame(tick);
    // Debug/perf hook for the measurement script (read-only numbers).
    window.__zorxTrail={renderer,outlines:()=>outlined.length,squad:()=>squadRoots.length,look:(p,l,f)=>setPose({pos:p,look:l,fov:f}),spots:()=>spots.map(s=>[s.x,s.z])};
  }
})();
