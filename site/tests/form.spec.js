// The setup form as a visitor uses it: the questions and their errors, each plan's download and what its zip holds,
// the switch that customises every setting and its steps, the preview window, and the route for a package that already
// exists. Each download is opened and its files checked.
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
  // The form opens with a short animation; a forced click (on a Download button that looks off) waits for it.
  await page.waitForFunction(() => document.querySelector('#setup').getAnimations().every((a) => a.playState !== 'running'));
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
  // The settings steps download from their last step.
  if (button === '#modDownload' && !(await page.locator(button).isVisible())) await page.locator('#stepBar button:visible').last().click();
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

// Customise a plan, then Next: the first settings step, CI checks.
async function customise(page) {
  if (!(await page.locator('#custom').isChecked())) await page.locator('#how label', { hasText: 'Customise a plan' }).click();
  await page.locator('#modify').click();
  await expect(page.locator('#stepTitle')).toHaveText('CI checks');
}
const step = (page, name) => page.locator('#stepBar button', { hasText: name }).click();

test.describe('the questions', () => {
  test('an empty form names what is missing', async ({ page }) => {
    await openForm(page);
    await expect(page.locator('#download')).toHaveAttribute('aria-disabled', 'true');
    await expect(page.locator('#missing')).toHaveText('Add a package name, a one-line title, the author\'s name and your GitHub name to download.');
    await page.locator('#download').click({ force: true });
    await expect(page.locator('#err-pkg')).toHaveText(/Give your package a name/);
    await expect(page.locator('#err-owner')).toHaveText(/Give your GitHub username or organisation/);
  });

  test('names R refuses are refused', async ({ page }) => {
    await openForm(page);
    await fillForm(page, { name: 'stats' });
    await page.locator('#download').click({ force: true });
    await expect(page.locator('#err-pkg')).toHaveText(/part of R itself/);
    await page.locator('#pkg').fill('my-pkg');
    await page.locator('#download').click({ force: true });
    await expect(page.locator('#err-pkg')).toHaveText(/letters, numbers and dots/);
  });

  test('a link is not a GitHub name, and the title stops at 65 characters', async ({ page }) => {
    await openForm(page);
    await fillForm(page, { owner: 'https://github.com/sample-org' });
    await page.locator('#download').click({ force: true });
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
    // The launchR credit badge is always on, whatever the plan.
    expect(readme).toContain('img.shields.io/badge/set%20up%20with-launchR');
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
  await page.locator('#download').click({ force: true });
  await expect(page.locator('#err-details')).toHaveText(/not with "This package"/);
  await page.locator('#details').fill('builds tables.');
  await page.locator('#download').click({ force: true });
  await expect(page.locator('#err-details')).toHaveText(/capital letter/);
  await page.locator('#details').fill('Builds   tables for clinical study reports');
  const { files } = await download(page, '#download');
  expect(files['tablePkg/DESCRIPTION']).toContain('Description: Builds tables for clinical study reports.');
  expect(files['tablePkg/man/tablePkg-package.Rd']).toContain('Builds tables for clinical study reports.');
});

test('Customise: the AI switch adds AGENTS.md, its rules files, CLAUDE.md and their issue form', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await step(page, 'Extras');
  await page.locator('label.sw', { hasText: 'Instructions for AI assistants' }).click();
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/AGENTS.md']).toContain('.agents/rules/');
  for (const rule of ['checks', 'docs', 'git', 'js-css', 'r-code', 'tests']) expect(`tablePkg/.agents/rules/${rule}.md` in files, rule).toBe(true);
  expect(files['tablePkg/CLAUDE.md']).toContain('@AGENTS.md');
  expect('tablePkg/.github/ISSUE_TEMPLATE/06-ai-instructions.yml' in files).toBe(true);
});

test('Customise: the CI report comment, licence, badges, issue forms, labels and the QC sections reach the zip', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await customise(page);
  await page.locator('label.pill', { hasText: 'ci-report' }).click();
  await step(page, 'Issues');
  // A form's label is on its card while the form is on; without the form it joins the other labels.
  await expect(page.locator('[data-label="idea"]')).toHaveCount(0);
  await page.locator('label.fcard', { hasText: 'Idea' }).click();
  // Its label joins the other labels, last and unticked.
  await expect(page.locator('[data-label="idea"]')).not.toBeChecked();
  await expect(page.locator('#bodyGit .ticks').first().locator('label.pill').last()).toContainText('idea');
  await expect(page.locator('[data-stage="qc"]')).toBeChecked();
  await step(page, 'README');
  await page.locator('label.shield[title="Lifecycle"]').click();
  await step(page, 'Extras');
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/workflows/lint.yaml']).toContain('ci-report: false');
  expect(files['tablePkg/LICENSE']).toContain('All rights reserved');
  expect('tablePkg/LICENSE.md' in files).toBe(false);
  expect(files['tablePkg/DESCRIPTION']).toContain('License: file LICENSE');
  expect(files['tablePkg/DESCRIPTION']).toContain('Config/launchR/checklists: Set up, Next release, QC');
  expect(files['tablePkg/DESCRIPTION']).toMatch(/Config\/launchR\/labels: .*bug/);
  expect(files['tablePkg/DESCRIPTION']).not.toMatch(/Config\/launchR\/labels: .*idea/);
  expect('tablePkg/.github/ISSUE_TEMPLATE/05-idea.yml' in files).toBe(false);
  expect(files['tablePkg/README.md']).toContain('lifecycle-experimental');
});

test('Customise: the navbar choices reach _pkgdown.yml', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await step(page, 'README');
  await page.locator('label.sw', { hasText: 'Add a website' }).click();
  await page.locator('label.pill', { hasText: 'Changelog' }).click();
  await page.locator('label.pill', { hasText: 'Light and dark switch' }).click();
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/_pkgdown.yml']).toContain('left: [reference, articles]');
  expect(files['tablePkg/_pkgdown.yml']).toContain('right: [search, github]');
});

test('Customise: the front-end switch adds the JS and CSS wording', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await step(page, 'Extras');
  await page.locator('label.sw', { hasText: 'JS or CSS' }).click();
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/CONTRIBUTING.md']).toMatch(/Biome[\s\S]*Chrome/);
  expect(files['tablePkg/.github/pull_request_template.md']).toContain('JavaScript and CSS changes');
  expect(files['tablePkg/tests/README.md']).toContain('test-demo-browser.R');
});

test('Customise: with every check off, there is no run-locally section, no Dependabot file and no caller files', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
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

test('Customise: the oldest R reaches DESCRIPTION, and the download works from there', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await customise(page);
  await page.locator('#minR').fill('4.3');
  await page.locator('#minR').dispatchEvent('change');
  await expect(page.locator('#minRZero')).toHaveText('.0');
  // The website note sits in the README and website step.
  await step(page, 'README');
  await expect(page.locator('#pagesNote')).toBeVisible();
  const { files } = await download(page, '#modDownload');
  await expect(page.locator('#nextView')).toBeVisible();
  expect(files['tablePkg/DESCRIPTION']).toContain('R (>= 4.3.0)');
  // No check runs on an R older than the one chosen.
  for (const [path, text] of Object.entries(files)) if (path.includes('/workflows/')) expect(text, path).not.toMatch(/^ *platforms:.*\/4\.1/m);
  // A private plan checks the oldest R on Linux too.
  expect(files['tablePkg/.github/workflows/r-cmd-check.yaml']).toContain('platforms: ubuntu/release, ubuntu/oldrel-1, ubuntu/4.3');
});

test('Customise: on a public plan, no check runs on an R older than the oldest R chosen', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=a]').check();
  await customise(page);
  await page.locator('#minR').fill('4.3');
  await page.locator('#minR').dispatchEvent('change');
  const { files } = await download(page, '#modDownload');
  const flows = Object.entries(files).filter(([path]) => path.includes('/workflows/'));
  for (const [path, text] of flows) expect(text, path).not.toMatch(/^ *platforms:.*\/4\.1/m);
  expect(files['tablePkg/.github/workflows/full-tests.yaml']).toContain('platforms: ubuntu/release, ubuntu/4.3');
});

test('Customise refuses an oldest R below 4.1 or with a patch number', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await page.locator('#minR').fill('4.1');
  await page.locator('#minR').dispatchEvent('change');
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/workflows/r-cmd-check.yaml'], 'the default oldest R adds no extra system').not.toContain('ubuntu/4.1');
  await page.locator('#nextChange').click();
  await customise(page);
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
  // Someone who made the repository on GitHub first connects to it, and a saved login is replaced, not kept.
  await expect(steps).toContainText('usethis::use_git_remote("origin", "https://github.com/sample-org/tablePkg.git")');
  await expect(steps).toContainText('gert::git_push(set_upstream = TRUE)');
  await expect(steps).toContainText('Replace these credentials');
  await page.getByText('With GitHub Desktop').click();
  await expect(steps).toContainText('Publish repository');
  await expect(steps).toContainText('If sample-org is an organisation, pick it under Organization.');
  await expect(steps).toContainText('paste https://github.com/sample-org/tablePkg.git as the remote, save, and click Publish branch');
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

test('Use a plan downloads at once; Customise a plan turns Download into Next and shows the steps', async ({ page }) => {
  await openForm(page);
  await expect(page.locator('#stepBar')).toBeHidden();
  await expect(page.locator('#modify')).toBeHidden();
  await fillForm(page);
  await expect(page.locator('#download')).toHaveAttribute('aria-disabled', 'false');
  await expect(page.locator('#missing')).toHaveText('');
  await page.locator('#how label', { hasText: 'Customise a plan' }).click();
  await expect(page.locator('#planLegend')).toHaveText('Start from this plan');
  await expect(page.locator('#download')).toBeHidden();
  await expect(page.locator('#stepBar button')).toHaveText([/^1\s*Your package$/, /^2\s*CI checks$/, /^3\s*Issues and checklists$/, /^4\s*README and website$/, /^5\s*Extras$/], { useInnerText: true });
  await page.locator('#modify').click();
  for (const [name, title] of [['Issues', 'Issues and checklists'], ['README', 'README and website'], ['Extras', 'Extras']]) {
    await page.locator('#stepNext').click();
    await expect(page.locator('#stepTitle')).toHaveText(title);
    await expect(page.locator(`#stepBar button[aria-current="step"]`)).toContainText(name);
  }
  await expect(page.locator('#stepNext')).toBeHidden();
  await expect(page.locator('#modDownload')).toHaveText('Download tablePkg.zip');
  // A change, then the switch off: the plan's own settings come back.
  await step(page, 'Extras');
  await page.locator('label.sw', { hasText: 'JS or CSS' }).click();
  await expect(page.locator('#pvCustom')).toBeVisible();
  await step(page, 'Your package');
  await page.locator('#how label', { hasText: 'Use a plan' }).click();
  await expect(page.locator('#planNote')).toHaveText("Your own settings were reset to the plan's.");
  await expect(page.locator('#pvCustom')).toBeHidden();
  await expect(page.locator('#download')).toBeVisible();
});

test('Customise: the checklists chosen reach DESCRIPTION, the preview beside the form and the steps after the download', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await expect(page.locator('#pvLists li')).toHaveText(['Set up', 'After public', 'Before CRAN', 'After acceptance', 'Next release']);
  await customise(page);
  await step(page, 'Issues');
  // A public plan is offered QC, but not Before public, and says why.
  await expect(page.locator('[data-stage="qc"]')).toHaveCount(1);
  await expect(page.locator('#bodyGit')).toContainText('Before public is for a private package.');
  await page.locator('label.pill', { hasText: 'After acceptance' }).click();
  await expect(page.locator('#pvLists li')).toHaveText(['Set up', 'After public', 'Before CRAN', 'Next release']);
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/DESCRIPTION']).toContain('Config/launchR/checklists: Set up, After public, Before CRAN, Next release');
  const after = page.locator('#nextAfter');
  await expect(after).toContainText('Set up, After public and Before CRAN open in your repository\'s issues on the first run of Set up this repository.');
  await expect(after).toContainText('Next release opens on a later run, once its stage arrives.');
  await expect(after.locator('li')).toHaveCount(4);
});

test('Customise: plan d starts with Set up and Next release with the QC sections', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await expect(page.locator('#pvLists li')).toHaveText(['Set up', 'Next release', 'QC']);
  await download(page, '#download');
  await expect(page.locator('#nextAfter')).toContainText('Set up and Next release open in your repository\'s issues on the first run of Set up this repository.');
  await expect(page.locator('#nextAfter')).toContainText('QC adds its sections to each Next release checklist.');
  await expect(page.locator('#nextAfter')).not.toContainText('QC opens on a later run');
});

test('Customise: the launchR credit is not offered but every README gets it, and a badge that needs something says what', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await page.locator('input[name=plan][value=d]').check();
  await customise(page);
  await step(page, 'README');
  await expect(page.locator('[data-badge="launchr"]')).toHaveCount(0);
  await expect(page.locator('.shield-opt', { has: page.locator('[data-badge="cran"]') }).locator('.shield-why')).toHaveAttribute('aria-label', 'For a package going to CRAN.');
  // One tooltip on the heading explains every badge; the shields carry none.
  await expect(page.locator('.shield-opt .tip:not(.shield-why)')).toHaveCount(0);
  await expect(page.locator('#bodySite h4 .tip')).toContainText('CRAN downloads');
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/README.md']).toContain('img.shields.io/badge/set%20up%20with-launchR');
});

test('the preview window shows the checklists, the issue forms and the guide for agents', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await step(page, 'Issues');
  await page.getByRole('button', { name: 'Preview the checklists' }).click();
  const win = page.locator('#peek');
  await expect(win).toBeVisible();
  await expect(win.locator('article:visible .peek-title')).toHaveText('Checklist: Set up');
  await win.getByRole('button', { name: 'QC', exact: true }).click();
  await expect(win.locator('article:visible .peek-title')).toHaveText('Added to Checklist: Next release');
  await expect(win.locator('article:visible')).toContainText('Coverage meets the limit in DESCRIPTION');
  await win.getByRole('button', { name: 'Bug report' }).click();
  await expect(win.locator('article:visible')).toContainText('Minimal reproducible example (reprex)');
  await expect(win.locator('article:visible')).toContainText('sets the label bug');
  await win.getByRole('button', { name: 'SKILL.md' }).click();
  await expect(win.locator('article:visible h1')).toHaveText('Working on a launchR package');
  await page.keyboard.press('Escape');
  await expect(win).toBeHidden();
  await expect(page.locator('#setup')).toBeVisible();
});

test('an existing package goes through Checks and Website only', async ({ page }) => {
  await openExisting(page);
  await page.locator('#exModify').click();
  await expect(page.locator('#stepBar button:visible')).toHaveText([/^1\s*CI checks$/, /^2\s*Website$/], { useInnerText: true });
  await page.locator('#stepNext').click();
  await expect(page.locator('#stepTitle')).toHaveText('Website');
  await expect(page.locator('.shields')).toBeHidden();
  await page.locator('#modBack').click();
  await page.locator('#modBack').click();
  await expect(page.locator('#existingView')).toBeVisible();
});

test('Customise: each plan is offered only the checklists it can open', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  const offered = async () => page.locator('#bodyGit [data-stage]').evaluateAll((boxes) => boxes.map((box) => box.dataset.stage));
  await page.locator('input[name=plan][value=c]').check();
  await customise(page);
  await step(page, 'Issues');
  expect(await offered()).toEqual(['set-up', 'before-public', 'after-public', 'before-cran', 'after-acceptance', 'next-release', 'qc']);
  await step(page, 'Your package');
  await page.locator('input[name=plan][value=a]').check();
  await step(page, 'Issues');
  expect(await offered()).toEqual(['set-up', 'after-public', 'before-cran', 'after-acceptance', 'next-release', 'qc']);
  await expect(page.locator('#bodyGit')).toContainText('Before public is for a private package.');
  await step(page, 'Your package');
  await page.locator('input[name=plan][value=d]').check();
  await step(page, 'Issues');
  expect(await offered()).toEqual(['set-up', 'before-public', 'after-public', 'next-release', 'qc']);
  await expect(page.locator('#bodyGit')).toContainText('Before CRAN and After acceptance are for a package going to CRAN.');
  // QC is sections of Next release: without QC, plan d keeps Set up and Next release.
  await page.locator('label.pill', { hasText: 'QC' }).click();
  await expect(page.locator('#pvLists li')).toHaveText(['Set up', 'Next release']);
  // Choosing QC chooses Next release, and leaving Next release out leaves QC out.
  await page.locator('label.pill', { hasText: 'Next release' }).click();
  await expect(page.locator('#pvLists li')).toHaveText(['Set up']);
  await page.locator('label.pill', { hasText: 'QC' }).click();
  await expect(page.locator('[data-stage="next-release"]')).toBeChecked();
  await expect(page.locator('#pvLists li')).toHaveText(['Set up', 'Next release', 'QC']);
  await page.locator('label.pill', { hasText: 'Next release' }).click();
  await expect(page.locator('[data-stage="qc"]')).not.toBeChecked();
});

test('Customise: one tooltip explains the AI files, naming every rules file the zip gets', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await step(page, 'Extras');
  const tip = page.locator('.opt', { has: page.locator('#ai') }).locator('.tip');
  await expect(tip).toHaveAttribute('aria-label', /\.agents\/rules\/: One rules file each for checks, docs, git, js-css, r-code, tests\./);
  await expect(tip).toHaveAttribute('aria-label', /SKILL\.md: launchR's skill/);
  await expect(page.locator('#bodyMore .sw-note')).toHaveCount(0);
});

test('Customise: New feature sets its own label, a shared label says which form still sets it, and the oldest R is filled in', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await expect(page.locator('#minR')).toHaveValue('4.1');
  await expect(page.locator('#bodyCi h4', { hasText: 'R CMD check: R versions × systems' })).toBeVisible();
  await step(page, 'Issues');
  await expect(page.locator('label.fcard', { hasText: 'New feature' })).toContainText('feature');
  await page.locator('label.fcard', { hasText: 'Bug report' }).click();
  await expect(page.locator('label.fcard', { hasText: 'Bug report' })).toContainText('not added');
  await step(page, 'README');
  await page.locator('label.sw', { hasText: 'Add a website' }).click();
  await expect(page.locator('#bodySite h4', { hasText: /^Navbar/ }).locator('.tip').first()).toHaveAttribute('aria-label', /_pkgdown\.yml: /);
  await expect(page.locator('#bodySite .sublabel', { hasText: 'Left' })).toBeVisible();
  await expect(page.locator('#bodySite .tip')).toHaveCount(3);
  // Every toggle shows its choice by its outline and fill, never by a tick.
  await expect(page.locator('#modifyView .pill svg:visible, #modifyView .fcard svg:visible')).toHaveCount(0);
  const { files } = await download(page, '#modDownload');
  expect(files['tablePkg/.github/ISSUE_TEMPLATE/02-feature.yml']).toContain('labels: [feature]');
  expect(files['tablePkg/DESCRIPTION']).toContain('R (>= 4.1.0)');
});

test('after Change my choices, the keyboard lands on the button that is there', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await download(page, '#download');
  await page.locator('#nextChange').click();
  await expect(page.locator('#download')).toBeFocused();
});

test('an existing package goes through its steps to a zip', async ({ page }) => {
  await openExisting(page);
  await page.locator('#exModify').click();
  await page.locator('#stepNext').click();
  const { name } = await download(page, '#modDownload');
  expect(name).toBe('launchR-files.zip');
  await expect(page.locator('#nextView')).toBeVisible();
});

test('an existing package with only a website is not pointed to the workflows README', async ({ page }) => {
  await openExisting(page);
  await page.locator('#exRows label.pill', { hasText: 'Automatic checks' }).click();
  await page.locator('#exRows label.pill', { hasText: 'Website' }).click();
  const { files } = await download(page, '#exDownload');
  expect('.github/workflows/README.md' in files).toBe(false);
  await expect(page.locator('#nextAfter')).not.toContainText('Codecov');
});

test('on a phone the preview window fills the screen', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openForm(page);
  await fillForm(page);
  await customise(page);
  await step(page, 'Issues');
  await page.getByRole('button', { name: 'Preview the issue forms' }).click();
  const box = await page.locator('#peek').boundingBox();
  expect(box.width).toBeGreaterThanOrEqual(389);
  expect(box.height).toBeGreaterThanOrEqual(843);
  await expect(page.locator('#peek article:visible .peek-title')).toHaveText('Bug report');
});

test('the oldest R takes one digit on each side of the dot, and puts the dot in for you', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await customise(page);
  const box = page.locator('#minR');
  for (const [typed, shown] of [['44', '4.4'], ['22.0', '2.2'], ['4.3', '4.3']]) {
    await box.fill('');
    await box.pressSequentially(typed);
    await expect(box).toHaveValue(shown);
  }
});

test("the landing page's SKILL.md link opens the preview window, and the address still serves the file", async ({ page }) => {
  await page.goto('/');
  const reject = page.locator('#cookieNo');
  if (await reject.isVisible()) await reject.click();
  await page.locator('a[data-open="skill"]').click();
  await expect(page.locator('#peek')).toBeVisible();
  await expect(page.locator('#peek article:visible h1')).toHaveText('Working on a launchR package');
  await expect(page).toHaveURL(/\/$/);
  const file = await page.request.get('/SKILL.md');
  expect(file.ok()).toBe(true);
});

test('the first screen fits a 1440 by 900 window, with the sign-up hint in the GitHub name tip', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openForm(page);
  const box = await page.locator('#download').boundingBox();
  expect(box.y + box.height).toBeLessThanOrEqual(900);
  await expect(page.locator('#owner-note')).toHaveCount(0);
  await expect(page.locator('#tip-owner')).toContainText('Sign up free at github.com/signup');
});

test('the preview card starts where the subtitle ends, on the first screen and every settings step', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  const gap = async () => page.evaluate(() => {
    const sub = [...document.querySelectorAll('#setup .setup-grid .sub')].find((el) => el.offsetParent);
    return Math.abs(document.querySelector('#setup .preview').getBoundingClientRect().top - sub.getBoundingClientRect().bottom);
  });
  await expect.poll(gap, { message: 'first screen' }).toBeLessThan(2);
  await customise(page);
  for (const name of ['CI checks', 'Issues', 'README', 'Extras']) {
    await step(page, name);
    await expect.poll(gap, { message: name }).toBeLessThan(2);
  }
});

test('the next steps give one step for the checks running and Set up this repository, on both routes', async ({ page }) => {
  await openForm(page);
  await fillForm(page);
  await download(page, '#download');
  const steps = page.locator('#stepList li');
  const actions = steps.filter({ hasText: 'go to Actions' });
  await expect(actions).toHaveCount(1);
  await expect(actions).toContainText('your checks are running. Then open Set up this repository');
  await page.getByText('With GitHub Desktop').click();
  await expect(steps.filter({ hasText: 'go to Actions' })).toHaveCount(1);
  await expect(steps.filter({ hasText: 'Set up this repository' })).toHaveCount(1);
  await expect(page.locator('#nextDone')).toHaveText('Close');
});

test('an existing package with CI and the issue forms gets one Actions step', async ({ page }) => {
  await openExisting(page);
  await page.locator('#exRows label.pill', { hasText: 'Issue forms' }).click();
  await download(page, '#exDownload');
  const actions = page.locator('#stepList li').filter({ hasText: 'go to Actions' });
  await expect(actions).toHaveCount(1);
  await expect(actions).toContainText('your checks are running. Then open Set up this repository');
});
