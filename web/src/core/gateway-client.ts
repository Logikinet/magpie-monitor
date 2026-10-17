import * as d from './decode';
import { statusError, type Transport, type Query, type Request } from './transport';
export async function decoded<T>(transport: Transport, req: Request, decode: (v: unknown) => T): Promise<T> {
  const result = await transport.request(req);
  if (result.status < 200 || result.status >= 300) throw statusError(result.status);
  return decode(result.json);
}
export class GatewayClient {
  constructor(private transport: Transport) {}
  private get<T>(path: string, decode: (v: unknown) => T, query?: Query, options: Partial<Request> = {}) {
    return decoded(this.transport, { ...options, api: 'gateway', path: `/v1/magpie/${path}`, query }, decode);
  }
  hello() {
    return decoded(this.transport, { api: 'web', path: '/api/hello' }, d.decodeHello);
  }
  usage(period: string) {
    return this.get('usage', d.decodeUsageSummary, { period });
  }
  requests(options: { period: string; offset?: number; limit?: number; filters?: Query }) {
    return this.get('usage/requests', d.decodeLedger, {
      ...options.filters,
      period: options.period,
      offset: options.offset,
      limit: options.limit,
    });
  }
  quotas(kept?: boolean) {
    return this.get('quotas', d.decodeQuotas, { kept: kept ? 1 : undefined });
  }
  quotaCards() {
    return this.get('quotas/cards', d.decodeQuotaCards);
  }
  quotaHistory(
    options: {
      days?: number;
      provider?: string;
      user?: string;
    } = {},
  ) {
    return this.get('quotas/history', d.decodeQuotaCard, options);
  }
  route(session: string, after?: number, wait?: number, signal?: AbortSignal) {
    return this.get('route', d.decodeRouteEnvelope, { session, after, wait }, { signal, timeoutMs: 35000 });
  }
  concurrency() {
    return this.get('concurrency', d.decodeConcurrency);
  }
  limit() {
    return this.get('limit', d.decodeLimit);
  }
}
