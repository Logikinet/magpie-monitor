import { CollectorClient } from './core/collector-client';
import {
  useCollector,
  HostOverview,
  ActivityTimeline,
  ServicesView,
  TmuxView,
} from './views/collector/CollectorViews';
import { RuntimesView } from './views/agent/RuntimesView';
import { UsageView } from './views/agent/UsageView';
import { ProvidersView } from './views/agent/ProvidersView';
import { fmtCost, fmtDate, fmtRelative, fmtNumber, fmtTokens } from './core/format';
import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { GatewayClient } from './core/gateway-client';
import { WebClient } from './core/web-client';
import { DirectTransport, MockTransport, ProxyTransport } from './core/transport';
import { createTraceLoop, createPoller, type TraceState } from './core/longpoll';
import { zhMessage } from './core/errors';
import { formatTokens, quotaSubtitle } from './core/tokens';
import {
  usedPercent,
  fiveHourWindow,
  weeklyWindow,
  type QuotaSpan,
  type Row,
  type Route,
} from './core/decode';
import { defaultProfile, loadProfiles, saveProfiles, validateProfile, type Profile } from './state/profiles';
import { createKeyStore } from './state/keys';
import { Icon } from './ui/icons';
import { RoutingView } from './views/agent/RoutingView';
import { AgentNav, AgentPlaceholder, readPage, type AgentTab } from './views/agent/AgentNav';
import type { decodeGroups } from './core/decode';
import { detectLocale, languageChoice, setLanguage, t, type LanguageChoice } from './i18n';

type Tab = 'home' | 'activity' | 'tmux' | 'agent' | 'svc' | 'settings';
const nav: { id: Tab; label: string; icon: string }[] = [
  { id: 'home', label: 'nav.overview', icon: 'overview' },
  { id: 'activity', label: 'nav.activity', icon: 'chart' },
  { id: 'tmux', label: 'collector.tmux', icon: 'terminal' },
  { id: 'agent', label: 'nav.agent', icon: 'bot' },
  { id: 'svc', label: 'collector.svc', icon: 'server' },
];
const fmt = fmtNumber;
const money = fmtCost;
const dateTime = fmtDate;
const relTime = fmtRelative;

function Status({
  kind,
  children,
}: {
  kind: 'ok' | 'warn' | 'error' | 'neutral';
  children: ComponentChildren;
}) {
  const icon =
    kind === 'ok'
      ? 'check-circle'
      : kind === 'warn'
        ? 'warning-triangle'
        : kind === 'error'
          ? 'x-circle'
          : 'minus-circle';
  return (
    <span class={`status status-${kind}`}>
      <Icon name={icon} size={15} />
      {children}
    </span>
  );
}
function Card({ children, class: cls = '' }: { children: ComponentChildren; class?: string }) {
  return <section class={`card ${cls}`}>{children}</section>;
}
function Metric({
  label,
  value,
  hint,
  icon,
}: {
  label: string;
  value: string;
  hint?: string;
  icon?: string;
}) {
  return (
    <Card class="metric">
      <div class="metric-label">
        {icon && <Icon name={icon} size={16} />}
        <span>{label}</span>
      </div>
      <strong class="metric-value">{value}</strong>
      {hint && <small>{hint}</small>}
    </Card>
  );
}
function ErrorBox({ message, retry }: { message: string; retry: () => void }) {
  return (
    <div class="error-box">
      <Status kind="error">{t('app.loadFailed')}</Status>
      <p>{message}</p>
      <button class="button" onClick={retry}>
        <Icon name="refresh" />
        {t('app.retry')}
      </button>
    </div>
  );
}
function Skeletons() {
  return (
    <div class="grid metrics-grid" aria-label={t('app.loading')}>
      <div class="skeleton" />
      <div class="skeleton" />
      <div class="skeleton" />
    </div>
  );
}
export function QuotaCard({ provider, window, usage }: { provider: string; window: QuotaSpan; usage?: any }) {
  const pct = Math.round(usedPercent(window));
  const danger = pct >= 100 ? 'error' : pct >= 80 ? 'warn' : 'ok';
  const period = /^(weekly|week)$/i.test(window.name) ? t('quota.week') : t('quota.fiveHours');
  const accessible = `${provider} ${period}, ${quotaSubtitle(window, provider, usage)}, ${t('quota.used', { percent: pct })}${window.limit ? `, ${t('quota.limitDescription', { limit: fmt(window.limit), unit: window.unit ?? '' })}` : ''}`;
  return (
    <Card class={`quota-card quota-${danger}`} aria-label={accessible}>
      <div class="quota-head">
        <div>
          <h3>
            {provider} <span>· {period}</span>
          </h3>
          <p>{quotaSubtitle(window, provider, usage)}</p>
        </div>
        <strong>{pct}%</strong>
      </div>
      <div
        class="progress"
        role="progressbar"
        aria-label={accessible}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={pct}
      >
        <span style={{ width: `${pct}%` }} />
      </div>
      <div class="quota-foot">
        <span title={window.resetsAt ? fmtDate(window.resetsAt) : undefined}>
          {t('quota.reset', { time: relTime(window.resetsAt) })}
        </span>
        <Status kind={danger}>
          {danger === 'ok' ? t('quota.ok') : danger === 'warn' ? t('quota.warn') : t('quota.exhausted')}
        </Status>
      </div>
    </Card>
  );
}

export default function App() {
  const params = new URLSearchParams(location.search);
  const [profiles, setProfiles] = useState<Profile[]>(() =>
    params.get('mock') === '1' ? [{ ...defaultProfile }] : loadProfiles(),
  );
  const [activeId, setActiveId] = useState(() =>
    params.get('mock') === '1'
      ? defaultProfile.id
      : (localStorage.getItem('magpie.activeProfile') ?? loadProfiles()[0]?.id ?? defaultProfile.id),
  );
  const profile = profiles.find((p) => p.id === activeId) ?? profiles[0] ?? defaultProfile;
  const [tab, setTab] = useState<Tab>(() => readPage().tab as Tab);
  const [locale, setLocale] = useState(detectLocale);
  const [language, setLanguageChoice] = useState<LanguageChoice>(languageChoice);
  const [agentTab, setAgentTab] = useState<AgentTab>(() => readPage().atab);
  const [routingGroups, setRoutingGroups] = useState<ReturnType<typeof decodeGroups>['groups']>([]);
  const [traceVersion, setTraceVersion] = useState(0);
  const [agentRevision, setAgentRevision] = useState(0);
  const [theme, setTheme] = useState(
    () => params.get('theme') ?? localStorage.getItem('magpie.theme') ?? 'dark',
  );
  const [keysVersion, setKeysVersion] = useState(0);
  const [usage, setUsage] = useState<any>();
  const [ledger, setLedger] = useState<any>();
  const [quotas, setQuotas] = useState<any[]>([]);
  const [concurrency, setConcurrency] = useState<any>();
  const [hello, setHello] = useState<any>();
  const [limitInfo, setLimitInfo] = useState<any>();
  const [lastUpdated, setLastUpdated] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [offset, setOffset] = useState(0);
  const [period, setPeriod] = useState('day');
  const [traceRoutes, setTraceRoutes] = useState<Route[]>([]);
  const [traceTotals, setTraceTotals] = useState<any>();
  const [traceState, setTraceState] = useState<TraceState>('stopped');
  const [sessionId, setSessionId] = useState('');
  const [routeError, setRouteError] = useState('');
  const [remember, setRemember] = useState(false);
  const [gatewayKey, setGatewayKey] = useState('');
  const [webKey, setWebKey] = useState('');
  const [showKeys, setShowKeys] = useState(false);
  const [profileEdit, setProfileEdit] = useState<Profile | null>(null);
  const [notice, setNotice] = useState('');
  const [autoLocked, setAutoLocked] = useState(false);
  const pressTimer = useRef<ReturnType<typeof setTimeout>>();
  const longPressed = useRef(false);
  useEffect(() => () => clearTimeout(pressTimer.current), []);
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(''), 3600);
    return () => clearTimeout(timer);
  }, [notice]);
  const keyStore = useMemo(() => createKeyStore(), []);
  const keys = useMemo(() => keyStore.getKeys(profile.id), [keyStore, profile.id, keysVersion]);
  useEffect(() => {
    setGatewayKey(keys.gatewayKey ?? '');
    setWebKey(keys.webKey ?? '');
    setRemember(keyStore.isRemembered(profile.id));
  }, [profile.id, keysVersion]);
  const transport = useMemo(
    () =>
      profile.mode === 'mock'
        ? new MockTransport()
        : profile.mode === 'direct'
          ? new DirectTransport(profile, { gatewayKey: keys.gatewayKey })
          : new ProxyTransport({ gatewayKey: keys.gatewayKey, webKey: keys.webKey }),
    [profile, keys.gatewayKey, keys.webKey],
  );
  const gateway = useMemo(() => new GatewayClient(transport), [transport]);
  const web = useMemo(() => new WebClient(transport), [transport]);
  const collector = useMemo(
    () =>
      profile.mode === 'mock' || profile.collectorUrl
        ? new CollectorClient(transport, profile.mode === 'mock' ? undefined : profile.collectorUrl)
        : undefined,
    [transport, profile.collectorUrl, profile.mode],
  );
  const {
    data: collectorData,
    error: collectorError,
    loading: collectorLoading,
  } = useCollector(collector, agentRevision, autoLocked);
  const [activityView, setActivityView] = useState('timeline');
  const isMock = profile.mode === 'mock';
  const refresh = useCallback(
    async (signal?: AbortSignal) => {
      setLoading(true);
      setError('');
      const results = await Promise.allSettled([
        gateway.usage(period),
        gateway.requests({ period, offset: 0, limit: 20 }),
        gateway.quotas(),
        gateway.concurrency(),
        profile.mode === 'direct' ? Promise.resolve(undefined) : gateway.hello(),
        gateway.limit(),
      ]);
      if (signal?.aborted) return;
      const failed = results.find((r) => r.status === 'rejected') as PromiseRejectedResult | undefined;
      if (results[0].status === 'fulfilled') setUsage(results[0].value);
      if (results[1].status === 'fulfilled') {
        setLedger(results[1].value);
        setOffset(results[1].value.rows.length);
      }
      if (results[2].status === 'fulfilled') setQuotas(results[2].value.data);
      if (results[3].status === 'fulfilled') setConcurrency(results[3].value);
      if (results[4].status === 'fulfilled') setHello(results[4].value);
      if (results[5].status === 'fulfilled') setLimitInfo(results[5].value);
      setLastUpdated(new Date().toISOString());
      setLoading(false);
      if (failed)
        setError(
          zhMessage((failed.reason ?? { kind: 'network' }) as any, {
            api: profile.mode === 'live' ? 'web' : 'gateway',
            mode: profile.mode,
          }),
        );
    },
    [gateway, profile.mode, period],
  );
  useEffect(() => {
    if (!autoLocked) void refresh();
    const poll = createPoller(profile.refreshSec * 1000, refresh);
    if (!autoLocked) poll.start();
    return () => poll.stop();
  }, [refresh, profile.refreshSec, profile.id, autoLocked]);
  useEffect(() => {
    const themeValue = ['dark', 'light'].includes(theme) ? theme : '';
    if (themeValue) document.documentElement.dataset.theme = themeValue;
    else delete document.documentElement.dataset.theme;
    if (!params.has('theme')) localStorage.setItem('magpie.theme', theme);
  }, [theme]);
  useEffect(() => {
    document.documentElement.lang = locale === 'zh' ? 'zh-CN' : locale;
  }, [locale]);
  useEffect(() => {
    const change = () => {
      const next = readPage();
      setTab(next.tab as Tab);
      setAgentTab(next.atab);
      if (location.hash === '#/quotas') history.replaceState(null, '', '#/agent?atab=usage');
    };
    change();
    addEventListener('hashchange', change);
    return () => removeEventListener('hashchange', change);
  }, []);
  useEffect(() => {
    if (tab !== 'agent' || agentTab !== 'routing' || profile.mode === 'direct') return;
    setTraceRoutes([]);
    setTraceTotals(undefined);
    setRoutingGroups([]);
    let active = true;
    void web
      .groups()
      .then((env) => {
        if (active) setRoutingGroups(env.groups);
      })
      .catch(() => {});
    const loop = createTraceLoop({
      fetchTrace: (after, wait, signal) => web.trace(after, wait, signal),
      onRoutes: setTraceRoutes,
      onEnvelope: (env) => setTraceTotals(env.totals),
      onState: setTraceState,
    });
    loop.start();
    return () => {
      active = false;
      loop.stop();
    };
  }, [tab, agentTab, profile.id, profile.mode, web, traceVersion]);
  useEffect(() => {
    if (profile.mode !== 'direct' || tab !== 'agent' || agentTab !== 'routing' || !sessionId) return;
    let active = true,
      after = 0;
    const poll = async () => {
      try {
        const env = await gateway.route(sessionId, after, 25);
        if (!active) return;
        after = env.seq;
        if (env.route) setTraceRoutes((prev) => [env.route!, ...prev].slice(0, 200));
        setRouteError('');
      } catch (e) {
        if (active) setRouteError(zhMessage(e as any, { api: 'gateway' }));
      }
      if (active) setTimeout(poll, 500);
    };
    void poll();
    return () => {
      active = false;
    };
  }, [profile.mode, tab, agentTab, sessionId, gateway, traceVersion]);
  const chooseAgentTab = (next: AgentTab) => {
    setAgentTab(next);
    setTab('agent');
    location.hash = `/agent?atab=${next}`;
  };
  const chooseTab = (id: Tab) => {
    location.hash = id === 'agent' ? `/agent?atab=${agentTab}` : `/${id}`;
    setTab(id);
  };
  const chooseProfile = (id: string) => {
    localStorage.setItem('magpie.activeProfile', id);
    setActiveId(id);
    setUsage(undefined);
    setLoading(true);
  };
  const allWindows = quotas.flatMap((q) =>
    [fiveHourWindow(q), weeklyWindow(q)]
      .filter(Boolean)
      .map((w: any) => ({ provider: q.provider, window: w })),
  );
  const topQuotas = allWindows.slice(0, 4);
  const series = ledger?.series ?? usage?.series ?? [];
  const rows: Row[] = ledger?.rows ?? [];
  const loadMore = async () => {
    try {
      const next = await gateway.requests({ period, offset, limit: 20 });
      setLedger((old: any) => ({ ...next, rows: [...(old?.rows ?? []), ...next.rows] }));
      setOffset(offset + next.rows.length);
    } catch (e) {
      setError(zhMessage(e as any, { api: 'gateway' }));
    }
  };
  const saveProfile = (p: Profile) => {
    const valid = validateProfile(p);
    const next = profiles.some((x) => x.id === valid.id)
      ? profiles.map((x) => (x.id === valid.id ? valid : x))
      : [...profiles, valid];
    saveProfiles(next);
    setProfiles(next);
    setProfileEdit(null);
    if (!profiles.some((x) => x.id === valid.id)) chooseProfile(valid.id);
  };
  const saveKeys = () => {
    keyStore.setKeys(profile.id, { gatewayKey, webKey }, remember);
    setKeysVersion((v) => v + 1);
    setNotice(t('app.savedKeys'));
  };
  const removeProfile = (id: string) => {
    if (profiles.length < 2) return;
    const next = profiles.filter((p) => p.id !== id);
    setProfiles(next);
    saveProfiles(next);
    keyStore.clearKeys(id);
    if (id === profile.id) chooseProfile(next[0].id);
  };

  return (
    <div class="app-shell" data-testid={`view-${tab}`}>
      <header class="topbar">
        <a
          class="brand"
          href="#/home"
          onClick={() => chooseTab('home')}
          aria-label={`magpie ${t('overview.title')}`}
        >
          <span class="brand-mark">M</span>
          <span>magpie monitor</span>
        </a>
        <span class="header-host">
          {collectorData.sys?.hostname ?? collectorData.hello?.host ?? profile.name}
        </span>
        <div class="header-state">
          {collectorData.hello?.readonly && <span class="badge">{t('collector.readonly')}</span>}
          <button
            class="connection-pill"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(
                  collectorData.hello?.ssh ??
                    collectorData.hello?.host ??
                    collectorData.sys?.hostname ??
                    profile.name,
                );
                setNotice(t('collector.copied'));
              } catch {
                setNotice(t('collector.copyFailed'));
              }
            }}
          >
            <Status kind={error || collectorError ? 'error' : 'ok'}>
              {error || collectorError ? t('app.connectionError') : t('app.connected')}
            </Status>
          </button>
          {isMock && (
            <span
              class="badge badge-secondary"
              data-testid="mock-badge"
              title={t('app.mock')}
              aria-label={t('app.mock')}
            >
              <Icon name="play-rect" />
              {t('app.mock')}
            </span>
          )}
          {profile.mode === 'direct' && profile.gatewayUrl?.startsWith('http://') && (
            <span class="badge badge-warn">
              <Icon name="lock-open" />
              {t('settings.insecure')}
            </span>
          )}
        </div>
        {profile.mode !== 'mock' && (
          <span class="mode-pill">
            {profile.mode === 'live' ? t('settings.live') : t('settings.directPill')}
          </span>
        )}
        <nav class="desktop-nav" aria-label={t('app.mainNav')}>
          {nav.map((n) => (
            <a
              href={`#cat=${n.id}`}
              onClick={() => chooseTab(n.id)}
              aria-current={tab === n.id ? 'page' : undefined}
            >
              {t(n.label)}
            </a>
          ))}
        </nav>
        <div class="top-actions">
          <button
            class="button button-quiet"
            aria-label={t('nav.settings')}
            onClick={() => chooseTab('settings')}
          >
            <Icon name="settings" />
          </button>
          <label class="language-switch">
            <span class="sr-only">{t('lang.label')}</span>
            <select
              aria-label={t('lang.label')}
              value={language}
              onChange={(e) => {
                const choice = (e.currentTarget as HTMLSelectElement).value as LanguageChoice;
                setLanguageChoice(choice);
                setLocale(setLanguage(choice));
              }}
            >
              <option value="auto">{t('lang.auto')}</option>
              <option value="zh">{t('lang.zh')}</option>
              <option value="en">{t('lang.en')}</option>
              <option value="ja">{t('lang.ja')}</option>
            </select>
          </label>
          {profile.webGuiUrl && (
            <a
              class="button button-quiet external"
              target="_blank"
              rel="noopener noreferrer"
              href={profile.webGuiUrl}
            >
              <Icon name="external-link" />
              {t('app.openWeb')}
            </a>
          )}
          <button
            class={`button button-quiet refresh-button ${loading || collectorLoading ? 'spinning' : ''}`}
            aria-label={t('app.refresh')}
            aria-pressed={autoLocked}
            onPointerDown={(e) => {
              if (e.button !== 0) return;
              longPressed.current = false;
              pressTimer.current = setTimeout(() => {
                longPressed.current = true;
                setAutoLocked((v) => !v);
                setNotice(t(autoLocked ? 'collector.unlocked' : 'collector.locked'));
              }, 500);
            }}
            onPointerUp={() => clearTimeout(pressTimer.current)}
            onPointerCancel={() => {
              clearTimeout(pressTimer.current);
              longPressed.current = true;
            }}
            onPointerLeave={() => clearTimeout(pressTimer.current)}
            onContextMenu={(e) => e.preventDefault()}
            onClick={() => {
              if (longPressed.current) {
                longPressed.current = false;
                return;
              }
              void refresh();
              setAgentRevision((v) => v + 1);
            }}
          >
            <Icon name="refresh" />
            <span>{t('app.refresh')}</span>
          </button>
        </div>
      </header>
      <nav class="mobile-nav" aria-label={t('app.mainNav')}>
        {nav.map((n) => (
          <a
            href={`#/${n.id}`}
            onClick={() => chooseTab(n.id)}
            aria-current={tab === n.id ? 'page' : undefined}
          >
            <Icon name={n.icon} />
            <span>{t(n.label)}</span>
          </a>
        ))}
      </nav>
      {notice && (
        <div class="shell-toast" role="status">
          {notice}
        </div>
      )}
      <main class="main-content">
        <div class="page-wrap">
          {collectorError && (
            <p role="alert">
              {collectorError}{' '}
              <button class="button" onClick={() => setAgentRevision((v) => v + 1)}>
                {t('app.retry')}
              </button>
            </p>
          )}
          {tab === 'home' && collector && (
            <HostOverview
              data={collectorData}
              navigate={(id) => (id === 'agent' ? chooseAgentTab('runtimes') : chooseTab(id as Tab))}
            />
          )}
          {tab === 'tmux' &&
            (collector ? (
              <TmuxView data={collectorData} client={collector} />
            ) : (
              <p>{t('collector.unconfigured')}</p>
            ))}
          {tab === 'svc' &&
            (collector ? <ServicesView data={collectorData} /> : <p>{t('collector.unconfigured')}</p>)}
          {tab === 'activity' && collector && (
            <>
              <nav class="collector-chips">
                {['timeline', 'ledger'].map((id) => (
                  <button
                    class="button"
                    aria-pressed={activityView === id}
                    onClick={() => setActivityView(id)}
                  >
                    {t(`collector.${id}`)}
                  </button>
                ))}
              </nav>
              {activityView === 'timeline' && <ActivityTimeline data={collectorData} />}
            </>
          )}
          {((tab === 'home' && !collector) || (tab === 'activity' && activityView === 'ledger')) && (
            <>
              <div class="page-heading">
                <div>
                  <p class="eyebrow">MAGPIE MONITOR</p>
                  <h1>{t('overview.title')}</h1>
                  <p>{t('overview.subtitle')}</p>
                </div>
                {profile.webGuiUrl && (
                  <a
                    class="button button-secondary external"
                    href={profile.webGuiUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <Icon name="external-link" />
                    {t('app.openWeb')}
                  </a>
                )}
              </div>
              {error && <ErrorBox message={error} retry={() => void refresh()} />}
              {loading && !usage ? (
                <Skeletons />
              ) : (
                <>
                  <Card class="connection-card">
                    <div class="connection-state">
                      <Status kind={error ? 'error' : 'ok'}>
                        {error ? t('app.connectionError') : t('app.connected')}
                      </Status>
                      <span>
                        {t('overview.service')} <b>{hello?.name ?? 'magpie'}</b> · {t('overview.version')}{' '}
                        <b class="mono">{hello?.version ?? '—'}</b>
                      </span>
                    </div>
                    <span class="status last-updated">
                      {t('overview.updated')} {dateTime(lastUpdated)}
                    </span>
                  </Card>
                  <div class="grid metrics-grid">
                    <Metric icon="activity" label={t('overview.requests')} value={fmt(usage?.calls)} />
                    <Metric
                      icon="gauge"
                      label={t('overview.tokens')}
                      value={usage?.tokens === undefined ? '—' : fmtTokens(usage.tokens)}
                      hint={t('overview.inputOutput')}
                    />
                    <Metric label={t('overview.cost')} value={money(usage?.cost)} />
                    <Metric label={t('overview.errors')} value={fmt(usage?.errors)} />
                    <Metric
                      label={t('overview.concurrency')}
                      value={`${fmt(concurrency?.active?.length ?? concurrency?.requests)} / ${fmt(concurrency?.waiting)}`}
                      hint={t('overview.runningWaiting')}
                    />
                  </div>
                  <Section
                    title={t('overview.quota')}
                    action={
                      <button
                        class="text-button"
                        onClick={() => {
                          chooseTab('agent');
                          chooseAgentTab('usage');
                        }}
                      >
                        {t('overview.viewAll')} <span aria-hidden="true">→</span>
                      </button>
                    }
                  />
                  <div class="grid quota-grid">
                    {topQuotas.map((x) => (
                      <QuotaCard provider={x.provider} window={x.window} usage={usage} />
                    ))}
                  </div>
                  <KeyValueCard
                    title={t('overview.limit')}
                    subtitle={t('overview.limitSubtitle')}
                    value={limitInfo}
                  />
                </>
              )}
            </>
          )}
          {tab === 'activity' && (!collector || activityView === 'ledger') && (
            <>
              <div class="page-heading">
                <div>
                  <p class="eyebrow">
                    {new URLSearchParams(location.search).get('lang') === 'en'
                      ? 'REQUEST LEDGER'
                      : t('activity.eyebrow')}
                  </p>
                  <h1>{t('activity.title')}</h1>
                  <p>{t('activity.subtitle')}</p>
                </div>
                <div class="segmented">
                  {[
                    ['day', t('activity.today')],
                    ['7d', t('activity.days7')],
                    ['30d', t('activity.days30')],
                  ].map(([key, label]) => (
                    <button
                      class={period === key ? 'selected' : ''}
                      onClick={() => {
                        setPeriod(key);
                        setOffset(0);
                      }}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>
              {error && <ErrorBox message={error} retry={() => void refresh()} />}
              {loading && !ledger ? (
                <Skeletons />
              ) : (
                <>
                  <Card class="chart-card">
                    <div class="section-title">
                      <div>
                        <h2>{t('activity.trend')}</h2>
                        <p class="chart-subtitle">
                          {t('chart.requests', { count: fmt(ledger?.total ?? usage?.calls ?? rows.length) })}
                        </p>
                      </div>
                      <span class="muted">{t('app.periods', { count: series.length })}</span>
                    </div>
                    <TrendChart series={series} />
                  </Card>
                  <Section
                    title={t('activity.records')}
                    action={<span class="muted">{ledger?.total ?? 0}</span>}
                  />
                  <Ledger rows={rows} />
                  {offset < (ledger?.total ?? 0) && (
                    <button class="button load-more" onClick={() => void loadMore()}>
                      {t('activity.loadMore')}
                    </button>
                  )}
                </>
              )}
            </>
          )}
          {tab === 'agent' && (
            <>
              <div class="page-heading">
                <div>
                  <p class="eyebrow">
                    {t(
                      (
                        {
                          routing: 'app.routingEyebrow',
                          usage: 'app.usageEyebrow',
                          providers: 'app.providersEyebrow',
                          runtimes: 'app.runtimesEyebrow',
                        } as const
                      )[agentTab],
                    )}
                  </p>
                  <h1>{t('agent.title')}</h1>
                  <p>{t('agent.subtitle')}</p>
                </div>
              </div>
              <AgentNav tab={agentTab} choose={chooseAgentTab} />
              {profile.mode === 'direct' && agentTab === 'routing' && (
                <Card class="notice-card">
                  <Status kind="warn">{t('agent.directMode')}</Status>
                  <p>{t('agent.sessionHint')}</p>
                  <form
                    class="session-form"
                    onSubmit={(e) => {
                      e.preventDefault();
                      setTraceRoutes([]);
                      setTraceVersion((v) => v + 1);
                    }}
                  >
                    <input
                      value={sessionId}
                      onInput={(e) => setSessionId((e.currentTarget as HTMLInputElement).value)}
                      placeholder={t('agent.session')}
                      aria-label={t('agent.session')}
                    />
                    <button class="button button-primary">{t('agent.startPolling')}</button>
                  </form>
                </Card>
              )}
              {agentTab === 'routing' && (
                <RoutingView
                  routes={traceRoutes}
                  totals={traceTotals}
                  groups={routingGroups}
                  loading={
                    profile.mode !== 'direct' &&
                    traceTotals === undefined &&
                    (traceState === 'running' || traceState === 'stopped')
                  }
                  state={profile.mode === 'direct' ? undefined : traceState}
                  refresh={() => setTraceVersion((v) => v + 1)}
                  usage={() => chooseAgentTab('usage')}
                  client={web}
                />
              )}
              {routeError && agentTab === 'routing' && (
                <ErrorBox message={routeError} retry={() => setTraceVersion((v) => v + 1)} />
              )}
              {agentTab === 'providers' && <ProvidersView client={web} revision={agentRevision} />}
              {agentTab === 'runtimes' &&
                (collector ? (
                  <RuntimesView data={collectorData} client={collector} web={web} revision={agentRevision} />
                ) : (
                  <p>{t('collector.unconfigured')}</p>
                ))}
            </>
          )}
          {tab === 'agent' && agentTab === 'usage' && (
            <UsageView client={web} consoleUrl={profile.webGuiUrl} revision={agentRevision} />
          )}
          {tab === 'settings' && (
            <>
              <div class="page-heading">
                <div>
                  <p class="eyebrow">{t('settings.eyebrow')}</p>
                  <h1>{t('settings.title')}</h1>
                  <p>{t('settings.subtitle')}</p>
                </div>
              </div>
              <Section
                title={t('settings.sectionServer')}
                action={
                  <button
                    class="button button-primary"
                    onClick={() =>
                      setProfileEdit({ id: `profile-${Date.now()}`, name: '', mode: 'mock', refreshSec: 20 })
                    }
                  >
                    {t('settings.addProfile')}
                  </button>
                }
              />
              {profileEdit && (
                <ProfileForm initial={profileEdit} cancel={() => setProfileEdit(null)} save={saveProfile} />
              )}
              <div class="profile-list">
                {profiles.map((p) => (
                  <Card class="profile-row">
                    <div class="profile-meta">
                      <strong>{p.name}</strong>
                      <span class="muted">
                        {p.mode === 'mock'
                          ? t('settings.mock')
                          : p.mode === 'live'
                            ? t('settings.proxy')
                            : t('settings.direct')}{' '}
                        · {t('settings.everySeconds', { seconds: p.refreshSec })}
                      </span>
                      {p.gatewayUrl?.startsWith('http://') && (
                        <span class="badge badge-warn">
                          <Icon name="lock-open" />
                          {t('settings.insecure')}
                        </span>
                      )}
                    </div>
                    <div class="row-actions">
                      <button class="button button-quiet" onClick={() => chooseProfile(p.id)}>
                        {t('settings.switch')}
                      </button>
                      <button class="button button-quiet" onClick={() => setProfileEdit(p)}>
                        {t('settings.edit')}
                      </button>
                      <button
                        class="button button-quiet danger-text"
                        disabled={profiles.length < 2}
                        onClick={() => removeProfile(p.id)}
                      >
                        {t('settings.delete')}
                      </button>
                    </div>
                  </Card>
                ))}
              </div>
              <Section title={t('settings.sectionKeys')} />
              <Card class="settings-card">
                <div class="form-grid">
                  <label>
                    {t('settings.gatewayKeyLabel')}
                    <input
                      type={showKeys ? 'text' : 'password'}
                      autoComplete="off"
                      value={gatewayKey}
                      onInput={(e) => setGatewayKey((e.currentTarget as HTMLInputElement).value)}
                      placeholder={t('settings.gatewayKey')}
                    />
                  </label>
                  {profile.mode === 'live' && (
                    <label>
                      {t('settings.runtimeKeyLabel')}
                      <input
                        type={showKeys ? 'text' : 'password'}
                        autoComplete="off"
                        value={webKey}
                        onInput={(e) => setWebKey((e.currentTarget as HTMLInputElement).value)}
                        placeholder={t('settings.runtimeKey')}
                      />
                    </label>
                  )}
                </div>
                <div class="inline-controls">
                  <button class="text-button" onClick={() => setShowKeys((v) => !v)}>
                    {showKeys ? t('settings.hideKey') : t('settings.showKey')}
                  </button>
                  <label class="check-label">
                    <input
                      type="checkbox"
                      checked={remember}
                      onChange={(e) => setRemember((e.currentTarget as HTMLInputElement).checked)}
                    />
                    {t('settings.remember')}
                  </label>
                </div>
                {remember && (
                  <div class="warning-box">
                    <Status kind="warn">{t('settings.localStorageTitle')}</Status>
                    <p>{t('settings.localStorageBody')}</p>
                  </div>
                )}
                <div class="row-actions">
                  <button class="button button-primary" onClick={saveKeys}>
                    {t('settings.saveKeys')}
                  </button>
                  <button
                    class="button"
                    onClick={() => {
                      keyStore.clearKeys();
                      setKeysVersion((v) => v + 1);
                      setGatewayKey('');
                      setWebKey('');
                    }}
                  >
                    {t('settings.clearKeys')}
                  </button>
                </div>
                {notice && <p class="success-note">{notice}</p>}
              </Card>
              <Section title={t('settings.sectionAppearance')} />
              <Card class="settings-card">
                <label class="field-label">
                  {t('settings.theme')}
                  <select
                    value={theme}
                    onChange={(e) => setTheme((e.currentTarget as HTMLSelectElement).value)}
                  >
                    <option value="system">{t('settings.system')}</option>
                    <option value="light">{t('settings.light')}</option>
                    <option value="dark">{t('settings.dark')}</option>
                  </select>
                </label>
                <div class="field-label">
                  {t('settings.profileManagement')}
                  <div class="row-actions">
                    <button class="button" onClick={() => downloadProfiles(profiles)}>
                      {t('settings.export')}
                    </button>
                    <label class="button file-button">
                      {t('settings.import')}
                      <input
                        type="file"
                        accept="application/json"
                        onChange={(e) =>
                          importProfileFile(e.currentTarget as HTMLInputElement, setProfiles, setNotice)
                        }
                      />
                    </label>
                  </div>
                  <small>{t('settings.exportNote')}</small>
                </div>
              </Card>
              <Section title={t('settings.sectionAbout')} />
              <Card class="about-card">
                <p>
                  <strong>magpie web</strong> · MIT License
                </p>
                <p>{t('settings.aboutBody')}</p>
                <a
                  href="https://magpie.example.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-link"
                >
                  {t('settings.project')} <Icon name="external-link" size={14} />
                </a>
              </Card>
            </>
          )}
        </div>
      </main>
    </div>
  );
}

function Section({ title, action }: { title: string; action?: ComponentChildren }) {
  return (
    <div class="section-heading">
      <h2>{title}</h2>
      {action}
    </div>
  );
}
function TrendChart({ series }: { series: any[] }) {
  const host = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(600),
    [height, setHeight] = useState(() => (matchMedia('(max-width: 760px)').matches ? 180 : 220));
  useEffect(() => {
    const el = host.current;
    if (!el) return;
    const update = () => setWidth(el.clientWidth || 600);
    update();
    if (typeof ResizeObserver !== 'undefined') {
      const observer = new ResizeObserver(update);
      observer.observe(el);
      return () => observer.disconnect();
    }
    addEventListener('resize', update);
    return () => removeEventListener('resize', update);
  }, []);
  useEffect(() => {
    const media = matchMedia('(max-width: 760px)'),
      update = () => setHeight(media.matches ? 180 : 220);
    update();
    media.addEventListener?.('change', update);
    return () => media.removeEventListener?.('change', update);
  }, []);
  const values = series.map((p) => Number(p.calls ?? 0));
  const max = Math.max(1, ...values);
  const left = 46,
    right = 8,
    top = 12,
    bottom = 28,
    plotW = width - left - right,
    plotH = height - top - bottom,
    gap = values.length > 1 ? 4 : 0,
    bar = Math.max(1, (plotW - gap * Math.max(0, values.length - 1)) / Math.max(1, values.length)),
    tickStep = Math.max(1, Math.ceil(values.length / Math.max(1, Math.floor(width / 80))));
  const label = (p: any) => p?.label ?? dateTime(p?.time);
  return (
    <div class="chart-wrap" ref={host}>
      <svg width={width} height={height} role="img" aria-label={t('chart.aria')}>
        <title>{t('chart.title')}</title>
        {[0, 1, 2, 3].map((i) => {
          const value = (max * (3 - i)) / 3,
            y = top + (i * plotH) / 3;
          return (
            <g>
              <path d={`M${left} ${y}H${width - right}`} class="chart-grid" />
              <text x={left - 7} y={y + 4} text-anchor="end" class="chart-y-label">
                {compactNumber(value)}
              </text>
            </g>
          );
        })}
        {values.map((v, i) => {
          const h = Math.max(v ? 2 : 0, (v / max) * plotH);
          const x = left + i * (bar + gap);
          return (
            <rect
              x={x}
              y={top + plotH - h}
              width={bar}
              height={h}
              rx="2"
              tabIndex={0}
              aria-label={`${label(series[i])}: ${t('chart.requests', { count: fmt(v) })}`}
            >
              <title>
                {label(series[i])} · {t('chart.requests', { count: fmt(v) })}
              </title>
            </rect>
          );
        })}
        {values.map((_, i) =>
          i === 0 || i === values.length - 1 || i % tickStep === 0 ? (
            <text
              x={left + i * (bar + gap) + bar / 2}
              y={height - 5}
              text-anchor="middle"
              class="chart-x-label"
            >
              {label(series[i])}
            </text>
          ) : null,
        )}
      </svg>
    </div>
  );
}
function compactNumber(n: number) {
  return fmtTokens(n);
}
function Ledger({ rows }: { rows: Row[] }) {
  if (!rows.length) return <Empty text={t('activity.emptyRows')} />;
  return (
    <>
      <div class="ledger-table-wrap">
        <table class="ledger-table">
          <thead>
            <tr>
              <th>{t('activity.th')}</th>
              <th>Agent</th>
              <th>{t('activity.thModel')}</th>
              <th>Provider</th>
              <th>{t('activity.thTokens')}</th>
              <th>{t('activity.cost')}</th>
              <th>{t('activity.status')}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <LedgerRow row={r} />
            ))}
          </tbody>
        </table>
      </div>
      <div class="ledger-mobile">
        {rows.map((r) => (
          <LedgerRow row={r} mobile />
        ))}
      </div>
    </>
  );
}
function LedgerRow({ row, mobile = false }: { row: Row; mobile?: boolean }) {
  const r = row as Record<string, any>;
  const ok = Number(r.status ?? 200) < 400;
  const when = dateTime(typeof r.t === 'string' ? r.t : undefined);
  const incoming = typeof r.in === 'number' ? r.in : undefined,
    outgoing = typeof r.out === 'number' ? r.out : undefined;
  const cost = typeof r.cost === 'number' ? r.cost : undefined;
  const agent = String(r.agentName ?? r.agent ?? '—'),
    model = String(r.model ?? '—'),
    provider = String(r.providerName ?? r.provider ?? '—');
  return mobile ? (
    <Card class="ledger-mobile-row">
      <div class="ledger-mobile-top">
        <time>{when}</time>
        <Status kind={ok ? 'ok' : 'error'}>{ok ? t('activity.ok') : t('activity.error')}</Status>
      </div>
      <strong>{agent}</strong>
      <code>{model}</code>
      <div class="ledger-meta">
        <span>{provider}</span>
        <span>
          {fmt(incoming)} / {fmt(outgoing)}
        </span>
        <span>{money(cost)}</span>
      </div>
      {(row.swapped || row.routed) && <small>{t('activity.switched')}</small>}
    </Card>
  ) : (
    <tr>
      <td>{when}</td>
      <td>{agent}</td>
      <td>
        <code>{model}</code>
      </td>
      <td>{provider}</td>
      <td class="number-cell">
        {fmt(incoming)} / {fmt(outgoing)}
      </td>
      <td>{money(cost)}</td>
      <td>
        <span class="row-status">
          <Status kind={ok ? 'ok' : 'error'}>{ok ? t('activity.ok') : t('activity.error')}</Status>
          {(row.swapped || row.routed) && <span class="muted">{t('activity.routed')}</span>}
        </span>
      </td>
    </tr>
  );
}
function KeyValueCard({ title, subtitle, value }: { title: string; subtitle: string; value: any }) {
  if (!value || typeof value !== 'object') return null;
  const entries = Object.entries(value).filter(
    ([, v]) => v != null && ['string', 'number', 'boolean'].includes(typeof v) && String(v).trim() !== '',
  );
  if (!entries.length) return null;
  return (
    <Card class="limit-card">
      <div>
        <h2>{title}</h2>
        <p>{subtitle}</p>
      </div>
      <dl>
        {entries.map(([k, v]) => (
          <div>
            <dt>{keyLabel(k)}</dt>
            <dd class={/id|key/i.test(k) ? 'mono' : ''}>
              {typeof v === 'number'
                ? fmt(v)
                : typeof v === 'boolean'
                  ? v
                    ? t('app.yes')
                    : t('app.no')
                  : k === 'period' && ['month', '本月'].includes(String(v))
                    ? t('collector.month')
                    : /caller.*label/i.test(k)
                      ? t('collector.callerLabel')
                      : String(v)}
            </dd>
          </div>
        ))}
      </dl>
    </Card>
  );
}
function keyLabel(k: string) {
  const keys: Record<string, string> = {
    name: 'key.name',
    version: 'key.version',
    label: 'key.caller',
    callerKeyLabel: 'key.caller',
    caller_key_label: 'key.caller',
    requests_limit: 'key.requestsLimit',
    budget: 'key.budget',
    spent: 'key.spent',
    remaining: 'key.remaining',
    period: 'key.period',
    limit: 'key.limit',
    requests: 'key.requestsLimit',
    tokens: 'key.tokens',
    active: 'key.active',
    waiting: 'key.waiting',
  };
  return keys[k] ? t(keys[k]) : k;
}
function Empty({ text }: { text: string }) {
  return (
    <div class="empty-state">
      <Icon name="minus-circle" size={20} />
      <span>{text}</span>
    </div>
  );
}
function ProfileForm({
  initial,
  cancel,
  save,
}: {
  initial: Profile;
  cancel: () => void;
  save: (p: Profile) => void;
}) {
  const [value, setValue] = useState(initial);
  const patch = (p: Partial<Profile>) => setValue((v) => ({ ...v, ...p }));
  const [err, setErr] = useState('');
  return (
    <Card class="settings-card profile-form">
      <div class="form-grid">
        <label>
          {t('settings.formName')}
          <input
            value={value.name}
            onInput={(e) => patch({ name: (e.currentTarget as HTMLInputElement).value })}
          />
        </label>
        <label>
          {t('settings.formMode')}
          <select
            value={value.mode}
            onChange={(e) => patch({ mode: (e.currentTarget as HTMLSelectElement).value as Profile['mode'] })}
          >
            <option value="live">{t('settings.liveDesc')}</option>
            <option value="direct">{t('settings.directDesc')}</option>
            <option value="mock">{t('settings.mockDesc')}</option>
          </select>
        </label>
        {value.mode === 'direct' && (
          <label>
            {t('settings.gatewayUrlLabel')}
            <input
              value={value.gatewayUrl ?? ''}
              placeholder="https://magpie.example.com"
              onInput={(e) => patch({ gatewayUrl: (e.currentTarget as HTMLInputElement).value })}
            />
          </label>
        )}
        {value.mode === 'live' && (
          <label>
            {t('settings.formWebPort')}
            <input
              type="number"
              min="1"
              max="65535"
              value={value.webPort ?? ''}
              onInput={(e) =>
                patch({ webPort: Number((e.currentTarget as HTMLInputElement).value) || undefined })
              }
            />
          </label>
        )}
        <label>
          {t('settings.formWebAddress')}
          <input
            value={value.webGuiUrl ?? ''}
            placeholder="https://magpie.example.com"
            onInput={(e) => patch({ webGuiUrl: (e.currentTarget as HTMLInputElement).value || undefined })}
          />
        </label>
        <label>
          {t('collector.collector')}
          <input
            type="url"
            value={value.collectorUrl ?? ''}
            onInput={(e) => patch({ collectorUrl: e.currentTarget.value || undefined })}
            placeholder="https://collector.example.com"
          />
        </label>
        <label>
          {t('settings.formInterval')}
          <select
            value={value.refreshSec}
            onChange={(e) =>
              patch({
                refreshSec: Number((e.currentTarget as HTMLSelectElement).value) as Profile['refreshSec'],
              })
            }
          >
            {[10, 20, 30, 60].map((n) => (
              <option value={n}>{t('settings.seconds', { seconds: n })}</option>
            ))}
          </select>
        </label>
      </div>
      {err && <p class="error-text">{err}</p>}
      <div class="row-actions">
        <button
          class="button button-primary"
          onClick={() => {
            try {
              if (!value.name.trim()) throw new Error(t('settings.nameRequired'));
              if (value.mode === 'direct' && !value.gatewayUrl)
                throw new Error(t('settings.gatewayRequired'));
              save(value);
            } catch (e) {
              setErr((e as Error).message);
            }
          }}
        >
          {t('settings.profileSaved')}
        </button>
        <button class="button" onClick={cancel}>
          {t('app.cancel')}
        </button>
      </div>
    </Card>
  );
}
function downloadProfiles(profiles: Profile[]) {
  const safe = profiles.map(
    ({ id, name, mode, gatewayUrl, webPort, webGuiUrl, collectorUrl, refreshSec }) => ({
      id,
      name,
      mode,
      gatewayUrl,
      webPort,
      webGuiUrl,
      collectorUrl,
      refreshSec,
    }),
  );
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(safe, null, 2)], { type: 'application/json' }));
  a.download = 'magpie-profiles.json';
  a.click();
  URL.revokeObjectURL(a.href);
}
function importProfileFile(
  input: HTMLInputElement,
  setProfiles: (p: Profile[]) => void,
  setNotice: (s: string) => void,
) {
  const file = input.files?.[0];
  if (!file) return;
  void file
    .text()
    .then((text) => {
      const parsed = JSON.parse(text);
      if (!Array.isArray(parsed)) throw new Error(t('settings.invalidFile'));
      setProfiles(parsed as Profile[]);
      saveProfiles(parsed as Profile[]);
      setNotice(t('settings.imported'));
    })
    .catch((e) => setNotice(t('settings.importFailed', { message: (e as Error).message })));
}
