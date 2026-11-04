// Makes the package for the sandbox test (.github/workflows/sandbox-e2e.yaml) the way a visitor would: a public CRAN
// plan with every check, R devel on Linux, browser tests, and those tests on the same systems as R CMD check (Linux,
// Mac and Windows). Saves the zip to SANDBOX_ZIP. Runs only when SANDBOX_ZIP is set (playwright.config.js leaves it
// out otherwise): `SANDBOX_ZIP=/tmp/pkg.zip npx playwright test sandbox-package`.
import { copyFile, readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import JSZip from 'jszip';

const NAME = process.env.SANDBOX_PACKAGE || 'sandboxPkg';
const OWNER = process.env.SANDBOX_OWNER || 'insightsurge';

test('the sandbox package: a public plan with every check, R devel and browser tests everywhere', async ({ page }) => {
  await page.goto('/');
  const reject = page.locator('#cookieNo');
  if (await reject.isVisible()) await reject.click();
  await page.locator('#endStart').click();
  await page.locator('#pkg').fill(NAME);
  await page.locator('#what').fill('Tests launchR Checks End To End');
  await page.locator('#first').fill('Sandbox');
  await page.locator('#last').fill('Tester');
  await page.locator('#email').fill('sandbox@example.com');
  await page.locator('#owner').fill(OWNER);
  await page.locator('input[name=plan][value=a]').check();

  await page.locator('#modify').click();
  // Every check: the public plan starts with all seven on; say so, so a change to the starter set shows up here.
  await expect(page.locator('#bodyCi .ticks input:checked')).toHaveCount(7);
  await page.locator('#bodyCi [data-matrix="ubuntu/devel"]').evaluate((input) => { if (!input.checked) input.click(); });
  await page.locator('label.sw', { hasText: 'Use the same systems for browser and extended tests' }).click();
  await page.locator('#modifyView summary', { hasText: 'Extras' }).click();
  await page.locator('label.sw', { hasText: 'JS or CSS' }).click();

  const waiting = page.waitForEvent('download', { timeout: 15_000 });
  await page.locator('#modDownload').click();
  const file = await waiting;
  expect(file.suggestedFilename()).toBe(`${NAME}.zip`);

  // What the sandbox run relies on, checked here so a form change fails before anything is pushed.
  const zip = await JSZip.loadAsync(await readFile(await file.path()));
  const text = (path) => zip.file(`${NAME}/${path}`)?.async('string');
  for (const check of ['r-cmd-check', 'lint', 'no-suggests', 'secret-scan', 'coverage', 'full-tests', 'r-cmd-check-extended']) {
    expect(await text(`.github/workflows/${check}.yaml`), check).toBeTruthy();
  }
  const matrix = /platforms: .*ubuntu\/devel/;
  expect(await text('.github/workflows/r-cmd-check.yaml')).toMatch(matrix);
  const full = await text('.github/workflows/full-tests.yaml');
  expect(full).toMatch(/platforms: .*windows\/release/);
  expect(full).toMatch(/platforms: .*macos\/release/);
  expect(await text('tests/testthat/test-demo-browser.R')).toBeTruthy();

  await copyFile(await file.path(), process.env.SANDBOX_ZIP);
});
