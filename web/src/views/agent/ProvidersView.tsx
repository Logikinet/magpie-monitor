import { t as translate } from '../../i18n';
import { Icon } from '../../ui/icons';
import { useEffect, useState } from 'preact/hooks';
import type { WebClient } from '../../core/web-client';
import { fmtNumber } from '../../core/format';
import { agentHue } from '../../core/routing-model';
import { usageText } from './usage-text';
type Provider = ReturnType<typeof import('../../core/decode').decodeProviders>['providers'][number];
export function ProvidersTable({ providers }: { providers: Provider[] }) {
  const t = usageText();
  return (
    <div class="mp-providers mp-panel" data-testid="providers-view">
      {!providers.length && <p>{t.empty}</p>}
      {providers.map((p) => {
        const account = p.account,
          status =
            (account?.plan === 'standard' ? translate('provider.standard') : account?.plan) ??
            (account ? t.signedIn : p.key?.set ? (p.key.masked ?? '—') : t.free);
        return (
          <article class={`mp-provider ${p.off ? 'mp-off' : ''}`}>
            <span class="mp-provider-icon" aria-hidden="true">
              <Icon name={String(p.icon ?? 'bot')} />
            </span>
            <div class="mp-provider-name">
              <b>{p.name ?? p.id}</b>
              <small>
                {account?.user ? (
                  <>
                    {t.signedInAs} <span class="pii">{account.user}</span>
                  </>
                ) : (
                  (p.host ?? p.base ?? '—')
                )}{' '}
                · {fmtNumber(p.active_models_count ?? p.models.length)} {t.modelCount}
              </small>
            </div>
            <div class="mp-agent-icons">
              {p.agents
                .filter((a) => a.current)
                .map((a) => (
                  <span
                    class="mp-agent-icon"
                    title={String(a.name ?? a.id)}
                    aria-label={String(a.name ?? a.id)}
                  >
                    <span
                      class="mp-agent-initial"
                      style={{ background: agentHue(String(a.id ?? a.name ?? 'agent')) }}
                      title={String(a.name ?? a.id)}
                      aria-label={String(a.name ?? a.id)}
                    >
                      {String(a.name ?? a.id ?? '?')
                        .slice(0, 1)
                        .toUpperCase()}
                    </span>
                  </span>
                ))}
            </div>
            <span class={`mp-pill ${!account && p.key?.set ? 'mp-mono' : ''}`}>{status}</span>
          </article>
        );
      })}
    </div>
  );
}
export function ProvidersView({
  client,
  revision = 0,
}: {
  client: Pick<WebClient, 'providers'>;
  revision?: number;
}) {
  const [providers, setProviders] = useState<Provider[]>([]),
    [error, setError] = useState(false),
    [loading, setLoading] = useState(true),
    [version, setVersion] = useState(0);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(false);
    client
      .providers()
      .then((d) => {
        if (active) setProviders(d.providers);
      })
      .catch(() => {
        if (active) setError(true);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [client, revision, version]);
  return (
    <div class="mp-usage">
      <div class="mp-toolbar">
        <button onClick={() => setVersion((v) => v + 1)}>{usageText().refresh}</button>
      </div>
      {loading && <p role="status">{usageText().loading}</p>}
      {error && (
        <p class="mp-error" role="alert">
          {usageText().failed}
        </p>
      )}
      <ProvidersTable providers={providers} />
    </div>
  );
}
