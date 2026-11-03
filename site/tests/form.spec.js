// The setup form as a visitor uses it: the questions and their errors, each plan's download and what its zip holds,
// the Modify page, and the route for a package that already exists. Each download is opened and its files checked.
import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import JSZip from 'jszip';

const PLANS = {
  a: { public: true, internal: false, extended: true },
  b: { public: true, internal: true, extended: true },
  c: { public: false, internal: false, extended: true },
  d: { public: false, internal: true, extended: false },
};

async function openForm(page) {
  await page.goto('/');
  // The analytics banner: decline, as most visitors would.
  const reject = page.locator('#cookieNo');
  if (await reject.isVisible()) await reject.click();
  await page.locator('#endStart').click();
  await expect(page.locator('#pkg')).toBeVisible();
}

async function fillForm(page, { name = 'tablePkg', owner = 'sample-org', email = 'a@example.com' } = {}) {
  await page.locator('#pkg').fill(name);
  await page.locator('#what').fill('Tools For Tables');
  await page.locator('#first').fill('Asha');
  await page.locator('#last').fill('Rao');
  await page.locator('#email').fill(email);
  await page.locator('#owner').fill(owner);
}

// Clicks a download button and returns the zip's files as { path: text }. When no zip comes, fails with the message
// the site showed (for example "The zip could not be built").
async function download(page, button) {
  const waiting = page.waitForEvent('download', { timeout: 15_000 });
  await page.locator(button).click();
  const file = await waiting.catch(async () => {
    const note = await page.locator('#planNote, #exNote').allTextContents();
    throw new Error(`No zip was downloaded. The site said: ${note.join(' ').trim() || '(nothing)'}`);
  });
  const zip = await JSZip.loadAsync(await readFile(await file.path()));
  const files = {};
  for (const [path, entry] of Object.entries(zip.files)) if (!entry.dir) files[path] = await entry.async('string');
  return { name: file.suggestedFilename(), files };
}

test.describe('the questions', () => {
  test('an empty form names what is missing', async ({ page }) => {
    await openForm(page);
    await page.locator('#download').click();
    await expect(page.locator('#err-pkg')).toHaveText(/Give your package a name/);
    await expect(page.locator('#err-owner')).toHaveText(/Give your GitHub username or organisation/);
  });

  test('names R refuses are refused', async ({ page }) => {
    await openForm(page);
    await fillForm(page, { name: 'stats' });
    await page.locator('#download').click();
    await expect(page.locator('#err-pkg')).toHaveText(/part of R itself/);
    await page.locator('#pkg').fill('my-pkg');
    await page.locator('#download').click();
    await expect(page.locator('#err-pkg')).toHaveText(/letters, numbers and dots/);
  });

  test('a link is not a GitHub name, and the title stops at 65 characters', async ({ page }) => {
    await openForm(page);
    await fillForm(page, { owner: 'https://github.com/sample-org' });
    await page.locator('#download').click();
    await expect(page.locator('#err-owner')).toHaveText(/not a link/);
    await expect(page.locator('#what')).toHaveAttribute('maxlength', '65');
  });
});

for (const [plan, want] of Object.entries(PLANS)) {
  test(`plan ${plan} downloads a package that matches the plan`, async ({ page }) => {
    await openForm(page);
    await fillForm(page);
    await page.locator(`input[name=plan][value=${plan}]`).check();
    const { name, files } = await download(page, '#download');
    expect(name).toBe('tablePkg.zip');
    await expect(page.locator('#nextView')).toBeVisible();

    const has = (path) => `tablePkg/${path}` in files;
    for (const path of ['DESCRIPTION', 'README.md', '.Renviron', 'tests/README.md', 'inst/WORDLIST', '.github/workflows/README.md']) {
      expect(has(path), path).toBe(true);
    }
    expect(has('.github/workflows/r-cmd-check-extended.yaml')).toBe(want.extended);
    const description = files['tablePkg/DESCRIPTION'];
    expect(description).toContain('URL: https://github.com/sample-org/tablePkg');
    expect(description.includes('Config/quality-gate/target: internal')).toBe(want.internal);
    const readme = files['tablePkg/README.md'];
    expect(readme).toContain('Set up with [launchR]');
    expect(readme.includes('img.shields.io/badge/set%20up%20with-launchR')).toBe(want.public);
    expect(files['tablePkg/inst/WORDLIST']).toContain('CMD');
    expect(files['tablePkg/.Renviron']).toMatch(/^EXTENDED_TESTS=true$/m);
    // No AI files unless asked for, and the issue forms are numbered without a gap.
    expect(has('AGENTS.md')).toBe(false);
    const forms = Object.keys(files).filter((path) => /ISSUE_TEMPLATE\/\d\d-/.test(path)).map((path) => path.match(/(\d\d)-/)[1]).sort();
    expect(forms).toEqual(['01', '02', '03', '04', '05']);
    // Without a longer description, DESCRIPTION's Description repeats the title.
    expect(description).toContain('Description: Tools For Tables.');
  });
}

test('the longer description reaches DESCRIPTION and the help page, and CRAN wording is checked', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#details').fill('This package builds tables.');
  await page.locator('#download').click();
  await expect(page.locator('#err-details')).toHaveText(/not with "This package"/);
  await page.locator('#details').fill('builds tables.');
  await page.locator('#download').click();
  await expect(page.locator('#err-details')).toHaveText(/capital letter/);
  await page.locator('#details').fill('Builds   tables for clinical study reports');
  const { files } = await download(page, '#download');
  expect(files['tablePkg/DESCRIPTION']).toContain('Description: Builds tables for clinical study reports.');
  expect(files['tablePkg/man/tablePkg-package.Rd']).toContain('Builds tables for clinical study reports.');
});

test('Modify: the AI switch adds AGENTS.md, CLAUDE.md and their issue form', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#modify').click();
  await page.locator('#modifyView summary', { hasText: 'Extras' }).click();
  await page.locator('label.sw', { hasText: 'Instructions for AI assistants' }).click();
  await expect(page.locator('#sumMore')).toHaveText('AI instructions');
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/AGENTS.md']).toContain('# tablePkg');
  expect(files['tablePkg/CLAUDE.md']).toContain('@AGENTS.md');
  expect('tablePkg/.github/ISSUE_TEMPLATE/06-ai-instructions.yml' in files).toBe(true);
});

test('Modify: the oldest R reaches DESCRIPTION, and the download works from there', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await page.locator('#modify').click();
  await page.locator('#minR').fill('4.3');
  await page.locator('#minR').dispatchEvent('change');
  await expect(page.locator('#minRZero')).toHaveText('.0');
  // The website note sits in the Website section, closed until the visitor opens it.
  await page.locator('#modifyView summary', { hasText: 'Website' }).click();
  await expect(page.locator('#pagesNote')).toBeVisible();
  const { files } = await download(page, '#modDownload');
  await expect(page.locator('#nextView')).toBeVisible();
  expect(files['tablePkg/DESCRIPTION']).toContain('R (>= 4.3.0)');
  // No check runs on an R older than the one chosen.
  for (const [path, text] of Object.entries(files)) if (path.includes('/workflows/')) expect(text, path).not.toMatch(/^ *platforms:.*\/4\.1/m);
  // A private plan checks the oldest R on Linux too.
  expect(files['tablePkg/.github/workflows/r-cmd-check.yaml']).toContain('platforms: ubuntu/release, ubuntu/oldrel-1, ubuntu/4.3');
});

test('Modify: on a public plan, no check runs on an R older than the oldest R chosen', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=a]').check();
  await page.locator('#modify').click();
  await page.locator('#minR').fill('4.3');
  await page.locator('#minR').dispatchEvent('change');
  const { files } = await download(page, '#modDownload');
  const flows = Object.entries(files).filter(([path]) => path.includes('/workflows/'));
  for (const [path, text] of flows) expect(text, path).not.toMatch(/^ *platforms:.*\/4\.1/m);
  expect(files['tablePkg/.github/workflows/full-tests.yaml']).toContain('platforms: ubuntu/release, ubuntu/4.3');
});

test('Modify refuses an oldest R below 4.1 or with a patch number', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#modify').click();
  await page.locator('#minR').fill('4.1');
  await page.locator('#minR').dispatchEvent('change');
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/workflows/r-cmd-check.yaml'], 'the default oldest R adds no extra system').not.toContain('ubuntu/4.1');
  await page.locator('#nextChange').click();
  await page.locator('#modify').click();
  await page.locator('#minR').fill('4.0');
  await page.locator('#minR').dispatchEvent('change');
  await expect(page.locator('#minRNote')).toHaveText(/from 4.1 on/);
  await page.locator('#minR').fill('4.4.1');
  await expect(page.locator('#minR')).toHaveValue('4.4');
});

test("the next steps give both routes, the first commands and an organisation's line", async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await download(page, '#download');
  const steps = page.locator('#stepList');
  await expect(steps).toContainText('pak::local_install_dev_deps()');
  await expect(steps).toContainText('devtools::test()');
  await expect(steps).toContainText('usethis::use_github(private = FALSE)');
  // The GitHub name may be an organisation: the site can't tell without asking GitHub, so both lines are there.
  await expect(steps).toContainText('usethis::use_github(organisation = "sample-org", private = FALSE)');
  await page.getByText('With GitHub Desktop').click();
  await expect(steps).toContainText('Publish repository');
  await expect(steps).toContainText('If sample-org is an organisation, pick it under Organization.');
  // Each step says what to do in a line; the explanations fold away until asked for.
  const more = steps.locator('details.more').first();
  await expect(more).not.toHaveAttribute('open', '');
  await expect(more.locator('p')).toBeHidden();
  await more.locator('summary').click();
  await expect(more.locator('p')).toBeVisible();
});

test('an existing package gets only the CI files', async ({ page }) => {
  await page.goto('/');
  const reject = page.locator('#cookieNo');
  if (await reject.isVisible()) await reject.click();
  await page.locator('#existingStart').click();
  await page.locator('#exPkg').fill('oldPkg');
  await page.locator('#exOwner').fill('sample-org');
  const { name, files } = await download(page, '#exDownload');
  expect(name).toBe('launchR-files.zip');
  await expect(page.locator('#nextView')).toBeVisible();
  expect('.github/workflows/r-cmd-check.yaml' in files).toBe(true);
  expect('.github/workflows/README.md' in files).toBe(true);
  for (const path of ['DESCRIPTION', 'R/say_hello.R', 'codecov.yml', '.Renviron']) expect(path in files, path).toBe(false);
});
