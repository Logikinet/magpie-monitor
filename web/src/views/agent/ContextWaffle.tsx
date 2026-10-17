import { useState } from 'preact/hooks';
import type { Route } from '../../core/decode';
import { contextCells, CONTEXT_KINDS, footSummary } from '../../core/routing-model';
import { value, word, type Lang } from './shared';
import { t as translate } from '../../i18n';
export function ContextWaffle({ route, lang }: { route: Route; lang: Lang }) {
  const [filter, setFilter] = useState('all'),
    [all, setAll] = useState(false),
    t = { title: translate('route.context', {}, lang), cache: translate('route.promptCache', {}, lang), all: translate('route.all', {}, lang), show: translate('route.showAll', {}, lang), free: translate('route.free', {}, lang), system: translate('route.system', {}, lang), tools: translate('route.tools', {}, lang), files: translate('route.files', {}, lang), results: translate('route.results', {}, lang), chat: translate('route.chat', {}, lang), empty: translate('route.noContext', {}, lang), turns: translate('route.turns', {}, lang) },
    cells = contextCells(route.prompt);
  const parts = (route.prompt?.parts ?? [])
    .flatMap((p) => p.items.map((item) => ({ ...item, kind: p.kind })))
    .filter((p) => filter === 'all' || p.kind === filter);
  return (
    <section class="ctx-card">
      <header>
        <h2>{t.title}</h2>
        <span>
          {value(route.prompt?.tokens, ' token')} · {t.cache} {value(footSummary(route).cacheHitPercent, '%')}
        </span>
      </header>
      {cells ? (
        <div
          class="ctx-waffle"
          role="img"
          aria-label={`${t.title}: ${value(route.prompt?.tokens)} / ${value(route.prompt?.window)}`}
        >
          {cells.map((k, i) => (
            <i class={`ctx-cell ctx-${k}`} style={{ '--d': `${(i % 40) * 3}ms` }} />
          ))}
        </div>
      ) : (
        <p>{t.empty}</p>
      )}
      <div class="ctx-legend">
        {[...CONTEXT_KINDS, 'free' as const].map((k) => (
          <span>
            <i class={`ctx-${k}`} />
            {t[k]}
          </span>
        ))}
      </div>
      <div class="ctx-tabs" aria-label={t.title}>
        {(['all', ...CONTEXT_KINDS] as const).map((k) => (
          <button
            aria-pressed={filter === k}
            onClick={() => {
              setFilter(k);
              setAll(false);
            }}
          >
            {t[k]}
          </button>
        ))}
      </div>
      <ul class="ctx-parts">
        {(all ? parts : parts.slice(0, 10)).map((p) => (
          <li>
            <span>
              {word(p.name)} {p.tag}
            </span>
            <code>{value(p.tokens, ' tk')}</code>
          </li>
        ))}
      </ul>
      {!all && parts.length > 10 && (
        <button onClick={() => setAll(true)}>
          {t.show} ({parts.length})
        </button>
      )}
      <footer>
        {word(route.session)} · {value(route.prompt?.turns)} {t.turns}
      </footer>
    </section>
  );
}
