import { language } from './shared';
export type AgentTab = 'routing' | 'usage' | 'providers' | 'runtimes';
const text = {
  zh: { routing: '实时路由', usage: '用量与配额', providers: '服务商', runtimes: '运行时', next: '即将推出' },
  en: {
    routing: 'Routing',
    usage: 'Usage',
    providers: 'Providers',
    runtimes: 'Runtimes',
    next: 'Coming next',
  },
};
export function AgentNav({ tab, choose }: { tab: AgentTab; choose: (tab: AgentTab) => void }) {
  const t = text[language()];
  return (
    <nav class="agent-subnav" aria-label="Agent">
      {(['routing', 'usage', 'providers', 'runtimes'] as const).map((id) => (
        <button aria-current={tab === id ? 'page' : undefined} onClick={() => choose(id)}>
          {t[id]}
        </button>
      ))}
    </nav>
  );
}
export function AgentPlaceholder() {
  return <section class="rt-panel">{text[language()].next}</section>;
}
export function readPage() {
  const hash = location.hash.slice(1),
    legacy = hash.startsWith('cat='),
    [path, query] = hash.replace(/^\//, '').split('?'),
    params = new URLSearchParams(legacy ? hash : query);
  const page = legacy ? params.get('cat') : path;
  const atab = page === 'quotas' ? 'usage' : params.get('atab');
  return {
    tab:
      page === 'quotas'
        ? 'agent'
        : ['overview', 'activity', 'agent', 'settings'].includes(page ?? '')
          ? page!
          : 'overview',
    atab: (['routing', 'usage', 'providers', 'runtimes'].includes(atab ?? '') ? atab : 'routing') as AgentTab,
  };
}
