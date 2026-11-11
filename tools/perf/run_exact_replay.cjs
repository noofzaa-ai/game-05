const {chromium}=require(process.env.PLAYWRIGHT_CORE || 'playwright-core');const fs=require('fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:false,args:['--no-first-run','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});const page=await browser.newPage({viewport:{width:1335,height:720},deviceScaleFactor:1});
 page.on('console',m=>{if(/ERROR|PERF|SCRIPT/.test(m.text()))fs.appendFileSync('/tmp/perf-v4-console.log',m.text()+'\n')});
 await page.goto('https://zorxplay.daiyooo.com/perf-lab/?v4=exact-packets',{waitUntil:'domcontentloaded'});await page.waitForTimeout(35000);
 const gpu=await page.evaluate(()=>{const g=document.querySelector('canvas').getContext('webgl2');const e=g.getExtension('WEBGL_debug_renderer_info');return {renderer:e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):'unavailable',vendor:e?g.getParameter(e.UNMASKED_VENDOR_WEBGL):'unavailable',ua:navigator.userAgent}});fs.writeFileSync('/tmp/perf-browser-hardware.json',JSON.stringify(gpu,null,2));console.log('GPU',gpu);
 const order=['B','N','R','P','P','R','R','P'];const positions={B:206,N:94,R:430,P:766};let count=0;
 for(const mode of order){
  await page.mouse.click(positions[mode],62);console.log('START',mode);
  let completed=false;
  for(let i=0;i<35;i++){
   await page.waitForTimeout(1000);const r=await page.evaluate(()=>window.zorxPerfReport||null);
   if(r&&r.results.length>count){count=r.results.length;fs.writeFileSync('/tmp/perf-browser-v4.json',JSON.stringify({order,hardware:gpu,report:r},null,2));console.log('DONE',mode,JSON.stringify(r.results.at(-1)));completed=true;break;}
  }
  if(!completed){await page.screenshot({path:'/tmp/perf-confirm-stuck.png'});throw Error('mode timeout '+mode);}
  await page.waitForTimeout(600);
 }
 await page.screenshot({path:'/tmp/perf-v4-complete.png'});await browser.close();console.log('CONFIRM COMPLETE');
})().catch(e=>{console.error(e);process.exit(1)});
