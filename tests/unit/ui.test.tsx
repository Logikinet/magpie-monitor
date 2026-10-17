import { afterEach, describe, expect, it } from 'vitest';
import { render } from 'preact';
import App, { QuotaCard } from '../../src/app';
import type { QuotaSpan } from '../../src/core/decode';

const root = document.createElement('div');
afterEach(() => { render(null, root); });

describe('quota UI', () => {
  it('shows token consumption and percentage', () => {
    const window: QuotaSpan = { name: '5-hour', used: 64, remaining: 36, amount: 1284000, unit: 'tokens', resetsAt: '2026-10-18T00:00:00Z' };
    render(<QuotaCard provider="anthropic" window={window}/>, root);
    expect(root.textContent).toContain('已消耗 128.4 万 token');
    expect(root.textContent).toContain('64%');
  });
  it('shows the mock mode badge', () => {
    render(<App/>, root);
    expect(root.querySelector('[data-testid="mock-badge"]')?.textContent).toContain('模拟数据');
  });
});
