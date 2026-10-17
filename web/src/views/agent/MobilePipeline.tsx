import type { Route } from '../../core/decode';
import { newestRoutes, outputSpeed, matchSeat } from '../../core/routing-model';
import { clock, strategy, value, word, type Lang } from './shared';
const text = {
  zh: { recent: '最近请求', responding: '回答中', hit: '命中', input: '输入', output: '输出' },
  en: {
    recent: 'Recent requests',
    responding: 'Responding',
    hit: 'Served by',
    input: 'Input',
    output: 'Output',
  },
};
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
  const t = text[lang],
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
        {t.hit}:{' '}
        <span class="pii">{(winner && matchSeat(route.order, winner)?.who) ?? winner?.id ?? '—'}</span> ·{' '}
        {route.done === false ? t.responding : value(route.status)} · {value(route.ms, ' ms')} · TTFT{' '}
        {value(route.ttft, ' ms')} · {value(outputSpeed(route), ' tok/s')} · {t.input}{' '}
        {Array.isArray(route.usage) && route.usage.length
          ? value(
              (route.usage as { in?: number }[]).every((u) => u.in !== undefined)
                ? (route.usage as { in: number }[]).reduce((n, u) => n + u.in, 0)
                : undefined,
            )
          : '—'}{' '}
        · {t.output} {value(route.out)}
      </p>
    </section>
  );
}
