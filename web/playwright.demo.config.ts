import { defineConfig, devices } from '@playwright/test';

const desktop = {
  ...devices['Desktop Chrome'],
  browserName: 'chromium' as const,
  viewport: { width: 1440, height: 900 },
  colorScheme: 'dark' as const,
  reducedMotion: 'no-preference' as const,
  video: {
    mode: 'on' as const,
    size: { width: 1440, height: 900 },
    fps: 30,
  },
};

export default defineConfig({
  testDir: 'tests/e2e',
  testMatch: '**/demo.spec.ts',
  timeout: 180_000,
  workers: 1,
  fullyParallel: false,
  retries: 0,
  outputDir: 'test-results',
  reporter: 'line',
  use: {
    baseURL: 'http://localhost:4173',
    ...desktop,
  },
  projects: [{ name: 'desktop', use: desktop }],
  webServer: {
    command: 'vite preview --port 4173',
    url: 'http://localhost:4173',
    reuseExistingServer: true,
  },
});
