// @vitest-environment node
import { beforeAll, afterEach, describe, expect, it, vi } from 'vitest';
import { proxy, type Env } from './proxy';
import worker from './index';
const upstream = vi.fn(async (_request: Request) => new Response('stream', { headers: { 'content-type': 'application/json', 'set-cookie': 'secret', 'access-control-allow-origin': '*', 'x-private': 'secret' } }));
const env: Env = {
  MAGPIE_GATEWAY: { fetch: upstream }, MAGPIE_WEB: { fetch: upstream },
  GATEWAY_ORIGIN: 'http://127.0.0.1:3425', WEB_ORIGIN: 'http://127.0.0.1:3426', WEB_PORT: '3426',
  ACCESS_TEAM_DOMAIN: 'test.cloudflareaccess.com', ACCESS_AUD: 'test-aud', ACCESS_DISABLED: 'true',
};
function request(path = '/proxy/gateway/api/hello', headers: HeadersInit = {}, method = 'GET', host = 'localhost') {
  return new Request(`http://${host}${path}`, { method, headers: { 'X-Magpie-Gateway-Key': 'gateway-secret', 'X-Magpie-Web-Key': 'web-secret', ...headers } });
}
afterEach(() => { vi.clearAllMocks(); vi.useRealTimers(); });
describe('proxy routing and credentials', () => {
  it.each(['/v1/magpie/usage', '/v1/magpie/usage/requests', '/v1/magpie/quotas', '/v1/magpie/quotas/cards', '/v1/magpie/quotas/history', '/v1/magpie/route', '/v1/magpie/concurrency', '/v1/magpie/limit', '/api/hello'])('allows %s', async path => {
    expect((await proxy(request(`/proxy/gateway${path}?limit=2`), env)).status).toBe(200);
    expect(upstream.mock.calls[0][0].url).toBe(`http://127.0.0.1:3425${path}?limit=2`);
  });
  it.each(['/proxy/gateway/api/no', '/proxy/web/api/hello', '/proxy/gateway//api/hello', '/proxy/gateway/api%2fhello', '/proxy/gateway/%252e/api/hello', '/proxy/gateway/../api/hello'])('rejects %s', async path => {
    expect((await proxy(request(path), env)).status).toBe(404); expect(upstream).not.toHaveBeenCalled();
  });
  it('handles methods and query limits', async () => {
    expect((await proxy(request(undefined, {}, 'POST'), env)).status).toBe(405);
    const options = await proxy(request(undefined, {}, 'OPTIONS'), env);
    expect(options.status).toBe(204); expect(options.headers.has('access-control-allow-origin')).toBe(false);
    expect((await proxy(request('/proxy/gateway/api/hello?' + 'a'.repeat(2048)), env)).status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });
  it('rebuilds headers and strips upstream secrets', async () => {
    const response = await proxy(request(undefined, { Cookie: 'CF_Authorization=jwt; secret=cookie', Authorization: 'incoming-secret', CF_Authorization: 'secret', 'cf-other': 'secret', 'x-forwarded-for': 'spoofed', 'CF-Connecting-IP': '192.0.2.1', accept: 'application/json', 'accept-language': 'zh', 'if-none-match': 'tag' }), env);
    const headers = upstream.mock.calls[0][0].headers;
    expect(Object.fromEntries(headers)).toEqual({ accept: 'application/json', 'accept-language': 'zh', 'if-none-match': 'tag', authorization: 'Bearer gateway-secret', forwarded: 'for=192.0.2.1', 'x-forwarded-for': '192.0.2.1' });
    expect(response.headers.has('set-cookie')).toBe(false); expect(response.headers.has('access-control-allow-origin')).toBe(false); expect(response.headers.has('x-private')).toBe(false);
    expect(response.headers.get('cache-control')).toBe('no-store'); expect(await response.text()).toBe('stream');
  });
  it.each(['trace', 'history'])('converts web key for %s', async path => {
    await proxy(request(`/proxy/web/api/gateway/${path}`), env);
    const headers = upstream.mock.calls[0][0].headers;
    expect(headers.get('cookie')).toBe('magpie_web_3426=web-secret'); expect(headers.has('authorization')).toBe(false);
    expect(headers.get('x-forwarded-for')).toBe('0.0.0.0'); expect(headers.get('forwarded')).toBe('for=0.0.0.0');
  });
  it('handles HEAD without a body', async () => {
    const response = await proxy(request(undefined, {}, 'HEAD'), env); expect(response.body).toBeNull(); expect(upstream.mock.calls[0][0].method).toBe('HEAD');
  });
  it('requires a key before calling upstream', async () => {
    const req = request(); req.headers.delete('X-Magpie-Gateway-Key');
    const response = await proxy(req, env); expect(response.status).toBe(401); expect(await response.json()).toEqual({ error: 'missing_key' }); expect(upstream).not.toHaveBeenCalled();
  });
  it.each(['a;b', 'a,b', 'a b', 'a'.repeat(513), 'é'])('rejects invalid key %s', async key => {
    expect((await proxy(request(undefined, { 'X-Magpie-Gateway-Key': key }), env)).status).toBe(400); expect(upstream).not.toHaveBeenCalled();
  });
  it('refuses a remote Access bypass', async () => {
    expect((await proxy(request(undefined, {}, 'GET', 'magpie.example.com'), env)).status).toBe(401); expect(upstream).not.toHaveBeenCalled();
  });
  it('maps upstream failures without logging secrets', async () => {
    const log = vi.spyOn(console, 'log'); const warn = vi.spyOn(console, 'warn'); const err = vi.spyOn(console, 'error');
    upstream.mockRejectedValueOnce(new Error('gateway-secret web-secret'));
    expect((await proxy(request(), env)).status).toBe(502);
    expect([log.mock.calls, warn.mock.calls, err.mock.calls].flat()).toEqual([]);
    log.mockRestore(); warn.mockRestore(); err.mockRestore();
  });
  it('times out and aborts an upstream that never resolves', async () => {
    vi.useFakeTimers(); upstream.mockImplementationOnce(() => new Promise(() => {}));
    const pending = proxy(request(), env); await vi.advanceTimersByTimeAsync(40000);
    expect((await pending).status).toBe(504); expect(upstream.mock.calls[0][0].signal.aborted).toBe(true);
  });
  it('secures static assets', async () => {
    const assets = vi.fn(async () => new Response('asset'));
    const response = await worker.fetch(new Request('http://localhost/settings'), { ...env, ASSETS: { fetch: assets } }, {} as ExecutionContext);
    expect(assets).toHaveBeenCalledOnce(); expect(response.headers.get('content-security-policy')).toContain("frame-ancestors 'none'"); expect(response.headers.get('permissions-policy')).toContain('camera=()'); expect(response.headers.get('x-content-type-options')).toBe('nosniff');
  });
});
describe('Access JWT verification', () => {
  let pair: CryptoKeyPair; let jwk: JsonWebKey;
  const now = 1800000000000;
  const secureEnv = { ...env, ACCESS_DISABLED: undefined };
  beforeAll(async () => {
    pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
    jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  });
  function encode(value: unknown) { return btoa(JSON.stringify(value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_'); }
  async function token(overrides = {}) {
    const data = `${encode({ alg: 'RS256', kid: 'test-key' })}.${encode({ iss: 'https://test.cloudflareaccess.com', aud: ['test-aud'], exp: now / 1000 + 300, nbf: now / 1000 - 10, ...overrides })}`;
    const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(data));
    return `${data}.${btoa(String.fromCharCode(...new Uint8Array(signature))).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')}`;
  }
  function dependencies() { return { now: () => now, fetchJwks: vi.fn(async () => Response.json({ keys: [{ ...jwk, kid: 'test-key' }] })) as unknown as typeof fetch }; }
  it('accepts a signed header or cookie and caches JWKS for ten minutes', async () => {
    const jwt = await token(); const deps = dependencies();
    expect((await proxy(request(undefined, { 'Cf-Access-Jwt-Assertion': jwt }), secureEnv, deps)).status).toBe(200);
    expect((await proxy(request(undefined, { Cookie: `CF_Authorization=${jwt}` }), secureEnv, deps)).status).toBe(200);
    expect(deps.fetchJwks).toHaveBeenCalledTimes(1);
    await proxy(request(undefined, { 'Cf-Access-Jwt-Assertion': await token({ exp: now / 1000 + 2000 }) }), secureEnv, { ...deps, now: () => now + 600001 });
    expect(deps.fetchJwks).toHaveBeenCalledTimes(2);
  });
  it.each([{ exp: now / 1000 - 61 }, { aud: ['wrong'] }, { iss: 'https://wrong.cloudflareaccess.com' }, { nbf: now / 1000 + 61 }])('rejects claims %j', async claims => {
    const response = await proxy(request(undefined, { 'Cf-Access-Jwt-Assertion': await token(claims) }), secureEnv, dependencies());
    expect(response.status).toBe(401); expect(await response.json()).toEqual({ error: 'access_required' }); expect(upstream).not.toHaveBeenCalled();
  });
  it('rejects missing, malformed and invalid signatures', async () => {
    const signed = await token(); const parts = signed.split('.'); parts[2] = 'AAAA';
    for (const jwt of ['', 'not-a-jwt', parts.join('.')]) {
      expect((await proxy(request(undefined, { 'Cf-Access-Jwt-Assertion': jwt }), secureEnv, dependencies())).status).toBe(401);
    }
    expect(upstream).not.toHaveBeenCalled();
  });
});
