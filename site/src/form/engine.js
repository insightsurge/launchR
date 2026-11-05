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
    badges: list('badges.tsv'),
    navbar: list('navbar.tsv'),
    forms: list('forms.tsv'),
    labels: list('labels.tsv'),
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

// The longer description is optional: left empty, DESCRIPTION repeats the title. R CMD check --as-cran notes a
// Description that starts with the package's name, with "This package", "A package" and the like, or in lower case.
export function checkDescription(text, name) {
  if (!text) return '';
  if (text.length > 500) return `Keep it to 500 characters. It is ${text.length} now.`;
  if (/["\\{}%]/.test(text)) return 'Use plain words here: no double quotes, backslashes, braces or percent signs.';
  if (/^(the|this|a|in this|in the) package/i.test(text) || (name && text.toLowerCase().startsWith(name.toLowerCase()))) {
    return 'Start with what it does, not with "This package", "A package" or its name: CRAN asks for that.';
  }
  if (!/^['A-Z]/.test(text)) return 'Start with a capital letter, as CRAN asks.';
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
    ...planExtras(lists, chosen),
  };
}

// The Modify choices that follow from the plan: badges and the QC checklist depend on the visibility; the licence is
// proprietary only for a private package that won't go to CRAN, since R CMD check as CRAN gives a NOTE for any other
// licence than an open-source one. cli/R/choices.R has the same.
export function planExtras(lists, chosen) {
  return {
    ciReport: true,
    licence: chosen.visibility === 'private' && chosen.release === 'internal' ? 'proprietary' : 'mit',
    badges: lists.badges.filter((row) => row[chosen.visibility] === 'yes').map((row) => row.key),
    navbar: lists.navbar.filter((row) => row.on === 'yes').map((row) => row.key),
    forms: lists.forms.map((row) => row.key),
    labels: lists.labels.map((row) => row.name),
    qc: chosen.qc === 'yes',
  };
}

// Whether a badge can be offered: its needs (lists/badges.tsv) are all met.
export function badgeOffered(row, choices) {
  return row.needs.split(',').filter(Boolean).every((need) => {
    if (need === 'owner') return choices.owner !== '';
    if (need === 'cran') return choices.release === 'cran';
    return choices.parts.includes('ci') && !!choices.checks[need]?.on;
  });
}

// The labels a package gets: the chosen ones, the label of every chosen issue form, and the ones the set-up step
// uses (the kept column), in lists/labels.tsv order.
export function chosenLabels(choices, lists) {
  const forms = lists.forms.filter((row) => choices.forms.includes(row.key) && choices.parts.includes(row.part));
  const kept = lists.labels.filter((row) => row.kept !== '').map((row) => row.name);
  const wanted = new Set([...choices.labels, ...forms.map((row) => row.label), ...kept]);
  return lists.labels.filter((row) => wanted.has(row.name)).map((row) => row.name);
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

// When a check runs, in words for the workflows README: "pull requests, pushes, Mondays at 05:17 UTC, by hand". The
// weekday names are in lists/settings.tsv, which cli/R/build.R reads too.
function whenText(check, lists) {
  const parts = [];
  if (check.events.includes('pr')) parts.push('pull requests');
  if (check.events.includes('push')) parts.push('pushes');
  if (check.events.includes('schedule')) {
    const [minute, hour, , , day] = check.cron.split(' ');
    const time = `${hour.padStart(2, '0')}:${minute.padStart(2, '0')} UTC`;
    parts.push(day === '*' ? `every day at ${time}` : `${lists.settings.weekdays.split(', ')[Number(day)]} at ${time}`);
  }
  if (check.events.includes('manual')) parts.push('by hand');
  return parts.join(', ');
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
    license_line: choices.licence === 'mit' ? 'License: MIT + file LICENSE' : 'License: file LICENSE',
    ci_report: choices.ciReport ? 'true' : 'false',
    credit_line: `\nSet up with [launchR](${siteUrl}).`,
  };
  // The oldest R supported: in DESCRIPTION, and in place of 4.1 in the default platforms.
  const minR = choices.minR || lists.settings.min_r;
  // DESCRIPTION takes major.minor.0: R CMD check warns about any other patch level. CI runs the newest patch of it.
  values.min_r = `${minR}.0`;
  const ciOn = choices.parts.includes('ci');
  const checkOn = (key) => ciOn && !!choices.checks[key]?.on;
  const onRows = lists.checks.filter((row) => checkOn(row.key));
  values.checks_table = onRows.map((row) => `| \`${row.check}.yaml\` | ${row.label} | ${whenText(choices.checks[row.key], lists)} |`).join('\n');
  // Which checks run each kind of test file (the test_kinds column of lists/checks.tsv), for tests/README.md.
  const kinds = new Set(lists.checks.flatMap((row) => row.test_kinds.split(',')).filter(Boolean));
  for (const kind of kinds) {
    const names = onRows.filter((row) => row.test_kinds.split(',').includes(kind)).map((row) => `\`${row.check}\``);
    values[`runs_${kind}`] = names.length ? names.join(', ') : 'none of the checks yet';
  }
  // .Renviron runs the extended tests locally when a check runs them in CI.
  values.extended_env = ['full_tests', 'coverage', 'r_cmd_check_extended'].some(checkOn) ? 'EXTENDED_TESTS=true' : '# EXTENDED_TESTS=true';
  // What the template's {{#has_...}} blocks ask. The paragraphs themselves are in the template.
  const yes = (on) => (on ? 'yes' : '');
  values.has_skeleton = yes(choices.parts.includes('skeleton'));
  values.has_frontend = yes(frontend);
  values.has_checks = yes(onRows.length > 0);
  values.has_coverage = yes(checkOn('coverage'));
  values.has_full_tests = yes(checkOn('full_tests'));
  values.has_time_limit = yes(checkOn('r_cmd_check'));
  values.is_internal = yes(choices.release === 'internal');
  values.is_private = yes(!isPublic);
  values.is_mit = yes(choices.licence === 'mit');
  // README badges: the chosen ones whose needs are met, in lists/badges.tsv order.
  const badgeLines = lists.badges
    .filter((row) => choices.badges.includes(row.key) && badgeOffered(row, choices))
    .map((row) => row.line.replaceAll('{repository}', repository).replaceAll('{owner}', owner).replaceAll('{package}', choices.package).replaceAll('{site_url}', siteUrl));
  values.badges = badgeLines.join('\n');
  values.has_badges = yes(badgeLines.length > 0);
  for (const side of ['left', 'right']) {
    values[`navbar_${side}`] = lists.navbar.filter((row) => row.side === side && choices.navbar.includes(row.key)).map((row) => row.name).join(', ');
  }
  for (const row of lists.forms) values[`form_${row.key}`] = yes(choices.forms.includes(row.key));
  // DESCRIPTION records a choice of labels and the QC checklist, for the Set up this repository step (cli/R/github.R).
  const labels = chosenLabels(choices, lists);
  values.labels_line = choices.parts.includes('github') && labels.length < lists.labels.length ? `Config/launchR/labels: ${labels.join(', ')}` : '';
  values.checklist_line = choices.parts.includes('github') && choices.qc && !isPublic ? `Config/launchR/checklist: ${lists.settings.qc_stage}` : '';
  for (const row of lists.checks) {
    const check = choices.checks[row.key];
    for (const event of ['pr', 'push', 'schedule', 'manual']) {
      values[`c_${row.key}_${event}`] = check.events.includes(event) ? '' : '# ';
    }
    values[`cron_${row.key}`] = check.cron;
    // The default oldest R (4.1) in a check's systems becomes the chosen one, and R CMD check runs on it on Linux, as
    // the site's Modify page does. cli/R/build.R has the same.
    const start = row[`platforms_${choices.visibility}`].replaceAll(`/${lists.settings.min_r}`, `/${minR}`);
    const oldest = row.key === 'r_cmd_check' && minR !== lists.settings.min_r && !start.includes(`ubuntu/${minR}`) ? `, ubuntu/${minR}` : '';
    values[`platforms_${row.key}`] = check.platforms ?? `${start}${oldest}`;
  }
  return values;
}

// Keeps or drops the template's blocks. A block is a line {{#name}} (kept when the value called name is not empty) or
// {{^name}} (kept when it is empty), the lines under it, and a line {{/name}}. Blocks nest. cli/R/build.R does the same.
function applyBlocks(text, values) {
  const keep = [true];
  const out = [];
  for (const line of text.split('\n')) {
    const open = line.match(/^\{\{([#^])(\w+)\}\}$/);
    if (open) {
      if (!(open[2] in values)) throw new Error(`No value for the block ${open[2]}`);
      keep.push(keep.at(-1) && (values[open[2]] !== '') === (open[1] === '#'));
    } else if (/^\{\{\/\w+\}\}$/.test(line)) {
      keep.pop();
    } else if (keep.at(-1)) {
      out.push(line);
    }
  }
  return out.join('\n');
}

export function renderText(text, values) {
  const empty = new Set(
    Object.keys(values)
      .filter((key) => values[key] === '')
      .map((key) => `{{${key}}}`),
  );
  let out = applyBlocks(text, values)
    .split('\n')
    .filter((line) => !empty.has(line))
    .join('\n');
  for (const [key, value] of Object.entries(values)) {
    out = out.replaceAll(`{{${key}}}`, value);
  }
  return out;
}

// The route for a package that already exists (choices.existing) has no skeleton part, but takes the settings files of
// the checks it chooses: the rows whose existing column names a check that is on.
export function selectedFiles(choices, lists, values = {}) {
  const onChecks = new Set(lists.checks.filter((row) => choices.checks[row.key].on).map((row) => row.check));
  const ci = choices.parts.includes('ci');
  const checkOk = (check) => check === '' || (ci && (check === 'any' ? onChecks.size > 0 : onChecks.has(check)));
  return lists.files
    .filter(
      (row) =>
        (row.release === 'any' || row.release === choices.release) &&
        (choices.parts.includes(row.part)
          ? checkOk(row.check)
          : choices.existing === true && row.existing !== '' && ci && onChecks.has(row.existing)) &&
        (row.needs === '' || (values[row.needs] ?? '') !== ''),
    )
    .map((row) => row.path);
}

export function buildPackage(rawChoices, bundle) {
  const lists = readLists(bundle);
  const choices = settleChoices(rawChoices);
  const values = placeholderValues(choices, lists);
  const files = {};
  for (const path of selectedFiles(choices, lists, values)) {
    files[renderText(path, values)] = renderText(bundle.template[path], values);
  }
  return files;
}
