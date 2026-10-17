import { fmtDate } from '../../core/format';
import type { Route } from '../../core/decode';
import { value, word, type Lang } from './shared';
const text = {
  zh: { title: '账号与 key', renew: '续期', remaining: '剩余', empty: '暂无账号信息' },
  en: { title: 'Accounts and keys', renew: 'Renews', remaining: 'Remaining', empty: 'No account data' },
};
export function AccountsPanel({ route, lang }: { route: Route; lang: Lang }) {
  const t = text[lang],
    seats = [...new Map(route.order.map((s, i) => [s.id ?? `missing-${i}`, s])).values()],
    providers = [...new Set(seats.map((s) => s.provider))];
  return (
    <section class="rt-panel">
      <h2>{t.title}</h2>
      {providers.map((provider) => (
        <div class="rt-provider">
          <h3>{word(provider)}</h3>
          {seats
            .filter((s) => s.provider === provider)
            .map((s) => (
              <div class="rt-account">
                <b class="pii">{s.who ?? s.name ?? s.id ?? '—'}</b>
                <span>
                  {t.remaining} {value(s.known && s.used !== undefined ? 100 - s.used : undefined, '%')}
                </span>
                <small>
                  {s.plan} · {t.renew} {s.renews[0] ? fmtDate(s.renews[0]) : '—'}
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
      {!seats.length && <p>{t.empty}</p>}
    </section>
  );
}
