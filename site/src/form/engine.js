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
  };
}

export function checkPackageName(name) {
  if (name.length < 2) return 'Names need at least two characters.';
  if (!/^[A-Za-z]/.test(name)) return 'Names must start with a letter.';
  if (/[.]$/.test(name)) return "Names can't end in a dot.";
  if (!/^[A-Za-z0-9.]+$/.test(name)) return 'Names can only use letters, numbers and dots.';
  return '';
}

export function defaultChoices(lists, preset = lists.settings.preset) {
  return {
    package: '',
    title: '',
    given: '',
    family: '',
    email: '',
    owner: '',
    visibility: 'private',
    release: 'cran',
    year: String(new Date().getFullYear()),
    branches: lists.settings.branches,
    parts: lists.parts.filter((row) => row[preset] === 'yes').map((row) => row.part),
    checks: Object.fromEntries(
      lists.checks.map((row) => [
        row.key,
        { on: row[preset] === 'yes', events: row.events.split(','), cron: row.cron, platforms: null },
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

export function placeholderValues(choices, lists) {
  const hasOwner = choices.owner !== '';
  const isPublic = choices.visibility === 'public';
  const siteUrl = lists.settings.site_url;
  const owner = hasOwner ? choices.owner : 'your-github-name';
  const frontend = choices.parts.includes('frontend');
  const repository = `https://github.com/${owner}/${choices.package}`;
  const site = `https://${owner}.github.io/${choices.package}`;
  const urls = [...(choices.parts.includes('website') ? [`${site}/`] : []), repository];
  const values = {
    package: choices.package,
    title: choices.title,
    description: `${choices.title}.`,
    author: `${choices.given} ${choices.family}`,
    given: choices.given,
    family: choices.family,
    email: choices.email,
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
    credit_badge: isPublic ? `[![Set up with launchR](https://img.shields.io/badge/set%20up%20with-launchR-f6ab85)](${siteUrl})\n` : '',
    credit_line: isPublic ? `\nSet up with [launchR](${siteUrl}).` : '',
    js_css_tests: frontend ? 'true' : 'false',
  };
  for (const row of lists.checks) {
    const check = choices.checks[row.key];
    for (const event of ['pr', 'push', 'weekly', 'manual']) {
      values[`c_${row.key}_${event}`] = check.events.includes(event) ? '' : '# ';
    }
    values[`cron_${row.key}`] = check.cron;
    values[`platforms_${row.key}`] = check.platforms ?? row[`platforms_${choices.visibility}`];
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
        (row.check === '' || onChecks.has(row.check)) &&
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
