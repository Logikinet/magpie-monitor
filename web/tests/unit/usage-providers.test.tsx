import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from 'preact';
import { act } from 'preact/test-utils';
import { UsageDashboard, UsageView, quotaColor, quotaPace } from '../../src/views/agent/UsageView';
import { ProvidersTable, ProvidersView } from '../../src/views/agent/ProvidersView';
import { decodeProviders, decodeUsageQuotas, decodeUsageSummary } from '../../src/core/decode';
import usage from '../../src/mock/fixtures/usage.json';
import quotas from '../../src/mock/fixtures/usage_quotas.json';
import providers from '../../src/mock/fixtures/providers.json';
const root = document.createElement('div');
const flush = () =>
  act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
const click = async (text: string) => {
  const button = [...root.querySelectorAll('button')].find((b) => b.textContent === text);
  expect(button).toBeTruthy();
  await act(() => button!.click());
};
beforeEach(() => history.replaceState(null, '', '/?lang=en'));
afterEach(() => {
  render(null, root);
  history.replaceState(null, '', '/');
});
const data = decodeUsageSummary(usage),
  quotaData = decodeUsageQuotas(quotas).data;
describe('usage dashboard', () => {
  it('renders measured KPIs, quota details and charts and toggles masking and usage', async () => {
    await act(() =>
      render(
        <UsageDashboard
          data={data}
          quotas={quotaData}
          period="today"
          setPeriod={() => {}}
          refresh={() => {}}
        />,
        root,
      ),
    );
    expect(root.querySelectorAll('.mp-kpis .mp-panel')).toHaveLength(5);
    const kpis = root.querySelectorAll('.mp-kpis strong');
    expect(kpis[2].textContent).toBe('228.7K');
    expect(kpis[3].textContent).toBe('23.6%');
    expect(kpis[4].textContent).toBe('800 ms');
    expect(root.textContent).toContain('1 unpriced');
    expect(root.querySelector('.mp-red')?.textContent).toBe('2 errors');
    expect(root.querySelector('.mp-quota-grid h3')?.textContent).toBe('Antigravity');
    expect(root.querySelector('details')?.open).toBe(false);
    expect(root.querySelector('summary')?.textContent).toBe('1 more accounts');
    expect(root.querySelector('.mp-spark')?.getAttribute('viewBox')).toBe('0 0 200 24');
    expect(root.textContent).toContain('pace');
    expect(root.textContent).toContain('Runs out');
    expect(root.querySelectorAll('.mp-column')).toHaveLength(24);
    expect(root.querySelector('.mp-column')?.getAttribute('title')).toContain('Requests');
    expect(root.querySelectorAll('.mp-breakdown')).toHaveLength(7);
    expect(root.querySelector('a')).toBeNull();
    await click('Hide accounts');
    expect(root.querySelector('.mp-masked')).toBeTruthy();
    const values = () => [...root.querySelectorAll('.mp-window-value')].map((el) => el.textContent);
    expect(values()).toContain('5h80%');
    await click('Used');
    expect(values()).toContain('5h20%');
  });
  it('shows unknown timing without fake values and only links a configured console', async () => {
    await act(() =>
      render(
        <UsageDashboard
          data={{ calls: 1, errors: 0, series: [], models: [] }}
          consoleUrl="https://example.ts.net"
          period="all"
          setPeriod={() => {}}
          refresh={() => {}}
        />,
        root,
      ),
    );
    expect(root.textContent).toContain('100% OK');
    expect(root.querySelectorAll('.mp-kpis strong')[4].textContent).toBe('—');
    expect(root.querySelector('a')?.getAttribute('href')).toBe('https://example.ts.net');
  });
  it('loads periods, reuses their cache across tab entries and refreshes explicitly', async () => {
    const client = {
      usage: vi.fn(async () => data),
      usageQuotas: vi.fn(async () => ({ data: quotaData, bad: 0 })),
    };
    await act(async () => {
      render(<UsageView client={client} />, root);
    });
    expect(client.usage).toHaveBeenCalledWith('today');
    await click('7 days');
    expect(client.usage).toHaveBeenCalledWith('7d');
    await click('Today');
    expect(client.usage).toHaveBeenCalledTimes(2);
    await act(() => render(null, root));
    await act(async () => {
      render(<UsageView client={client} />, root);
    });
    expect(client.usage).toHaveBeenCalledTimes(2);
    await click('Refresh');
    expect(client.usage).toHaveBeenCalledTimes(3);
  });
  it('ignores late responses from a previous period', async () => {
    let resolve!: (v: typeof data) => void;
    const client = {
      usage: vi.fn((p: string) =>
        p === 'today'
          ? new Promise<typeof data>((r) => (resolve = r))
          : Promise.resolve({ ...data, calls: 777 }),
      ),
      usageQuotas: vi.fn(async () => ({ data: quotaData, bad: 0 })),
    };
    await act(() => render(<UsageView client={client} />, root));
    await click('7 days');
    await act(async () => resolve({ ...data, calls: 999 }));
    expect(root.querySelector('.mp-kpis strong')?.textContent).toBe('777');
  });
  it('renders a recoverable fetch failure', async () => {
    const client = {
      usage: vi.fn(async () => {
        throw Error('offline');
      }),
      usageQuotas: vi.fn(async () => ({ data: [], bad: 0 })),
    };
    await act(async () => {
      render(<UsageView client={client} />, root);
    });
    await flush();
    expect(root.querySelector('[role=alert]')?.textContent).toContain('Could not load');
  });
  it('calculates pace and boundary colors', () => {
    expect(
      quotaPace(60, '2026-10-17T00:00:00Z', '2026-10-17T10:00:00Z', Date.parse('2026-10-17T05:00:00Z')),
    ).toBe(10);
    expect(quotaPace(10, 'bad', 'bad')).toBeUndefined();
    expect([15, 50, 51].map((n) => quotaColor(n, false))).toEqual(['#ef4444', '#f59e0b', '#22c55e']);
    expect([85, 50, 49].map((n) => quotaColor(n, true))).toEqual(['#ef4444', '#f59e0b', '#22c55e']);
  });
});
describe('providers', () => {
  it('derives plans, sign-in, masked key and free statuses from data', () => {
    render(<ProvidersTable providers={decodeProviders(providers).providers} />, root);
    expect([...root.querySelectorAll('.mp-pill')].map((p) => p.textContent)).toEqual([
      'Demo standard',
      'Signed in',
      'demo…0000',
      'Free',
    ]);
    expect(root.querySelectorAll('.mp-off')).toHaveLength(1);
    expect(root.textContent).toContain('Signed in as demo-user@example.com');
    expect(root.textContent).toContain('https://example.ts.net · 2 models');
    expect(root.querySelector('.mp-mono')?.textContent).toBe('demo…0000');
    expect(root.querySelectorAll('.mp-agent-icon')).toHaveLength(12);
    expect(root.textContent).not.toContain('SuperGrok');
  });
  it('loads providers and supports retry after failure', async () => {
    const client = {
      providers: vi
        .fn()
        .mockRejectedValueOnce(Error('offline'))
        .mockResolvedValue(decodeProviders(providers)),
    };
    await act(async () => {
      render(<ProvidersView client={client} />, root);
    });
    await flush();
    expect(root.querySelector('[role=alert]')).toBeTruthy();
    await click('Refresh');
    await flush();
    expect(root.querySelector('[role=alert]')).toBeNull();
    expect(root.querySelectorAll('.mp-provider')).toHaveLength(4);
  });
});
