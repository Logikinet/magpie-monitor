import { useEffect, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { CollectorClient, type RecordData } from '../../core/collector-client';
import { ansiToHtml } from '../../core/ansi';
import { fmtRelative } from '../../core/format';
import { detectLocale, t } from '../../i18n';
const text = (key: string) => t(`collector.${key}`);
export const metric = (v: unknown, suffix = '') =>
  typeof v === 'number' && Number.isFinite(v) ? `${v.toFixed(1).replace(/\.0$/, '')}${suffix}` : '—';
export const gigabytes = (v: unknown) =>
  typeof v === 'number' ? (v / 1073741824).toFixed(v / 1073741824 >= 100 ? 0 : 1) : '—';
export const duration = (v: unknown) => {
  if (typeof v !== 'number' || !Number.isFinite(v)) return '—';
  const locale = detectLocale(),
    n = new Intl.NumberFormat(locale);
  const units =
    locale === 'zh' ? ['天', '时', '分'] : locale === 'ja' ? ['日', '時間', '分'] : ['d ', 'h ', 'm'];
  return [Math.floor(v / 86400), Math.floor((v % 86400) / 3600), Math.floor((v % 3600) / 60)]
    .map((x, i) => n.format(x) + units[i])
    .join('');
};
export function repoColor(repo = '') {
  return `hsl(${Array.from(repo).reduce((n, c) => (n * 31 + c.charCodeAt(0)) % 360, 0)} 58% 62%)`;
}
export function hasImage(e: RecordData) {
  return (
    !!e.image ||
    (e.files ?? []).some((f: RecordData) => /\.(png|jpe?g|gif|webp|svg|avif)$/i.test(f.path ?? ''))
  );
}
export function activityMatches(e: RecordData, filter: string) {
  if (filter === 'all') return true;
  if (filter === 'img') return hasImage(e);
  if (filter === 'done') return e.src === 'done' || e.kind === 'complete';
  return e.kind === filter || e.origin === filter || e.src === filter;
}
export function isWebService(s: RecordData) {
  return (
    !!s.port &&
    (s.web === true ||
      s.http === true ||
      ['http', 'https'].includes(s.scheme) ||
      /^https?:\/\//.test(s.url ?? ''))
  );
}
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
export function useCollector(client: CollectorClient | undefined, revision: number, locked = false) {
  const lock = useRef(locked);
  lock.current = locked;
  const [loading, setLoading] = useState(false);
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
      setLoading(true);
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
      if (!controller.signal.aborted) setLoading(false);
    };
    const autoRefresh = () => {
      if (!lock.current) void refresh();
    };
    void refresh();
    const timer = setInterval(autoRefresh, 10000);
    document.addEventListener('visibilitychange', autoRefresh);
    return () => {
      controller.abort();
      clearInterval(timer);
      document.removeEventListener('visibilitychange', autoRefresh);
    };
  }, [client, revision]);
  return { data, error, loading };
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
            {id === 'activity' && (
              <span class="badge">{t('collector.recent', { n: (data.activity?.events ?? []).length })}</span>
            )}
            {id === 'activity' &&
              (data.activity?.events ?? []).slice(0, 4).map((e: RecordData) => (
                <p>
                  <b style={{ color: repoColor(e.repo) }}>● {e.repo}</b>{' '}
                  {hasImage(e) && <span aria-label={text('img')}>▧ </span>}
                  {e.subject}
                  <small>
                    <span class="pii">{e.author}</span> · {fmtRelative(new Date(e.ts * 1000).toISOString())}
                  </small>
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
                      String(
                        services.filter(
                          (s: RecordData) =>
                            s.port &&
                            !s.paused &&
                            !s.svcctl_paused &&
                            s.state !== 'failed' &&
                            s.state !== 'inactive',
                        ).length,
                      ),
                    )
                    .replace(
                      '{total}',
                      String(
                        new Set(
                          services
                            .filter((s: RecordData) => s.port)
                            .map((s: RecordData) => `${s.ip ?? ''}:${s.port}`),
                        ).size,
                      ),
                    )}
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
    colors = ['var(--ch-cpu)', 'var(--ch-mem)', 'var(--ch-swap)', 'var(--ch-load)'];
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
              {b.label === 'primary'
                ? '5h'
                : ['secondary', 'Weekly'].includes(b.label)
                  ? t('quota.week')
                  : b.label}{' '}
              {metric(b.remaining_pct, '%')}
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
  const [filter, setFilter] = useState('all'),
    [autoPublish, setAutoPublish] = useState(false);
  const events: RecordData[] = [...(data.activity?.events ?? [])].sort((a, b) => b.ts - a.ts);
  let published = false;
  const visible = events.filter((e) => {
    if (!e.auto_publish || autoPublish) return true;
    if (published) return false;
    published = true;
    return true;
  });
  const dayKey = (date: Date) =>
    new Intl.DateTimeFormat('sv-SE', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
  const days = new Map<string, RecordData[]>();
  visible
    .filter((e) => activityMatches(e, filter))
    .forEach((e) => {
      const day = dayKey(new Date(e.ts * 1000));
      days.set(day, [...(days.get(day) ?? []), e]);
    });
  return (
    <>
      <h1>{text('timeline')}</h1>
      <div class="activity-toolbar">
        <Chips
          values={['all', 'commit', 'img', 'both', 'local', 'done', 'watchdog']}
          selected={filter}
          choose={setFilter}
          count={(v) => visible.filter((e) => activityMatches(e, v)).length}
        />
        <label>
          <input type="checkbox" checked={autoPublish} onChange={() => setAutoPublish(!autoPublish)} />
          {text('autoPublish')}
        </label>
      </div>
      {!days.size && <Empty />}
      {[...days].map(([day, rows]) => (
        <section class="activity-timeline">
          <h2>
            {day} ·{' '}
            {day === dayKey(new Date())
              ? text('today')
              : new Intl.DateTimeFormat(detectLocale(), { weekday: 'long' }).format(
                  new Date(rows[0].ts * 1000),
                )}
            {t('collector.changes', { n: rows.length })}
          </h2>
          {rows.map((e, i) => (
            <div class={`act-spine ${i === 0 ? 'first' : ''} ${i === rows.length - 1 ? 'last' : 'mid'}`}>
              <span class="act-node" />
              <Panel>
                <div class="commit-meta">
                  <span class="badge" style={{ color: repoColor(e.repo) }}>
                    {e.repo}
                  </span>{' '}
                  <code>{e.short_sha ?? e.sha?.slice(0, 7)}</code> <span>{e.branch}</span>{' '}
                  <span class="badge">{text(e.origin ?? 'local')}</span>{' '}
                  {hasImage(e) && <span class="badge">▧ {text('img')}</span>}
                </div>
                <h3>{e.subject ?? e.title}</h3>
                <p>
                  <span class="pii">{e.author}</span> ·{' '}
                  <time>
                    {new Intl.DateTimeFormat(detectLocale(), { hour: '2-digit', minute: '2-digit' }).format(
                      new Date(e.ts * 1000),
                    )}
                  </time>
                </p>
                {!!e.files?.length && (
                  <div class="commit-files">
                    {e.files.slice(0, 8).map((f: RecordData) => (
                      <p>
                        <b class={`file-${f.status}`}>{f.status}</b> {f.path}
                      </p>
                    ))}
                    {e.files.length > 8 && (
                      <small>{t('collector.moreFiles', { n: e.files.length - 8 })}</small>
                    )}
                  </div>
                )}
                {e.url && /^https:\/\/github\.com\//.test(e.url) && (
                  <a href={e.url} target="_blank" rel="noopener noreferrer">
                    {text('githubDiff')} ↗
                  </a>
                )}
              </Panel>
            </div>
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
    v === 'all' || (v === 'web' ? isWebService(s) : s.scope === v);
  return (
    <>
      <h1>{text('svc')}</h1>
      <div class="service-filters">
        <Chips
          values={['user', 'web', 'docker', 'system', 'all']}
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
        <Chips values={['tasks', 'tailscale']} selected={scope} choose={setScope} />
      </div>
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
                  <span
                    class={`service-dot ${s.paused || s.svcctl_paused ? 'paused' : (s.state ?? 'unknown')}`}
                    aria-label={text(
                      s.paused ? 'paused' : s.state === 'running' ? 'runningState' : (s.state ?? 'unknown'),
                    )}
                  />{' '}
                  <b>{s.name}</b> <span class="badge">{s.type}</span>
                </div>
                <div>
                  {s.port ? (
                    <a
                      href={`${s.scheme === 'https' ? 'https' : 'http'}://${loopback(s.ip) ? '127.0.0.1' : !s.ip || ['0.0.0.0', '::'].includes(s.ip) ? (data.sys?.hostname ?? location.hostname) : s.ip.includes(':') ? `[${s.ip}]` : s.ip}:${s.port}`}
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
export function RuntimesView({
  data,
  client,
  gateways = [],
}: {
  data: RecordData;
  client?: CollectorClient;
  gateways?: RecordData[];
}) {
  const filters = ['all', 'run', 'tasks', 'quota', 'none'];
  const [filter, setFilter] = useState(() => {
    const saved = localStorage.getItem('svc-rtf') ?? 'all';
    return filters.includes(saved) ? saved : 'all';
  });
  const [detail, setDetail] = useState<RecordData>(),
    [error, setError] = useState('');
  useEffect(() => {
    setDetail(undefined);
  }, [client]);
  const tr = (key: string, params = {}) => t(`runtime.${key}`, params);
  const agents: RecordData[] = data.runtimes?.agents ?? [];
  const tasks = (a: RecordData): RecordData[] => a.tasks ?? [];
  const active = (a: RecordData) =>
    tasks(a).filter((x) => !['done', 'completed', 'failed'].includes(x.status ?? x.state)).length;
  const buckets = (a: RecordData): RecordData[] => a.quota?.buckets ?? [];
  const low: RecordData[] = agents.flatMap((a) =>
    buckets(a)
      .filter((b) => typeof b.remaining_pct === 'number' && b.remaining_pct < 15)
      .map((b) => ({ ...b, agent: a.name })),
  );
  const rank = (a: RecordData) => [
    Number(!!a.installed),
    Number(a.procs > 0 || active(a) > 0),
    active(a),
    a.procs ?? 0,
    (a.meta?.tasks_30d ?? 0) + (a.meta?.sessions_24h ?? 0),
    Math.max(0, ...tasks(a).map((x) => Date.parse(x.updated_at ?? x.time) || 0)),
  ];
  const sorted = [...agents]
    .sort((a, b) => {
      const aa = rank(a),
        bb = rank(b);
      for (let i = 0; i < aa.length; i++) if (aa[i] !== bb[i]) return bb[i] - aa[i];
      return String(a.name).localeCompare(String(b.name));
    })
    .filter(
      (a) =>
        filter === 'all' ||
        (filter === 'run'
          ? a.procs > 0
          : filter === 'tasks'
            ? tasks(a).length > 0
            : filter === 'quota'
              ? buckets(a).length > 0
              : !a.installed),
    );
  return (
    <div class="runtime-view">
      <div class="runtime-kpis">
        {[
          ['installed', `${agents.filter((a) => a.installed).length}/${agents.length}`],
          ['processes', agents.reduce((n, a) => n + (a.procs ?? 0), 0)],
          ['tasks', agents.reduce((n, a) => n + tasks(a).length, 0)],
          ['gateways', gateways.length],
          ['alerts', low.length],
        ].map(([key, count]) => (
          <Panel>
            <span>{tr(String(key))}</span>
            <strong
              style={{
                color:
                  key === 'alerts'
                    ? low.length
                      ? 'var(--c-red)'
                      : 'var(--c-green)'
                    : (
                        {
                          installed: 'var(--text-title)',
                          processes: 'var(--c-green)',
                          tasks: 'var(--c-blue)',
                          gateways: 'var(--c-violet)',
                        } as Record<string, string>
                      )[String(key)],
              }}
            >
              {count}
            </strong>
          </Panel>
        ))}
      </div>
      {low.length > 0 && (
        <p class="runtime-warning" role="status">
          {tr('low')}: {low.map((b) => `${b.agent} · ${b.label} ${metric(b.remaining_pct, '%')}`).join(' / ')}
        </p>
      )}
      <nav class="collector-chips" aria-label={t('agent.tabRuntimes')}>
        {filters.map((f) => (
          <button
            class="button"
            aria-pressed={filter === f}
            onClick={() => {
              setFilter(f);
              localStorage.setItem('svc-rtf', f);
            }}
          >
            {tr(f)}
          </button>
        ))}
      </nav>
      <div class="runtime-grid">
        {sorted.map((a) => (
          <Panel>
            <header class="runtime-heading">
              <span class="dot" style={{ background: a.procs > 0 ? 'var(--c-green)' : 'var(--text-dim)' }} />
              <h3>{a.name}</h3>
              <span class="mp-pill">
                {!a.installed ? tr('none') : a.procs > 0 ? tr('running', { count: a.procs }) : tr('idle')}
              </span>
            </header>
            <p class="muted">{a.version ?? '—'}</p>
            {(a.proc_list ?? []).map((p: RecordData) => (
              <p class="runtime-process">
                PID {p.pid} · {p.cwd ?? '—'} · {metric(p.cpu_pct, '%')} · {metric(p.mem_mb, ' MB')}
              </p>
            ))}
            {tasks(a).length > 0 && (
              <>
                <h4>{tr('tasks')}</h4>
                <ul>
                  {tasks(a).map((task) => (
                    <li>
                      {task.name ?? task.title ?? task.id} · {task.kind} · {task.cwd ?? task.path ?? '—'}
                    </li>
                  ))}
                </ul>
              </>
            )}
            {buckets(a).length > 0 && <RuntimeQuotas agents={[a]} />}
            {client && (
              <button
                class="text-button"
                onClick={() => {
                  setError('');
                  void client
                    .runtime(a.id)
                    .then(setDetail)
                    .catch(() => setError(t('app.loadFailed')));
                }}
              >
                {t('route.usageDetails')}
              </button>
            )}
          </Panel>
        ))}
      </div>
      {!sorted.length && <Empty />}
      {error && <p role="alert">{error}</p>}
      {detail && (
        <Panel>
          <h3>{detail.name}</h3>
          <p>
            {detail.bin ?? '—'} · {detail.version ?? '—'}
          </p>
          <button class="button" onClick={() => setDetail(undefined)}>
            {text('close')}
          </button>
        </Panel>
      )}
      <Panel>
        <h2>{tr('gateways')}</h2>
        <div class="runtime-grid">
          {gateways.map((p) => (
            <article>
              <h3>
                <span
                  class="dot"
                  style={{ background: p.key?.set || p.account ? 'var(--c-green)' : 'var(--text-dim)' }}
                />{' '}
                {p.name ?? p.id}
              </h3>
              <p>
                {p.key?.set || p.account ? tr('keyReady') : tr('keyMissing')} · {p.host ?? '—'}
              </p>
              <div class="collector-chips">
                {(p.models ?? []).map((m: RecordData) => (
                  <code>{m.id}</code>
                ))}
              </div>
            </article>
          ))}
        </div>
        {!gateways.length && <Empty />}
      </Panel>
      <Panel>
        <h2>{tr('environment')}</h2>
        <div class="collector-chips">
          {Object.entries(data.runtimes?.env_tools ?? {}).map(([name, version]) => (
            <span class="mp-pill">
              {name} {String(version)}
            </span>
          ))}
        </div>
      </Panel>
    </div>
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
      {data.hello?.readonly === false && (
        <button class="button" disabled title={text('unwired')}>
          {text('newSession')}
        </button>
      )}
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
            <strong
              style={{
                color: (
                  { windows: '#38bdf8', panes: '#a78bfa', attached: '#4ade80', agent: '#fbbf24' } as Record<
                    string,
                    string
                  >
                )[String(k)],
              }}
            >
              {v ?? '—'}
            </strong>
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
          <Session session={s} open={setTarget} writable={data.hello?.readonly === false} />
        ))}
      {!sessions.length && <Empty />}
      {target && client && <TerminalSheet client={client} target={target} close={() => setTarget('')} />}
    </>
  );
}
function Session({
  session: s,
  open,
  writable,
}: {
  session: RecordData;
  open: (s: string) => void;
  writable: boolean;
}) {
  const [index, setIndex] = useState(0),
    [copied, setCopied] = useState(false);
  const windows = s.windows ?? [],
    panes = windows[index]?.panes ?? [];
  return (
    <Panel>
      <header>
        <h2>{s.name}</h2>
        <span class="badge">{text(s.attached ? 'attached' : 'detached')}</span>
      </header>
      <div class="row-actions">
        <button class="button" onClick={() => open(panes[0]?.target ?? panes[0]?.pane)}>
          {text('fullscreen')}
        </button>
        <button
          class="button"
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(
                s.attach_cmd ?? `tmux attach-session -t '${String(s.name).replace(/'/g, "'\\''")}'`,
              );
              setCopied(true);
            } catch {
              setCopied(false);
            }
          }}
        >
          {text(copied ? 'copied' : 'copyAttach')}
        </button>
        {writable && (
          <>
            <button class="button" disabled title={text('unwired')}>
              {text('wake')}
            </button>
            <button class="button" disabled title={text('unwired')}>
              {text('kill')}
            </button>
          </>
        )}
      </div>
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
