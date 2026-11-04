// Browser tests of the built site (tests/*.spec.js), the way a visitor uses it. Build first: npm run build.
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'tests',
  // sandbox-package.spec.js makes the package for .github/workflows/sandbox-e2e.yaml; it runs only when asked for.
  testIgnore: process.env.SANDBOX_ZIP ? [] : ['**/sandbox-package.spec.js'],
  timeout: 60_000,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['github']] : 'list',
  use: {
    baseURL: 'http://localhost:4330',
    acceptDownloads: true,
    ...devices['Desktop Chrome'],
  },
  webServer: {
    command: 'npx astro preview --port 4330 --ignore-lock',
    url: 'http://localhost:4330',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
