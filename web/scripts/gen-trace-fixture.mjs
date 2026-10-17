import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const webPath = resolve(root, 'web/src/mock/fixtures/trace.json');
const iosPath = resolve(root, 'ios/Packages/MagpieKit/Sources/MagpieKit/MockData/trace.json');
const trace = JSON.parse(await readFile(webPath, 'utf8'));
const providers = [
  ['demo-claude', 'claude-sonnet'],
  ['demo-codex', 'gpt-code'],
  ['demo-gemini', 'gemini-pro'],
  ['demo-claude', 'claude-opus'],
  ['demo-codex', 'gpt-general'],
  ['demo-gemini', 'gemini-flash'],
];
const base = Date.parse('2026-10-17T08:00:00Z');
const date = (ms) => new Date(base + ms).toISOString();
const partKinds = ['system', 'tools', 'files', 'results', 'chat'];

trace.routes = trace.routes.map((route, i) => {
  const isLive = i === trace.routes.length - 1;
  const failedRoute = i === trace.routes.length - 8;
  const [provider, model] = providers[i % providers.length];
  const elapsed = 600 + ((i * 977) % 13_401);
  const ttft = 180 + ((i * 173) % 2_321);
  const output = 90 + ((i * 137) % 2_100);
  const input = 700 + ((i * 311) % 8_400);
  const cacheRead = i % 3 === 0 ? 0 : (i * 83) % 1_700;
  const reasoning = i % 4 === 0 ? (i * 19) % 220 : 0;
  const seat = route.order.find((s) => s.provider === provider && s.model === model) ?? route.order[0];
  const start = date((i - trace.routes.length + 1) * 90_000);
  const tryStart = date((i - trace.routes.length + 1) * 90_000 + 30);
  const promptTokens = input + cacheRead;
  const parts = partKinds.map((kind, partIndex) => {
    const tokens = Math.floor(promptTokens * [0.12, 0.08, 0.24, 0.16, 0.4][partIndex]);
    return { kind, tokens, items: [{ name: `Demo ${kind}`, tokens, tag: 'sample' }] };
  });
  const tries = isLive
    ? [{ id: seat.id, model, effort: 'medium', start: tryStart, done: false, ttft, firstText: ttft + 20, served: model }]
    : (i % 5 === 0
      ? [
          { id: route.tries?.[0]?.id ?? seat.id, model, effort: 'medium', start, done: true, status: 429, ms: 120 + (i % 180) },
          { id: seat.id, model, effort: 'medium', start: date((i - trace.routes.length + 1) * 90_000 + 130), done: true, status: failedRoute ? 502 : 200, ms: elapsed, ttft, firstText: ttft + 20, flow: Math.max(0, elapsed - ttft), served: model, net: { dns: 8, connect: 12, tls: 15, send: 5 } },
        ]
      : [{ id: seat.id, model, effort: 'medium', start: tryStart, done: true, status: failedRoute ? 502 : 200, ms: elapsed, ttft, firstText: ttft + 20, flow: Math.max(0, elapsed - ttft), served: model, net: { dns: 8, connect: 12, tls: 15, send: 5 } }]);

  route.time = start;
  route.provider = provider;
  route.model = `group/${model}`;
  route.served = model;
  route.tries = tries;
  route.done = !isLive;
  route.status = isLive ? undefined : failedRoute ? 502 : 200;
  route.ms = isLive ? undefined : elapsed;
  route.ttft = ttft;
  route.firstText = ttft + 20;
  route.flow = isLive ? undefined : Math.max(0, elapsed - ttft);
  route.tokens = isLive ? undefined : input + output + reasoning;
  route.out = isLive ? undefined : output;
  route.reasoning = isLive ? undefined : reasoning;
  route.cost = isLive || i % 7 === 0 ? undefined : Number((0.0004 + (i % 19) * 0.00031).toFixed(5));
  route.priced = !isLive && i % 7 !== 0;
  route.unpriced = !route.priced;
  route.usage = [{ provider, model, in: isLive ? input : input, out: isLive ? undefined : output, reasoning: isLive ? undefined : reasoning, cache_read: cacheRead, cache_write: i % 4 ? 0 : 40 + i * 3 }];
  route.prompt = { window: 128000, tokens: promptTokens, counted: true, turns: 2 + (i % 8), parts };
  route.session = 'demo-session';
  route.conv = 'demo-conversation';
  route.folder = 'devbox/sample-project';
  return route;
});
trace.seq = Math.max(...trace.routes.map((r) => r.seq));
trace.now = date(0);
trace.totals = { requests: 40, rerouted: trace.routes.filter((r) => r.tries.length > 1).length, errors: 1 };
const output = `${JSON.stringify(trace, null, 2)}\n`;
await writeFile(webPath, output);
await writeFile(iosPath, output);
