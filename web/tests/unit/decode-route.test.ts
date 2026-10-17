import { expect, it } from 'vitest';
import {
  decodeRoute,
  decodeTraceEnvelope,
  decodeGroups,
  decodeProviders,
  decodeUsageQuotas,
} from '../../src/core/decode';
import { WebClient } from '../../src/core/web-client';
import { MockTransport } from '../../src/core/transport';
import trace from '../../src/mock/fixtures/trace.json';
import groups from '../../src/mock/fixtures/groups.json';
import providers from '../../src/mock/fixtures/providers.json';
import quotas from '../../src/mock/fixtures/usage_quotas.json';

it('decodes the complete sanitized route contract without supplying missing metrics', () => {
  const env = decodeTraceEnvelope(trace);
  expect(env.bad).toBe(0);
  expect(env.routes).toHaveLength(40);
  expect(env.routes.map((r) => r.seq)).toEqual([...env.routes.map((r) => r.seq)].sort((a, b) => a - b));
  const route = env.routes[0];
  expect(route.group).toMatchObject({ routing: 'usage', members: groups.groups[0].members, via: ['demo'] });
  expect(route.group?.subs[0]).toMatchObject({ id: 'backup', in: 'demo' });
  expect(route.order).toHaveLength(18);
  expect(route.order[2].rest?.status).toBe(429);
  expect(route.order.at(-1)?.fallback).toBe(true);
  expect(route.tries).toHaveLength(2);
  expect(route.prompt?.parts.map((p) => p.kind)).toEqual(['system', 'tools', 'files', 'results', 'chat']);
  expect(route.prompt?.parts[0].items[0]).toMatchObject({ tokens: 1000, n: 1 });
  expect(route).toMatchObject({ ttft: 340, firstText: 360, flow: 1440, ms: 1800, cost: 0.003, done: true });
  const newest = env.routes.at(-1)!;
  expect(newest.done).toBe(false);
  expect(newest.ms).toBeUndefined();
  expect(newest.cost).toBeUndefined();
});
it('accepts scalar drift and drops malformed optional nested objects and array children', () => {
  const route = decodeRoute({
    seq: '2',
    done: 'false',
    ms: '15',
    prompt: 7,
    group: [],
    order: [null, { id: 3, used: '23', rest: false }],
    tries: [false, { status: '503', done: 1, net: { connect: '4', reused: 'true' } }],
  });
  expect(route).toMatchObject({
    seq: 2,
    done: false,
    ms: 15,
    order: [{ id: '3', used: 23 }],
    tries: [{ status: 503, done: true, net: { connect: 4, reused: true } }],
  });
  expect(route.prompt).toBeUndefined();
  expect(route.group).toBeUndefined();
  expect(() => decodeRoute({ seq: 'no' })).toThrow();
});
it('decodes groups and pools using the upstream field names', () => {
  const result = decodeGroups(groups);
  expect(result.bad).toBe(0);
  expect(result.pools[0]).toMatchObject({
    provider: 'demo-claude',
    kind: 'account',
    who: ['demo-user@example.com', 'ops@example.com', 'builder@example.com'],
  });
});
it('retains masked provider keys and discards raw credentials and unknown fields', () => {
  const result = decodeProviders({
    providers: [
      null,
      {
        ...providers.providers[0],
        secret: 'raw-secret',
        anonKey: 'raw-anon',
        key: { masked: 'demo…0000', set: true, raw: 'raw-key' },
        keyList: [{ masked: 'demo…0000', secret: 'raw-list-key' }],
      },
    ],
  });
  expect(result.bad).toBe(1);
  expect(result.providers[0].key).toEqual({ masked: 'demo…0000', set: true });
  expect(JSON.stringify(result)).not.toContain('raw-');
});
it('decodes bare quota arrays, structured holds and vendor history', () => {
  const result = decodeUsageQuotas(quotas);
  expect(result.bad).toBe(0);
  expect(result.data[0].windows[0]).toMatchObject({
    runsOut: 7200,
    holds: { tokens: 20000, routed: { calls: 10, tokens: 7000 } },
  });
  expect(result.data[0]).toMatchObject({
    resets: { count: 2 },
    daily: { days: [{ used: 12 }] },
    checkin: { outcome: 'ok' },
    balanceTrend: { perDay: 2, points: [{ amount: 25 }] },
  });
});
it('serves new web endpoints through the mock transport, including one route by id', async () => {
  const web = new WebClient(new MockTransport());
  expect((await web.groups()).groups).toHaveLength(1);
  expect((await web.providers()).providers).toHaveLength(3);
  expect((await web.usage('today')).calls).toBeDefined();
  expect((await web.usageQuotas()).data).toHaveLength(1);
  expect(await web.route(4039, '2026-10-17')).toMatchObject({ id: '4039', seq: 640, done: false });
  await expect(web.route(9999, '2026-10-17')).rejects.toMatchObject({ kind: 'badStatus', status: 404 });
});

it('sends web endpoint parameters without triggering an asked refresh', async () => {
  const requests: import('../../src/core/transport').Request[] = [];
  const web = new WebClient({
    request: async (req) => {
      requests.push(req);
      return {
        status: 200,
        json: req.path.endsWith('/quotas') ? [] : req.path.endsWith('/route') ? { seq: 1 } : {},
      };
    },
  });
  await web.trace(0);
  await web.trace(12, 1);
  await web.groups();
  await web.providers();
  await web.usage('7d');
  await web.usageQuotas();
  await web.route(4039, '2026-10-17');
  expect(requests.map((r) => [r.api, r.path, r.query])).toEqual([
    ['web', '/api/gateway/trace', { after: 0, wait: undefined }],
    ['web', '/api/gateway/trace', { after: 12, wait: 1 }],
    ['web', '/api/groups', undefined],
    ['web', '/api/providers', undefined],
    ['web', '/api/usage', { period: '7d' }],
    ['web', '/api/usage/quotas', undefined],
    ['web', '/api/gateway/route', { id: 4039, day: '2026-10-17' }],
  ]);
});
