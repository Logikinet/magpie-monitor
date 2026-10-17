import type { MagpieError } from './errors';
export type Query = Record<string, string | number | boolean | undefined>;
export interface Request {
    api: 'gateway' | 'web';
    path: string;
    query?: Query;
    signal?: AbortSignal;
    timeoutMs?: number;
}
export interface Transport {
    request(req: Request): Promise<{
        status: number;
        json: unknown;
    }>;
}
export function statusError(status: number): MagpieError { return { kind: status === 401 ? 'unauthorized' : status === 403 ? 'forbidden' : 'badStatus', status }; }
export function queryString(query?: Query) { const params = new URLSearchParams(); for (const [key, value] of Object.entries(query ?? {}))
    if (value !== undefined)
        params.set(key, String(value)); const s = params.toString(); return s ? `?${s}` : ''; }
export function sleep(ms: number, signal?: AbortSignal): Promise<void> { return new Promise((resolve, reject) => { const abort = () => { clearTimeout(timer); signal?.removeEventListener('abort', abort); reject({ kind: 'aborted' }); }; const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve(); }, ms); if (signal?.aborted)
    abort();
else
    signal?.addEventListener('abort', abort, { once: true }); }); }
interface FetchOptions {
    fetch?: typeof fetch;
    gatewayKey?: string;
    webKey?: string;
}
async function fetchJSON(url: string, req: Request, headers: Record<string, string>, fetcher: typeof fetch, direct: boolean) { const controller = new AbortController(); let timedOut = false; const abort = () => controller.abort(); req.signal?.addEventListener('abort', abort, { once: true }); if (req.signal?.aborted)
    abort(); const timer = setTimeout(() => { timedOut = true; controller.abort(); }, req.timeoutMs ?? 15000); try {
    const response = await fetcher(url, { method: 'GET', headers, credentials: 'omit', signal: controller.signal });
    if (!response.ok)
        throw statusError(response.status);
    let json: unknown;
    try {
        json = await response.json();
    }
    catch {
        throw { kind: 'decoding' };
    }
    return { status: response.status, json };
}
catch (err) {
    if (controller.signal.aborted)
        throw { kind: timedOut ? 'timeout' : 'aborted' };
    if (err instanceof TypeError)
        throw { kind: direct ? 'cors' : 'network' };
    throw err;
}
finally {
    clearTimeout(timer);
    req.signal?.removeEventListener('abort', abort);
} }
export class ProxyTransport implements Transport {
    constructor(private options: FetchOptions = {}) { }
    request(req: Request) { const key = req.api === 'gateway' ? this.options.gatewayKey : this.options.webKey; const headers: Record<string, string> = {}; if (key)
        headers[req.api === 'gateway' ? 'X-Magpie-Gateway-Key' : 'X-Magpie-Web-Key'] = key; return fetchJSON(`/proxy/${req.api}${req.path}${queryString(req.query)}`, req, headers, this.options.fetch ?? fetch, false); }
}
export class DirectTransport implements Transport {
    constructor(private profile: {
        gatewayUrl?: string;
    }, private options: FetchOptions & {
        pageProtocol?: string;
    } = {}) { }
    async request(req: Request) { if (req.api === 'web')
        throw { kind: 'badStatus', status: 400 } satisfies MagpieError; let url: URL; try {
        url = new URL(this.profile.gatewayUrl ?? '');
    }
    catch {
        throw { kind: 'network' };
    } if ((this.options.pageProtocol ?? globalThis.location?.protocol) === 'https:' && url.protocol === 'http:')
        throw { kind: 'mixedContent' } satisfies MagpieError; if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password)
        throw { kind: 'network' }; const headers: Record<string, string> = {}; if (this.options.gatewayKey)
        headers.Authorization = `Bearer ${this.options.gatewayKey}`; return fetchJSON(`${url.href.replace(/\/$/, '')}${req.path}${queryString(req.query)}`, req, headers, this.options.fetch ?? fetch, true); }
}
const fixtures = import.meta.glob('../mock/fixtures/*.json', { eager: true, import: 'default' }) as Record<string, unknown>;
export class MockTransport implements Transport {
    private seq = 0;
    constructor(private options: {
        latencyMs?: number;
        traceWaitMs?: number;
    } = {}) { }
    async request(req: Request) { const names: Record<string, string> = { '/api/hello': 'hello', '/v1/magpie/limit': 'hello', '/v1/magpie/usage': 'usage', '/v1/magpie/usage/requests': 'ledger', '/v1/magpie/quotas': 'quotas', '/v1/magpie/quotas/cards': 'quota_cards', '/v1/magpie/concurrency': 'concurrency', '/api/gateway/trace': 'trace', '/v1/magpie/route': 'route' }; const name = names[req.path]; await sleep(req.path === '/api/gateway/trace' ? Math.max(1, this.options.traceWaitMs ?? 1000) : this.options.latencyMs ?? 0, req.signal); if (req.path === '/v1/magpie/quotas/history')
        return { status: 200, json: { data: [] } }; if (req.path === '/api/gateway/history')
        return { status: 200, json: { days: ['2026-10-17'], routes: (fixtures['../mock/fixtures/trace.json'] as {
                    routes: unknown[];
                }).routes, cut: false } }; if (!name)
        throw statusError(404); const json = structuredClone(fixtures[`../mock/fixtures/${name}.json`]) as Record<string, unknown>; if (name === 'trace') {
        this.seq = Math.max(this.seq, Number(req.query?.after) || 0, Number(json.seq) || 0) + 1;
        json.seq = this.seq;
        json.routes = (json.routes as Record<string, unknown>[]).slice(0, 1).map(r => ({ ...r, seq: this.seq }));
    } if (name === 'ledger') {
        const rows = json.rows as unknown[], offset = Math.max(0, Number(req.query?.offset) || 0), limit = Math.max(0, Number(req.query?.limit ?? rows.length));
        json.offset = offset;
        json.total = rows.length;
        json.rows = rows.slice(offset, offset + limit);
    } return { status: 200, json }; }
}
