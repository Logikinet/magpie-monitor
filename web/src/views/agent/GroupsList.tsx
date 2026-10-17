import type { decodeGroups } from '../../core/decode';
import { word, type Lang } from './shared';
import { t } from '../../i18n';
export function GroupsList({
  groups,
  lang,
}: {
  groups: ReturnType<typeof decodeGroups>['groups'];
  lang: Lang;
}) {
  const text = { title: t('route.routingGroups', {}, lang), empty: t('route.noGroups', {}, lang) };
  return (
    <section class="rt-panel rt-groups">
      <h2>{text.title}</h2>
      {groups.map((g) => (
        <div>
          <b>{g.name ?? g.id}</b> <code>group/{g.id}</code> <span>{word(g.routing)}</span>
          <p>{g.members.join(' · ') || '—'}</p>
        </div>
      ))}
      {!groups.length && <p>{text.empty}</p>}
    </section>
  );
}
