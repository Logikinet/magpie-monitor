import { afterEach, expect, it } from 'vitest';
import { render } from 'preact';
import { decodeTraceEnvelope } from '../../src/core/decode';
import { footSummary, latencyBreakdown, seatStatus } from '../../src/core/routing-model';
import { AgentNav } from '../../src/views/agent/AgentNav';
import { RoutingLog } from '../../src/views/agent/RoutingLog';
import { ContextWaffle } from '../../src/views/agent/ContextWaffle';
import { RoutingStage } from '../../src/views/agent/RoutingStage';
import { RequestList } from '../../src/views/agent/RequestList';
import { t, type Locale } from '../../src/i18n';
import fixture from '../../src/mock/fixtures/trace.json';
const root = document.createElement('div');
const trace = decodeTraceEnvelope(fixture);
const latest = trace.routes.reduce((a, b) => (a.seq > b.seq ? a : b));
afterEach(() => {
  render(null, root);
  localStorage.removeItem('mm-lang');
});

it('renders measured latency segments and the actual cache-read ratio on the latest fixture', () => {
  render(<RoutingLog route={latest} lang="zh" refresh={() => {}} usage={() => {}} />, root);
  expect(root.querySelectorAll('.rt-latency span')).toHaveLength(3);
  const b = latencyBreakdown(latest);
  expect(b.magpie! + b.network! + b.vendor!).toBe(latest.tries!.at(-1)!.ms);
  expect(b.dns).toBeGreaterThan(0);
  render(<ContextWaffle route={latest} lang="zh" />, root);
  expect(root.querySelector('header')?.textContent).toContain(
    `${footSummary(latest).cacheHitPercent!.toFixed(1)}%`,
  );
  expect(root.textContent).toContain('工具定义');
  expect(root.textContent).toContain('src/app.ts');
});

for (const lang of ['zh', 'en', 'ja'] as Locale[]) {
  it(`localizes Agent navigation, context, seats and unpriced requests in ${lang}`, () => {
    localStorage.setItem('mm-lang', lang);
    render(<AgentNav tab="routing" choose={() => {}} />, root);
    expect(root.querySelector('button')?.textContent).toBe(t('agent.tabRouting', {}, lang));
    render(<ContextWaffle route={latest} lang={lang} />, root);
    expect(root.textContent).toContain(t('context.system', {}, lang));
    const route = {
      ...latest,
      done: true,
      tries: latest.tries!.map((tr) => ({ ...tr, done: true, status: 200 })),
    };
    const now = Date.parse(trace.now!);
    render(
      <RoutingStage route={route} routes={[route]} now={now} account={null} filter={() => {}} lang={lang} />,
      root,
    );
    expect(root.querySelector('.rt-accts li.on')?.textContent).toContain(t('route.answered', {}, lang));
    const idle = route.order.find((s) => seatStatus(s, route, now).kind === 'remaining')!;
    const status = seatStatus(idle, route, now);
    expect(root.textContent).toContain(
      t('route.resetDays', { days: Math.ceil(Number(status.params.resetInMs) / 86400000) }, lang),
    );
    render(
      <RequestList
        routes={[latest]}
        todayRoutes={[]}
        selected={latest.seq}
        pinned={false}
        pick={() => {}}
        live={() => {}}
        account={null}
        clear={() => {}}
        lang={lang}
      />,
      root,
    );
    expect(root.querySelector('.rt-requests')?.textContent).toContain(t('usage.unpriced', {}, lang));
  });
}
