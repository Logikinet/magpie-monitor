import { describe, expect, it } from 'vitest';
import { en, ja, zh, t } from '../../src/i18n';

describe('web translations', () => {
  it('keeps all locale dictionaries complete', () => {
    expect(Object.keys(en).sort()).toEqual(Object.keys(zh).sort());
    expect(Object.keys(ja).sort()).toEqual(Object.keys(zh).sort());
  });

  it('replaces named parameters', () => {
    expect(t('settings.refreshEvery', { seconds: 12 }, 'en')).toBe('Refresh every 12s');
  });
});
