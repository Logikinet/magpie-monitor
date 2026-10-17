import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'preact';
import { act } from 'preact/test-utils';
import { CollectorClient, decodeChart, decodeCollectorList } from '../../src/core/collector-client';
import { MockTransport } from '../../src/core/transport';
import { ansiToHtml, terminalColor } from '../../src/core/ansi';
import {
  ActivityTimeline,
  HostOverview,
  ServicesView,
  TmuxView,
  RuntimesView,
  gigabytes,
  localDayKey,
  portalServices,
} from '../../src/views/collector/CollectorViews';
import { readPage } from '../../src/views/agent/AgentNav';
import { validateProfile, exportProfiles } from '../../src/state/profiles';
const root = document.createElement('div');
afterEach(() => {
  render(null, root);
  history.replaceState(null, '', '/');
  vi.restoreAllMocks();
});
const client = new CollectorClient(new MockTransport());
function localDay(date: Date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}
async function data() {
  return {
    sys: await client.sys(),
    chart: await client.chart(),
    tmux: await client.tmux(),
    services: await client.services(),
    activity: await client.activity(),
    runtimes: await client.runtimes(),
    tasks: await client.tasks(),
    tailscale: await client.tailscale(),
  };
}
describe('collector', () => {
  it('reads every offline endpoint', async () => {
    expect((await client.hello()).readonly).toBe(true);
    expect((await client.repos()).repos).toHaveLength(1);
    expect((await client.runtime('codex')).id).toBe('codex');
    expect((await client.capture('%1')).text).toContain('devbox');
    expect(await data()).toHaveProperty('sys.hostname', 'devbox');
  });
  it('rejects broken lists and retains missing metrics', () => {
    expect(() => decodeChart({})).toThrow();
    expect(() => decodeCollectorList({}, 'services')).toThrow();
    expect(decodeChart([{ t: 1 }])[0].cpu).toBeUndefined();
    expect(gigabytes(1073741824)).toBe('1.0');
    expect(gigabytes(107374182400)).toBe('100');
  });
  it('filters portal listeners before deduplication', () => {
    expect(
      portalServices([
        { name: 'a', port: 80, ip: '127.0.0.1' },
        { name: 'a', port: 80, ip: '0.0.0.0' },
        { name: 'a', port: 80 },
        { name: 'b', port: 90, scope: 'system' },
        { name: 'c', port: 91, paused: true },
      ]),
    ).toHaveLength(1);
  });
  it('escapes terminal HTML and supports indexed colours', () => {
    const html = ansiToHtml('\x1b[38;5;196m<script>alert(1)</script>\x1b[0m');
    expect(html).toContain('rgb(255,0,0)');
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
    expect(terminalColor(232)).toBe('rgb(8,8,8)');
  });
  it.each([
    ['all', 'home'],
    ['goal', 'tmux'],
    ['log', 'svc'],
    ['network', 'svc'],
    ['manage', 'agent'],
    ['tools', 'agent'],
    ['overview', 'home'],
  ])('aliases %s', (alias, page) => {
    history.replaceState(null, '', `#cat=${alias}`);
    expect(readPage().tab).toBe(page);
    history.replaceState(null, '', `#/${alias}`);
    expect(readPage().tab).toBe(page);
  });
  it('stores collector URL in exported profiles without credentials', () => {
    const p = validateProfile({
      id: 'demo',
      name: 'demo',
      mode: 'live',
      refreshSec: 20,
      collectorUrl: 'https://collector.example.com',
    });
    expect(JSON.parse(exportProfiles([p]))[0].collectorUrl).toBe(p.collectorUrl);
    expect(() => validateProfile({ ...p, collectorUrl: 'https://key@example.com' })).toThrow();
  });
  it('renders home, timeline, services, tmux and runtimes from sanitized fixtures', async () => {
    const d = await data();
    for (const view of [
      <HostOverview data={d} navigate={() => {}} />,
      <ActivityTimeline data={d} />,
      <ServicesView data={d} />,
      <TmuxView data={d} client={client} />,
      <RuntimesView data={d} client={client} />,
    ]) {
      await act(() => render(view, root));
      expect(root.textContent?.length).toBeGreaterThan(20);
      expect(root.querySelector('button:not([disabled])')).not.toBeNull();
    }
  });
  it('services filters and tmux window previews work', async () => {
    const d = await data();
    await act(() => render(<ServicesView data={d} />, root));
    expect(root.querySelectorAll('.service-row')).toHaveLength(4);
    await act(() =>
      [...root.querySelectorAll('button')].find((b) => b.textContent?.startsWith('Docker'))!.click(),
    );
    expect(root.querySelectorAll('.service-row')).toHaveLength(2);
    await act(() => render(<TmuxView data={d} client={client} />, root));
    expect(root.querySelector('.terminal-frame pre')?.textContent).toContain('devbox');
  });
});

it('proxy transport never sends magpie keys to the collector', async () => {
  const { ProxyTransport } = await import('../../src/core/transport');
  const fetcher = vi.fn(async () => new Response('{}'));
  await new ProxyTransport({ gatewayKey: 'fake-gateway', webKey: 'fake-web', fetch: fetcher }).request({
    api: 'collector',
    path: '/v1/collector/hello',
  });
  expect(fetcher.mock.calls[0]).toBeDefined();
  const options = (fetcher.mock.calls as unknown as [string, RequestInit][])[0][1];
  expect(options.headers).toEqual({});
});

it('terminal capture polls only while visible and stops on close', async () => {
  vi.useFakeTimers();
  const d = await data();
  const capture = vi.spyOn(client, 'capture');
  const showModal = HTMLDialogElement.prototype.showModal;
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute('open', '');
  };
  try {
    await act(() => render(<TmuxView data={d} client={client} />, root));
    await act(() => root.querySelector<HTMLButtonElement>('.terminal-frame button')!.click());
    expect(capture).toHaveBeenCalledTimes(1);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2500);
    });
    expect(capture).toHaveBeenCalledTimes(2);
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000);
    });
    expect(capture).toHaveBeenCalledTimes(2);
    await act(() =>
      [...root.querySelectorAll<HTMLButtonElement>('.terminal-sheet button')]
        .find((b) => b.textContent === '关闭')!
        .click(),
    );
    expect(root.querySelector('dialog')).toBeNull();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000);
    });
    expect(capture).toHaveBeenCalledTimes(2);
  } finally {
    HTMLDialogElement.prototype.showModal = showModal;
    vi.useRealTimers();
  }
});

it('shows five categories, header settings and the collector activity by default', async () => {
  const { default: App } = await import('../../src/app');
  history.replaceState(null, '', '/?mock=1#/activity');
  await act(async () => {
    render(<App />, root);
    await new Promise((resolve) => setTimeout(resolve, 30));
  });
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 30));
  });
  expect(root.querySelectorAll('.desktop-nav a')).toHaveLength(5);
  expect(root.querySelector('[data-testid="view-activity"]')).not.toBeNull();
  expect(root.querySelector('.activity-timeline')).not.toBeNull();
  const settings = root.querySelector<HTMLButtonElement>('.top-actions button[aria-label]')!;
  await act(() => settings.click());
  expect(root.querySelector('[data-testid="view-settings"]')).not.toBeNull();
});

it('formats durations for all supported languages without inventing missing values', async () => {
  const { duration } = await import('../../src/views/collector/CollectorViews');
  for (const [lang, expected] of [
    ['zh', '1天0时1分'],
    ['en', '1d 0h 1m'],
    ['ja', '1日0時間1分'],
  ]) {
    localStorage.setItem('mm-lang', lang);
    expect(duration(86460)).toBe(expected);
  }
  expect(duration(undefined)).toBe('—');
  localStorage.removeItem('mm-lang');
});

it('renders all activity filters, file truncation, nodes and only supplied diff links', async () => {
  const fixedNow = new Date('2026-10-17T03:30:00Z');
  const probe = new Date('2026-10-16T18:30:00Z');
  expect(localDayKey(probe)).toBe(localDay(probe));
  const d = await data();
  localStorage.setItem('mm-lang', 'zh');
  try {
    await act(() => render(<ActivityTimeline data={d} now={fixedNow} />, root));
    expect(root.querySelectorAll('.collector-chips button')).toHaveLength(7);
    const events = [...d.activity.events].sort((a: { ts: number }, b: { ts: number }) => b.ts - a.ts);
    let published = false;
    const visible = events.filter((e: { auto_publish?: boolean }) => {
      if (!e.auto_publish) return true;
      if (published) return false;
      published = true;
      return true;
    });
    const groups = new Map<string, number>();
    for (const event of visible) {
      const day = localDay(new Date(event.ts * 1000));
      groups.set(day, (groups.get(day) ?? 0) + 1);
    }
    const today = localDay(fixedNow);
    const sections = [...root.querySelectorAll('.activity-timeline')];
    expect(sections).toHaveLength(groups.size);
    [...groups].forEach(([day, count], index) => {
      const heading = sections[index].querySelector('h2')?.textContent ?? '';
      expect(heading).toContain(day);
      expect(heading).toContain(`（${count} 项变更）`);
      expect(heading.includes('今天')).toBe(day === today);
      expect(sections[index].querySelectorAll('.act-node')).toHaveLength(count);
    });
    expect(root.querySelector('.act-spine.first .act-node')).not.toBeNull();
    expect(root.querySelector('.act-spine.last')).not.toBeNull();
    expect(root.querySelector('.commit-files')?.querySelectorAll('p')).toHaveLength(8);
    expect(root.querySelector('.commit-files small')?.textContent).toContain('3');
    expect(root.querySelector('.pii')).not.toBeNull();
    for (const anchor of root.querySelectorAll('a')) {
      expect(d.activity.events.some((e: any) => e.url === anchor.href)).toBe(true);
    }
    await act(() => root.querySelectorAll<HTMLButtonElement>('.collector-chips button')[2].click());
    expect(root.querySelectorAll('.act-node')).toHaveLength(3);
    await act(() => root.querySelectorAll<HTMLButtonElement>('.collector-chips button')[5].click());
    expect(root.querySelectorAll('.act-node')).toHaveLength(3);
  } finally {
    localStorage.removeItem('mm-lang');
  }
});

it('classifies HTTP services from metadata and preserves zero resources', async () => {
  const { isWebService } = await import('../../src/views/collector/CollectorViews');
  expect(isWebService({ port: 5173 })).toBe(false);
  expect(isWebService({ port: 9101, http: true })).toBe(true);
  expect(isWebService({ port: 9101, scheme: 'https' })).toBe(true);
  await act(() =>
    render(
      <ServicesView
        data={{
          services: {
            services: [
              {
                name: 'demo-http',
                port: 9101,
                web: true,
                scope: 'user',
                state: 'active',
                res: { cpu: 0, mem_mb: 0, up_sec: 0 },
              },
              { name: 'demo-socket', port: 5173, scope: 'user', state: 'failed' },
            ],
          },
        }}
      />,
      root,
    ),
  );
  await act(() => root.querySelectorAll<HTMLButtonElement>('.collector-chips button')[1].click());
  expect(root.textContent).toContain('demo-http');
  expect(root.textContent).not.toContain('demo-socket');
  expect(root.textContent).toContain('0% · 0 M · 0天0时0分');
  expect(root.querySelector('.service-dot.active')).not.toBeNull();
  expect(root.querySelectorAll('.service-filters nav')).toHaveLength(2);
});

it('keeps writes hidden unless hello explicitly permits them and copies attach commands', async () => {
  const d = await data();
  const writeText = vi.fn().mockResolvedValue(undefined);
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
  await act(() => render(<TmuxView data={{ ...d, hello: { readonly: true } }} />, root));
  expect(root.querySelectorAll('button[disabled]')).toHaveLength(0);
  const copy = [...root.querySelectorAll<HTMLButtonElement>('button')].find(
    (b) => b.textContent === '复制连接命令',
  )!;
  await act(() => copy.click());
  expect(writeText).toHaveBeenCalledWith('tmux attach-session -t devbox');
  await act(() => render(<TmuxView data={{ ...d, hello: { readonly: false } }} />, root));
  expect(root.querySelectorAll('button[disabled]')).toHaveLength(3);
});

it('ends collector home at portals and locks auto refresh after 500ms', async () => {
  const { default: App } = await import('../../src/app');
  Object.defineProperty(HTMLElement.prototype, 'onpointerdown', {
    configurable: true,
    writable: true,
    value: null,
  });
  history.replaceState(null, '', '/?mock=1#cat=home');
  await act(async () => {
    render(<App />, root);
    await new Promise((resolve) => setTimeout(resolve, 60));
  });
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 30));
  });
  expect(root.querySelectorAll('.collector-portals > section')).toHaveLength(4);
  expect(root.querySelector('.limit-card')).toBeNull();
  expect(root.textContent).toContain('magpie monitor');
  expect(root.querySelectorAll('.desktop-nav a')).toHaveLength(5);
  vi.useFakeTimers();
  try {
    const button = root.querySelector<HTMLButtonElement>('.refresh-button')!;
    await act(() => {
      button.dispatchEvent(new MouseEvent('pointerdown', { button: 0, bubbles: true }));
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(499);
    });
    expect(button.getAttribute('aria-pressed')).toBe('false');
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(button.getAttribute('aria-pressed')).toBe('true');
    expect(root.querySelector('[role=status]')?.textContent).toContain('自动刷新已暂停');
    await act(() => button.click());
    expect(button.getAttribute('aria-pressed')).toBe('true');
  } finally {
    vi.useRealTimers();
  }
});

it('renders runtime status, low quota and persists runtime filters', async () => {
  localStorage.setItem('mm-lang', 'zh');
  localStorage.removeItem('svc-rtf');
  const d = await data();
  await act(() =>
    render(
      <RuntimesView
        data={d}
        gateways={[
          { id: 'fake-gateway', name: 'Gateway', key: { set: true }, models: [{ id: 'sample-chat' }] },
        ]}
      />,
      root,
    ),
  );
  expect(root.querySelectorAll('.runtime-kpis strong')).toHaveLength(5);
  expect(root.querySelector('[role=status]')?.textContent).toContain('12%');
  expect(root.querySelectorAll('.runtime-grid')[0].children).toHaveLength(7);
  expect(root.textContent).toContain('PID 4100');
  expect(root.textContent).toContain('sample-chat');
  expect(root.textContent).toContain('node 22.14.0');
  const none = [...root.querySelectorAll<HTMLButtonElement>('nav button')].find(
    (b) => b.textContent === '未安装',
  )!;
  await act(() => none.click());
  expect(localStorage.getItem('svc-rtf')).toBe('none');
  expect(root.querySelectorAll('.runtime-grid')[0].children).toHaveLength(2);
  await act(() => render(null, root));
  await act(() => render(<RuntimesView data={d} />, root));
  expect(root.querySelectorAll('.runtime-grid')[0].children).toHaveLength(2);
  localStorage.removeItem('svc-rtf');
  localStorage.removeItem('mm-lang');
});
