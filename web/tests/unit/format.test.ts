import { describe, expect, it } from 'vitest';
import {
  activeLocale,
  fmtCost,
  fmtDate,
  fmtLatency,
  fmtRelative,
  fmtSpeed,
  fmtTokens,
} from '../../src/core/format';
describe('locale formatters', () => {
  it('formats token scales and preserves missing measurements', () => {
    expect([999, 1200, 2500000, 3100000000].map((n) => fmtTokens(n, 'en'))).toEqual([
      '999',
      '1.2K',
      '2.5M',
      '3.1B',
    ]);
    expect(fmtTokens(undefined)).toBe('—');
    expect(fmtTokens(NaN)).toBe('—');
  });
  it('uses the required currency precision', () => {
    expect([123, 1.2, 0.12, 0].map((n) => fmtCost(n, 'en'))).toEqual(['$123.0', '$1.20', '$0.120', '$0']);
    expect(fmtCost(undefined)).toBe('—');
  });
  it('formats latency, speed, zero and invalid values', () => {
    expect(fmtLatency(1200, 'en')).toBe('1.2 s');
    expect(fmtLatency(0, 'en')).toBe('0 ms');
    expect(fmtSpeed(25.45, 'en')).toBe('25.5 t/s');
    expect(fmtSpeed(Infinity)).toBe('—');
    expect(fmtLatency(-1)).toBe('—');
  });
  it.each(['zh', 'en', 'ja'] as const)('uses Intl dates and relative times for %s', (locale) => {
    const date = '2026-10-17T12:30:15Z',
      now = Date.parse(date) - 3600000;
    expect(fmtDate(date, locale, true)).toBe(
      new Intl.DateTimeFormat(locale, {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false,
      }).format(new Date(date)),
    );
    expect(fmtRelative(date, locale, now)).toBe(
      new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(1, 'hour'),
    );
    expect(fmtRelative(date, locale, now + 7200000)).toBe(
      new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(-1, 'hour'),
    );
    expect(fmtDate('bad', locale)).toBe('—');
  });
  it('reads the active locale with Chinese as default', () => {
    history.replaceState(null, '', '/?lang=ja');
    expect(activeLocale()).toBe('ja');
    history.replaceState(null, '', '/?lang=en');
    expect(activeLocale()).toBe('en');
    history.replaceState(null, '', '/');
    expect(activeLocale()).toBe(navigator.language.startsWith('en') ? 'en' : 'zh');
  });
});
