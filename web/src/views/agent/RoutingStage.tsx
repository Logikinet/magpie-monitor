import { fmtDate } from '../../core/format';
// Stage layout and wire behavior adapted from yetone/magpie routing plugin (MIT), @7660399.
import { useEffect, useRef, useState } from 'preact/hooks';
import type { Route } from '../../core/decode';
import { agentHue, groupSeats, recentAgents, seatKey, seatState, seatStatus } from '../../core/routing-model';
import { agentToHub, hubToRow, relativeRect, subheaderToRow } from '../../core/wire-geometry';
import { strategy, value, word, type Lang } from './shared';
import { t as translate } from '../../i18n';
export function RoutingStage({
  route,
  routes,
  now,
  account,
  filter,
  lang,
}: {
  route: Route;
  routes: Route[];
  now: number;
  account: string | null;
  filter: (id: string) => void;
  lang: Lang;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [paths, setPaths] = useState<{ d: string; key: string; state?: string; live?: boolean }[]>([]);
  const [hover, setHover] = useState('');
  const groups = groupSeats(route, now),
    agents = recentAgents(routes),
    t = {
      accounts: translate('route.accounts', {}, lang),
      available: translate('route.available', {}, lang),
      fallback: translate('route.fallback', {}, lang),
      trying: translate('route.trying', {}, lang),
      answered: translate('route.answered', {}, lang),
      resting: translate('route.resting', {}, lang),
      remaining: translate('route.remaining', {}, lang),
      credits: translate('route.credits', {}, lang),
      'single-key': translate('route.singleKey', {}, lang),
      ready: translate('route.ready', {}, lang),
      reset: translate('route.reset', {}, lang),
    };
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    let frame = 0;
    const measure = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const origin = el.getBoundingClientRect(),
          hub = el.querySelector('.rt-hub');
        if (!hub) return;
        el.querySelector('svg')?.setAttribute('viewBox', `0 0 ${origin.width} ${origin.height}`);
        const rect = (node: Element) => relativeRect(node.getBoundingClientRect(), origin);
        const h = rect(hub),
          next: typeof paths = [];
        el.querySelectorAll<HTMLElement>('[data-agent]').forEach((node) =>
          next.push({
            key: `agent-${node.dataset.agent}`,
            d: agentToHub(rect(node), h),
            live: node.dataset.agent === route.agent,
            state: route.done ? 'finished' : undefined,
          }),
        );
        el.querySelectorAll<HTMLElement>('[data-seat]').forEach((node) => {
          const header = node.dataset.group
            ? el.querySelector(`[data-header="${node.dataset.group}"]`)
            : null;
          next.push({
            key: node.dataset.seat!,
            d: header ? subheaderToRow(rect(header), rect(node)) : hubToRow(h, rect(node)),
            state: node.dataset.state,
            live: node.dataset.state === 'trying' || node.dataset.state === 'answered',
          });
        });
        el.querySelectorAll<HTMLElement>('[data-header]').forEach((node) =>
          next.push({
            key: `header-${node.dataset.header}`,
            d: hubToRow(h, rect(node)),
            live: !!node.parentElement?.querySelector('.on'),
          }),
        );
        setPaths(next);
      });
    };
    measure();
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(measure);
    observer?.observe(el);
    addEventListener('resize', measure);
    return () => {
      cancelAnimationFrame(frame);
      observer?.disconnect();
      removeEventListener('resize', measure);
    };
  }, [route, routes, now]);
  return (
    <div class="rt-stage" ref={box} style={{ '--agent': agentHue(word(route.agent)) }}>
      <svg class="rt-wires" aria-hidden="true">
        {paths.map((p) => (
          <path
            key={p.key}
            d={p.d}
            class={`${p.live ? 'live' : ''} ${hover === p.key ? 'lit' : ''} ${p.state === 'rest' ? 'rest' : ''} ${p.state === 'answered' ? 'answered' : p.state === 'finished' ? 'finished' : ''}`}
          />
        ))}
      </svg>
      <div class="rt-srcs">
        {agents.map((a) => (
          <div
            class={`rt-node ${route.agent === a ? 'selected' : ''}`}
            data-agent={a}
            style={{ '--agent': agentHue(a) }}
          >
            <span class="rt-icon">{a.slice(0, 1).toUpperCase()}</span>
            <b>{a}</b>
          </div>
        ))}
      </div>
      <div class="rt-node rt-hub">
        <span class="rt-icon rt-logo">M</span>
        <b>magpie</b>
        <small>127.0.0.1:3426</small>
        <span class="rt-pill">{strategy(route, lang)}</span>
      </div>
      <ol class="rt-accts">
        {groups.map((g, i) => (
          <li class="rt-seat-group" key={g.key}>
            {g.seats.length > 1 && (
              <div class="rt-sub" data-header={i}>
                <b>{word(g.provider)}</b>
                <code>{word(g.model)}</code>
                <small>
                  {g.accounts} {t.accounts} · {g.available} {t.available}
                </small>
              </div>
            )}
            <ol>
              {g.seats.map((s, j) => {
                const state = seatState(s, route, now),
                  status = seatStatus(s, route, now),
                  key = `${i}-${j}`;
                return (
                  <li
                    key={seatKey(s)}
                    data-seat={key}
                    data-group={g.seats.length > 1 ? i : undefined}
                    data-state={state}
                    class={`${state === 'trying' || state === 'answered' ? 'on' : ''} ${state === 'rest' ? 'rest' : ''} ${account === s.id ? 'filtered' : ''}`}
                    onMouseEnter={() => setHover(key)}
                    onMouseLeave={() => setHover('')}
                  >
                    <button
                      disabled={!s.id}
                      aria-pressed={account === s.id}
                      onFocus={() => setHover(key)}
                      onBlur={() => setHover('')}
                      onClick={() => s.id && filter(s.id)}
                    >
                      <span class="dot" />
                      <span>
                        <b class="pii">{s.who ?? s.name ?? s.id ?? '—'}</b> <small>{s.plan}</small>{' '}
                        <code>{s.model}</code> {s.fallback && <span class="rt-pill">{t.fallback}</span>}
                      </span>
                      <em>
                        {status.kind === 'remaining'
                          ? `${t.remaining} ${value(status.params.percent, '%')}${typeof status.params.resetInMs === 'number' ? ' · ' + translate('route.resetDays', { days: Math.ceil(status.params.resetInMs / 86400000) }, lang) : ''}`
                          : status.kind === 'credits'
                            ? `${t.credits} ${value(status.params.amount)} ${status.params.unit ?? ''}`
                            : t[status.kind]}
                      </em>
                      {status.kind !== 'remaining' && typeof status.params.resetInMs === 'number' && (
                        <small class="rt-renew">
                          {t.reset} · {fmtDate(now + status.params.resetInMs)}
                        </small>
                      )}
                      {s.known && s.used !== undefined && (
                        <span class="rt-bar">
                          <i style={{ width: `${Math.max(0, Math.min(100, 100 - s.used))}%` }} />
                        </span>
                      )}
                    </button>
                  </li>
                );
              })}
            </ol>
          </li>
        ))}
      </ol>
    </div>
  );
}
