export interface Binding { fetch(request: Request): Promise<Response> }
export interface Env {
  MAGPIE_GATEWAY: Binding;
  MAGPIE_WEB: Binding;
  GATEWAY_ORIGIN: string;
  WEB_ORIGIN: string;
  WEB_PORT: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  ACCESS_DISABLED?: string;
}
export interface Dependencies {
  fetchJwks?: typeof fetch;
  now?: () => number;
  timeoutMs?: number;
}
const gateway = new Set(['/v1/magpie/usage', '/v1/magpie/usage/requests', '/v1/magpie/quotas', '/v1/magpie/quotas/cards', '/v1/magpie/quotas/history', '/v1/magpie/route', '/v1/magpie/concurrency', '/v1/magpie/limit', '/api/hello']);
const web = new Set(['/api/gateway/trace', '/api/gateway/history']);
type SigningKey = JsonWebKey & { kid?: string };
// Cache public keys only, scoped to the team and injected fetcher.
const caches = new WeakMap<typeof fetch, Map<string, { until: number; keys: SigningKey[] }>>();
export function secureResponse(response: Response, staticAsset = false): Response {
  const headers = new Headers(response.headers);
  headers.delete('set-cookie');
  for (const name of [...headers.keys()]) if (name.startsWith('access-control-')) headers.delete(name);
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  if (staticAsset) headers.set('Content-Security-Policy', "default-src 'self'; connect-src 'self' https:; img-src 'self' data:; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'");
  else headers.set('Cache-Control', 'no-store');
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}
function error(status: number, message: string): Response {
  return secureResponse(new Response(JSON.stringify({ error: message }), { status, headers: { 'content-type': 'application/json' } }));
}
function decode(part: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(part.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
}
async function authorized(request: Request, env: Env, deps: Dependencies): Promise<boolean> {
  const host = new URL(request.url).hostname;
  if (env.ACCESS_DISABLED === 'true') return host === 'localhost' || host === '127.0.0.1';
  try {
    if (!/^[a-z0-9.-]+\.cloudflareaccess\.com$/i.test(env.ACCESS_TEAM_DOMAIN) || !env.ACCESS_AUD) return false;
    const token = request.headers.get('Cf-Access-Jwt-Assertion') ?? request.headers.get('cookie')?.split(';').map(c => c.trim()).find(c => c.startsWith('CF_Authorization='))?.slice('CF_Authorization='.length);
    if (!token || token.length > 32768) return false;
    const parts = token.split('.');
    if (parts.length !== 3) return false;
    const header = JSON.parse(new TextDecoder().decode(decode(parts[0])));
    const claims = JSON.parse(new TextDecoder().decode(decode(parts[1])));
    const now = (deps.now ?? Date.now)();
    const issuer = `https://${env.ACCESS_TEAM_DOMAIN}`;
    if (header.alg !== 'RS256' || typeof header.kid !== 'string' || claims.iss !== issuer || typeof claims.exp !== 'number' || !Number.isFinite(claims.exp) || claims.exp <= now / 1000 - 60 || (claims.nbf !== undefined && (typeof claims.nbf !== 'number' || !Number.isFinite(claims.nbf) || claims.nbf > now / 1000 + 60))) return false;
    if (!(Array.isArray(claims.aud) ? claims.aud : [claims.aud]).includes(env.ACCESS_AUD)) return false;
    const fetcher = deps.fetchJwks ?? fetch;
    let cache = caches.get(fetcher);
    if (!cache) { cache = new Map(); caches.set(fetcher, cache); }
    let entry = cache.get(issuer);
    if (!entry || entry.until <= now) {
      const response = await fetcher(`${issuer}/cdn-cgi/access/certs`, { redirect: 'error', signal: AbortSignal.timeout(10000) });
      if (!response.ok) return false;
      const data = await response.json() as { keys: SigningKey[] };
      if (!Array.isArray(data.keys)) return false;
      entry = { until: now + 600000, keys: data.keys };
      cache.set(issuer, entry);
    }
    const jwk = entry.keys.find(k => k.kid === header.kid && k.kty === 'RSA' && (!k.alg || k.alg === 'RS256') && (!k.use || k.use === 'sig'));
    if (!jwk) return false;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    return await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, decode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  } catch { return false; }
}
export async function proxy(request: Request, env: Env, deps: Dependencies = {}): Promise<Response> {
  const url = new URL(request.url);
  // URL parsing normalizes literal dot segments; encoded separators and remaining dots are never accepted.
  if (/%|\\|\/\/|(?:^|\/)\.{1,2}(?:\/|$)/.test(url.pathname)) return error(404, 'not_found');
  const match = /^\/proxy\/(gateway|web)(\/.*)$/.exec(url.pathname);
  if (!match || !(match[1] === 'gateway' ? gateway : web).has(match[2])) return error(404, 'not_found');
  if (request.method === 'OPTIONS') return secureResponse(new Response(null, { status: 204 }));
  if (!['GET', 'HEAD'].includes(request.method)) return error(405, 'method_not_allowed');
  if (url.search.length > 2048) return error(400, 'query_too_long');
  if (!await authorized(request, env, deps)) return error(401, 'access_required');
  const isGateway = match[1] === 'gateway';
  const key = request.headers.get(isGateway ? 'X-Magpie-Gateway-Key' : 'X-Magpie-Web-Key');
  if (!key) return error(401, 'missing_key');
  if (key.length > 512 || /[^\x21-\x7e]|[;,]/.test(key)) return error(400, 'invalid_key');
  if (!isGateway && !/^\d{1,5}$/.test(env.WEB_PORT)) return error(502, 'upstream_unreachable');
  const headers = new Headers();
  for (const name of ['accept', 'accept-language', 'if-none-match']) {
    const value = request.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  headers.set(isGateway ? 'Authorization' : 'Cookie', isGateway ? `Bearer ${key}` : `magpie_web_${env.WEB_PORT}=${key}`);
  const rawIp = request.headers.get('CF-Connecting-IP');
  const ip = rawIp && /^[0-9a-f:.]+$/i.test(rawIp) ? rawIp : '0.0.0.0';
  headers.set('X-Forwarded-For', ip);
  headers.set('Forwarded', ip.includes(':') ? `for="[${ip}]"` : `for=${ip}`);
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const target = new URL(match[2] + url.search, isGateway ? env.GATEWAY_ORIGIN : env.WEB_ORIGIN);
    const upstreamRequest = new Request(target, { method: request.method, headers, redirect: 'manual', signal: controller.signal });
    const response = await Promise.race([
      (isGateway ? env.MAGPIE_GATEWAY : env.MAGPIE_WEB).fetch(upstreamRequest),
      new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('timeout')); }, deps.timeoutMs ?? 40000); }),
    ]);
    const resultHeaders = new Headers();
    for (const name of ['content-type', 'cache-control', 'etag', 'content-encoding']) {
      const value = response.headers.get(name);
      if (value !== null) resultHeaders.set(name, value);
    }
    return secureResponse(new Response(request.method === 'HEAD' ? null : response.body, { status: response.status, headers: resultHeaders }));
  } catch { return controller.signal.aborted ? error(504, 'upstream_timeout') : error(502, 'upstream_unreachable'); }
  finally { if (timer !== undefined) clearTimeout(timer); }
}
// Deliberately no logging: neither credentials nor arbitrary paths/query strings reach console.
