import type { Route } from '../../core/decode';
import { fmtNumber, fmtDate, formatDuration } from '../../core/format';
export { formatDuration } from '../../core/format';
export type Lang = 'zh' | 'en';
export const language = (): Lang => (new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'zh');
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
const text = {
  zh: { smart: '智能分配', order: '依序尝试', rotate: '轮流分配', usage: '按用量分配' },
  en: { smart: 'Smart selection', order: 'Try in order', rotate: 'Round robin', usage: 'Usage based' },
};
export const strategy = (r: Route, lang: Lang) =>
  text[lang][(r.group?.routing || 'smart') as keyof typeof text.zh] ?? word(r.group?.routing);
