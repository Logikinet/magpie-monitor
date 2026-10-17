import type { Route } from '../../core/decode';
import { failedTry, latencyBreakdown } from '../../core/routing-model';
import { value, word, type Lang } from './shared';
const text = {
  zh: {
    title: '请求决策过程',
    details: '用量详情',
    refresh: '刷新',
    empty: '没有决策记录',
    stream: '输出',
    total: '总计',
  },
  en: {
    title: 'Request decisions',
    details: 'Usage details',
    refresh: 'Refresh',
    empty: 'No decision records',
    stream: 'Stream',
    total: 'Total',
  },
};
export function RoutingLog({
  route,
  lang,
  refresh,
  usage,
}: {
  route: Route;
  lang: Lang;
  refresh: () => void;
  usage: () => void;
}) {
  const t = text[lang],
    b = latencyBreakdown(route),
    segments = [b.magpie, b.network, b.vendor],
    sum = segments.reduce<number>((n, v) => n + (v ?? 0), 0);
  return (
    <section class="rt-log">
      <header>
        <h2>{t.title}</h2>
        <button onClick={usage}>{t.details}</button>
        <button aria-label={t.refresh} onClick={refresh}>
          ↻
        </button>
      </header>
      <ol class="rt-steps">
        {route.tries?.length ? (
          route.tries.map((tr, i) => (
            <li
              class={
                failedTry(tr)
                  ? 'rt-error'
                  : tr.gone || tr.earlier || tr.again || tr.replan
                    ? 'aside'
                    : tr.done
                      ? 'ok rt-ok'
                      : 'why'
              }
            >
              <span>
                {i + 1}. {word(tr.id)} · {word(tr.model)}
              </span>
              <small>
                {tr.fail ?? tr.error ?? (tr.status === undefined ? '—' : String(tr.status))} ·{' '}
                {value(tr.ms, ' ms')}
              </small>
            </li>
          ))
        ) : (
          <li>{t.empty}</li>
        )}
      </ol>
      <div class="rt-latency" aria-label={`${t.total} ${value(b.total, ' ms')}`}>
        {segments.map(
          (v, i) =>
            v !== null && (
              <span
                style={{
                  width: `${sum ? (v / sum) * 100 : 0}%`,
                  background: ['#64d2ff', '#ff9f0a', '#30d158'][i],
                }}
              />
            ),
        )}
      </div>
      <dl class="rt-timings">
        {Object.entries({
          magpie: b.magpie,
          net: b.network,
          vendor: b.vendor,
          DNS: b.dns,
          TCP: b.tcp,
          TLS: b.tls,
          send: b.send,
          TTFT: b.ttft,
          [t.stream]: b.stream,
        }).map(([k, v]) => (
          <div>
            <dt>{k}</dt>
            <dd>{value(v, ' ms')}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
