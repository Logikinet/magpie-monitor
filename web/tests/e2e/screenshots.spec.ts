import { expect, test } from '@playwright/test';

const views = [
  'home',
  'activity',
  'tmux',
  'svc',
  'agent',
  'agent-usage',
  'agent-providers',
  'agent-runtimes',
  'settings',
] as const;
const themes = ['light', 'dark'] as const;

for (const view of views) {
  for (const theme of themes) {
    test(`${view} · ${theme}`, async ({ page }, testInfo) => {
      const outsideRequests: string[] = [];
      page.on('request', (request) => {
        const host = new URL(request.url()).hostname;
        if (host !== 'localhost') outsideRequests.push(request.url());
      });
      const target =
        view === 'agent-runtimes'
          ? 'agent?atab=runtimes'
          : view === 'agent-providers'
            ? 'agent?atab=providers'
            : view === 'agent-usage'
              ? 'agent?atab=usage'
              : view === 'agent'
                ? 'agent?atab=routing'
                : view;
      await page.goto(`/?mock=1&theme=${theme}#/${target}`);
      await expect(
        page.getByTestId(
          `view-${view === 'agent-usage' || view === 'agent-providers' || view === 'agent-runtimes' ? 'agent' : view}`,
        ),
      ).toBeVisible();
      await page.waitForLoadState('networkidle');
      await expect(page.getByTestId('mock-badge')).toBeVisible();
      expect(outsideRequests).toEqual([]);
      if (view === 'agent') await page.waitForTimeout(1500);
      await page.screenshot({
        path: `docs/screenshots/${view}-${testInfo.project.name}-${theme}.png`,
        fullPage: testInfo.project.name === 'desktop',
        animations: 'disabled',
      });
    });
  }
}

test('agent routing · en', async ({ page }, testInfo) => {
  await page.goto('/?mock=1&theme=dark&lang=en#/agent?atab=routing');
  await expect(page.getByTestId('view-agent')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1500);
  await page.screenshot({
    path: `docs/screenshots/agent-routing-en-${testInfo.project.name}.png`,
    fullPage: testInfo.project.name === 'desktop',
    animations: 'disabled',
  });
});
