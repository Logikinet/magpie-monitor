import type { Route, TraceEnvelope } from '../../core/decode';
import { footSummary } from '../../core/routing-model';
import { value, word, type Lang } from './shared';
const text = {
  zh: { requests: '请求', retries: '迂回', errors: '错误', first: '首字', cache: '缓存' },
  en: { requests: 'Requests', retries: 'Rerouted', errors: 'Errors', first: 'First text', cache: 'Cache' },
};
export function RoutingFoot({
  route,
  totals,
  error,
  lang,
}: {
  route: Route;
  totals?: TraceEnvelope['totals'];
  error: () => void;
  lang: Lang;
}) {
  const s = footSummary(route, totals),
    t = text[lang];
  return (
    <footer class="rt-foot">
      <p>
        {word(s.provider)} · {word(s.model)} · {value(s.ms, ' ms')} · {value(s.tokens, ' tk')} · {t.first}{' '}
        {value(s.firstText, ' ms')} · {value(s.tokensPerSecond, ' tok/s')} · {t.cache}{' '}
        {value(s.cacheHitPercent, '%')}
      </p>
      <div class="rt-stats">
        <span>
          {t.requests} {value(s.counts.requests)}
        </span>
        <span class={s.counts.retries ? 'rt-warn' : ''}>
          {t.retries} {value(s.counts.retries)}
        </span>
        <button class={s.counts.errors ? 'rt-error' : ''} onClick={error}>
          {t.errors} {value(s.counts.errors)}
        </button>
      </div>
    </footer>
  );
}
