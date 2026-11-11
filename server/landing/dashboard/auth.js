// Google login resolves to a Nakama account on the website backend.
const status = document.getElementById('auth-status');
const login = document.getElementById('google-login');
const logout = document.getElementById('google-logout');
const guestSection=document.getElementById('guest-section');
const guestButton=document.getElementById('guest-login');
let guestConfig=null, captchaToken='', widgetId=null, captchaLoading=null, guestBusy=false;
async function prepareCaptcha(){
  if(!guestConfig?.configured || user || widgetId!==null) return;
  if(!captchaLoading) captchaLoading=new Promise((resolve,reject)=>{
    const script=document.createElement('script');script.src='https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.async=true;script.onload=resolve;script.onerror=reject;document.head.append(script);
  }).catch(e=>{captchaLoading=null;throw e;});
  try{
    await captchaLoading;
    if(widgetId!==null || user) return;
    widgetId=window.turnstile.render('#guest-captcha',{sitekey:guestConfig.site_key,action:'guest_login',size:'flexible',
      callback:token=>{captchaToken=token;guestButton.disabled=guestBusy;},
      'expired-callback':()=>{captchaToken='';guestButton.disabled=true;},
      'error-callback':()=>{captchaToken='';guestButton.disabled=true;status.textContent='ตรวจสอบป้องกันบอทไม่สำเร็จ กรุณาลองใหม่';}});
  }catch{status.textContent='โหลดระบบป้องกันบอทไม่ได้ กรุณาโหลดหน้าใหม่';}
}
guestButton.addEventListener('click',async()=>{
  if(!captchaToken || guestBusy) return;
  guestBusy=true;guestButton.disabled=true;login.disabled=true;
  status.textContent='กำลังเข้าสู่ระบบ Guest…';
  try{
    const response=await fetch('/auth/guest',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:captchaToken})});
    if(!response.ok) throw Error('guest_failed');
    location.assign(gameUrl);
  }catch{status.textContent='เข้า Guest ไม่สำเร็จ กรุณาตรวจสอบป้องกันบอทแล้วลองอีกครั้ง';}
  finally{guestBusy=false;captchaToken='';guestButton.disabled=true;login.disabled=false;if(widgetId!==null)window.turnstile.reset(widgetId);}
});
let user = null;
let configured = false;
const gameUrl = 'https://zorxplay.daiyooo.com/';
function render() {
  login.hidden = Boolean(user);
  guestSection.hidden=Boolean(user) || !guestConfig?.configured;
  logout.hidden = !user;
  if (user) status.textContent = `เข้าสู่ระบบแล้ว: ${user.name || user.email} — เชื่อมบัญชีเกม Nakama แล้ว`;
  else if (!configured) status.textContent = 'กำลังเตรียม Google Login กรุณาลองอีกครั้งภายหลัง';
  else status.textContent = 'เข้าสู่ระบบด้วย Google เพื่อเริ่มการเดินทาง';
}
async function refresh() {
  try {
    const response = await fetch('/auth/session', { credentials: 'same-origin', cache: 'no-store' });
    if (!response.ok) throw new Error('unavailable');
    const data = await response.json();
    user = data.user || null;
    guestConfig=data.guest || null;
    configured = data.configured === true;
    render();
    return true;
  } catch { status.textContent = 'ยังเชื่อมต่อระบบบัญชีไม่ได้ กรุณาลองใหม่'; }
}
logout.addEventListener('click', async () => {
  logout.disabled = true;
  try {
    const response = await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin' });
    if (!response.ok) throw new Error('logout_failed');
    user = null; render();
  } catch { status.textContent = 'ออกจากระบบไม่สำเร็จ กรุณาลองใหม่'; }
  finally { logout.disabled = false; }
});
let pendingAuthResult = null;
window.addEventListener('zorx:login-ready', async () => {
  const attempt = document.getElementById('trail-stage').dataset.loginAttempt;
  login.disabled = true;
  status.textContent = 'กำลังตรวจสอบบัญชี…';
  try {
    const ok = await refresh();
    if (!document.getElementById('trail-stage').classList.contains('is-login') || document.getElementById('trail-stage').dataset.loginAttempt !== attempt) return;
    if (ok && user) { location.assign(gameUrl); return; }
    const messages = { cancelled: 'ยกเลิกการเข้าสู่ระบบแล้ว', invalid_state: 'ลิงก์เข้าสู่ระบบหมดอายุ กรุณากด Google ใหม่',
      failed: 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่', backend_failed: 'เชื่อมบัญชีเกมไม่สำเร็จ กรุณาลองใหม่', account_conflict: 'Google นี้ผูกกับบัญชีเกมอื่นแล้ว ไม่ได้ย้ายหรือรวมไอเทม', not_configured: 'กำลังเตรียม Google Login กรุณาลองอีกครั้งภายหลัง' };
    if (messages[pendingAuthResult]) status.textContent = messages[pendingAuthResult];
    pendingAuthResult = null;
    await prepareCaptcha();
    login.focus({preventScroll:true});
  } finally { login.disabled = false; }
});
const params = new URLSearchParams(location.search);
if (params.get('logout') === '1') {
  // Same-origin POST can clear the HttpOnly landing cookie, including on iPhone.
  login.disabled = true;
  document.getElementById('start-game').disabled = true;
  let cleared = false;
  try {
    const response = await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin', cache: 'no-store' });
    if (!response.ok) throw new Error('logout_failed');
    cleared = true;
    user = null;
    params.delete('logout'); params.delete('play'); params.delete('auth');
    history.replaceState(null, '', `${location.pathname}${params.size ? `?${params}` : ''}`);
    await refresh();
    status.textContent = 'ออกจากระบบแล้ว กรุณาเข้าสู่ระบบเพื่อเลือกบัญชีใหม่';
  } catch {
    status.textContent = 'ออกจากระบบไม่สำเร็จ กรุณาโหลดหน้านี้ใหม่เพื่อลองอีกครั้ง';
  } finally {
    login.disabled = !cleared;
    document.getElementById('start-game').disabled = !cleared;
  }
}

if (params.get('play') === '1') {
  params.delete('play');
  history.replaceState(null, '', `${location.pathname}${params.size ? `?${params}` : ''}${location.hash}`);
  document.getElementById('start-game').click();
}
if (params.has('auth')) {
  const result = params.get('auth');
  params.delete('auth');
  history.replaceState(null, '', `${location.pathname}${params.size ? `?${params}` : ''}${location.hash}`);
  document.getElementById('start-game').click();
  pendingAuthResult = result;
}
