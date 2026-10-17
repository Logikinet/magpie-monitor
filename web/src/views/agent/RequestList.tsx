import type { Route } from '../../core/decode';
import { agentHue, requestsForAccount } from '../../core/routing-model';
import { clock, value, word, type Lang } from './shared';
const text = {
  zh: { title: '请求记录', live: '跟随实时', clear: '清除账号筛选', empty: '没有匹配的请求' },
  en: {
    title: 'Requests',
    live: 'Follow live',
    clear: 'Clear account filter',
    empty: 'No matching requests',
  },
};
export function RequestList({
  routes,
  selected,
  pinned,
  pick,
  live,
  account,
  clear,
  lang,
}: {
  routes: Route[];
  selected: number;
  pinned: boolean;
  pick: (seq: number) => void;
  live: () => void;
  account: string | null;
  clear: () => void;
  lang: Lang;
}) {
  const t = text[lang],
    filtered = requestsForAccount(routes, account);
  return (
    <section class="rt-panel" id="rt-requests" tabIndex={-1}>
      <header>
        <h2>{t.title}</h2>
        <button aria-pressed={!pinned} onClick={live}>
          {t.live}
        </button>
      </header>
      {account && (
        <button class="rt-filter" onClick={clear}>
          {account} × <span class="sr-only">{t.clear}</span>
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
                {value(r.ms, ' ms')} · {value(r.tokens, ' tk')} · {r.priced ? value(r.cost, ' USD') : '—'}
              </small>
            </button>
          </li>
        ))}
      </ol>
      {!filtered.length && <p>{t.empty}</p>}
    </section>
  );
}
