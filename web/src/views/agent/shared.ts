import type { Route } from '../../core/decode';
export type Lang = 'zh' | 'en';
export const language = (): Lang => (new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'zh');
export const value = (v: unknown, suffix = '') =>
  typeof v === 'number' && Number.isFinite(v)
    ? `${v.toLocaleString(undefined, { maximumFractionDigits: 1 })}${suffix}`
    : '—';
export const word = (v: unknown) => (typeof v === 'string' && v ? v : '—');
export const clock = (s?: string) =>
  s && Number.isFinite(Date.parse(s))
    ? new Date(s).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })
    : '—';
const text = {
  zh: { smart: '智能分配', order: '依序尝试', rotate: '轮流分配', usage: '按用量分配' },
  en: { smart: 'Smart selection', order: 'Try in order', rotate: 'Round robin', usage: 'Usage based' },
};
export const strategy = (r: Route, lang: Lang) =>
  text[lang][(r.group?.routing || 'smart') as keyof typeof text.zh] ?? word(r.group?.routing);
