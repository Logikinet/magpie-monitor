import { useEffect, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { CollectorClient, type RecordData } from '../../core/collector-client';
import { ansiToHtml } from '../../core/ansi';
import { detectLocale, t } from '../../i18n';
const text = (key: string) => t(`collector.${key}`);
export const metric = (v: unknown, suffix = '') =>
  typeof v === 'number' && Number.isFinite(v) ? `${v.toFixed(1).replace(/\.0$/, '')}${suffix}` : '—';
export const gigabytes = (v: unknown) =>
  typeof v === 'number' ? (v / 1073741824).toFixed(v / 1073741824 >= 100 ? 0 : 1) : '—';
export const duration = (v: unknown) =>
  typeof v === 'number'
    ? `${Math.floor(v / 86400)}d ${Math.floor((v % 86400) / 3600)}h ${Math.floor((v % 3600) / 60)}m`
    : '—';
export function loopback(ip?: string) {
  return ip === '::1' || ip?.startsWith('127.');
}
export function portalServices(rows: RecordData[]) {
  const seen = new Set<string>();
  return rows
    .filter((s) => {
      const key = `${s.port}:${s.name}`;
      if (
        !s.port ||
        s.scope === 'system' ||
        s.paused ||
        s.svcctl_paused ||
        loopback(s.ip) ||
        [22000, 5355].includes(s.port) ||
        seen.has(key)
      )
        return false;
      seen.add(key);
      return true;
    })
    .slice(0, 6);
}
function Panel({ children }: { children: ComponentChildren }) {
  return <section class="card collector-panel">{children}</section>;
}
function Chips({
  values,
  selected,
  choose,
  count,
}: {
  values: string[];
  selected: string;
  choose: (s: string) => void;
  count?: (s: string) => number;
}) {
  return (
    <nav class="collector-chips">
      {values.map((v) => (
        <button class="button" aria-pressed={v === selected} onClick={() => choose(v)}>
          {text(v)}
          {count ? ` (${count(v)})` : ''}
        </button>
      ))}
    </nav>
  );
}
function Empty() {
  return <p class="muted">{text('empty')}</p>;
}
export function useCollector(client: CollectorClient | undefined, revision: number) {
  const [data, setData] = useState<RecordData>({}),
    [error, setError] = useState('');
  useEffect(() => {
    setData({});
    setError('');
    if (!client) return;
    const controller = new AbortController();
    const methods = [
      'hello',
      'sys',
      'services',
      'chart',
      'tmux',
      'runtimes',
      'activity',
      'tasks',
      'tailscale',
      'repos',
    ] as const;
    let busy = false;
    const refresh = async () => {
      if (busy || document.hidden) return;
      busy = true;
      const results = await Promise.allSettled(
        methods.map((name) =>
          name === 'services' ? client.services('all', controller.signal) : client[name](controller.signal),
        ),
      );
      if (!controller.signal.aborted) {
        setData((old) => {
          const next = { ...old };
          results.forEach((r, i) => {
            if (r.status === 'fulfilled') next[methods[i]] = r.value;
          });
          return next;
        });
        setError(results.some((r) => r.status === 'rejected') ? t('app.loadFailed') : '');
      }
      busy = false;
    };
    void refresh();
    const timer = setInterval(refresh, 10000);
    document.addEventListener('visibilitychange', refresh);
    return () => {
      controller.abort();
      clearInterval(timer);
      document.removeEventListener('visibilitychange', refresh);
    };
  }, [client, revision]);
  return { data, error };
}
export function HostOverview({ data, navigate }: { data: RecordData; navigate: (s: string) => void }) {
  const sys = data.sys ?? {},
    mem = sys.mem ?? {},
    disk = sys.disk ?? {};
  const values = [
    ['load', sys.loadavg?.map((n: number) => metric(n)).join(' / ') ?? '—', undefined],
    ['cpu', `${metric(sys.cpu_usage, '%')} · ${metric(sys.cpu_count)} ${text('cores')}`, sys.cpu_usage],
    ['memory', `${gigabytes(mem.used)}/${gigabytes(mem.total)} G (${metric(mem.percent, '%')})`, mem.percent],
    [
      'disk',
      `${gigabytes(disk.used)}/${gigabytes(disk.total)} G (${metric(disk.percent, '%')})`,
      disk.percent,
    ],
    ['uptime', duration(sys.uptime), undefined],
  ];
  const services = data.services?.services ?? [],
    sessions = data.tmux?.sessions ?? [];
  return (
    <div class="collector-section">
      <div class="collector-stats">
        {values.map(([label, value, pct]) => (
          <Panel>
            <small>{text(String(label))}</small>
            <strong class={Number(pct) > 90 ? 'bad' : Number(pct) >= 75 ? 'warn' : ''}>{value}</strong>
          </Panel>
        ))}
      </div>
      <Panel>
        <h2>{text('trend')}</h2>
        <HostChart points={data.chart ?? []} />
      </Panel>
      <div class="collector-portals">
        {['activity', 'tmux', 'svc', 'agent'].map((id) => (
          <Panel>
            <header>
              <h2>{id === 'activity' ? text('timeline') : text(id)}</h2>
              <button class="text-button" onClick={() => navigate(id)}>
                {text('viewAll')}
              </button>
            </header>
            {id === 'activity' &&
              (data.activity?.events ?? []).slice(0, 4).map((e: RecordData) => (
                <p>
                  <b>{e.repo}</b> {e.subject}
                  <small>{e.author}</small>
                </p>
              ))}
            {id === 'tmux' &&
              sessions.slice(0, 4).map((s: RecordData) => (
                <p>
                  {s.name} · {s.windows_count} {text('windows')} · {s.main_command}{' '}
                  <span class="badge">
                    {text(s.is_agent ? 'agent' : s.attached ? 'attached' : 'detached')}
                  </span>
                </p>
              ))}
            {id === 'svc' && (
              <>
                <small>
                  {text('running')
                    .replace(
                      '{n}',
                      String(services.filter((s: RecordData) => !s.paused && !s.svcctl_paused).length),
                    )
                    .replace('{total}', String(services.filter((s: RecordData) => s.port).length))}
                </small>
                <div class="service-tiles">
                  {portalServices(services).map((s) => (
                    <p>
                      {s.name} :{s.port}
                      <small>
                        {metric(s.res?.cpu, '%')} · {metric(s.res?.mem_mb, ' M')}
                      </small>
                    </p>
                  ))}
                </div>
              </>
            )}
            {id === 'agent' && <RuntimeQuotas agents={data.runtimes?.agents ?? []} />}
          </Panel>
        ))}
      </div>
    </div>
  );
}
export function HostChart({ points }: { points: RecordData[] }) {
  const samples = points.slice(-24),
    colors = ['#38bdf8', '#4ade80', '#a78bfa', '#fbbf24'];
  if (!samples.length) return <Empty />;
  const loadMax = Math.max(2, ...samples.map((p) => Number(p.load) || 0));
  return (
    <>
      <div class="chart-legend">
        {['cpu', 'memory', 'swap', 'load'].map((key, i) => (
          <span style={{ color: colors[i] }}>{text(key)}</span>
        ))}
      </div>
      <svg
        class="host-chart"
        viewBox="0 0 600 140"
        role="img"
        aria-label={text('trend')}
        preserveAspectRatio="none"
      >
        {[25, 50, 75].map((n) => (
          <g>
            <path d={`M24 ${140 - n * 1.3}H600`} stroke="currentColor" opacity=".15" />
            <text x="0" y={140 - n * 1.3} fill="currentColor" font-size="9">
              {n}
            </text>
          </g>
        ))}
        {['cpu', 'mem', 'swap', 'load'].map((key, k) => {
          const coords = samples.map((p, i) =>
            typeof p[key] === 'number'
              ? [
                  24 + (24 - samples.length + i) * 25,
                  140 - Math.min(100, key === 'load' ? (p[key] / loadMax) * 100 : p[key]) * 1.3,
                ]
              : null,
          );
          return (
            <g>
              {coords.map(
                (p, i) =>
                  p && (
                    <>
                      {i > 0 && coords[i - 1] && (
                        <path
                          d={`M${coords[i - 1]!.join(',')}L${p.join(',')}`}
                          fill="none"
                          stroke={colors[k]}
                          stroke-width="1.8"
                        />
                      )}
                      {samples.length <= 8 && <circle cx={p[0]} cy={p[1]} r="2.5" fill={colors[k]} />}
                    </>
                  ),
              )}
            </g>
          );
        })}
      </svg>
    </>
  );
}
function RuntimeQuotas({ agents }: { agents: RecordData[] }) {
  const rows = agents.filter((a) => a.quota?.buckets?.length).sort((a, b) => b.procs - a.procs);
  return rows.length ? (
    <>
      {rows.map((a) => (
        <div>
          <b>{a.name}</b> · {a.procs} {text('processes')}
          {a.quota.buckets.map((b: RecordData) => (
            <label>
              {b.label} {metric(b.remaining_pct, '%')}
              <meter min={0} max={100} low={15} high={50} optimum={100} value={b.remaining_pct} />
            </label>
          ))}
        </div>
      ))}
    </>
  ) : (
    <Empty />
  );
}
export function ActivityTimeline({ data }: { data: RecordData }) {
  const [filter, setFilter] = useState('all');
  const events: RecordData[] = data.activity?.events ?? [];
  const days = new Map<string, RecordData[]>();
  events
    .filter((e) => filter === 'all' || e.kind === filter || e.origin === filter)
    .forEach((e) => {
      const day = new Date(e.ts * 1000).toLocaleDateString(detectLocale());
      days.set(day, [...(days.get(day) ?? []), e]);
    });
  return (
    <>
      <h1>{text('timeline')}</h1>
      <Chips
        values={['all', 'local']}
        selected={filter}
        choose={setFilter}
        count={(v) => events.filter((e) => v === 'all' || e.kind === v || e.origin === v).length}
      />
      {!events.length && <Empty />}
      {[...days].map(([day, rows]) => (
        <section class="activity-timeline">
          <h2>
            {day} · {rows.length}
          </h2>
          {rows.map((e) => (
            <Panel>
              <small>
                {e.repo} · {e.branch} · {e.short_sha} · {text('local')}
              </small>
              <h3>{e.subject}</h3>
              <p>
                {e.author} · {new Date(e.ts * 1000).toLocaleTimeString(detectLocale())}
              </p>
              {e.files?.slice(0, 8).map((f: RecordData) => (
                <p>
                  {f.status} {f.path}
                </p>
              ))}
            </Panel>
          ))}
        </section>
      ))}
    </>
  );
}
export function ServicesView({ data }: { data: RecordData }) {
  const initial = location.hash.includes('network') ? 'tailscale' : 'all';
  const [scope, setScope] = useState(initial),
    [actions, setActions] = useState(false);
  const rows: RecordData[] = data.services?.services ?? [];
  const matches = (s: RecordData, v: string) =>
    v === 'all' ||
    (v === 'web' ? [80, 443, 3000, 3426, 5173, 8000, 8080, 8787].includes(s.port) : s.scope === v);
  return (
    <>
      <h1>{text('svc')}</h1>
      <Chips
        values={['user', 'web', 'docker', 'system', 'all', 'tasks', 'tailscale']}
        selected={scope}
        choose={setScope}
        count={(v) =>
          v === 'tasks'
            ? (data.tasks?.tasks ?? []).length
            : v === 'tailscale'
              ? (data.tailscale?.peers ?? []).length
              : rows.filter((s) => matches(s, v)).length
        }
      />
      {data.hello?.readonly === false && (
        <label>
          <input
            type="checkbox"
            checked={actions}
            onChange={() => {
              if (actions || confirm(text('confirm'))) setActions(!actions);
            }}
          />
          {text('actions')}
          {actions && <button disabled>{text('unwired')}</button>}
        </label>
      )}
      {scope === 'tasks' ? (
        <div>
          {(data.tasks?.tasks ?? []).map((r: RecordData) => (
            <Panel>
              <h3>
                {r.name} <span class="badge">{r.kind}</span>
              </h3>
              <p>
                {r.scope} · {r.state ?? '—'} · {r.expr ?? r.schedule ?? '—'}
              </p>
              <p>{r.command}</p>
              <small>{r.next ? new Date(Number(r.next) / 1000).toLocaleString(detectLocale()) : '—'}</small>
            </Panel>
          ))}
        </div>
      ) : scope === 'tailscale' ? (
        <>
          <p>{data.tailscale?.backend_state ?? '—'}</p>
          {[data.tailscale?.self, ...(data.tailscale?.peers ?? [])].filter(Boolean).map((r) => (
            <Panel>
              <h3>{r.hostname}</h3>
              <p>
                {r.dns_name} · {r.ips?.join(', ')} · {String(r.online ?? '—')}
              </p>
              <p>
                {r.relay ?? ''} {r.direct === true ? 'direct' : ''}
              </p>
            </Panel>
          ))}
        </>
      ) : (
        <div class="services-table">
          <div class="service-row service-heading">
            {['service', 'port', 'resources', 'detail'].map((k) => (
              <b>{text(k)}</b>
            ))}
          </div>
          {rows
            .filter((s) => matches(s, scope))
            .map((s) => (
              <div class="service-row">
                <div>
                  <b>{s.name}</b> <span class="badge">{s.type}</span>
                </div>
                <div>
                  {s.port ? (
                    <a
                      href={`http://${loopback(s.ip) ? '127.0.0.1' : !s.ip || ['0.0.0.0', '::'].includes(s.ip) ? (data.sys?.hostname ?? location.hostname) : s.ip.includes(':') ? `[${s.ip}]` : s.ip}:${s.port}`}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      :{s.port} ↗
                    </a>
                  ) : (
                    '—'
                  )}
                </div>
                <div>
                  {metric(s.res?.cpu, '%')} · {metric(s.res?.mem_mb, ' M')} · {duration(s.res?.up_sec)}
                </div>
                <div>{s.unit ?? s.cwd ?? s.scope}</div>
              </div>
            ))}
        </div>
      )}
    </>
  );
}
export function RuntimesView({ data, client }: { data: RecordData; client?: CollectorClient }) {
  const [detail, setDetail] = useState<RecordData>(),
    [error, setError] = useState('');
  useEffect(() => {
    setDetail(undefined);
  }, [client]);
  return (
    <>
      <h2>{text('agent')}</h2>
      <p>
        {text('installed')} {metric(data.runtimes?.total_installed)} · {text('processes')}{' '}
        {metric(data.runtimes?.total_running)}
      </p>
      {(data.runtimes?.agents ?? []).map((a: RecordData) => (
        <Panel>
          <button
            class="text-button"
            onClick={() => {
              setError('');
              void client
                ?.runtime(a.id)
                .then(setDetail)
                .catch(() => setError(t('app.loadFailed')));
            }}
          >
            {a.name}
          </button>
          <p>
            {a.version ?? '—'} · {text('installed')} {String(a.installed)} · {metric(a.procs)}{' '}
            {text('processes')}
          </p>
          <RuntimeQuotas agents={[a]} />
        </Panel>
      ))}
      {error && <p role="alert">{error}</p>}
      {detail && (
        <Panel>
          <h3>{detail.name}</h3>
          <p>
            {detail.bin ?? '—'} · {detail.version ?? '—'}
          </p>
          {detail.proc_list?.map((p: RecordData) => (
            <p>
              {p.pid} · {metric(p.cpu_pct, '%')} · {metric(p.mem_mb, ' M')}
            </p>
          ))}
        </Panel>
      )}
    </>
  );
}
export function TmuxView({ data, client }: { data: RecordData; client?: CollectorClient }) {
  const [filter, setFilter] = useState('all'),
    [target, setTarget] = useState('');
  const sessions: RecordData[] = data.tmux?.sessions ?? [],
    summary = data.tmux?.summary ?? {};
  const matches = (s: RecordData, v: string) =>
    v === 'all' ||
    (v === 'agent'
      ? s.is_agent
      : v === 'standalone'
        ? !s.is_agent
        : v === 'resumable'
          ? !!s.goal?.resume_cmd
          : v === 'attached'
            ? !!s.attached
            : !s.attached);
  return (
    <>
      <h1>Tmux</h1>
      <div class="collector-stats">
        {[
          ['sessions', summary.total],
          ['windows', data.tmux ? sessions.reduce((n, s) => n + (s.windows_count ?? 0), 0) : undefined],
          ['panes', summary.panes_total],
          ['attached', `${summary.attached ?? '—'}/${summary.detached ?? '—'}`],
          ['agent', summary.agents],
        ].map(([k, v]) => (
          <Panel>
            <small>{text(String(k))}</small>
            <strong>{v ?? '—'}</strong>
          </Panel>
        ))}
      </div>
      <Chips
        values={['all', 'agent', 'resumable', 'standalone', 'attached', 'detached']}
        selected={filter}
        choose={setFilter}
        count={(v) => sessions.filter((s) => matches(s, v)).length}
      />
      {sessions
        .filter((s) => matches(s, filter))
        .map((s) => (
          <Session session={s} open={setTarget} />
        ))}
      {!sessions.length && <Empty />}
      {target && client && <TerminalSheet client={client} target={target} close={() => setTarget('')} />}
    </>
  );
}
function Session({ session: s, open }: { session: RecordData; open: (s: string) => void }) {
  const [index, setIndex] = useState(0);
  const windows = s.windows ?? [],
    panes = windows[index]?.panes ?? [];
  return (
    <Panel>
      <header>
        <h2>{s.name}</h2>
        <span class="badge">{text(s.attached ? 'attached' : 'detached')}</span>
      </header>
      <div class="collector-chips">
        {windows.map((w: RecordData, i: number) => (
          <button class="button" aria-pressed={index === i} onClick={() => setIndex(i)}>
            {w.name ?? w.index}
          </button>
        ))}
      </div>
      {panes.map((p: RecordData) => (
        <div class="terminal-frame">
          <header>
            <span aria-hidden="true">🔴 🟡 🟢</span>
            <span>{p.command}</span>
            <button class="text-button" onClick={() => open(p.target ?? p.pane)}>
              {text('capture')}
            </button>
          </header>
          <pre>{p.preview?.join('\n') || text('readonly')}</pre>
        </div>
      ))}
    </Panel>
  );
}
function TerminalSheet({
  client,
  target,
  close,
}: {
  client: CollectorClient;
  target: string;
  close: () => void;
}) {
  const [lines, setLines] = useState(300),
    [live, setLive] = useState(true),
    [output, setOutput] = useState(''),
    [error, setError] = useState(''),
    [bottom, setBottom] = useState(true);
  const pre = useRef<HTMLPreElement>(null),
    dialog = useRef<HTMLDialogElement>(null),
    following = useRef(true);
  useEffect(() => {
    dialog.current?.showModal();
    const previous = document.activeElement as HTMLElement;
    return () => previous?.focus();
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    let busy = false;
    const capture = async () => {
      if (document.hidden || busy) return;
      busy = true;
      try {
        const r = await client.capture(target, lines, controller.signal);
        if (!controller.signal.aborted) {
          setOutput(r.text ?? r.raw ?? '');
          setError('');
        }
      } catch {
        if (!controller.signal.aborted) setError(t('app.loadFailed'));
      } finally {
        busy = false;
      }
    };
    void capture();
    const timer = live ? setInterval(capture, 2500) : undefined;
    return () => {
      controller.abort();
      clearInterval(timer);
    };
  }, [client, target, lines, live]);
  useEffect(() => {
    if (pre.current && following.current) pre.current.scrollTop = pre.current.scrollHeight;
  }, [output]);
  return (
    <dialog ref={dialog} class="terminal-sheet" aria-label={`${text('capture')} ${target}`} onCancel={close}>
      <header>
        <b>{target}</b>
        <label>
          <input type="checkbox" checked={live} onChange={() => setLive(!live)} />
          {text('live')}
        </label>
        <label>
          {text('lines')}
          <select value={lines} onChange={(e) => setLines(Number(e.currentTarget.value))}>
            {[100, 300, 1000, 2000].map((n) => (
              <option value={n}>{n}</option>
            ))}
          </select>
        </label>
        <button
          class="button"
          onClick={() => void navigator.clipboard.writeText(output.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, ''))}
        >
          {text('copy')}
        </button>
        <button class="button" onClick={close}>
          {text('close')}
        </button>
      </header>
      {error && <p role="alert">{error}</p>}
      <pre
        ref={pre}
        tabIndex={0}
        onScroll={() => {
          const el = pre.current!;
          following.current = el.scrollHeight - el.scrollTop - el.clientHeight < 30;
          setBottom(following.current);
        }}
        dangerouslySetInnerHTML={{ __html: ansiToHtml(output) }}
      />
      {!bottom && (
        <button
          class="button"
          onClick={() => {
            pre.current!.scrollTop = pre.current!.scrollHeight;
            following.current = true;
            setBottom(true);
          }}
        >
          {text('bottom')}
        </button>
      )}
    </dialog>
  );
}
