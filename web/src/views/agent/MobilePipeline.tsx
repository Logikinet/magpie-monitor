import type { Route } from '../../core/decode';
import { newestRoutes, outputSpeed, matchSeat } from '../../core/routing-model';
import { formatDuration } from '../../core/format';
import { clock, formatElapsed, strategy, value, word, type Lang } from './shared';
import { t as translate } from '../../i18n';
export function MobilePipeline({
  route,
  routes,
  pick,
  lang,
}: {
  route: Route;
  routes: Route[];
  pick: (seq: number) => void;
  lang: Lang;
}) {
  const t = { recent: translate('route.recent', {}, lang), responding: translate('route.responding', {}, lang), hit: translate('route.hit', {}, lang), input: translate('route.input', {}, lang), output: translate('route.output', {}, lang), duration: translate('route.duration', {}, lang), elapsed: translate('route.elapsed', {}, lang), first: translate('route.firstText', {}, lang), speed: translate('route.speed', {}, lang), status: translate('route.status', {}, lang) },
    winner = [...(route.tries ?? [])]
      .reverse()
      .find(
        (tr) =>
          tr.done &&
          tr.status !== undefined &&
          tr.status < 400 &&
          !tr.fail &&
          !tr.error &&
          !tr.gone &&
          !tr.earlier &&
          !tr.again &&
          !tr.replan,
      );
  const selectedTry = route.done === false ? route.tries?.at(-1) : winner;
  return (
    <section class="rt-pipeline-m">
      <div class="rt-recent" aria-label={t.recent}>
        {newestRoutes(routes)
          .slice(0, 8)
          .map((r) => (
            <button aria-pressed={route.seq === r.seq} onClick={() => pick(r.seq)}>
              {word(r.agent)} › {word(r.provider)} {clock(r.time)}
            </button>
          ))}
      </div>
      <div class="rt-mobile-flow">
        <div>
          {word(route.agent)}
          <small>{word(route.model)}</small>
        </div>
        <span>→</span>
        <div>
          <b class="rt-logo">M</b> magpie<small>{strategy(route, lang)}</small>
        </div>
        <span>→</span>
        <div class="rt-ok">
          {word(route.provider)}
          <small>{word(route.served)}</small>
        </div>
      </div>
      <p>
        {t.hit}: <span class="pii">{(selectedTry && matchSeat(route.order, selectedTry)?.who) ?? selectedTry?.id ?? '—'}</span>
        {route.done === false
          ? ` · ${t.status} ${t.responding} · ${t.elapsed} ${formatElapsed(route.time)}`
          : ` · ${t.status} ${value(route.status)} · ${t.duration} ${formatDuration(route.ms)}`}
        {(route.ttft ?? route.tries?.find((tr) => tr.served === route.served)?.ttft) !== undefined && <> · {t.first} {formatDuration(route.ttft ?? route.tries?.find((tr) => tr.served === route.served)?.ttft)}</>}
        {route.done !== false && outputSpeed(route) !== null && <> · {t.speed} {value(outputSpeed(route), ' tok/s')}</>}
        {route.done !== false && <>
          {Array.isArray(route.usage) && route.usage.length && (route.usage as { in?: number }[]).every((u) => u.in !== undefined) && <> · {t.input} {(route.usage as { in: number }[]).reduce((n, u) => n + u.in, 0).toLocaleString()}</>}
          {route.out !== undefined && <> · {t.output} {value(route.out)}</>}
        </>}
      </p>
    </section>
  );
}
