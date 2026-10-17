import { decodeHello, decodeHistory, decodeTraceEnvelope } from './decode';
import { decoded } from './gateway-client';
import type { Transport } from './transport';
export class WebClient {
  constructor(private transport: Transport) {}
  hello() {
    return decoded(this.transport, { api: 'web', path: '/api/hello' }, decodeHello);
  }
  trace(after: number, wait = 1, signal?: AbortSignal) {
    return decoded(
      this.transport,
      { api: 'web', path: '/api/gateway/trace', query: { after, wait }, signal, timeoutMs: 35000 },
      decodeTraceEnvelope,
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
