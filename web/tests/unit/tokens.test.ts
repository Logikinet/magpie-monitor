import { it, expect } from 'vitest';
import { formatTokens, quotaSubtitle, tokenUsage } from '../../src/core/tokens';
import { decodeUsageSummary } from '../../src/core/decode';
it('formats Chinese and English boundaries like Swift', () => {
  for (const [n, zh, en] of [
    [-1, '0', '0'],
    [9999, '9,999', '9,999'],
    [10000, '1 万', '10K'],
    [1284000, '128.4 万', '1.28M'],
    [100000000, '1 亿', '100M'],
    [123450000, '1.2 亿', '123.45M'],
  ] as const) {
    expect(formatTokens(n, 'zh')).toBe(zh);
    expect(formatTokens(n, 'en')).toBe(en);
  }
});
it('uses token amount first, otherwise provider totals and appropriate label', () => {
  localStorage.setItem('mm-lang', 'zh');
  const usage = decodeUsageSummary({
    models: [
      { provider: 'p', input: 12000, output: 3400 },
      { provider: 'other', input: 99999 },
    ],
  });
  expect(quotaSubtitle({ name: '5h', amount: 42000, unit: 'TOKENS' }, 'p', usage)).toBe(
    '已消耗 4.2 万 token',
  );
  expect(quotaSubtitle({ name: '5h' }, 'p', usage)).toBe('今日已消耗 1.5 万 token');
  expect(quotaSubtitle({ name: 'weekly' }, 'p', usage)).toBe('近 7 天已消耗 1.5 万 token');
  expect(quotaSubtitle({ name: 'weekly', used: 52 }, 'missing', usage)).toBe('已用 52%');
  for (const amount of [-1, NaN, Infinity])
    expect(tokenUsage({ name: '5h', amount, unit: 'token' }, 'p', usage, 'today')?.source).toBe('today');
  expect(tokenUsage({ name: '5h', amount: 20, unit: 'requests' }, 'p', usage, 'today')?.count).toBe(15400);
  localStorage.removeItem('mm-lang');
});
