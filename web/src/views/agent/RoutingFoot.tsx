import type { Route, TraceEnvelope } from '../../core/decode';
import { footSummary } from '../../core/routing-model';
import { elapsedSeconds, value, word, type Lang } from './shared';
const text = {
  zh: { requests: '请求', retries: '迂回', errors: '错误', first: '首字', cache: '缓存命中', provider: '服务商', model: '模型', duration: '耗时', tokens: 'Token', speed: '速度', status: '状态', elapsed: '已用', responding: '回答中' },
  en: { requests: 'Requests', retries: 'Rerouted', errors: 'Errors', first: 'First text', cache: 'Cache hit', provider: 'Provider', model: 'Model', duration: 'Duration', tokens: 'Tokens', speed: 'Speed', status: 'Status', elapsed: 'Elapsed', responding: 'Responding' },
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
        {t.provider} {word(s.provider)} · {t.model} {word(s.model)} ·{' '}
        {route.done === false ? `${t.status} ${t.responding} · ${t.elapsed} ${value(elapsedSeconds(route.time), 's')}` : `${t.duration} ${value(s.ms, ' ms')} · ${t.tokens} ${value(s.tokens, ' tk')}`}
        {s.firstText !== null && <> · {t.first} {value(s.firstText, ' ms')}</>}
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
