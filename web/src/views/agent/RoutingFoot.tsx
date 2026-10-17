import type { Route, TraceEnvelope } from '../../core/decode';
import { footSummary } from '../../core/routing-model';
import { formatDuration } from '../../core/format';
import { formatElapsed, value, word, type Lang } from './shared';
import { t as translate } from '../../i18n';
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
    t = { requests: translate('usage.requests', {}, lang), retries: translate('route.retries', {}, lang), errors: translate('route.errors', {}, lang), first: translate('route.firstText', {}, lang), cache: translate('route.cacheHit', {}, lang), provider: translate('route.provider', {}, lang), model: translate('route.model', {}, lang), duration: translate('route.duration', {}, lang), tokens: translate('route.tokens', {}, lang), speed: translate('route.speed', {}, lang), status: translate('route.status', {}, lang), elapsed: translate('route.elapsed', {}, lang), responding: translate('route.responding', {}, lang) };
  return (
    <footer class="rt-foot">
      <p>
        {t.provider} {word(s.provider)} · {t.model} {word(s.model)} ·{' '}
        {route.done === false ? `${t.status} ${t.responding} · ${t.elapsed} ${formatElapsed(route.time)}` : `${t.duration} ${formatDuration(s.ms)} · ${t.tokens} ${value(s.tokens, ' tk')}`}
        {(route.ttft ?? route.tries?.find((tr) => tr.served === route.served)?.ttft) !== undefined && <> · {t.first} {formatDuration(route.ttft ?? route.tries?.find((tr) => tr.served === route.served)?.ttft)}</>}
        {s.tokensPerSecond !== null && <> · {t.speed} {value(s.tokensPerSecond, ' tok/s')}</>}
        {s.cacheHitPercent !== null && <> · {t.cache} {value(s.cacheHitPercent, '%')}</>}
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
