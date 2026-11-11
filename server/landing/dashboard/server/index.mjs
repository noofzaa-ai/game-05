import http from 'node:http';
import {isAdmin,adminCall,readJson} from './admin.mjs';
import { createHash, createCipheriv, createDecipheriv, randomBytes, createHmac } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { OAuth2Client } from 'google-auth-library';
import { nakamaConfigured, authenticateGoogle, authenticateGuest, verifyGameAccount, refreshGameSession, logoutGameSession } from './nakama.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const origin = new URL(process.env.PUBLIC_ORIGIN || 'http://localhost:4173');
if (origin.origin !== origin.href.replace(/\/$/, '')) throw new Error('PUBLIC_ORIGIN must be an origin');
const secure = origin.protocol === 'https:';
if (!secure && !['localhost', '127.0.0.1'].includes(origin.hostname)) throw new Error('HTTPS required');
const secret = process.env.SESSION_SECRET || '';
if (secret.length < 32) throw new Error('Set SESSION_SECRET to at least 32 random characters');
const configured = Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET && nakamaConfigured);
const guestSiteKey = process.env.TURNSTILE_SITE_KEY || '0x4AAAAAAFfYmmETLpxucNy3';
const guestSecret = process.env.ZORX_GUEST_SECRET || '';
const guestConfigured = process.env.ZORX_GUEST_ENABLED === '1' && Boolean(process.env.TURNSTILE_SECRET_KEY) && guestSecret.length >= 32 && nakamaConfigured;
const guestName = secure ? '__Host-zorx_guest' : 'zorx_guest';
const gameOrigin = new URL(process.env.GAME_ORIGIN || 'https://zorxplay.daiyooo.com').origin;
const oauth = new OAuth2Client(process.env.GOOGLE_CLIENT_ID, process.env.GOOGLE_CLIENT_SECRET,
  `${origin.origin}/auth/google/callback`);
const sessionName = secure ? '__Host-zorx_session' : 'zorx_session';
const flowName = secure ? '__Host-zorx_oauth' : 'zorx_oauth';
// Authenticated encryption keeps Nakama credentials confidential in HttpOnly cookies.
const cookieKey = createHash('sha256').update(secret).digest();
function seal(value) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', cookieKey, iv);
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString('base64url');
}
function unseal(value) {
  try {
    if (typeof value !== 'string' || value.length > 3800) return null;
    const bytes = Buffer.from(value, 'base64url');
    if (bytes.length < 29) return null;
    const decipher = createDecipheriv('aes-256-gcm', cookieKey, bytes.subarray(0, 12));
    decipher.setAuthTag(bytes.subarray(12, 28));
    const data = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]));
    return data.exp > Date.now() ? data : null;
  } catch { return null; }
}
function cookies(req) {
  return Object.fromEntries((req.headers.cookie || '').split(';').map(x => x.trim().split('=')));
}
function cookie(name, value, age) {
  if (value.length > 3800) throw new Error('Session exceeds cookie limit');
  return `${name}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${age}${secure ? '; Secure' : ''}`;
}
function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}
function redirect(res, target) { res.writeHead(303, { Location: target }); res.end(); }
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
  '.webp': 'image/webp', '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml' };
// Bounded origin-wide budget: never trust a client-supplied forwarding header.
let authTokens = 40, authAt = Date.now(), authActive = 0;
const staticCache = new Map();
const server = http.createServer(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  let authSlot = false;
  try {
    const url = new URL(req.url, origin);
    if ((url.pathname.startsWith('/auth/') && url.pathname !== '/auth/session') || url.pathname.startsWith('/admin/api/')) {
      const now = Date.now();
      authTokens = Math.min(40, authTokens + Math.max(0, now - authAt) * 5 / 1000); authAt = now;
      if (authTokens < 1 || authActive >= 16) {
        res.setHeader('Retry-After', '2'); return json(res, 429, {error:'rate_limited'});
      }
      authTokens--; authActive++; authSlot = true;
    }
    const jar = cookies(req);
    const trustedOrigin = req.headers.origin === origin.origin || req.headers.origin === gameOrigin;
    if (url.pathname === '/admin' || url.pathname.startsWith('/admin/')) {
      const session=unseal(jar[sessionName]);
      if(!session){if(url.pathname==='/admin')return redirect(res,'/auth/google?next=admin');return json(res,401,{error:'login_required'});}
      if(!isAdmin(session)){
        if(url.pathname==='/admin'){
          const email=String(session.user?.email || '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
          res.setHeader('X-Frame-Options','DENY');
          res.setHeader('Content-Security-Policy',"default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
          res.writeHead(403,{'Content-Type':'text/html; charset=utf-8'});
          return res.end('<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ZORX · ไม่มีสิทธิ์ Admin</title><h1>บัญชีนี้ยังไม่มีสิทธิ์ Admin</h1><p>บัญชีที่ล็อกอินอยู่: <strong>'+email+'</strong></p><p><a href="/auth/google?next=admin">เลือกบัญชี Google ใหม่</a></p><p><a href="/">กลับหน้าเว็บ</a></p></html>');
        }
        return json(res,403,{error:'forbidden'});
      }
      res.setHeader('X-Frame-Options','DENY');
      res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
      if(url.pathname==='/admin/api/me' && req.method==='GET')return json(res,200,{email:session.user.email});
      if(url.pathname==='/admin/api/action' && req.method==='POST'){
        if(req.headers.origin!==origin.origin || !req.headers['content-type']?.startsWith('application/json'))return json(res,403,{error:'origin_rejected'});
        try{const input=await readJson(req);if(!['ban','unban'].includes(input.op))return json(res,400,{error:'invalid_action'});return json(res,200,await adminCall(session,{op:input.op,target:input.target,reason:input.reason}));}
        catch(e){return json(res,400,{error:['invalid_action','user_not_found','action_failed','admin_not_configured'].includes(e.message)?e.message:'request_failed'});}
      }
      if(req.method==='GET' && ['/admin/api/security','/admin/api/character','/admin/api/history','/admin/api/status','/admin/api/users','/admin/api/audit','/admin/api/feedback'].includes(url.pathname)){
        try{return json(res,200,await adminCall(session,{op:url.pathname.split('/').pop(),target:url.searchParams.get('target')||'',range:url.searchParams.get('range')||'24h',search:url.searchParams.get('search')||'',cursor:url.searchParams.get('cursor')||''}));}
        catch{return json(res,503,{error:'admin_unavailable'});}
      }
      const files={'/admin':'index.html','/admin/admin.js':'admin.js','/admin/admin.css':'admin.css'};
      if(req.method==='GET' && files[url.pathname]){
        const file=files[url.pathname];const body=await readFile(path.join(root,'admin',file));
        res.writeHead(200,{'Content-Type':types[path.extname(file)]+'; charset=utf-8'});return res.end(body);
      }
      return json(res,404,{error:'not_found'});
    }

    if (['/auth/game-session', '/auth/google/link'].includes(url.pathname) && trustedOrigin) {
      res.setHeader('Access-Control-Allow-Origin', req.headers.origin);
      res.setHeader('Access-Control-Allow-Credentials', 'true');
      res.setHeader('Vary', 'Origin');
      if (req.method === 'OPTIONS') {
        res.setHeader('Access-Control-Allow-Methods', 'POST');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        res.writeHead(204); return res.end();
      }
      if (req.method === 'POST' && url.pathname === '/auth/game-session') {
        const session = unseal(jar[sessionName]);
        if (session?.kind !== 'session' || !session.game) return json(res, 401, { error: 'login_required' });
        // Refresh on exchange so the game never receives an expired session.
        const game = await refreshGameSession(session.game);
        session.game = game;
        res.setHeader('Set-Cookie', cookie(sessionName, seal(session), Math.max(0, Math.floor((session.exp - Date.now()) / 1000))));
        return json(res, 200, { ...game, api_origin: process.env.NAKAMA_PUBLIC_ORIGIN || 'https://zorxapi.daiyooo.com' });
      }
    }
    if (url.pathname === '/auth/google/link' && req.method === 'POST') {
      // Game supplies its current Nakama session explicitly. No lookup by email, name or supplied user ID.
      if (!trustedOrigin) return json(res, 403, { error: 'origin_rejected' });
      const token = (req.headers.authorization || '').replace(/^Bearer /, '');
      if (!token || token.length > 4096) return json(res, 401, { error: 'game_session_required' });
      const userId = await verifyGameAccount(token);
      res.setHeader('Set-Cookie', cookie(flowName, seal({ kind: 'link', token, userId, exp: Date.now() + 600000 }), 600));
      return json(res, 200, { url: '/auth/google' });
    }
    if (url.pathname === '/auth/session' && req.method === 'GET') {
      const session = unseal(jar[sessionName]);
      return json(res, 200, { configured, guest: {configured:guestConfigured, site_key:guestSiteKey}, user: session?.kind === 'session' ? session.user : null, game_account_id: session?.game?.user_id || null });
    }
    if (url.pathname === '/auth/guest' && req.method === 'POST') {
      if(req.headers.origin!==origin.origin || !req.headers['content-type']?.startsWith('application/json')) return json(res,403,{error:'origin_rejected'});
      if(!guestConfigured) return json(res,503,{error:'guest_not_configured'});
      const current=unseal(jar[sessionName]);
      if(current?.kind==='session') return json(res,409,{error:'already_logged_in'});
      let input;
      try{input=await readJson(req);}catch{return json(res,400,{error:'invalid_payload'});}
      if(typeof input.token!=='string' || input.token.length<1 || input.token.length>2048) return json(res,400,{error:'captcha_required'});
      const verify=await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify',{
        method:'POST',redirect:'error',signal:AbortSignal.timeout(8000),
        headers:{'Content-Type':'application/x-www-form-urlencoded'},
        body:new URLSearchParams({secret:process.env.TURNSTILE_SECRET_KEY,response:input.token})});
      if(!verify.ok) return json(res,503,{error:'captcha_unavailable'});
      const check=await verify.json();
      if(check.success!==true || check.hostname!==origin.hostname || check.action!=='guest_login') return json(res,403,{error:'captcha_failed'});
      const prior=unseal(jar[guestName]);
      const id=prior?.kind==='guest' && /^zorx_guest_[a-f0-9]{64}$/.test(prior.id) ? prior.id : 'zorx_guest_'+randomBytes(32).toString('hex');
      const at=String(Date.now()), nonce=randomBytes(16).toString('hex');
      const proof=createHmac('sha256',guestSecret).update(id+'\n'+at+'\n'+nonce).digest('base64');
      let game;
      try{game=await authenticateGuest(id,{at,nonce,proof});}catch(e){return json(res,e.status===429?429:503,{error:'guest_unavailable'});}
      res.setHeader('Set-Cookie',[
        cookie(guestName,seal({kind:'guest',id,exp:Date.now()+180*86400000}),180*86400),
        cookie(sessionName,seal({kind:'session',user:{name:'Guest',guest:true},game,exp:Date.now()+8*3600000}),8*3600)]);
      return json(res,200,{ok:true});
    }
    if (url.pathname === '/auth/logout' && req.method === 'POST') {
      if (req.headers.origin !== origin.origin) return json(res, 403, { error: 'origin_rejected' });
      const session = unseal(jar[sessionName]);
      if (session?.game) {
        try { await logoutGameSession(session.game); } catch { /* Expired sessions still clear locally. */ }
      }
      res.setHeader('Set-Cookie', [cookie(sessionName, '', 0), cookie(flowName, '', 0)]);
      return json(res, 200, { ok: true });
    }
    if (url.pathname === '/auth/google' && req.method === 'GET') {
      if (!configured) return redirect(res, '/?auth=not_configured');
      const state = randomBytes(32).toString('base64url');
      const nonce = randomBytes(32).toString('base64url');
      const { codeVerifier, codeChallenge } = await oauth.generateCodeVerifierAsync();
      const link = unseal(jar[flowName]);
      // HttpOnly cookie binds the callback to this browser; expires in 10 minutes.
      res.setHeader('Set-Cookie', cookie(flowName, seal({ kind: 'oauth', state, nonce,
        verifier: codeVerifier, admin: url.searchParams.get('next') === 'admin', link: link?.kind === 'link' ? { token: link.token, userId: link.userId } : null, exp: Date.now() + 600000 }), 600));
      return redirect(res, oauth.generateAuthUrl({ response_type: 'code', scope: ['openid', 'email', 'profile'],
        state, nonce, code_challenge: codeChallenge, code_challenge_method: 'S256', prompt: 'select_account' }));
    }
    if (url.pathname === '/auth/google/callback' && req.method === 'GET') {
      res.setHeader('Set-Cookie', cookie(flowName, '', 0));
      const flow = unseal(jar[flowName]);
      if (!flow || flow.kind !== 'oauth' || url.searchParams.get('state') !== flow.state) {
        return redirect(res, '/?auth=invalid_state');
      }
      if (url.searchParams.has('error')) return redirect(res, '/?auth=cancelled');
      const code = url.searchParams.get('code');
      if (!code || code.length > 8192) return redirect(res, '/?auth=failed');
      const { tokens } = await oauth.getToken({ code, codeVerifier: flow.verifier });
      const ticket = await oauth.verifyIdToken({ idToken: tokens.id_token,
        audience: process.env.GOOGLE_CLIENT_ID });
      const claims = ticket.getPayload();
      if (!claims?.sub || claims.nonce !== flow.nonce || claims.email_verified !== true) {
        return redirect(res, '/?auth=failed');
      }
      let game;
      try {
        game = await authenticateGoogle(tokens.id_token, flow.link?.token || null);
        if (flow.link && game.user_id !== flow.link.userId) throw new Error('Account mismatch');
      } catch (error) {
        return redirect(res, error.status === 409 ? '/?auth=account_conflict' : '/?auth=backend_failed');
      }
      // Use Google sub as the stable identity. Never use email as an account key.
      // Google access/refresh/ID tokens are not exposed to frontend storage or URLs.
      const user = { id: claims.sub, name: String(claims.name || '').slice(0, 160), email: claims.email };
      res.setHeader('Set-Cookie', [cookie(flowName, '', 0), cookie(sessionName,
        seal({ kind: 'session', user, game, exp: Date.now() + 8 * 3600000 }), 8 * 3600)]);
      return redirect(res, flow.admin ? '/admin' : gameOrigin + '/');
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method_not_allowed' });
    // Explicit public files only: never expose .env, server code or package files.
    const pathname = decodeURIComponent(url.pathname);
    const relative = pathname === '/' ? 'index.html' : pathname.slice(1);
    const allowed = ['index.html', 'config.js', 'trail.js', 'auth.js', 'styles.css'].includes(relative)
      || /^assets\/[a-zA-Z0-9_-]+\.(webp|jpg|png|svg)$/.test(relative);
    if (!allowed) return json(res, 404, { error: 'not_found' });
    let body = staticCache.get(relative);
    if (!body) {
      body = await readFile(path.join(root, relative));
      // Only cache successful, explicitly allowed files; misses cannot grow the map.
      staticCache.set(relative, body);
    }
    res.setHeader('Cache-Control', relative.startsWith('assets/') ? 'public, max-age=3600' : 'no-cache');
    res.setHeader('X-Frame-Options', 'DENY');
    res.writeHead(200, { 'Content-Type': `${types[path.extname(relative)] || 'application/octet-stream'}; charset=utf-8` });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch {
    // Do not log authorization codes, tokens, cookies or Google response bodies.
    if (!res.headersSent) {
      if (req.url?.startsWith('/auth/google/callback')) return redirect(res, '/?auth=failed');
      return json(res, 500, { error: 'request_failed' });
    }
    res.end();
  } finally {
    if (authSlot) authActive--;
  }
});
server.headersTimeout = 10000;
server.requestTimeout = 15000;
server.keepAliveTimeout = 5000;
server.maxRequestsPerSocket = 100;
server.listen(Number(process.env.PORT || 4173), '0.0.0.0', () => console.log(`ZORX web listening at ${origin.origin}`));
