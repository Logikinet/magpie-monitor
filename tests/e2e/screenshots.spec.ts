import { expect, test } from '@playwright/test';

const views = ['overview', 'activity', 'agent', 'quotas', 'settings'] as const;
const themes = ['light', 'dark'] as const;

for (const view of views) {
  for (const theme of themes) {
    test(`${view} · ${theme}`, async ({ page }, testInfo) => {
      const outsideRequests: string[] = [];
      page.on('request', (request) => {
        const host = new URL(request.url()).hostname;
        if (host !== 'localhost') outsideRequests.push(request.url());
      });
      await page.goto(`/?mock=1&theme=${theme}#/${view}`);
      await expect(page.getByTestId(`view-${view}`)).toBeVisible();
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
