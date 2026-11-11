const { chromium }=require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const fs=require('fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:false,args:['--no-first-run','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
 const context=await browser.newContext({viewport:{width:1335,height:720},deviceScaleFactor:1});
 const page=await context.newPage();
 page.on('console',msg=>{if(/ERROR|PERF|FX|WebGL|pack loader|SCRIPT/.test(msg.text()))fs.appendFileSync('/tmp/perf-browser-console.log',msg.type()+': '+msg.text()+'\n');});
 page.on('pageerror',e=>fs.appendFileSync('/tmp/perf-browser-console.log','PAGEERROR '+e.message+'\n'));
 await page.addInitScript(()=>{
  window.__perfRaf=[];window.__perfEnds=[];let last=performance.now();
  function frame(now){window.__perfRaf.push([now,now-last]);last=now;requestAnimationFrame(frame);}requestAnimationFrame(frame);
  window.addEventListener('zorx-perf-result',()=>{const r=window.zorxPerfReport;if(r?.results.length)window.__perfEnds.push({at:performance.now(),count:r.results.length});});
 });
 await page.goto('https://zorxplay.daiyooo.com/perf-lab/?test=2',{waitUntil:'domcontentloaded',timeout:60000});
 console.log('BROWSER',await browser.version());
 for(let i=0;i<120;i++){
  await page.waitForTimeout(1000);
  if(i%10===0)console.log('LOAD',i);
  const ready=await page.evaluate(()=>!!window.zorxBootProgress && !document.querySelector('#loading')?.offsetParent).catch(()=>false);
  if(i>40 && ready)break;
 }
 await page.screenshot({path:'/tmp/perf-browser-ready.png'});
 console.log('GPU',await page.evaluate(()=>{const c=document.querySelector('canvas');const g=c?.getContext('webgl2');const e=g?.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):'unavailable'}));
 console.log('CLICK ALL');await page.mouse.click(38,58);
 let last=-1;
 for(let i=0;i<180;i++){
  await page.waitForTimeout(3000);
  const report=await page.evaluate(()=>window.zorxPerfReport||null);
  if(report){
   fs.writeFileSync('/tmp/perf-browser-results.json',JSON.stringify(report,null,2));
   fs.writeFileSync('/tmp/perf-browser-raf.json',JSON.stringify(await page.evaluate(()=>({frames:window.__perfRaf,ends:window.__perfEnds})),null,2));
   if(report.results.length!==last){last=report.results.length;console.log('RESULTS',last,report.results.at(-1));}
   if(last>=24){await page.screenshot({path:'/tmp/perf-browser-complete.png'});console.log('COMPLETE');break;}
  }
  if(i%10===0)await page.screenshot({path:'/tmp/perf-browser-progress.png'});
 }
 await page.screenshot({path:'/tmp/perf-browser-last.png'});await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
