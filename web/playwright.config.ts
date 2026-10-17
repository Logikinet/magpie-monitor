import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'tests/e2e',
  // demo.spec.ts is driven only by playwright.demo.config.ts (long video run).
  testIgnore: '**/demo.spec.ts',
  use: { baseURL: 'http://localhost:4173' },
  projects: [
    {
      name: 'desktop',
      use: { ...devices['Desktop Chrome'], browserName: 'chromium', viewport: { width: 1440, height: 900 } },
    },
    {
      name: 'mobile',
      use: {
        browserName: 'chromium',
        viewport: { width: 390, height: 844 },
        isMobile: true,
        deviceScaleFactor: 2,
      },
    },
  ],
  webServer: {
    command: 'vite preview --port 4173',
    url: 'http://localhost:4173',
    reuseExistingServer: true,
  },
});
