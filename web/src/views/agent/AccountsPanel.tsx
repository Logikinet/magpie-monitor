import { fmtDate } from '../../core/format';
import type { Route } from '../../core/decode';
import { value, word, type Lang } from './shared';
import { t } from '../../i18n';
export function AccountsPanel({ route, lang }: { route: Route; lang: Lang }) {
  const text = { title: t('route.accountKeys', {}, lang), renew: t('route.renews', {}, lang), remaining: t('route.remaining', {}, lang), empty: t('route.noAccounts', {}, lang) },
    seats = [...new Map(route.order.map((s, i) => [s.id ?? `missing-${i}`, s])).values()],
    providers = [...new Set(seats.map((s) => s.provider))];
  return (
    <section class="rt-panel">
      <h2>{text.title}</h2>
      {providers.map((provider) => (
        <div class="rt-provider">
          <h3>{word(provider)}</h3>
          {seats
            .filter((s) => s.provider === provider)
            .map((s) => (
              <div class="rt-account">
                <b class="pii">{s.who ?? s.name ?? s.id ?? '—'}</b>
                <span>
                  {text.remaining} {value(s.known && s.used !== undefined ? 100 - s.used : undefined, '%')}
                </span>
                <small>
                  {s.plan} · {text.renew} {s.renews[0] ? fmtDate(s.renews[0]) : '—'}
                </small>
                {s.known && s.used !== undefined && (
                  <div class="rt-bar">
                    <i style={{ width: `${Math.max(0, Math.min(100, 100 - s.used))}%` }} />
                  </div>
                )}
              </div>
            ))}
        </div>
      ))}
      {!seats.length && <p>{text.empty}</p>}
    </section>
  );
}
