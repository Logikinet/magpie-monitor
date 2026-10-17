import { useEffect, useState } from 'preact/hooks';
import { RuntimesView as RuntimeCards } from '../collector/CollectorViews';
import type { CollectorClient, RecordData } from '../../core/collector-client';
import type { WebClient } from '../../core/web-client';
import { t } from '../../i18n';
export function RuntimesView({
  data,
  client,
  web,
  revision,
}: {
  data: RecordData;
  client?: CollectorClient;
  web: Pick<WebClient, 'providers'>;
  revision: number;
}) {
  const [providers, setProviders] = useState<RecordData[]>([]),
    [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    setProviders([]);
    setError(false);
    web
      .providers()
      .then((d) => {
        if (active) setProviders(d.providers);
      })
      .catch(() => {
        if (active) setError(true);
      });
    return () => {
      active = false;
    };
  }, [web, revision]);
  return (
    <>
      {error && <p role="alert">{t('app.loadFailed')}</p>}
      <RuntimeCards data={data} client={client} gateways={providers} />
    </>
  );
}
