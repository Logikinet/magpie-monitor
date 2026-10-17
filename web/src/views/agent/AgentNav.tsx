import { language } from './shared';
import { t } from '../../i18n';
export type AgentTab = 'routing' | 'usage' | 'providers' | 'runtimes';
export function AgentNav({ tab, choose }: { tab: AgentTab; choose: (tab: AgentTab) => void }) {
  const lang = language();
  return (
    <nav class="agent-subnav" aria-label="Agent">
      {(['routing', 'usage', 'providers', 'runtimes'] as const).map((id) => (
        <button aria-current={tab === id ? 'page' : undefined} onClick={() => choose(id)}>
          {t(
            (
              {
                routing: 'agent.tabRouting',
                usage: 'agent.tabUsage',
                providers: 'agent.tabProviders',
                runtimes: 'agent.tabRuntimes',
              } as const
            )[id],
            {},
            lang,
          )}
        </button>
      ))}
    </nav>
  );
}
export function AgentPlaceholder() {
  return <section class="rt-panel">{t('agent.comingSoon')}</section>;
}
export function readPage() {
  const hash = location.hash.slice(1),
    legacy = hash.startsWith('cat='),
    [path, query] = hash.replace(/^\//, '').split('?'),
    params = new URLSearchParams(legacy ? hash : query);
  const original = legacy ? params.get('cat') : path;
  const aliases: Record<string, string> = {
    overview: 'home',
    all: 'home',
    goal: 'tmux',
    log: 'svc',
    network: 'svc',
    manage: 'agent',
    tools: 'agent',
    quotas: 'agent',
  };
  const page = aliases[original ?? ''] ?? original;
  const atab = original === 'quotas' ? 'usage' : params.get('atab');
  return {
    tab: ['home', 'activity', 'tmux', 'agent', 'svc', 'settings'].includes(page ?? '') ? page! : 'home',
    atab: (['routing', 'usage', 'providers', 'runtimes'].includes(atab ?? '') ? atab : 'routing') as AgentTab,
  };
}
