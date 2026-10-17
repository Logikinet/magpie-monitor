import { useEffect, useRef, useState } from 'preact/hooks';
import {
  activeLocale,
  fmtCost,
  fmtDate,
  fmtLatency,
  fmtNumber,
  fmtRelative,
  fmtSpeed,
  fmtTokens,
} from '../../core/format';
import { usageText } from './usage-text';
import type { WebClient } from '../../core/web-client';

type Client = Pick<WebClient, 'usage' | 'usageQuotas'>;
// These records retain optional upstream fields; missing measurements remain unknown.
type Data = Record<string, any>;
type Snapshot = { data: Data; quotas: Data[] };
const caches = new WeakMap<Client, { revision: number; periods: Map<string, Snapshot> }>();
const order = [
  'antigravity',
  'agy',
  'dim',
  'codex',
  'grok',
  'kiro',
  'workbuddy-ai',
  'our-free-model',
  'openrouter',
  'deepseek',
];
const colors = ['var(--c-blue)', 'var(--c-green)', 'var(--c-blue)', 'var(--c-violet)', 'var(--c-orange)'];
const providerColors: Record<string, string> = {
  antigravity: '#c084fc',
  agy: '#c084fc',
  dim: '#10b981',
  codex: '#10b981',
  grok: '#e2e8f0',
  kiro: '#8b5cf6',
  workbuddy: '#06b6d4',
  'workbuddy-ai': '#06b6d4',
  'our-free-model': '#64748b',
  openrouter: '#f59e0b',
  deepseek: '#3b82f6',
};
export function quotaPace(used: number, since: string, reset: string, now = Date.now()) {
  const start = Date.parse(since),
    end = Date.parse(reset);
  return end > start && Number.isFinite(used)
    ? Math.round((used / 100 - Math.max(0, Math.min(1, (now - start) / (end - start)))) * 100)
    : undefined;
}
export function quotaColor(value: number, used: boolean) {
  return (used ? value >= 85 : value <= 15)
    ? '#ef4444'
    : (used ? value >= 50 : value <= 50)
      ? '#f59e0b'
      : '#22c55e';
}
function Sparkline({ points }: { points: Data[] }) {
  const values = points.map((p) => Number(p.amount)).filter(Number.isFinite);
  if (!values.length) return null;
  const min = Math.min(...values),
    span = Math.max(...values) - min || 1;
  return (
    <svg
      class="mp-spark"
      width="200"
      height="24"
      viewBox="0 0 200 24"
      role="img"
      aria-label={usageText().balanceTrend}
    >
      <polyline
        fill="none"
        stroke="#38bdf8"
        stroke-width="2"
        points={values
          .map(
            (v, i) =>
              `${values.length === 1 ? 100 : (i / (values.length - 1)) * 198 + 1},${22 - ((v - min) / span) * 20}`,
          )
          .join(' ')}
      />
    </svg>
  );
}
function Account({ account: q, used }: { account: Data; used: boolean }) {
  const t = usageText();
  return (
    <div class="mp-account">
      <header>
        <b class="mp-acc-email">{q.user ?? q.name ?? '—'}</b>
        <span>{q.plan}</span>
      </header>
      <div class="mp-windows">
        {(q.windows ?? []).map((w: Data) => {
          const measured = typeof w.used === 'number',
            percent = measured ? Math.max(0, Math.min(100, w.used)) : undefined;
          const value = percent === undefined ? undefined : used ? percent : 100 - percent;
          const pace =
            w.holds?.since && w.resetsAt && measured
              ? quotaPace(w.used, w.holds.since, w.resetsAt)
              : undefined;
          const name = /^(5 hours|5-hour|5h)$/.test(w.name)
            ? '5h'
            : /^(7 days|weekly|week)$/.test(w.name)
              ? ({ zh: '7天', en: '7d', ja: '7日' } as const)[activeLocale()]
            : /^(credits?)$/i.test(w.name)
              ? ({ zh: '额度', en: 'Credits', ja: 'クレジット' } as const)[activeLocale()]
              : w.name;
          return (
            <section>
              <div class="mp-window-value">
                <b>{name}</b>
                <span>
                  {fmtNumber(value, 1)}
                  {value === undefined ? '' : '%'}
                  {w.amount !== undefined && (
                    <>
                      {' '}
                      · {fmtNumber(w.amount, 1)}
                      {w.limit !== undefined && ` / ${fmtNumber(w.limit, 1)}`} {w.unit}
                    </>
                  )}
                </span>
              </div>
              <div class="mp-track">
                <i style={{ width: `${value ?? 0}%`, background: quotaColor(value ?? 0, used) }} />
              </div>
              {w.resetsAt && (
                <small>
                  {t.resets} {fmtDate(w.resetsAt)} · {fmtRelative(w.resetsAt)}
                  {pace !== undefined && ` · ${({ zh: '节奏', en: 'pace', ja: 'ペース' } as const)[activeLocale()]} ${pace >= 0 ? '+' : ''}${fmtNumber(pace)}%`}
                </small>
              )}
              {w.holds && (
                <small>
                  {fmtTokens(w.holds.tokens)} {{ zh: 'Token', en: 'token', ja: 'トークン' }[activeLocale()]} · {fmtCost(w.holds.cost)}
                </small>
              )}
              {w.runsOutAt && (
                <small>
                  {t.runsOut} {fmtDate(w.runsOutAt)} · {fmtRelative(w.runsOutAt)}
                </small>
              )}
            </section>
          );
        })}
      </div>
      {q.balance !== undefined && (
        <p>{Number.isFinite(Number(q.balance)) ? fmtCost(Number(q.balance)) : q.balance}</p>
      )}
      {q.balanceTrend && (
        <>
          <Sparkline points={q.balanceTrend.points ?? []} />
          {q.balanceTrend.perDay !== undefined && (
            <small>
              {t.daily} {fmtCost(q.balanceTrend.perDay)}
            </small>
          )}
          {q.balanceTrend.runsOut && (
            <small>
              {t.runsOut} {fmtDate(q.balanceTrend.runsOut)} · {fmtRelative(q.balanceTrend.runsOut)}
            </small>
          )}
        </>
      )}
      {q.daily?.days?.[0] && (
        <small>
          {t.daily} {fmtNumber(q.daily.days[0].used, 1)}%
        </small>
      )}
      {q.resets?.count !== undefined && (
        <small>
          {fmtNumber(q.resets.count)} {t.resetCount}
        </small>
      )}
      {q.error && (
        <p class="mp-error" role="alert">
          {q.error}
        </p>
      )}
    </div>
  );
}
function Breakdown({
  title,
  groups = [],
  model = false,
}: {
  title: string;
  groups?: Data[];
  model?: boolean;
}) {
  const sorted = [...groups].sort((a, b) => (b.calls ?? 0) - (a.calls ?? 0)),
    max = Math.max(1, ...sorted.map((g) => g.calls ?? 0));
  return (
    <section class={`mp-panel ${model ? 'mp-models' : ''}`}>
      <h3>{title}</h3>
      {!sorted.length && <p>{usageText().empty}</p>}
      {sorted.slice(0, model ? 15 : undefined).map((g) => (
        <div class="mp-breakdown">
          <div>
            <b>{g.name ?? g.model ?? g.id ?? '—'}</b>
            <span>{fmtNumber(g.calls)}</span>
          </div>
          <small>
            {[g.provider, g.sub].filter(Boolean).join(' · ')}{' '}
            {model &&
              (g.decode_ms > 0 && typeof g.decode_out === 'number'
                ? fmtSpeed((g.decode_out / g.decode_ms) * 1000)
                : g.timed > 0
                  ? fmtLatency(g.ttft_ms / g.timed)
                  : '—')}
          </small>
          <div class="mp-track">
            <i style={{ width: `${((g.calls ?? 0) / max) * 100}%` }} />
          </div>
        </div>
      ))}
    </section>
  );
}
export function UsageDashboard({
  data,
  quotas = [],
  consoleUrl,
  period,
  setPeriod,
  refresh,
  loading = false,
  error = '',
}: {
  data?: Data;
  quotas?: Data[];
  consoleUrl?: string;
  period: string;
  setPeriod: (p: string) => void;
  refresh: () => void;
  loading?: boolean;
  error?: string;
}) {
  const [masked, setMasked] = useState(false),
    [used, setUsed] = useState(false),
    t = usageText(),
    d = data;
  const groups = new Map<string, Data[]>();
  for (const q of quotas) groups.set(q.provider, [...(groups.get(q.provider) ?? []), q]);
  const rank = (p: string) => (order.includes(p) ? order.indexOf(p) : order.length);
  const sorted = [...groups].sort(([a], [b]) => rank(a) - rank(b) || a.localeCompare(b));
  const tokens =
    d && ['input', 'output', 'reasoning', 'cache_read'].some((k) => typeof d[k] === 'number')
      ? ['input', 'output', 'reasoning', 'cache_read'].reduce((sum, k) => sum + (d[k] ?? 0), 0)
      : undefined;
  const denominator = (d?.input ?? 0) + (d?.cache_read ?? 0);
  const kpis = [
    [
      t.requests,
      fmtNumber(d?.calls),
      d?.errors ? `${fmtNumber(d.errors)} ${t.errors}` : d?.errors === 0 && d?.calls > 0 ? '100% OK' : '—',
    ],
    [t.cost, fmtCost(d?.cost), d?.unpriced ? `${fmtNumber(d.unpriced)} ${t.unpriced}` : 'USD'],
    [
      t.tokens,
      fmtTokens(tokens),
      `↓${fmtTokens(d?.input)} · ↑${fmtTokens(d?.output)} · ⚡${fmtTokens(d?.reasoning)}`,
    ],
    [
      t.cache,
      denominator > 0 && typeof d?.cache_read === 'number'
        ? `${new Intl.NumberFormat(activeLocale(), { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(((d!.cache_read ?? 0) / denominator) * 100)}%`
        : '—',
      '',
    ],
    [t.ttft, d?.timed > 0 ? fmtLatency(d!.ttft_ms / d!.timed) : '—', `${fmtNumber(d?.timed)} ${t.samples}`],
  ];
  const max = Math.max(1, ...(d?.series ?? []).map((p: Data) => p.calls ?? 0));
  return (
    <div class={`mp-usage ${masked ? 'mp-masked' : ''}`} data-testid="usage-view">
      <div class="mp-toolbar">
        <div>
          {['today', '7d', '30d', 'all'].map((p, i) => (
            <button aria-pressed={p === period} onClick={() => setPeriod(p)}>
              {[t.today, t.week, t.month, t.all][i]}
            </button>
          ))}
        </div>
        {consoleUrl && /^https?:\/\//.test(consoleUrl) && (
          <a href={consoleUrl} target="_blank" rel="noreferrer">
            {t.console}
          </a>
        )}
        <button aria-pressed={masked} onClick={() => setMasked(!masked)}>
          {masked ? t.show : t.hide}
        </button>
        <button aria-pressed={!used} onClick={() => setUsed(false)}>
          {t.remaining}
        </button>
        <button aria-pressed={used} onClick={() => setUsed(true)}>
          {t.used}
        </button>
        <button onClick={refresh}>{t.refresh}</button>
        <small>
          {t.updated} {fmtDate(d?.fetched_at ? d.fetched_at * 1000 : undefined, undefined, true)}
        </small>
      </div>
      {error && (
        <p class="mp-error" role="alert">
          {error}
        </p>
      )}
      {loading && <p role="status">{t.loading}</p>}
      <div class="mp-kpis">
        {kpis.map(([label, value, sub], i) => (
          <section class="mp-panel">
            <small>{label}</small>
            <strong style={{ color: colors[i] }}>{value}</strong>
            <small class={i === 0 ? (d?.errors ? 'mp-red' : 'mp-green') : ''}>{sub}</small>
          </section>
        ))}
      </div>
      <div class="mp-quota-grid">
        {sorted.map(([provider, accounts]) => (
          <section class="mp-panel">
            <h3 style={{ color: providerColors[provider] ?? '#64748b' }}>
              {accounts[0].name ?? provider}
            </h3>
            <Account account={accounts[0]} used={used} />
            {accounts.length > 1 && (
              <details>
                <summary>
                  {fmtNumber(accounts.length - 1)} {t.more}
                </summary>
                {accounts.slice(1).map((q) => (
                  <Account account={q} used={used} />
                ))}
              </details>
            )}
          </section>
        ))}
      </div>
      <section class="mp-panel">
        <h3>
          {t.trend} · {period === 'today' ? '24h' : t.daily}
        </h3>
        {!d?.series?.length && <p>{t.empty}</p>}
        <div class="mp-timeline">
          {(d?.series ?? []).map((p: Data) => (
            <div
              class="mp-column"
              role="img"
              aria-label={`${p.label ?? fmtDate(p.time)} · ${fmtNumber(p.calls)} ${t.requests} · ${fmtCost(p.cost)} · ${fmtTokens(p.tokens)}`}
              title={`${p.label ?? fmtDate(p.time)} · ${fmtNumber(p.calls)} ${t.requests} · ${fmtCost(p.cost)} · ${fmtTokens(p.tokens)}`}
            >
              <i
                style={{
                  height: `${p.calls ? Math.max(6, (p.calls / max) * 100) : 2}%`,
                  opacity: p.calls ? 1 : 0.2,
                }}
              />
              <small>{p.label ?? fmtDate(p.time)}</small>
            </div>
          ))}
        </div>
      </section>
      <div class="mp-breakdowns">
        <Breakdown title={t.agents} groups={d?.agents} />
        <Breakdown title={t.models} groups={d?.models} model />
      </div>
      <section class="mp-panel">
        <h3>{t.accounts}</h3>
        <div class="mp-quota-grid">
          {(d?.accounts ?? []).map((a: Data) => (
            <article class="mp-account">
              <b class="pii">{a.name ?? a.account ?? a.id}</b> <span class="mp-pill">{a.provider}</span>
              <p>
                {fmtNumber(a.calls)} {t.requests} · {fmtCost(a.cost)} ·{' '}
                {fmtTokens((a.input ?? 0) + (a.output ?? 0) + (a.reasoning ?? 0) + (a.cache_read ?? 0))} token
                ·{' '}
                <span class={a.errors ? 'mp-red' : ''}>
                  {fmtNumber(a.errors)} {t.errors}
                </span>
              </p>
            </article>
          ))}
        </div>
        {!d?.accounts?.length && <p>{t.empty}</p>}
      </section>
    </div>
  );
}
export function UsageView({
  client,
  consoleUrl,
  revision = 0,
}: {
  client: Client;
  consoleUrl?: string;
  revision?: number;
}) {
  const [period, setPeriod] = useState('today'),
    [data, setData] = useState<Data>(),
    [quotas, setQuotas] = useState<Data[]>([]),
    [loading, setLoading] = useState(false),
    [error, setError] = useState(''),
    [version, setVersion] = useState(0);
  const epoch = useRef(0);
  useEffect(() => {
    let cache = caches.get(client);
    if (!cache || cache.revision !== revision) {
      cache = { revision, periods: new Map() };
      caches.set(client, cache);
    }
    const periods = cache.periods,
      id = ++epoch.current,
      cached = periods.get(period);
    setData(cached?.data);
    setQuotas(cached?.quotas ?? []);
    setError('');
    if (cached) {
      setLoading(false);
      return;
    }
    setLoading(true);
    Promise.all([client.usage(period), client.usageQuotas()])
      .then(([summary, q]) => {
        const value = { ...summary, fetched_at: summary.fetched_at ?? Date.now() / 1000 };
        periods.set(period, { data: value, quotas: q.data });
        if (epoch.current === id) {
          setData(value);
          setQuotas(q.data);
        }
      })
      .catch(() => {
        if (epoch.current === id) setError(usageText().failed);
      })
      .finally(() => {
        if (epoch.current === id) setLoading(false);
      });
    return () => {
      epoch.current++;
    };
  }, [client, period, version, revision]);
  return (
    <UsageDashboard
      data={data}
      quotas={quotas}
      consoleUrl={consoleUrl}
      period={period}
      setPeriod={setPeriod}
      loading={loading}
      error={error}
      refresh={() => {
        caches.delete(client);
        setVersion((v) => v + 1);
      }}
    />
  );
}
