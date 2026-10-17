import type { Route } from '../../core/decode';
import { failedTry, latencyBreakdown } from '../../core/routing-model';
import { formatDuration } from '../../core/format';
import { value, word, type Lang } from './shared';
import { t as translate } from '../../i18n';
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
  const t = { title: translate('route.decisions', {}, lang), details: translate('route.usageDetails', {}, lang), refresh: translate('app.refresh', {}, lang), empty: translate('route.noDecisions', {}, lang), stream: translate('route.stream', {}, lang), total: translate('route.total', {}, lang), magpie: translate('route.gateway', {}, lang), network: translate('route.network', {}, lang), vendor: translate('route.vendor', {}, lang), dns: 'DNS', tcp: 'TCP', tls: 'TLS', send: translate('route.send', {}, lang), ttft: translate('route.ttft', {}, lang) },
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
              {(tr.fail || tr.error || tr.status !== undefined || tr.ms !== undefined) && (
                <small>
                  {tr.fail ?? tr.error ?? (tr.status === undefined ? '' : `HTTP ${tr.status}`)}
                  {(tr.fail || tr.error || tr.status !== undefined) && tr.ms !== undefined ? ' · ' : ''}
                  {tr.ms !== undefined ? formatDuration(tr.ms) : ''}
                </small>
              )}
            </li>
          ))
        ) : (
          <li>{t.empty}</li>
        )}
      </ol>
      <div class="rt-latency" aria-label={`${t.total} ${formatDuration(b.total)}`}>
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
          [t.magpie]: b.magpie,
          [t.network]: b.network,
          [t.vendor]: b.vendor,
          [t.dns]: b.dns,
          [t.tcp]: b.tcp,
          [t.tls]: b.tls,
          [t.send]: b.send,
          [t.ttft]: b.ttft,
          [t.stream]: b.stream,
        }).map(([k, v]) => (
          <div>
            <dt>{k}</dt>
            <dd>{formatDuration(v)}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
