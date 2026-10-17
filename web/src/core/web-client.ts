import {
  decodeHello,
  decodeHistory,
  decodeTraceEnvelope,
  decodeGroups,
  decodeProviders,
  decodeUsageSummary,
  decodeUsageQuotas,
  decodeRoute,
} from './decode';
import { decoded } from './gateway-client';
import type { Transport } from './transport';
export class WebClient {
  constructor(private transport: Transport) {}
  hello() {
    return decoded(this.transport, { api: 'web', path: '/api/hello' }, decodeHello);
  }
  trace(after: number, wait?: number, signal?: AbortSignal) {
    return decoded(
      this.transport,
      { api: 'web', path: '/api/gateway/trace', query: { after, wait }, signal, timeoutMs: 35000 },
      decodeTraceEnvelope,
    );
  }
  groups() {
    return decoded(this.transport, { api: 'web', path: '/api/groups' }, decodeGroups);
  }
  providers() {
    return decoded(this.transport, { api: 'web', path: '/api/providers' }, decodeProviders);
  }
  usage(period: string) {
    return decoded(this.transport, { api: 'web', path: '/api/usage', query: { period } }, decodeUsageSummary);
  }
  usageQuotas() {
    return decoded(this.transport, { api: 'web', path: '/api/usage/quotas' }, decodeUsageQuotas);
  }
  route(id: string | number, day: string) {
    return decoded(
      this.transport,
      { api: 'web', path: '/api/gateway/route', query: { id, day } },
      decodeRoute,
    );
  }
  history(day: string) {
    return decoded(
      this.transport,
      { api: 'web', path: '/api/gateway/history', query: { day } },
      decodeHistory,
    );
  }
}
