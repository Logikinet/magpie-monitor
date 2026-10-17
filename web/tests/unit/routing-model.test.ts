import { expect, it } from 'vitest';
import { decodeRoute, decodeTry } from '../../src/core/decode';
import {
  AGENT_HUES,
  agentHue,
  contextCells,
  currentRoute,
  errorJumpTarget,
  footSummary,
  groupSeats,
  latencyBreakdown,
  matchSeat,
  recentAgents,
  requestsForAccount,
  seatKey,
  seatState,
  seatStatus,
} from '../../src/core/routing-model';
const route = (v: object = {}) => decodeRoute({ seq: 1, ...v });
const now = Date.parse('2026-10-17T00:00:00Z');
it('selects newest, not routes[0], and falls back to live when pinned is evicted', () => {
  const routes = Array.from({ length: 61 }, (_, seq) => route({ seq }));
  expect(currentRoute(routes)?.seq).toBe(60);
  expect(currentRoute(routes, 2)?.seq).toBe(2);
  expect(currentRoute(routes, 0)?.seq).toBe(60);
  expect(currentRoute([])).toBeNull();
});
it('matches model seats first, falls back to id, and leaves failed or handed-off seats unlit', () => {
  const r = route({
    order: [{ id: 'fake-a', model: 'a' }, { id: 'fake-a', model: 'b' }, { id: 'fake-b' }],
    tries: [
      { id: 'fake-a', model: 'a', done: true, status: 200, fail: 'other' },
      { id: 'fake-a', model: 'b', done: false },
      { id: 'fake-b', done: true, status: 200, gone: true },
    ],
  });
  expect(seatKey(r.order[0])).toBe('fake-a\0a');
  expect(matchSeat(r.order, { id: 'fake-a', model: 'unknown' })).toBe(r.order[0]);
  expect(r.order.map((s) => seatState(s, r, now))).toEqual(['idle', 'trying', 'idle']);
});
it('prioritizes active and answered states over resting and quota, using real reset times', () => {
  const r = route({
    order: [
      {
        id: 'fake-a',
        known: true,
        used: 25,
        renews: ['2026-10-17T02:00:00Z'],
        rest: { until: '2026-10-17T01:00:00Z' },
      },
    ],
    tries: [],
  });
  const s = r.order[0];
  expect(seatStatus(s, r, now).kind).toBe('resting');
  r.tries = [decodeTry({ id: 'fake-a', done: true, status: 200 })];
  expect(seatStatus(s, r, now).kind).toBe('answered');
  r.tries!.push(decodeTry({ id: 'fake-a', done: false }));
  expect(seatStatus(s, r, now).kind).toBe('trying');
  r.tries = [];
  expect(seatStatus(s, r, now + 3600000)).toEqual({
    kind: 'remaining',
    params: { percent: 75, resetInMs: 3600000 },
  });
});
it('keeps every agent hue away from red and hashes unknown names consistently', () => {
  for (const id of [
    ...Object.keys(AGENT_HUES),
    ...Array.from({ length: 100 }, (_, i) => `agent-${i}`),
    'toString',
  ]) {
    const hex = agentHue(id);
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
    const max = Math.max(r, g, b),
      min = Math.min(r, g, b);
    const hue =
      max === r
        ? (((g - b) / (max - min)) * 60 + 360) % 360
        : max === g
          ? ((b - r) / (max - min)) * 60 + 120
          : ((r - g) / (max - min)) * 60 + 240;
    expect(hue > 12 && hue < 345).toBe(true);
    expect(agentHue(id)).toBe(hex);
  }
});
it('groups providers and models, counts availability, filters accounts and finds latest errors', () => {
  const r = route({
    seq: 3,
    order: [
      { id: 'fake-a', provider: 'demo', model: 'm' },
      { id: 'fake-b', provider: 'demo', model: 'm', held: true },
    ],
    tries: [{ id: 'fake-a', done: true, status: 503 }],
  });
  expect(groupSeats(r, now)[0]).toMatchObject({ key: 'demo::m', accounts: 2, available: 1 });
  const routes = [route({ seq: 1, status: 500 }), r, route({ seq: 4, status: 200 })];
  expect(errorJumpTarget(routes)).toBe(r);
  expect(requestsForAccount(routes, 'fake-a')).toEqual([r]);
  expect(requestsForAccount(routes)).toHaveLength(3);
  expect(
    recentAgents(Array.from({ length: 12 }, (_, seq) => route({ seq, agent: `demo-${seq % 4}` }))),
  ).toEqual(['demo-3', 'demo-2', 'demo-1']);
});
it('never fabricates missing metrics or context examples', () => {
  const r = route();
  expect(latencyBreakdown(r)).toEqual({
    total: null,
    ttft: null,
    firstText: null,
    magpie: null,
    network: null,
    vendor: null,
    dns: null,
    tcp: null,
    tls: null,
    send: null,
    stream: null,
    tries: [],
  });
  expect(footSummary(r)).toMatchObject({
    provider: null,
    model: null,
    ms: null,
    tokens: null,
    tokensPerSecond: null,
    cacheHitPercent: null,
    counts: { requests: null, retries: null, errors: null },
  });
  expect(contextCells(r.prompt)).toBeNull();
  expect(seatStatus(route({ order: [{ known: true }] }).order[0], r, now)).toEqual({
    kind: 'ready',
    params: {},
  });
});
it('derives measured timings and proportional context cells', () => {
  const r = route({
    time: '2026-10-17T00:00:00Z',
    ms: 1000,
    ttft: 200,
    firstText: 250,
    out: 80,
    tries: [
      {
        start: '2026-10-17T00:00:00.010Z',
        done: true,
        ms: 990,
        net: { dns: 1, connect: 2, tls: 3, send: 4 },
      },
    ],
    prompt: {
      window: 1000,
      tokens: 500,
      parts: [
        { kind: 'chat', tokens: 250 },
        { kind: 'system', tokens: 250 },
      ],
    },
  });
  expect(latencyBreakdown(r)).toMatchObject({ magpie: 10, network: 10, vendor: 990, stream: 800 });
  expect(footSummary(r).tokensPerSecond).toBe(100);
  const cells = contextCells(r.prompt)!;
  expect(cells).toHaveLength(400);
  expect(cells.slice(0, 100).every((c) => c === 'system')).toBe(true);
  expect(cells.filter((c) => c === 'free')).toHaveLength(200);
  expect(
    contextCells(route({ prompt: { tokens: 500, parts: [{ kind: 'chat', tokens: 500 }] } }).prompt),
  ).toBeNull();
});
