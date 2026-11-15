// Isolated HTTP regression for the staging-only ZORX_GUEST_CAPTCHA_OFF switch. All keys are synthetic QA data.
// Run from the landing root: node server/test_guest_captcha_off.mjs
import {spawn} from 'node:child_process';
import {createHmac} from 'node:crypto';
import assert from 'node:assert/strict';
import http from 'node:http';

const STAGING = 'https://zorx.daiyooo.com';
const guestSecret = 'g'.repeat(40);
const base = {SESSION_SECRET: 's'.repeat(40), NAKAMA_URL: 'http://127.0.0.1:14186', NAKAMA_SERVER_KEY: 'qa-key',
  ZORX_GUEST_ENABLED: '1', ZORX_GUEST_SECRET: guestSecret};
const cwd = new URL('../', import.meta.url);

// Fake Nakama: checks the guest proof the same way google_auth.ts does and returns a synthetic session.
const seen = [];
const nakama = http.createServer(async (req, res) => {
  let body = ''; for await (const p of req) body += p;
  const input = JSON.parse(body);
  seen.push({path: req.url, input});
  const {id, vars} = input;
  const expected = createHmac('sha256', guestSecret).update(id + '\n' + vars.at + '\n' + vars.nonce).digest('base64');
  if (!/^zorx_guest_[a-f0-9]{64}$/.test(id) || vars.proof !== expected) { res.writeHead(401); return res.end('{}'); }
  const claims = Buffer.from(JSON.stringify({uid: '11111111-1111-4111-8111-111111111111', exp: Math.floor(Date.now() / 1000) + 3600})).toString('base64url');
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({token: 'h.' + claims + '.s', refresh_token: 'r', created: true}));
});
await new Promise(r => nakama.listen(14186, '127.0.0.1', r));

function start(port, env) {
  const child = spawn(process.execPath, ['server/index.mjs'], {cwd, env: {...process.env, ...base, PORT: String(port), ...env}});
  let out = '', err = '';
  child.stdout.on('data', c => { out += c; }); child.stderr.on('data', c => { err += c; });
  const ready = new Promise((resolve, reject) => {
    const poll = setInterval(() => { if (/listening/.test(out)) { clearInterval(poll); resolve(); } }, 20);
    child.once('exit', code => { clearInterval(poll); reject(Object.assign(Error('exit ' + code), {code, err})); });
  });
  return {child, ready, log: () => out, err: () => err};
}
const post = (port, path, headers, body) => fetch(`http://127.0.0.1:${port}${path}`, {method: 'POST', redirect: 'manual',
  headers: {'Content-Type': 'application/json', ...headers}, body: JSON.stringify(body)});

const children = [];
try {
  // 1. Refused on any non-staging origin: the process must not start.
  for (const bad of ['https://zorx-prod.example.com', 'https://zorxplay.daiyooo.com', 'http://127.0.0.1:14181']) {
    const s = start(14181, {PUBLIC_ORIGIN: bad, ZORX_GUEST_CAPTCHA_OFF: '1'}); children.push(s.child);
    await assert.rejects(s.ready, e => /allowed only on the staging origin/.test(e.err), 'captcha off must refuse ' + bad);
  }

  // 2. Staging + flag: session reports no site key, guest works without a token, proof is valid.
  const on = start(14182, {PUBLIC_ORIGIN: STAGING, ZORX_GUEST_CAPTCHA_OFF: '1', TURNSTILE_SECRET_KEY: ''}); children.push(on.child);
  await on.ready;
  let r = await fetch('http://127.0.0.1:14182/auth/session');
  let data = await r.json();
  assert.deepEqual(data.guest, {configured: true, site_key: null, captcha: false});
  r = await post(14182, '/auth/guest', {Origin: STAGING}, {});
  assert.equal(r.status, 200, 'guest without Turnstile token');
  const set = r.headers.getSetCookie();
  assert.ok(set.some(c => c.startsWith('__Host-zorx_guest=')) && set.some(c => c.startsWith('__Host-zorx_session=')), 'same cookies as /auth/guest');
  assert.equal(seen.length, 1);
  assert.match(seen[0].path, /^\/v2\/account\/authenticate\/custom\?create=true$/);
  assert.match(seen[0].input.id, /^zorx_guest_[a-f0-9]{64}$/);
  // A second fresh visitor gets a different random id.
  r = await post(14182, '/auth/guest', {Origin: STAGING}, {});
  assert.equal(r.status, 200); assert.notEqual(seen[1].input.id, seen[0].input.id);
  // Origin check unchanged: a foreign origin is refused before Nakama is called.
  r = await post(14182, '/auth/guest', {Origin: 'https://attacker.test'}, {});
  assert.equal(r.status, 403); assert.equal(seen.length, 2);
  // Existing session cookie still refused (409).
  const sessionCookie = set.find(c => c.startsWith('__Host-zorx_session=')).split(';')[0];
  r = await post(14182, '/auth/guest', {Origin: STAGING, Cookie: sessionCookie}, {});
  assert.equal(r.status, 409); assert.equal(seen.length, 2);
  await new Promise(res => setTimeout(res, 50));
  const lines = on.log().split('\n').filter(l => l.includes('"auth"'));
  assert.ok(lines.length >= 4 && lines.every(l => l.includes('"captcha_off":true')), 'auth log marks captcha_off');
  assert.match(on.log(), /"auth_config":"captcha_off"/);
  assert.ok(!on.log().includes(guestSecret) && !on.log().includes('__Host-'), 'no secrets or cookies in the log');

  // 3. Flag absent: unchanged behaviour (site key reported, a missing token is refused).
  const off = start(14183, {PUBLIC_ORIGIN: STAGING, TURNSTILE_SECRET_KEY: 'qa-turnstile'}); children.push(off.child);
  await off.ready;
  data = await (await fetch('http://127.0.0.1:14183/auth/session')).json();
  assert.equal(data.guest.configured, true); assert.equal(typeof data.guest.site_key, 'string'); assert.equal(data.guest.captcha, undefined);
  r = await post(14183, '/auth/guest', {Origin: STAGING}, {});
  assert.equal(r.status, 400); assert.equal((await r.json()).error, 'captcha_required'); assert.equal(seen.length, 2);
  assert.ok(!off.log().includes('captcha_off'));

  // 4. Any value other than "1" does not switch it off.
  const odd = start(14184, {PUBLIC_ORIGIN: STAGING, ZORX_GUEST_CAPTCHA_OFF: 'true', TURNSTILE_SECRET_KEY: 'qa-turnstile'}); children.push(odd.child);
  await odd.ready;
  r = await post(14184, '/auth/guest', {Origin: STAGING}, {});
  assert.equal(r.status, 400);

  console.log('PASS Guest captcha-off: refused off staging (3 origins), staging guest without Turnstile with valid proof and fresh ids, origin check + 409 kept, captcha_off logged without secrets, flag absent/odd value unchanged');
} finally {
  for (const c of children) c.kill();
  nakama.close();
}
