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
    // The weekly time comes from lists/checks.tsv (an odd minute), not from the form.
    expect(files['tablePkg/.github/workflows/r-cmd-check.yaml']).toContain('- cron: "17 5 * * 1"');
    // Text that depends on the plan or the parts: CRAN wording only for a CRAN package, JS and CSS only with a front end.
    expect(files['tablePkg/.github/SECURITY.md'].includes('is on CRAN')).toBe(!want.internal);
    expect(files['tablePkg/.github/CONTRIBUTING.md']).not.toMatch(/Biome|JavaScript|Chrome/);
    expect(files['tablePkg/.github/pull_request_template.md']).not.toContain('JavaScript');
    expect(files['tablePkg/.github/CONTRIBUTING.md']).toContain('Language: en-GB');
    // Without a longer description, DESCRIPTION's Description repeats the title.
    expect(description).toContain('Description: Tools For Tables.');
  });
}

test('the workflows README describes the extended check without naming systems a private package lacks', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=c]').check();
  const { files } = await download(page, '#download');
  expect(files['tablePkg/.github/workflows/r-cmd-check-extended.yaml']).toContain('platforms: ubuntu/release');
  const readme = files['tablePkg/.github/workflows/README.md'];
  const row = readme.split('\n').find((line) => line.startsWith('| `r-cmd-check-extended.yaml`'));
  expect(row).toContain('Run R CMD check on more systems, with the extended tests');
  expect(row).not.toMatch(/Mac|Windows/);
});

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

test('Modify: the AI switch adds AGENTS.md, its rules files, CLAUDE.md and their issue form', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#modify').click();
  await page.locator('#modifyView summary', { hasText: 'Extras' }).click();
  await page.locator('label.sw', { hasText: 'Instructions for AI assistants' }).click();
  await expect(page.locator('#sumMore')).toContainText('AI instructions');
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/AGENTS.md']).toContain('.agents/rules/');
  for (const rule of ['checks', 'docs', 'git', 'js-css', 'r-code', 'tests']) expect(`tablePkg/.agents/rules/${rule}.md` in files, rule).toBe(true);
  expect(files['tablePkg/CLAUDE.md']).toContain('@AGENTS.md');
  expect('tablePkg/.github/ISSUE_TEMPLATE/06-ai-instructions.yml' in files).toBe(true);
});

test('Modify: the CI report comment, licence, badges, issue forms, labels and QC checklist reach the zip', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await page.locator('#modify').click();
  // Checks on GitHub is the section open on arrival.
  await page.locator('label.sw', { hasText: 'CI report comment' }).click();
  await page.locator('#modifyView summary', { hasText: 'GitHub setup' }).click();
  await page.locator('label.pill', { hasText: /^Idea$/ }).click();
  await expect(page.locator('[data-label="idea"]')).toBeEnabled();
  await page.locator('label.pill', { hasText: /^idea$/ }).click();
  await expect(page.locator('[data-label="idea"]')).not.toBeChecked();
  await expect(page.locator('#sumGit')).toHaveText('4 of 5 issue forms, 10 of 11 labels, QC checklist');
  await page.locator('#modifyView summary', { hasText: 'Extras' }).click();
  await expect(page.locator('#sumMore')).toHaveText('Proprietary licence, no badges');
  await page.locator('label.pill', { hasText: 'Lifecycle' }).click();
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/workflows/lint.yaml']).toContain('ci-report: false');
  expect(files['tablePkg/LICENSE']).toContain('All rights reserved');
  expect('tablePkg/LICENSE.md' in files).toBe(false);
  expect(files['tablePkg/DESCRIPTION']).toContain('License: file LICENSE');
  expect(files['tablePkg/DESCRIPTION']).toContain('Config/launchR/checklists: QC before release');
  expect(files['tablePkg/DESCRIPTION']).toMatch(/Config\/launchR\/labels: .*bug/);
  expect(files['tablePkg/DESCRIPTION']).not.toMatch(/Config\/launchR\/labels: .*idea/);
  expect('tablePkg/.github/ISSUE_TEMPLATE/05-idea.yml' in files).toBe(false);
  expect(files['tablePkg/README.md']).toContain('lifecycle-experimental');
});

test('the plan preview lists the QC checklist while it is on', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await expect(page.locator('#pvLists')).toContainText('QC before release');
  await expect(page.locator('#pvLists')).not.toContainText('Before public');
  await page.locator('#modify').click();
  await page.locator('#modifyView summary', { hasText: 'GitHub setup' }).click();
  await page.locator('label.sw', { hasText: 'QC checklist' }).click();
  await expect(page.locator('#pvLists')).not.toContainText('QC before release');
  // Private for good starts with the QC checklist alone, so without it there is none.
  await expect(page.locator('#pvLists')).toHaveText('None, no release features');
  await page.locator('#modBack').click();
  await page.locator('input[name=plan][value=a]').check();
  await expect(page.locator('#pvLists')).not.toContainText('QC before release');
  await expect(page.locator('#pvLists')).toContainText('After public');
});

test('Modify: the navbar choices reach _pkgdown.yml', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#modify').click();
  await page.locator('#modifyView summary', { hasText: 'Website' }).click();
  await page.locator('label.sw', { hasText: 'Add a website' }).click();
  await page.locator('label.pill', { hasText: 'Changelog' }).click();
  await page.locator('label.pill', { hasText: 'Light and dark switch' }).click();
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/_pkgdown.yml']).toContain('left: [reference, articles]');
  expect(files['tablePkg/_pkgdown.yml']).toContain('right: [search, github]');
});

test('Modify: the front-end switch adds the JS and CSS wording', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#modify').click();
  await page.locator('#modifyView summary', { hasText: 'Extras' }).click();
  await page.locator('label.sw', { hasText: 'JS or CSS' }).click();
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/CONTRIBUTING.md']).toMatch(/Biome[\s\S]*Chrome/);
  expect(files['tablePkg/.github/pull_request_template.md']).toContain('JavaScript and CSS changes');
  expect(files['tablePkg/tests/README.md']).toContain('test-demo-browser.R');
});

test('Modify: with every check off, there is no run-locally section, no Dependabot file and no caller files', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('#modify').click();
  // The page repaints after each click, so pick each check by its key.
  for (const key of ['r_cmd_check', 'lint', 'no_suggests', 'secret_scan', 'coverage', 'full_tests', 'r_cmd_check_extended']) {
    await page.locator(`#bodyCi [data-check=${key}]`).evaluate((input) => input.click());
  }
  await expect(page.locator('#bodyCi .ticks input:checked')).toHaveCount(0);
  const { files } = await download(page, '#modDownload');
  const readme = files['tablePkg/.github/workflows/README.md'];
  expect(readme).toContain('| None yet | Come back to the site to add one | |');
  expect(readme).not.toContain('Run the checks on your computer');
  expect(readme).not.toContain('Leaving launchR');
  expect('tablePkg/.github/dependabot.yml' in files).toBe(false);
  expect(Object.keys(files).filter((path) => path.includes('/workflows/') && path.endsWith('.yaml')).every((path) => path.endsWith('github-setup.yaml'))).toBe(true);
  expect(files['tablePkg/.github/CONTRIBUTING.md']).not.toContain('CI runs on every pull request');
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

async function openExisting(page) {
  await page.goto('/');
  const reject = page.locator('#cookieNo');
  if (await reject.isVisible()) await reject.click();
  await page.locator('#existingStart').click();
  await page.locator('#exPkg').fill('oldPkg');
  await page.locator('#exOwner').fill('sample-org');
}

test('an existing package gets only the CI files and the settings files its checks read', async ({ page }) => {
  await openExisting(page);
  // The Finder note is next to the download button, not only in the steps.
  await expect(page.locator('#exFinder')).toContainText('Cmd+Shift+.');
  const { name, files } = await download(page, '#exDownload');
  expect(name).toBe('launchR-files.zip');
  await expect(page.locator('#nextView')).toBeVisible();
  expect('.github/workflows/r-cmd-check.yaml' in files).toBe(true);
  expect('.github/workflows/README.md' in files).toBe(true);
  // The lint check is on by default, so its settings files come along; so does codecov.yml, with the coverage check.
  for (const path of ['.lintr', 'air.toml', 'codecov.yml']) expect(path in files, path).toBe(true);
  for (const path of ['DESCRIPTION', 'R/say_hello.R', '.Renviron', '.gitignore', 'tests/README.md']) expect(path in files, path).toBe(false);
  // The steps list the .Rbuildignore lines for what is in the zip, as one block to copy.
  const block = page.locator('#stepList .cmd.block code');
  await expect(block).toBeVisible();
  const lines = (await block.textContent()).split('\n');
  expect(lines).toEqual(expect.arrayContaining(['^\\.github$', '^\\.lintr$', '^air\\.toml$', '^codecov\\.yml$', '^\\.gitleaksignore$']));
  expect(lines).not.toContain('^_pkgdown\\.yml$');
  await expect(page.locator('#stepList')).toContainText('Cmd+Shift+.');
});

test('an existing package without the lint check gets no lint settings files, and a website adds its own lines', async ({ page }) => {
  await openExisting(page);
  await page.locator('#exRows label.pill', { hasText: 'Website' }).click();
  await page.locator('#exModify').click();
  await page.locator('#bodyCi label.pill', { hasText: 'lint' }).first().click();
  await page.locator('#bodyCi label.pill', { hasText: 'coverage' }).click();
  const { files } = await download(page, '#modDownload');
  for (const path of ['.lintr', 'air.toml', 'codecov.yml']) expect(path in files, path).toBe(false);
  expect('_pkgdown.yml' in files).toBe(true);
  const lines = (await page.locator('#stepList .cmd.block code').textContent()).split('\n');
  expect(lines).toEqual(expect.arrayContaining(['^_pkgdown\\.yml$', '^pkgdown$']));
  expect(lines).not.toContain('^\\.lintr$');
});

test('the existing-package button works when it is pressed before the lists have loaded', async ({ page }) => {
  let open;
  const gate = new Promise((resolve) => { open = resolve; });
  await page.route('**/kit/bundle.json', async (route) => { await gate; await route.continue(); });
  const asked = page.waitForRequest('**/kit/bundle.json');
  await page.goto('/', { waitUntil: 'commit' });
  await asked;
  await expect(page.locator('#existingStart')).toBeVisible();
  const reject = page.locator('#cookieNo');
  if (await reject.isVisible()) await reject.click();
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.locator('#existingStart').click();
  open();
  await expect(page.locator('#exRows .pill')).toHaveCount(3);
  expect(errors).toEqual([]);
});
