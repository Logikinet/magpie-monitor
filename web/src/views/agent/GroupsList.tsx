import type { decodeGroups } from '../../core/decode';
import { word, type Lang } from './shared';
const text = {
  zh: { title: '路由组', empty: '暂无路由组' },
  en: { title: 'Routing groups', empty: 'No routing groups' },
};
export function GroupsList({
  groups,
  lang,
}: {
  groups: ReturnType<typeof decodeGroups>['groups'];
  lang: Lang;
}) {
  const t = text[lang];
  return (
    <section class="rt-panel rt-groups">
      <h2>{t.title}</h2>
      {groups.map((g) => (
        <div>
          <b>{g.name ?? g.id}</b> <code>group/{g.id}</code> <span>{word(g.routing)}</span>
          <p>{g.members.join(' · ') || '—'}</p>
        </div>
      ))}
      {!groups.length && <p>{t.empty}</p>}
    </section>
  );
}
