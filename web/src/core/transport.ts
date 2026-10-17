import type { MagpieError } from './errors';
export type Query = Record<string, string | number | boolean | undefined>;
export interface Request {
  api: 'gateway' | 'web' | 'collector';
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
export function statusError(status: number): MagpieError {
  return { kind: status === 401 ? 'unauthorized' : status === 403 ? 'forbidden' : 'badStatus', status };
}
export function queryString(query?: Query) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {}))
    if (value !== undefined) params.set(key, String(value));
  const s = params.toString();
  return s ? `?${s}` : '';
}
export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const abort = () => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      reject({ kind: 'aborted' });
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', abort);
      resolve();
    }, ms);
    if (signal?.aborted) abort();
    else signal?.addEventListener('abort', abort, { once: true });
  });
}
interface FetchOptions {
  fetch?: typeof fetch;
  gatewayKey?: string;
  webKey?: string;
}
async function fetchJSON(
  url: string,
  req: Request,
  headers: Record<string, string>,
  fetcher: typeof fetch,
  direct: boolean,
) {
  const controller = new AbortController();
  let timedOut = false;
  const abort = () => controller.abort();
  req.signal?.addEventListener('abort', abort, { once: true });
  if (req.signal?.aborted) abort();
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, req.timeoutMs ?? 15000);
  try {
    const response = await fetcher(url, {
      method: 'GET',
      headers,
      credentials: 'omit',
      signal: controller.signal,
    });
    if (!response.ok) throw statusError(response.status);
    let json: unknown;
    try {
      json = await response.json();
    } catch {
      throw { kind: 'decoding' };
    }
    return { status: response.status, json };
  } catch (err) {
    if (controller.signal.aborted) throw { kind: timedOut ? 'timeout' : 'aborted' };
    if (err instanceof TypeError) throw { kind: direct ? 'cors' : 'network' };
    throw err;
  } finally {
    clearTimeout(timer);
    req.signal?.removeEventListener('abort', abort);
  }
}
export class ProxyTransport implements Transport {
  constructor(private options: FetchOptions = {}) {}
  request(req: Request) {
    const key = req.api === 'collector' ? undefined : req.api === 'gateway' ? this.options.gatewayKey : this.options.webKey;
    const headers: Record<string, string> = {};
    if (key) headers[req.api === 'gateway' ? 'X-Magpie-Gateway-Key' : 'X-Magpie-Web-Key'] = key;
    return fetchJSON(
      `/proxy/${req.api}${req.path}${queryString(req.query)}`,
      req,
      headers,
      this.options.fetch ?? fetch,
      false,
    );
  }
}
export class DirectTransport implements Transport {
  constructor(
    private profile: {
      gatewayUrl?: string;
    },
    private options: FetchOptions & {
      pageProtocol?: string;
    } = {},
  ) {}
  async request(req: Request) {
    if (req.api === 'web') throw { kind: 'badStatus', status: 400 } satisfies MagpieError;
    let url: URL;
    try {
      url = new URL(this.profile.gatewayUrl ?? '');
    } catch {
      throw { kind: 'network' };
    }
    if ((this.options.pageProtocol ?? globalThis.location?.protocol) === 'https:' && url.protocol === 'http:')
      throw { kind: 'mixedContent' } satisfies MagpieError;
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password)
      throw { kind: 'network' };
    const headers: Record<string, string> = {};
    if (this.options.gatewayKey) headers.Authorization = `Bearer ${this.options.gatewayKey}`;
    return fetchJSON(
      `${url.href.replace(/\/$/, '')}${req.path}${queryString(req.query)}`,
      req,
      headers,
      this.options.fetch ?? fetch,
      true,
    );
  }
}
const fixtures = import.meta.glob('../mock/fixtures/**/*.json', { eager: true, import: 'default' }) as Record<
  string,
  unknown
>;
export class MockTransport implements Transport {
  private seq = 0;
  private traceCalls = 0;
  constructor(
    private options: {
      latencyMs?: number;
      traceWaitMs?: number;
      now?: () => Date;
    } = {},
  ) {}
  private fixtures() {
    const now = (this.options.now?.() ?? new Date()).getTime();
    const all = Object.fromEntries(
      Object.entries(fixtures).map(([key, value]) => [key, structuredClone(value)]),
    ) as Record<string, any>;
    const recordTimes: number[] = [];
    const visit = (value: any): void => {
      if (!value || typeof value !== 'object') return;
      if (Array.isArray(value)) {
        value.forEach(visit);
        return;
      }
      for (const key of ['time', 't']) {
        const n = Date.parse(value[key]);
        if (Number.isFinite(n)) recordTimes.push(n);
      }
      Object.values(value).forEach(visit);
    };
    for (const key of ['ledger', 'usage', 'route']) visit(all[`../mock/fixtures/${key}.json`]);
    const trace = all['../mock/fixtures/trace.json'] as any;
    const newest = trace.routes.reduce((a: any, b: any) => Number(a.seq) > Number(b.seq) ? a : b, trace.routes[0]);
    const latestStart = Date.parse(newest.time);
    const traceOffset = now - 8_000 - latestStart;
    const shiftTrace = (value: any): void => {
      if (!value || typeof value !== 'object') return;
      if (Array.isArray(value)) { value.forEach(shiftTrace); return; }
      for (const [key, item] of Object.entries(value)) {
        if (
          typeof item === 'string' &&
          /^(time|start|now|until|due|renews|usedRenews|day)$/.test(key) &&
          Number.isFinite(Date.parse(item))
        ) {
          const shifted = Date.parse(item) + traceOffset;
          value[key] = key === 'day' ? new Date(shifted).toISOString().slice(0, 10) : new Date(shifted).toISOString();
        }
        else shiftTrace(item);
      }
    };
    shiftTrace(trace);
    trace.now = new Date(now).toISOString();
    const offset = now - 60_000 - Math.max(...recordTimes);
    const shift = (value: any): void => {
      if (!value || typeof value !== 'object') return;
      if (Array.isArray(value)) {
        value.forEach(shift);
        return;
      }
      for (const [key, item] of Object.entries(value)) {
        if (
          typeof item === 'string' &&
          /^(t|time|resetsAt|startsAt|start|at|fitFrom|runsOut|runsOutAt|due|restarts|capBack|usedRenews|sunk|asOf|readAt|until|since|day)$/.test(
            key,
          ) &&
          Number.isFinite(Date.parse(item))
        ) {
          let ms = Date.parse(item) + offset;
          if (key === 'resetsAt') while (ms <= now) ms += 86_400_000;
          value[key] = key === 'day' ? new Date(ms).toISOString().slice(0, 10) : new Date(ms).toISOString();
        } else shift(item);
      }
    };
    Object.entries(all).filter(([key]) => !key.endsWith('/trace.json')).forEach(([, value]) => shift(value));
    return all;
  }
  async request(req: Request) {
    if (req.api === 'collector') {
      const suffix = req.path.replace('/v1/collector/', '');
      const name = suffix.startsWith('runtimes/') ? 'runtime' : suffix.replace('/', '-');
      const json = fixtures[`../mock/fixtures/collector/${name}.json`];
      if (!json) throw statusError(404);
      return { status: 200, json: structuredClone(json) };
    }
    const names: Record<string, string> = {
      '/api/hello': 'hello',
      '/api/groups': 'groups',
      '/api/providers': 'providers',
      '/api/usage': 'usage',
      '/api/usage/quotas': 'usage_quotas',
      '/api/gateway/route': 'trace',
      '/v1/magpie/limit': 'limit',
      '/v1/magpie/usage': 'usage',
      '/v1/magpie/usage/requests': 'ledger',
      '/v1/magpie/quotas': 'quotas',
      '/v1/magpie/quotas/cards': 'quota_cards',
      '/v1/magpie/concurrency': 'concurrency',
      '/api/gateway/trace': 'trace',
      '/v1/magpie/route': 'route',
    };
    const name = names[req.path];
    if (req.path === '/api/gateway/trace' && this.traceCalls++ > 0)
      await sleep(this.options.traceWaitMs ?? 4000, req.signal);
    else await sleep(req.path === '/api/gateway/trace' ? 0 : (this.options.latencyMs ?? 0), req.signal);
    if (req.path === '/v1/magpie/quotas/history') return { status: 200, json: { data: [] } };
    if (req.path === '/api/gateway/history') {
      const shifted = this.fixtures();
      return {
        status: 200,
        json: {
          days: [...new Set((shifted['../mock/fixtures/trace.json'] as any).routes.map((route: any) => route.time.slice(0, 10)))],
          routes: (
            shifted['../mock/fixtures/trace.json'] as {
              routes: unknown[];
            }
          ).routes,
          cut: false,
        },
      };
    }
    if (!name) throw statusError(404);
    const json = this.fixtures()[`../mock/fixtures/${name}.json`] as Record<string, unknown>;
    if (req.path === '/api/gateway/route') {
      const route = (json.routes as Record<string, unknown>[]).find(
        (r) => String(r.id) === String(req.query?.id),
      );
      if (!route) throw statusError(404);
      return { status: 200, json: route };
    }
    if (name === 'trace') {
      const fixtureRoutes = json.routes as Record<string, any>[];
      if (Number(req.query?.after) === 0 && this.traceCalls === 1) {
        const routes = fixtureRoutes.slice().sort((a, b) => Number(a.seq) - Number(b.seq));
        this.seq = Math.max(...routes.map((r) => Number(r.seq)), Number(json.seq) || 0);
        json.seq = this.seq;
        json.routes = routes;
      } else {
        this.seq = Math.max(this.seq, Number(req.query?.after) || 0, Number(json.seq) || 0) + 1;
        const source = fixtureRoutes[this.seq % fixtureRoutes.length];
        json.seq = this.seq;
        json.routes = [
          {
            ...source,
            seq: this.seq,
            id: this.seq + 3500,
            time: new Date((this.options.now?.() ?? new Date()).getTime() - 8_000).toISOString(),
            session: `sess-demo-${String(this.seq).slice(-3)}`,
          },
        ];
      }
    }
    if (name === 'ledger') {
      const rows = json.rows as unknown[],
        offset = Math.max(0, Number(req.query?.offset) || 0),
        limit = Math.max(0, Number(req.query?.limit ?? rows.length));
      json.offset = offset;
      json.total = rows.length;
      json.rows = rows.slice(offset, offset + limit);
    }
    return { status: 200, json };
  }
}
