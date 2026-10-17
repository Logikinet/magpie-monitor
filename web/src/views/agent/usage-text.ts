import { activeLocale } from '../../core/format';
import { t } from '../../i18n';
const keys = {
  today: 'usage.today', week: 'usage.week', month: 'usage.month', all: 'usage.all', console: 'usage.console',
  hide: 'usage.hideAccounts', show: 'usage.showAccounts', remaining: 'usage.remaining', used: 'usage.used',
  updated: 'usage.updated', requests: 'usage.requests', cost: 'usage.cost', tokens: 'usage.tokens', cache: 'usage.cache',
  ttft: 'usage.ttft', errors: 'usage.errors', unpriced: 'usage.unpriced', samples: 'usage.samples', more: 'usage.moreAccounts',
  resets: 'usage.resets', runsOut: 'usage.runsOut', daily: 'usage.daily', resetCount: 'usage.resetCount', trend: 'usage.trend',
  agents: 'usage.byAgent', models: 'usage.byModel', accounts: 'usage.accounts', refresh: 'app.refresh', empty: 'usage.noData',
  loading: 'app.loading', failed: 'usage.failed', signedInAs: 'usage.signedInAs', modelCount: 'usage.modelCount',
  free: 'usage.free', signedIn: 'usage.signedIn', balanceTrend: 'usage.balanceTrend',
} as const;
export const usageText = () => Object.fromEntries(Object.entries(keys).map(([key, message]) => [key, t(message, {}, activeLocale())])) as Record<keyof typeof keys, string>;
