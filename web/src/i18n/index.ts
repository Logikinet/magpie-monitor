import zh from './zh';
import en from './en';
import ja from './ja';

export type Locale = 'zh' | 'en' | 'ja';
export type LanguageChoice = Locale | 'auto';
const dictionaries = { zh, en, ja };
export type MessageKey = keyof typeof zh;

function validLocale(value: string | null | undefined): Locale | undefined {
  const normalized = value?.toLowerCase().split('-')[0];
  return normalized === 'zh' || normalized === 'en' || normalized === 'ja' ? normalized : undefined;
}

export function detectLocale(): Locale {
  if (typeof window === 'undefined') return 'zh';
  const saved = localStorage.getItem('mm-lang');
  if (saved && saved !== 'auto') return validLocale(saved) ?? 'zh';
  const query = new URLSearchParams(location.search).get('lang');
  return validLocale(query) ?? (saved === 'auto' ? validLocale(navigator.language) : undefined) ?? 'zh';
}

export function languageChoice(): LanguageChoice {
  if (typeof window === 'undefined') return 'auto';
  const saved = localStorage.getItem('mm-lang');
  if (saved === 'zh' || saved === 'en' || saved === 'ja') return saved;
  if (saved === 'auto') return 'auto';
  return validLocale(new URLSearchParams(location.search).get('lang')) ?? 'auto';
}

export function t(key: MessageKey | string, params: Record<string, string | number> = {}, locale = detectLocale()): string {
  const table = dictionaries[locale] as Record<string, string>;
  const fallback = dictionaries.zh as Record<string, string>;
  const message = table[key] ?? fallback[key] ?? key;
  return message.replace(/\{([\w]+)\}/g, (_, name: string) => String(params[name] ?? `{${name}}`));
}

export function setLanguage(choice: LanguageChoice): Locale {
  localStorage.setItem('mm-lang', choice);
  return choice === 'auto' ? detectLocale() : choice;
}

export { zh, en, ja };
