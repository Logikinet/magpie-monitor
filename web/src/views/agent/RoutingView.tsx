import { useEffect, useState } from 'preact/hooks';
import type { TraceState } from '../../core/longpoll';
import type { Route, TraceEnvelope, decodeGroups } from '../../core/decode';
import { currentRoute, errorJumpTarget, recentAgents, routeWindow } from '../../core/routing-model';
import { RoutingStage } from './RoutingStage';
import { RoutingFoot } from './RoutingFoot';
import { RoutingLog } from './RoutingLog';
import { ContextWaffle } from './ContextWaffle';
import { RequestList } from './RequestList';
import { AccountsPanel } from './AccountsPanel';
import { GroupsList } from './GroupsList';
import { MobilePipeline } from './MobilePipeline';
import { clock, language, strategy, type Lang } from './shared';
const text = {
  zh: {
    group: '路由组',
    active: '有效席位',
    agents: '个 Agent',
    live: '回到实时',
    loading: '正在加载路由…',
    refresh: '刷新路由',
    running: '实时连接',
    offline: '等待网关连接',
    backoff: '正在重新连接',
    needsAuth: '请在设置中更新密钥',
    stopped: '连接已暂停',
    empty: '暂无请求，等待路由事件',
    mask: '隐藏账号',
    show: '显示账号',
    smart: '结合可用状态选择目标。',
    order: '按配置顺序尝试可用目标。',
    rotate: '在可用目标之间轮流分配。',
    usage: '优先选择用量较低的可用目标。',
  },
  en: {
    group: 'routing group',
    active: 'active',
    agents: 'agents',
    live: 'Back to live',
    loading: 'Loading routes…',
    refresh: 'Refresh routes',
    running: 'Live connection',
    offline: 'Waiting for gateway',
    backoff: 'Reconnecting',
    needsAuth: 'Update credentials in Settings',
    stopped: 'Connection paused',
    empty: 'No requests yet. Waiting for routing events.',
    mask: 'Hide accounts',
    show: 'Show accounts',
    smart: 'Select an available target using routing signals.',
    order: 'Try available targets in their configured order.',
    rotate: 'Take turns across available targets.',
    usage: 'Prefer available targets with lower usage.',
  },
};
export function RoutingView({
  routes,
  totals,
  groups = [],
  loading = false,
  state,
  refresh = () => {},
  usage = () => {},
  lang = language(),
}: {
  routes: Route[];
  totals?: TraceEnvelope['totals'];
  groups?: ReturnType<typeof decodeGroups>['groups'];
  loading?: boolean;
  state?: TraceState;
  refresh?: () => void;
  usage?: () => void;
  lang?: Lang;
}) {
  const [pinned, setPinned] = useState<number | null>(null),
    [account, setAccount] = useState<string | null>(null),
    [masked, setMasked] = useState(false),
    [now, setNow] = useState(Date.now());
  const window = routeWindow(routes),
    route = currentRoute(window, pinned),
    t = text[lang];
  useEffect(() => {
    if (pinned !== null && !window.some((r) => r.seq === pinned)) setPinned(null);
  }, [routes, pinned]);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const scroll = (seq?: number) => {
    const el = document.getElementById('rt-requests');
    el?.scrollIntoView?.({
      behavior: globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth',
      block: 'start',
    });
    el?.focus({ preventScroll: true });
    if (seq !== undefined)
      requestAnimationFrame(() =>
        el?.querySelector(`[data-seq="${seq}"]`)?.scrollIntoView?.({ block: 'nearest' }),
      );
  };
  if (!route)
    return (
      <section class="routing-view rt-panel" role="status">
        {loading ? <span class="rt-loading">◌ {t.loading}</span> : t.empty}
        {state && <p>{t[state]}</p>}
        <button onClick={refresh}>{t.refresh}</button>
      </section>
    );
  const mode = (route.group?.routing || 'smart') as 'smart' | 'order' | 'rotate' | 'usage';
  return (
    <div
      class={`routing-view ${masked ? 'rt-masked' : ''}`}
      data-testid="routing-view"
      data-current-seq={route.seq}
    >
      <section class="rt">
        <header class="rt-top">
          <div>
            <b>{route.group?.name ?? route.group?.id ?? '—'}</b> · {t.group} ·{' '}
            {route.order.filter((s) => !s.fallback).length} {t.active} · {recentAgents(routes).length}{' '}
            {t.agents}
          </div>
          <div class="rt-actions">
            {state && <span role="status">{t[state]}</span>}
            {pinned !== null && (
              <>
                <span class="rt-pin">
                  #{route.seq} · {clock(route.time)}
                </span>
                <button onClick={() => setPinned(null)}>{t.live}</button>
              </>
            )}
            <button aria-pressed={masked} onClick={() => setMasked(!masked)}>
              {masked ? t.show : t.mask}
            </button>
          </div>
        </header>
        <p class="rt-mode">
          {strategy(route, lang)} · {t[mode] ?? '—'}
        </p>
        <MobilePipeline route={route} routes={window} pick={setPinned} lang={lang} />
        <RoutingStage
          route={route}
          routes={window}
          now={now}
          account={account}
          filter={(id) => {
            setAccount(account === id ? null : id);
            scroll();
          }}
          lang={lang}
        />
        <RoutingFoot
          route={route}
          totals={totals}
          error={() => {
            const target = errorJumpTarget(window);
            if (target) {
              setPinned(target.seq);
              setAccount(null);
              scroll(target.seq);
            }
          }}
          lang={lang}
        />
        <RoutingLog route={route} lang={lang} refresh={refresh} usage={usage} />
      </section>
      <ContextWaffle key={route.seq} route={route} lang={lang} />
      <div class="rt-more">
        <RequestList
          routes={window}
          selected={route.seq}
          pinned={pinned !== null}
          pick={setPinned}
          live={() => setPinned(null)}
          account={account}
          clear={() => setAccount(null)}
          lang={lang}
        />
        <AccountsPanel route={route} lang={lang} />
      </div>
      <GroupsList groups={groups} lang={lang} />
    </div>
  );
}
