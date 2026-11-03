// Turns choices into files. cli/R/build.R follows the same steps, and tests/compare-routes.mjs compares them.

export function parseList(text) {
  const rows = text.split('\n').filter((line) => line !== '' && !line.startsWith('#'));
  const header = rows[0].split('\t');
  return rows.slice(1).map((row) => {
    const cells = row.split('\t');
    return Object.fromEntries(header.map((name, i) => [name, cells[i] ?? '']));
  });
}

export function readLists(bundle) {
  const list = (name) => parseList(bundle.lists[name]);
  const settings = Object.fromEntries(list('settings.tsv').map((row) => [row.key, row.value]));
  return {
    settings,
    parts: list('parts.tsv'),
    checks: list('checks.tsv'),
    files: list('files.tsv'),
    plans: list('plans.tsv'),
  };
}

// The rules for what a person types, with the same messages in cli/R/choices.R. DESCRIPTION holds these as text and as
// R code (Authors@R), so quotes and backslashes would break it.
export function checkTitle(title) {
  if (!title) return 'Say in one line what it does. This goes in DESCRIPTION.';
  if (title.length > 65) return `Keep it to 65 characters. It is ${title.length} now.`;
  if (/["\\{}%]/.test(title)) return 'Use plain words here: no double quotes, backslashes, braces or percent signs.';
  return '';
}

// The longer description is optional: left empty, DESCRIPTION repeats the title. CRAN asks that it doesn't start with
// the package's name or "This package".
export function checkDescription(text, name) {
  if (!text) return '';
  if (text.length > 500) return `Keep it to 500 characters. It is ${text.length} now.`;
  if (/["\\{}%]/.test(text)) return 'Use plain words here: no double quotes, backslashes, braces or percent signs.';
  const start = text.toLowerCase();
  if (start.startsWith('this package') || (name && start.startsWith(name.toLowerCase()))) {
    return 'Start with what it does, not with "This package" or its name: CRAN asks for that.';
  }
  return '';
}

export function checkPerson(name, which) {
  if (!name) return `Add a ${which} name. DESCRIPTION needs an author.`;
  return /["\\]/.test(name) ? "Names can't contain double quotes or backslashes." : '';
}

export function checkEmail(email) {
  return !email || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ? '' : 'That email looks incomplete, or leave it empty.';
}

// The oldest R a package supports, as x.y (one digit each) from 4.1 on; DESCRIPTION gets x.y.0. cli/R/choices.R has
// the same.
export function checkMinR(minR) {
  const parts = minR.split('.').map(Number);
  const ok = /^\d\.\d$/.test(minR) && (parts[0] > 4 || (parts[0] === 4 && parts[1] >= 1));
  return ok ? '' : 'Give x.y from 4.1 on, such as 4.3. The .0 is added for you.';
}

// A title without its full stop: DESCRIPTION's Description adds one.
export const cleanTitle = (title) => title.replace(/[.\s]+$/, '');
// DESCRIPTION's Description: the person's own sentences, or the title, ending in a full stop either way.
export const descriptionText = (choices) => (choices.description?.trim() ? choices.description.trim().replace(/\s+/g, ' ').replace(/([^.!?])$/, '$1.') : `${cleanTitle(choices.title)}.`);

// R's rules for a package name, plus a length limit and the names of R's own packages. cli/R/choices.R has the same.
export function checkPackageName(name, lists) {
  if (name.length < 2) return 'Names need at least two characters.';
  if (name.length > 60) return 'Keep the name under 60 characters.';
  if (lists.settings.base_packages.split(',').map((base) => base.trim()).includes(name)) {
    return `${name} is part of R itself, so choose another name.`;
  }
  if (!/^[A-Za-z]/.test(name)) return 'Names must start with a letter.';
  if (/[.]$/.test(name)) return "Names can't end in a dot.";
  if (!/^[A-Za-z0-9.]+$/.test(name)) return 'Names can only use letters, numbers and dots.';
  return '';
}

// What a plan starts from: visibility, release, and whether r-cmd-check-extended is on (lists/plans.tsv).
export function planRow(lists, plan = lists.settings.plan) {
  return lists.plans.find((row) => row.plan === plan) ?? lists.plans.find((row) => row.plan === lists.settings.plan);
}

export function defaultChoices(lists, preset = lists.settings.preset, plan = lists.settings.plan) {
  const chosen = planRow(lists, plan);
  return {
    package: '',
    title: '',
    description: '',
    given: '',
    family: '',
    email: '',
    owner: '',
    visibility: chosen.visibility,
    release: chosen.release,
    year: String(new Date().getFullYear()),
    branches: lists.settings.branches,
    minR: lists.settings.min_r,
    parts: lists.parts.filter((row) => row[preset] === 'yes').map((row) => row.part),
    checks: Object.fromEntries(
      lists.checks.map((row) => [
        row.key,
        {
          on: row[preset] === 'yes' && !(row.key === 'r_cmd_check_extended' && chosen.extended === 'no'),
          events: row.events.split(','),
          cron: row.cron,
          platforms: null,
        },
      ]),
    ),
  };
}

function settleChoices(choices) {
  if (choices.owner !== '') return choices;
  return { ...choices, parts: choices.parts.filter((part) => part !== 'website') };
}

function manSeealso(urls, repository) {
  return [
    '\\seealso{',
    'Useful links:',
    '\\itemize{',
    ...urls.map((url) => `  \\item \\url{${url}}`),
    `  \\item Report bugs at \\url{${repository}/issues}`,
    '}',
    '',
    '}',
  ].join('\n');
}

// When a check runs, in words for the workflows README: "pull requests, pushes, Mondays at 05:00 UTC, by hand".
const WEEKDAYS = ['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];
function whenText(check) {
  const [minute, hour, , , day] = check.cron.split(' ');
  const time = `${hour.padStart(2, '0')}:${minute.padStart(2, '0')} UTC`;
  const parts = [];
  if (check.events.includes('pr')) parts.push('pull requests');
  if (check.events.includes('push')) parts.push('pushes');
  if (check.events.includes('schedule')) parts.push(day === '*' ? `every day at ${time}` : `${WEEKDAYS[Number(day)]} at ${time}`);
  if (check.events.includes('manual')) parts.push('by hand');
  return parts.join(', ');
}

// Which of the package's checks run each kind of test file, for tests/README.md.
const TEST_KINDS = {
  plain: ['r_cmd_check', 'coverage', 'full_tests', 'r_cmd_check_extended'],
  browser: ['full_tests'],
  snap: ['full_tests'],
  extended: ['coverage', 'full_tests', 'r_cmd_check_extended'],
};

export function placeholderValues(choices, lists) {
  const hasOwner = choices.owner !== '';
  const isPublic = choices.visibility === 'public';
  const siteUrl = lists.settings.site_url;
  const owner = hasOwner ? choices.owner : 'your-github-name';
  const frontend = choices.parts.includes('frontend');
  const repository = `https://github.com/${owner}/${choices.package}`;
  const site = `https://${owner}.github.io/${choices.package}`;
  const urls = [...(choices.parts.includes('website') ? [`${site}/`] : []), repository];
  // The spelling check splits a name at digits and dots (demoPkg2 is read as demoPkg), so the parts go in the word list.
  const parts = [...new Set(choices.package.split(/[^A-Za-z]+/))].filter((part) => part.length > 1 && part !== choices.package);
  const values = {
    package: choices.package,
    name_words: parts.map((part) => `${part}\n`).join(''),
    title: cleanTitle(choices.title),
    description: descriptionText(choices),
    author: `${choices.given} ${choices.family}`,
    given: choices.given,
    family: choices.family,
    email: choices.email || lists.settings.placeholder_email,
    owner,
    owner_or_you: owner,
    year: choices.year,
    kit_version: lists.settings.kit_version,
    branches: choices.branches,
    url_line: hasOwner ? `URL: ${urls.join(', ')}` : '',
    man_seealso: hasOwner ? manSeealso(urls, repository) : '',
    pkgdown_url_line: hasOwner ? `url: ${site}/` : '',
    bugreports_line: hasOwner ? `BugReports: ${repository}/issues` : '',
    chromote_line: frontend ? '    chromote,' : '',
    target_line: choices.release === 'internal' ? 'Config/quality-gate/target: internal' : '',
    check_badge: isPublic && hasOwner && choices.parts.includes('ci') && choices.checks.r_cmd_check?.on
      ? `[![R-CMD-check](${repository}/actions/workflows/r-cmd-check.yaml/badge.svg)](${repository}/actions/workflows/r-cmd-check.yaml)`
      : '',
    credit_badge: isPublic ? `[![Set up with launchR](https://img.shields.io/badge/set%20up%20with-launchR-f6ab85)](${siteUrl})\n` : '',
    credit_line: `\nSet up with [launchR](${siteUrl}).`,
  };
  // The oldest R supported: in DESCRIPTION, and in place of 4.1 in the default platforms.
  const minR = choices.minR || lists.settings.min_r;
  // DESCRIPTION takes major.minor.0: R CMD check warns about any other patch level. CI runs the newest patch of it.
    values.min_r = `${minR}.0`;
  const ciOn = choices.parts.includes('ci');
  const onRows = ciOn ? lists.checks.filter((row) => choices.checks[row.key].on) : [];
  values.checks_table = onRows.length
    ? onRows.map((row) => `| \`${row.check}.yaml\` | ${row.label} | ${whenText(choices.checks[row.key])} |`).join('\n')
    : '| None yet | Come back to the site to add one | |';
  for (const [kind, keys] of Object.entries(TEST_KINDS)) {
    const names = onRows.filter((row) => keys.includes(row.key)).map((row) => `\`${row.check}\``);
    values[`runs_${kind}`] = names.length ? names.join(', ') : 'none of the checks yet';
  }
  // .Renviron runs the extended tests locally when a check runs them in CI.
  const extendedInCi = ['full_tests', 'coverage', 'r_cmd_check_extended'].some((key) => ciOn && choices.checks[key]?.on);
  values.extended_env = extendedInCi ? 'EXTENDED_TESTS=true' : '# EXTENDED_TESTS=true';
  values.browser_row = frontend
    ? `| \`-browser.R\` | Tests that drive a browser (shinytest2, chromote); start them with \`options(chromote.timeout = 60)\`, as Chrome can start slowly on CI | \`test-demo-browser.R\` | ${values.runs_browser} |`
    : '';
  values.browser_skip = frontend ? 'skip_on_cran()                                                    # -browser.R files' : '';
  // How to send coverage to Codecov; codecov.yml comes with new packages only (an existing package's .Rbuildignore
  // doesn't list it).
  values.codecov_note = ciOn && choices.checks.coverage?.on
    ? `${[
      '## Codecov',
      '',
      'The coverage check decides on its own. To also show coverage on Codecov:',
      '',
      '1. Sign in at <https://about.codecov.io> with GitHub and add this repository.',
      '2. Copy its upload token. On GitHub, add it as a repository secret named `CODECOV_TOKEN` (Settings, then Secrets and',
      '   variables, then Actions).',
      '3. In `coverage.yaml`, remove the `#` before the `secrets:` and `CODECOV_TOKEN:` lines.',
      ...(choices.parts.includes('skeleton') ? [
        '',
        '`codecov.yml` at the top of the package keeps Codecov to reporting: no blocking status and no second comment.',
      ] : []),
    ].join('\n')}\n\n`
    : '';
  const testKinds = [
    '## Test file kinds',
    '',
    'Most tests run in every check. Files whose name ends in a kind run only where they can:',
    '',
    '| File name ends in | What it holds | Runs in |',
    '| --- | --- | --- |',
    `| \`-browser.R\` | Tests that drive a browser (shinytest2, chromote); start them with \`options(chromote.timeout = 60)\`, as Chrome can start slowly on CI | ${values.runs_browser} |`,
    `| \`-snap.R\` | Snapshot tests (\`expect_snapshot()\`) | ${values.runs_snap} |`,
    `| \`-extended.R\` | Slow or detailed tests | ${values.runs_extended} |`,
    '',
    'Start each browser file with `skip_on_cran()` and each extended file with',
    '`skip_if_not(identical(Sys.getenv("EXTENDED_TESTS"), "true"))`, so CRAN and R CMD check skip them.',
  ].join('\n');
  values.test_kinds_section = choices.parts.includes('skeleton')
    ? 'Which test files each check runs: `tests/README.md`.\n\n'
    : `${testKinds}\n\n`;
  values.full_tests_line = ciOn && choices.checks.full_tests?.on ? '`full-tests` runs every kind and fails if any test skips there. ' : '';
  values.time_limit_section = ciOn && choices.checks.r_cmd_check?.on
    ? '## The time limit\n\n`r-cmd-check` fails when the tests take longer than `test-time-limit` seconds on Linux with R release (180 by default;\n0 turns it off). CRAN asks for quick checks. Move slow tests to a `-extended.R` file, or make them faster.\n\n'
    : '';
  for (const row of lists.checks) {
    const check = choices.checks[row.key];
    for (const event of ['pr', 'push', 'schedule', 'manual']) {
      values[`c_${row.key}_${event}`] = check.events.includes(event) ? '' : '# ';
    }
    values[`cron_${row.key}`] = check.cron;
    // A chosen oldest R is checked on Linux by R CMD check, as the site's Modify page does. cli/R/build.R has the same.
    const oldest = row.key === 'r_cmd_check' && minR !== lists.settings.min_r ? `, ubuntu/${minR}` : '';
    values[`platforms_${row.key}`] = check.platforms ?? `${row[`platforms_${choices.visibility}`]}${oldest}`;
  }
  return values;
}

export function renderText(text, values) {
  const empty = new Set(
    Object.keys(values)
      .filter((key) => values[key] === '')
      .map((key) => `{{${key}}}`),
  );
  let out = text
    .split('\n')
    .filter((line) => !empty.has(line))
    .join('\n');
  for (const [key, value] of Object.entries(values)) {
    out = out.replaceAll(`{{${key}}}`, value);
  }
  return out;
}

export function selectedFiles(choices, lists) {
  const onChecks = new Set(lists.checks.filter((row) => choices.checks[row.key].on).map((row) => row.check));
  return lists.files
    .filter(
      (row) =>
        choices.parts.includes(row.part) &&
        (row.check === '' || (choices.parts.includes('ci') && onChecks.has(row.check))) &&
        (row.release === 'any' || row.release === choices.release),
    )
    .map((row) => row.path);
}

export function buildPackage(rawChoices, bundle) {
  const lists = readLists(bundle);
  const choices = settleChoices(rawChoices);
  const values = placeholderValues(choices, lists);
  const files = {};
  for (const path of selectedFiles(choices, lists)) {
    files[renderText(path, values)] = renderText(bundle.template[path], values);
  }
  return files;
}
