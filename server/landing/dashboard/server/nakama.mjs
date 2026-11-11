// Google identity is verified by Google in the website callback AND by Nakama.
// The Nakama server key identifies the application; it is not a signing/admin key.
const base = new URL(process.env.NAKAMA_URL || 'https://zorxapi.daiyooo.com');
if (base.protocol !== 'https:' && !(base.protocol === 'http:' &&
    (['localhost', '127.0.0.1', 'nakama'].includes(base.hostname) || base.hostname.endsWith('.svc.cluster.local')))) {
  throw new Error('NAKAMA_URL must use HTTPS or an internal service/loopback host');
}
const serverKey = process.env.NAKAMA_SERVER_KEY || '';
export const nakamaConfigured = Boolean(serverKey);
export class NakamaError extends Error {
  constructor(status) { super('Nakama request failed'); this.status = status; }
}
async function request(route, body, token = null, method = 'POST') {
  if (!nakamaConfigured) throw new NakamaError(503);
  const response = await fetch(new URL(route, base), {
    method, signal: AbortSignal.timeout(10000), redirect: 'error',
    headers: { Authorization: token ? `Bearer ${token}` : `Basic ${Buffer.from(`${serverKey}:`).toString('base64')}`,
      'Content-Type': 'application/json', Accept: 'application/json' },
    ...(method === 'GET' ? {} : { body: JSON.stringify(body) })
  });
  if (!response.ok) throw new NakamaError(response.status);
  if (response.status === 204) return {};
  const text = await response.text();
  if (text.length > 65536) throw new NakamaError(502);
  return text ? JSON.parse(text) : {};
}
function session(value) {
  if (typeof value.token !== 'string' || typeof value.refresh_token !== 'string') throw new NakamaError(502);
  // Claims below are read only after a successful response from the configured Nakama.
  const claims = JSON.parse(Buffer.from(value.token.split('.')[1], 'base64url'));
  if (typeof claims.uid !== 'string' || !Number.isFinite(claims.exp)) throw new NakamaError(502);
  return { token: value.token, refresh_token: value.refresh_token, user_id: claims.uid,
    expires_at: claims.exp * 1000, created: value.created === true };
}
export async function authenticateGoogle(idToken, existingToken = null) {
  if (existingToken) {
    // Linking requires proof of ownership of the existing game account. Never merge by email/name.
    await request('/v2/account/link/google', { token: idToken }, existingToken);
  }
  return session(await request('/v2/account/authenticate/google?create=true', { token: idToken }));
}
export async function verifyGameAccount(token) {
  const account = await request('/v2/account', null, token, 'GET');
  if (!account.user?.id) throw new NakamaError(401);
  return account.user.id;
}
export async function refreshGameSession(current) {
  return session(await request('/v2/account/session/refresh', { token: current.refresh_token }));
}
export async function logoutGameSession(current) {
  await request('/v2/session/logout', { token: current.token, refresh_token: current.refresh_token }, current.token);
}

export async function authenticateGuest(id, vars) {
  return session(await request('/v2/account/authenticate/custom?create=true', {id,vars}));
}
