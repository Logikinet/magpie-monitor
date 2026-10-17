import type { ComponentChildren } from 'preact';

const paths: Record<string, ComponentChildren> = {
  'check-circle': <><circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/></>,
  'warning-triangle': <><path d="M10.3 4.3 2.7 18a2 2 0 0 0 1.8 3h15a2 2 0 0 0 1.8-3L13.7 4.3a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4m0 4h.01"/></>,
  'x-circle': <><circle cx="12" cy="12" r="9"/><path d="m9 9 6 6m0-6-6 6"/></>,
  'minus-circle': <><circle cx="12" cy="12" r="9"/><path d="M8 12h8"/></>,
  'lock-open': <><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 7.5-2"/></>,
  'play-rect': <><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m10 9 5 3-5 3z"/></>,
  gauge: <><path d="M4 19a9 9 0 1 1 16 0"/><path d="m12 13 4-4m-4 4-2 3"/><path d="M4 19h16"/></>,
  activity: <><path d="M3 12h4l3-8 4 16 3-8h4"/></>,
  bot: <><rect x="4" y="7" width="16" height="13" rx="3"/><path d="M12 3v4m-4 5h.01M16 12h.01M8 16h8"/></>,
  settings: <><circle cx="12" cy="12" r="3"/><path d="m19.4 15 .1.1 1.4 1.1-1.4 2.4-1.7-.6a8 8 0 0 1-1.7 1l-.3 1.8h-2.8l-.3-1.8a8 8 0 0 1-1.7-1l-1.7.6-1.4-2.4 1.4-1.1a8 8 0 0 1 0-2l-1.4-1.1 1.4-2.4 1.7.6a8 8 0 0 1 1.7-1l.3-1.8h2.8l.3 1.8a8 8 0 0 1 1.7 1l1.7-.6 1.4 2.4-1.4 1.1a8 8 0 0 1-.1 1.9Z" transform="translate(-1 -1) scale(1.08)"/></>,
  refresh: <><path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.5 9A7 7 0 0 1 18 6l2 6M4 12l2 6a7 7 0 0 0 12.5-3"/></>,
  'external-link': <><path d="M14 4h6v6m-10 4L20 4"/><path d="M18 13v6a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h6"/></>,
  overview: <><rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="5" rx="2"/><rect x="13" y="10" width="8" height="11" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/></>,
  chart: <><path d="M4 19V5m0 14h17"/><path d="m7 15 4-5 3 2 5-7"/></>,
  quota: <><path d="M4 20V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v15l-4-2-4 2-4-2z"/><path d="M8 8h8m-8 4h8"/></>,
};

export function Icon({ name, size = 18, class: className = '' }: { name: string; size?: number; class?: string }) {
  return <svg class={`icon ${className}`} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{paths[name] ?? paths['minus-circle']}</svg>;
}
