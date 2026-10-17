import { useEffect, useState } from 'preact/hooks';
import type { TraceState } from '../../core/longpoll';
import type { Route, TraceEnvelope, decodeGroups } from '../../core/decode';
import type { WebClient } from '../../core/web-client';
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
import { t as translate } from '../../i18n';
export function RoutingView({
  routes,
  totals,
  groups = [],
  loading = false,
  state,
  refresh = () => {},
  usage = () => {},
  client,
  lang = language(),
}: {
  routes: Route[];
  totals?: TraceEnvelope['totals'];
  groups?: ReturnType<typeof decodeGroups>['groups'];
  loading?: boolean;
  state?: TraceState;
  refresh?: () => void;
  usage?: () => void;
  client?: Pick<WebClient, 'history'>;
  lang?: Lang;
}) {
  const [pinned, setPinned] = useState<number | null>(null),
    [account, setAccount] = useState<string | null>(null),
    [masked, setMasked] = useState(false),
    [now, setNow] = useState(Date.now());
  const [todayHistory, setTodayHistory] = useState<Route[]>([]);
  const today = new Date().toLocaleDateString('en-CA');
  const window = routeWindow(routes),
    route = currentRoute(window, pinned),
    t = { group: translate('route.group', {}, lang), active: translate('route.active', {}, lang), agents: translate('route.agents', {}, lang), live: translate('route.live', {}, lang), loading: translate('route.loading', {}, lang), refresh: translate('route.refresh', {}, lang), running: translate('route.running', {}, lang), offline: translate('route.offline', {}, lang), backoff: translate('route.backoff', {}, lang), needsAuth: translate('route.auth', {}, lang), stopped: translate('route.stopped', {}, lang), empty: translate('route.empty', {}, lang), mask: translate('route.hide', {}, lang), show: translate('route.show', {}, lang), smart: translate('route.smartDesc', {}, lang), order: translate('route.orderDesc', {}, lang), rotate: translate('route.rotateDesc', {}, lang), usage: translate('route.usageDesc', {}, lang) };
  useEffect(() => {
    let active = true;
    client?.history(today).then((result) => { if (active) setTodayHistory(result.routes); }).catch(() => {});
    return () => { active = false; };
  }, [client, today]);
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
          todayRoutes={todayHistory.length ? todayHistory : window.filter((r) => r.time?.slice(0, 10) === today)}
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
