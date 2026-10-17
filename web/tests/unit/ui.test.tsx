import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { render } from 'preact';
import App, { QuotaCard } from '../../src/app';
import { t } from '../../src/i18n';
import type { QuotaSpan } from '../../src/core/decode';

const root = document.createElement('div');
beforeEach(() => localStorage.setItem('mm-lang', 'zh'));
afterEach(() => {
  render(null, root);
  localStorage.removeItem('mm-lang');
});

describe('quota UI', () => {
  it('shows token consumption and percentage', () => {
    const window: QuotaSpan = {
      name: '5-hour',
      used: 64,
      remaining: 36,
      amount: 1284000,
      unit: 'tokens',
      resetsAt: '2026-10-18T00:00:00Z',
    };
    render(<QuotaCard provider="anthropic" window={window} />, root);
    expect(root.textContent).toContain('已消耗 128.4 万 token');
    expect(root.textContent).toContain('64%');
  });
  it('shows the mock mode badge', () => {
    render(<App />, root);
    expect(root.querySelector('[data-testid="mock-badge"]')?.textContent).toContain(t('app.mock'));
  });
});

import { RoutingView } from '../../src/views/agent/RoutingView';
import { readPage } from '../../src/views/agent/AgentNav';
import { decodeTraceEnvelope } from '../../src/core/decode';
import traceFixture from '../../src/mock/fixtures/trace.json';
import { act } from 'preact/test-utils';

const trace = decodeTraceEnvelope(traceFixture);
describe('routing UI', () => {
  it('highlights the newest mock request, pins older requests and returns to live', async () => {
    await act(() => render(<RoutingView routes={trace.routes} totals={trace.totals} />, root));
    const latest = Math.max(...trace.routes.map((r) => r.seq));
    expect(root.querySelector('[data-current-seq]')?.getAttribute('data-current-seq')).toBe(String(latest));
    expect(root.querySelector('.rt-requests .selected')?.getAttribute('data-seq')).toBe(String(latest));
    expect(root.querySelectorAll('.ctx-cell')).toHaveLength(400);
    const older = root.querySelectorAll<HTMLButtonElement>('.rt-requests button')[1];
    await act(() => older.click());
    expect(root.querySelector('.rt-pin')?.textContent).toContain(`#${older.dataset.seq}`);
    const live = [...root.querySelectorAll<HTMLButtonElement>('button')].find(
      (b) => b.textContent === '回到实时',
    )!;
    await act(() => live.click());
    expect(root.querySelector('.rt-pin')).toBeNull();
    expect(root.querySelector('[data-current-seq]')?.getAttribute('data-current-seq')).toBe(String(latest));
  });
  it('shows missing counts and latency as dashes without legacy fallback numbers', () => {
    render(<RoutingView routes={[{ seq: 1, order: [] }]} />, root);
    expect(root.querySelector('.rt-stats')?.textContent).toBe('请求 —迂回 —错误 —');
    expect(root.querySelector('.rt-stats')?.textContent).not.toMatch(/186|14|3/);
    expect(root.querySelector('.rt-timings')?.textContent).not.toMatch(/DNS|TCP|TLS|发送/);
  });
  it('filters by account and selects the latest failed request', async () => {
    await act(() => render(<RoutingView routes={trace.routes} totals={trace.totals} />, root));
    const account = root.querySelector<HTMLButtonElement>('.rt-accts li[data-seat] button')!;
    await act(() => account.click());
    expect(root.querySelector('.rt-filter')).not.toBeNull();
    const count = root.querySelectorAll('.rt-requests button').length;
    expect(count).toBeLessThan(trace.routes.length);
    await act(() => root.querySelector<HTMLButtonElement>('.rt-filter')!.click());
    expect(root.querySelectorAll('.rt-requests button')).toHaveLength(trace.routes.length);
    await act(() => root.querySelector<HTMLButtonElement>('.rt-stats button')!.click());
    const error = [...trace.routes]
      .sort((a, b) => b.seq - a.seq)
      .find(
        (r) =>
          Number(r.status) >= 400 || r.tries?.some((tr) => tr.fail || tr.error || Number(tr.status) >= 400),
      )!;
    expect(root.querySelector('.rt-pin')?.textContent).toContain(`#${error.seq}`);
  });
  it('supports both hash forms and the old quotas page', () => {
    for (const hash of ['#/agent?atab=usage', '#cat=agent&atab=usage', '#/quotas']) {
      history.replaceState(null, '', hash);
      expect(readPage()).toEqual({ tab: 'agent', atab: 'usage' });
    }
    history.replaceState(null, '', '#/overview');
  });
});
