import { detectLocale } from '../i18n';
import type { Locale } from '../i18n';
export type { Locale };
export const activeLocale = detectLocale;
export const fmtNumber = (n: unknown, digits = 0, locale: Locale = activeLocale()) =>
  typeof n === 'number' && Number.isFinite(n)
    ? new Intl.NumberFormat(locale, { maximumFractionDigits: digits }).format(n)
    : '—';
export function fmtTokens(n: unknown, locale: Locale = activeLocale()): string {
  if (typeof n !== 'number' || !Number.isFinite(n)) return '—';
  const scale = Math.abs(n) >= 1e9 ? 1e9 : Math.abs(n) >= 1e6 ? 1e6 : Math.abs(n) >= 1e3 ? 1e3 : 1;
  return (
    fmtNumber(n / scale, scale === 1 ? 0 : 1, locale) +
    { 1: '', 1000: 'K', 1000000: 'M', 1000000000: 'B' }[scale]
  );
}
export function fmtCost(n: unknown, locale: Locale = activeLocale()): string {
  if (typeof n !== 'number' || !Number.isFinite(n)) return '—';
  const digits = Math.abs(n) >= 100 ? 1 : Math.abs(n) >= 1 ? 2 : n === 0 ? 0 : 3;
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(n);
}
export const fmtLatency = (n: unknown, locale: Locale = activeLocale()) =>
  typeof n === 'number' && Number.isFinite(n) && n >= 0
    ? `${fmtNumber(n >= 1000 ? n / 1000 : n, n >= 1000 ? 1 : 0, locale)} ${n >= 1000 ? 's' : 'ms'}`
    : '—';
export const fmtSpeed = (n: unknown, locale: Locale = activeLocale()) =>
  typeof n === 'number' && Number.isFinite(n) && n >= 0 ? `${fmtNumber(n, 1, locale)} t/s` : '—';
export function fmtDate(value?: string | number, locale: Locale = activeLocale(), timeOnly = false): string {
  const date = value === undefined ? new Date(NaN) : new Date(value);
  return Number.isFinite(date.getTime())
    ? new Intl.DateTimeFormat(
        locale,
        timeOnly
          ? { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }
          : { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' },
      ).format(date)
    : '—';
}
export function fmtRelative(value?: string, locale: Locale = activeLocale(), now = Date.now()): string {
  const seconds = (Date.parse(value ?? '') - now) / 1000;
  if (!Number.isFinite(seconds)) return '—';
  const [scale, unit] =
    Math.abs(seconds) >= 86400
      ? ([86400, 'day'] as const)
      : Math.abs(seconds) >= 3600
        ? ([3600, 'hour'] as const)
        : Math.abs(seconds) >= 60
          ? ([60, 'minute'] as const)
          : ([1, 'second'] as const);
  return new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(Math.round(seconds / scale), unit);
}
export const formatDuration = (ms?: unknown): string => {
  if (typeof ms !== 'number' || !Number.isFinite(ms) || ms < 0) return '—';
  if (ms < 60000) return fmtLatency(ms);
  const minutes = Math.floor(ms / 60000);
  return minutes < 60
    ? `${fmtNumber(minutes)}m ${fmtNumber(Math.floor(ms / 1000) % 60)}s`
    : `${fmtNumber(Math.floor(minutes / 60))}h ${fmtNumber(minutes % 60)}m`;
};
