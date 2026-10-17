import { language } from '../../src/views/agent/shared';
import { describe, expect, it } from 'vitest';
import { en, ja, zh, t, detectLocale } from '../../src/i18n';

describe('web translations', () => {
  it('keeps all locale dictionaries complete', () => {
    expect(Object.keys(en).sort()).toEqual(Object.keys(zh).sort());
    expect(Object.keys(ja).sort()).toEqual(Object.keys(zh).sort());
  });

  it('replaces named parameters', () => {
    expect(t('settings.refreshEvery', { seconds: 12 }, 'en')).toBe('Refresh every 12s');
  });
});

it('uses the shell locale in Agent, including default and auto mode', () => {
  const saved = localStorage.getItem('mm-lang');
  const url = location.href;
  try {
    localStorage.removeItem('mm-lang');
    history.replaceState(null, '', '/');
    expect(language()).toBe('zh');
    for (const choice of ['zh', 'en', 'ja', 'auto']) {
      localStorage.setItem('mm-lang', choice);
      expect(language()).toBe(detectLocale());
    }
    localStorage.removeItem('mm-lang');
    history.replaceState(null, '', '/?lang=ja');
    expect(language()).toBe('ja');
  } finally {
    if (saved === null) localStorage.removeItem('mm-lang');
    else localStorage.setItem('mm-lang', saved);
    history.replaceState(null, '', url);
  }
});
