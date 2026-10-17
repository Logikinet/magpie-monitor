import type { Route } from '../../core/decode';
import { useState } from 'preact/hooks';
import { formatDuration } from '../../core/format';
import { agentHue, requestsForAccount } from '../../core/routing-model';
import { clock, value, word, type Lang } from './shared';
import { t } from '../../i18n';
export function RequestList({
  routes,
  todayRoutes,
  selected,
  pinned,
  pick,
  live,
  account,
  clear,
  lang,
}: {
  routes: Route[];
  todayRoutes: Route[];
  selected: number;
  pinned: boolean;
  pick: (seq: number) => void;
  live: () => void;
  account: string | null;
  clear: () => void;
  lang: Lang;
}) {
  const text = {
    title: t('route.requests', {}, lang),
    live: t('route.followLive', {}, lang),
    today: t('route.today', { count: todayRoutes.length }, lang),
    clear: t('route.clearFilter', {}, lang),
    empty: t('route.noMatch', {}, lang),
  };
  const [showToday, setShowToday] = useState(false);
  const filtered = requestsForAccount(showToday ? todayRoutes : routes, account);
  return (
    <section class="rt-panel" id="rt-requests" tabIndex={-1}>
      <header>
        <h2>{text.title}</h2>
        <button
          aria-pressed={!pinned && !showToday}
          onClick={() => {
            setShowToday(false);
            live();
          }}
        >
          {text.live}
        </button>
        <button aria-pressed={showToday} onClick={() => setShowToday(true)}>
          {text.today}
        </button>
      </header>
      {account && (
        <button class="rt-filter" onClick={clear}>
          {account} × <span class="sr-only">{text.clear}</span>
        </button>
      )}
      <ol class="rt-requests">
        {filtered.map((r) => (
          <li>
            <button
              data-seq={r.seq}
              aria-pressed={r.seq === selected}
              class={r.seq === selected ? 'selected' : ''}
              onClick={() => pick(r.seq)}
            >
              <time>{clock(r.time)}</time>
              <span class="dot" style={{ background: agentHue(word(r.agent)) }} />
              <span>
                <b>{word(r.agent)}</b> <code>group/{r.group?.name ?? '—'}</code>
                <small class={Number(r.status) >= 400 ? 'rt-error' : ''}>
                  {word(r.provider)} · {word(r.served ?? r.model)}
                </small>
              </span>
              <small>
                {formatDuration(r.ms)} · {value(r.tokens, ' tk')} ·{' '}
                {r.priced ? value(r.cost, ' USD') : t('usage.unpriced', {}, lang)}
              </small>
            </button>
          </li>
        ))}
      </ol>
      {!filtered.length && <p>{text.empty}</p>}
    </section>
  );
}
