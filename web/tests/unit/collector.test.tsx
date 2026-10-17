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
  await act(async () => { await new Promise(resolve => setTimeout(resolve, 30)); });
  expect(root.querySelectorAll('.sidebar nav a')).toHaveLength(5);
  expect(root.querySelector('[data-testid="view-activity"]')).not.toBeNull();
  expect(root.querySelector('.activity-timeline')).not.toBeNull();
  const settings = root.querySelector<HTMLButtonElement>('.top-actions button[aria-label]')!;
  await act(() => settings.click());
  expect(root.querySelector('[data-testid="view-settings"]')).not.toBeNull();
});
