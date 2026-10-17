import { queryString, type Transport, type Query } from './transport';

export type RecordData = Record<string, any>;
// Preserve optional measurements: an absent sample must never become a successful zero.
export function decodeCollector(value: unknown): RecordData {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw { kind: 'decoding' };
  return value as RecordData;
}
export function decodeCollectorList(value: unknown, key: string): RecordData {
  const data = decodeCollector(value);
  if (
    !Array.isArray(data[key]) ||
    data[key].some((row: unknown) => !row || typeof row !== 'object' || Array.isArray(row))
  )
    throw { kind: 'decoding' };
  return data;
}
export function decodeChart(value: unknown): RecordData[] {
  if (
    !Array.isArray(value) ||
    value.some(
      (p) =>
        !p ||
        !Number.isFinite(p.t) ||
        ['cpu', 'mem', 'swap', 'load'].some(
          (k) => p[k] != null && (typeof p[k] !== 'number' || !Number.isFinite(p[k])),
        ),
    )
  )
    throw { kind: 'decoding' };
  return value.slice(-24);
}
export class CollectorClient {
  constructor(
    private transport: Transport,
    private base?: string,
  ) {}
  private async read(path: string, query?: Query, signal?: AbortSignal): Promise<unknown> {
    if (!this.base)
      return (
        await this.transport.request({ api: 'collector', path: `/v1/collector/${path}`, query, signal })
      ).json;
    const url = new URL(this.base);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password)
      throw { kind: 'network' };
    if (location.protocol === 'https:' && url.protocol === 'http:') throw { kind: 'mixedContent' };
    const response = await fetch(`${url.href.replace(/\/$/, '')}/v1/collector/${path}${queryString(query)}`, {
      credentials: 'omit',
      redirect: 'error',
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000),
    });
    if (!response.ok) throw { kind: 'badStatus', status: response.status };
    return response.json();
  }
  async hello(signal?: AbortSignal) {
    return decodeCollector(await this.read('hello', undefined, signal));
  }
  async sys(signal?: AbortSignal) {
    return decodeCollector(await this.read('sys', undefined, signal));
  }
  async services(scope = 'all', signal?: AbortSignal) {
    return decodeCollectorList(await this.read('services', { scope }, signal), 'services');
  }
  async chart(signal?: AbortSignal) {
    return decodeChart(await this.read('chart', { n: 24 }, signal));
  }
  async tmux(signal?: AbortSignal) {
    return decodeCollectorList(await this.read('tmux', undefined, signal), 'sessions');
  }
  async capture(target: string, lines = 300, signal?: AbortSignal) {
    return decodeCollector(await this.read('tmux/capture', { target, lines, ansi: 1 }, signal));
  }
  async runtimes(signal?: AbortSignal) {
    return decodeCollectorList(await this.read('runtimes', undefined, signal), 'agents');
  }
  async runtime(id: string, signal?: AbortSignal) {
    return decodeCollector(await this.read(`runtimes/${encodeURIComponent(id)}`, undefined, signal));
  }
  async tasks(signal?: AbortSignal) {
    return decodeCollectorList(await this.read('tasks', undefined, signal), 'tasks');
  }
  async activity(signal?: AbortSignal) {
    return decodeCollectorList(await this.read('activity', { limit: 200 }, signal), 'events');
  }
  async repos(signal?: AbortSignal) {
    return decodeCollectorList(await this.read('repos', undefined, signal), 'repos');
  }
  async tailscale(signal?: AbortSignal) {
    return decodeCollector(await this.read('tailscale', undefined, signal));
  }
}
