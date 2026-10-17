import { usedPercent, type QuotaSpan, type UsageSummary } from './decode';
export type TokenSource = 'window' | 'today' | 'sevenDays';
export function tokenUsage(window: QuotaSpan, provider: string, usage: UsageSummary | undefined, approximateSource: TokenSource) { if (window.amount !== undefined && Number.isFinite(window.amount) && window.amount >= 0 && /^(tokens?)$/i.test(window.unit ?? ''))
    return { count: Math.round(window.amount), source: 'window' as TokenSource }; const models = usage?.models.filter(m => m.provider === provider) ?? []; return models.length ? { count: models.reduce((sum, m) => sum + (m.input ?? 0) + (m.output ?? 0), 0), source: approximateSource } : undefined; }
const decimal = (n: number, places: number) => n.toFixed(places).replace(/\.?0+$/, '');
export function formatTokens(count: number, locale = 'zh') { const n = Number.isFinite(count) ? Math.max(0, Math.round(count)) : 0; if (locale.startsWith('zh')) {
    if (n >= 1e8)
        return decimal(n / 1e8, 1) + ' 亿';
    if (n >= 1e4)
        return decimal(n / 1e4, 1) + ' 万';
}
else {
    if (n >= 1e6)
        return decimal(n / 1e6, 2) + 'M';
    if (n >= 1e4)
        return decimal(n / 1e3, 1) + 'K';
} return n.toLocaleString('en-US'); }
export function quotaSubtitle(window: QuotaSpan, provider: string, usage?: UsageSummary, approximateSource: TokenSource = /^(week|weekly)$/i.test(window.name) ? 'sevenDays' : 'today') { const value = tokenUsage(window, provider, usage, approximateSource); return value ? `${{ window: '已消耗', today: '今日已消耗', sevenDays: '近 7 天已消耗' }[value.source]} ${formatTokens(value.count)} token` : `已用 ${Math.round(usedPercent(window))}%`; }
export const TokenUsage = { value: tokenUsage };
export const TokenFormatter = { compact: formatTokens };
