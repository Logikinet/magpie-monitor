import type { Route } from '../../core/decode';
import { fmtNumber, fmtDate, formatDuration } from '../../core/format';
import { t as translate } from '../../i18n';
export { formatDuration } from '../../core/format';
export type Lang = 'zh' | 'en' | 'ja';
export const language = (): Lang => {
  const selected = localStorage.getItem('mm-lang');
  if (selected === 'zh' || selected === 'en' || selected === 'ja') return selected;
  const query = new URLSearchParams(location.search).get('lang');
  if (query === 'zh' || query === 'en' || query === 'ja') return query;
  return navigator.language.startsWith('ja') ? 'ja' : navigator.language.startsWith('en') ? 'en' : 'zh';
};
export const value = (v: unknown, suffix = '') =>
  typeof v === 'number' && Number.isFinite(v) ? `${fmtNumber(v, 1)}${suffix}` : '—';
export const word = (v: unknown) => (typeof v === 'string' && v ? v : '—');
export const clock = (s?: string) => fmtDate(s, undefined, true);
export const elapsedSeconds = (s?: string) => {
  const start = s ? Date.parse(s) : NaN;
  return Number.isFinite(start) ? Math.max(0, Math.floor((Date.now() - start) / 1000)) : null;
};
export const formatElapsed = (s?: string, now = Date.now()) => {
  const start = s ? Date.parse(s) : NaN;
  return Number.isFinite(start) ? formatDuration(Math.max(0, now - start)) : '—';
};
export const strategy = (r: Route, lang: Lang) =>
  translate(({ smart: 'strategy.smart', order: 'strategy.order', rotate: 'strategy.rotate', usage: 'strategy.usage' } as const)[(r.group?.routing || 'smart') as 'smart' | 'order' | 'rotate' | 'usage'] ?? 'strategy.smart', {}, lang) ?? word(r.group?.routing);
