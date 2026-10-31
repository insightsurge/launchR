// The form: plain JavaScript with no framework, so Astro can be swapped without touching it.
import JSZip from 'jszip';
import { buildPackage, checkPackageName, defaultChoices, readLists } from './engine.js';

const steps = ['Name', 'Where it lives', 'What you get', 'Download', 'Next steps'];
const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const eventLabels = { pr: 'Pull requests', push: 'Pushes', weekly: 'On a schedule', manual: 'By hand' };

const esc = (text) =>
  String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

let bundle;
let lists;
let state;
let root;

function fresh() {
  return { step: 0, modify: false, repo: 'new', author: '', errors: {}, choices: defaultChoices(lists) };
}

function field(id, label, value, hint, type = 'text') {
  const error = state.errors[id];
  const describedBy = [hint ? `${id}-hint` : '', error ? `${id}-error` : ''].filter(Boolean).join(' ');
  return `<div class="field">
    <label for="${id}">${label}</label>
    ${hint ? `<p class="hint" id="${id}-hint">${hint}</p>` : ''}
    <input id="${id}" type="${type}" value="${esc(value)}" ${error ? 'aria-invalid="true"' : ''}
      ${describedBy ? `aria-describedby="${describedBy}"` : ''} />
    ${error ? `<p class="error" id="${id}-error">${esc(error)}</p>` : ''}
  </div>`;
}

function radios(name, legend, options, current) {
  return `<fieldset><legend>${legend}</legend>
    ${options
      .map(
        ([value, label]) =>
          `<label class="choice"><input type="radio" name="${name}" value="${value}" ${value === current ? 'checked' : ''} /> ${label}</label>`,
      )
      .join('')}
    ${state.errors[name] ? `<p class="error">${esc(state.errors[name])}</p>` : ''}
  </fieldset>`;
}

function stepName() {
  const c = state.choices;
  return `<h2 tabindex="-1">Name your package</h2>
    ${field('package', 'Package name', c.package, 'Letters, numbers and dots. It starts with a letter.')}
    ${field('title', 'One-line title', c.title, 'In title case, such as "Tools for Clinical Tables".')}
    ${field('author', 'Your name', state.author, 'For the licence and DESCRIPTION.')}
    ${field('email', 'Your email', c.email, 'Shown in DESCRIPTION. It stays in your browser until you download.', 'email')}`;
}

function stepWhere() {
  const c = state.choices;
  return `<h2 tabindex="-1">Where will it live?</h2>
    ${radios('repo', 'GitHub', [['new', "Not yet, I'll make a repository"], ['existing', 'I already have an empty repository'], ['none', "I don't use GitHub"]], state.repo)}
    ${state.repo === 'none' ? '<p class="hint">The zip is still a complete package. CI and checklists need GitHub, so they\'re left out. You can add them later.</p>' : `
      ${field('owner', 'GitHub user or organisation', c.owner, 'A name such as insightsurge, or paste a GitHub link. This fills in the package\'s links.')}
      ${radios('visibility', 'Public or private repository', [['private', 'Private'], ['public', 'Public']], c.visibility)}`}
    ${radios('release', 'Where is it going?', [['cran', 'CRAN'], ['internal', 'Staying internal, such as at a company']], c.release)}`;
}

function partsList() {
  const c = state.choices;
  return lists.parts
    .map((part) => {
      const noOwner = part.part === 'website' && c.owner === '';
      const on = c.parts.includes(part.part) && !noOwner;
      if (noOwner) return `<li>– <strong>${esc(part.label)}</strong>: needs a GitHub user or organisation for its address.</li>`;
      if (!state.modify) return `<li>${on ? '✓' : '–'} <strong>${esc(part.label)}</strong>: ${esc(part.description)}${on ? '' : ' (off)'}</li>`;
      const locked = part.part === 'skeleton' ? 'disabled' : '';
      return `<li><label><input type="checkbox" data-part="${part.part}" ${on ? 'checked' : ''} ${locked} />
        <strong>${esc(part.label)}</strong>: ${esc(part.description)}</label></li>`;
    })
    .join('');
}

function cronParts(cron) {
  const [minute, hour, dom, , dow] = cron.split(' ');
  if (dom !== '*') return { every: 'month', hour, minute, day: '1' };
  if (dow !== '*') return { every: 'week', hour, minute, day: dow };
  return { every: 'day', hour, minute, day: '1' };
}

function scheduleControls(row, check) {
  const cron = cronParts(check.cron);
  const hours = Array.from({ length: 24 }, (_, h) => `<option value="${h}" ${String(h) === cron.hour ? 'selected' : ''}>${String(h).padStart(2, '0')}:00</option>`);
  return `<div class="field">
    <label for="every-${row.key}">Schedule</label>
    <select id="every-${row.key}" data-cron="${row.key}" data-part-of="every">
      ${['day', 'week', 'month'].map((v) => `<option value="${v}" ${v === cron.every ? 'selected' : ''}>Every ${v}</option>`).join('')}
    </select>
    ${cron.every === 'week' ? `<select aria-label="Day" data-cron="${row.key}" data-part-of="day">${days.map((d, i) => `<option value="${i}" ${String(i) === cron.day ? 'selected' : ''}>${d}</option>`).join('')}</select>` : ''}
    <select aria-label="Time, UTC" data-cron="${row.key}" data-part-of="hour">${hours.join('')}</select>
    <p class="hint">Times are UTC. This writes <code>cron: "${esc(check.cron)}"</code>.</p>
  </div>`;
}

function checkEditor(row) {
  const c = state.choices;
  const check = c.checks[row.key];
  const hasPlatforms = row.platforms_public !== '';
  const platforms = check.platforms ?? row[`platforms_${c.visibility}`];
  return `<details class="check panel">
    <summary><label><input type="checkbox" data-check="${row.key}" ${check.on ? 'checked' : ''} /> ${esc(row.label)}</label></summary>
    <fieldset><legend>When it runs</legend><div class="events">
      ${Object.entries(eventLabels)
        .map(
          ([event, label]) =>
            `<label class="choice"><input type="checkbox" data-event="${event}" data-for="${row.key}" ${check.events.includes(event) ? 'checked' : ''} /> ${label}</label>`,
        )
        .join('')}
    </div></fieldset>
    ${check.events.includes('weekly') ? scheduleControls(row, check) : ''}
    ${
      hasPlatforms
        ? `<div class="field"><label for="platforms-${row.key}">Systems and R versions</label>
          <p class="hint">As system/R version, such as <code>windows/4.1</code>. macOS uses about ten times the minutes on private repositories.</p>
          <input type="text" id="platforms-${row.key}" data-platforms="${row.key}" value="${esc(platforms)}" /></div>`
        : '<p class="hint">Runs on Linux only.</p>'
    }
  </details>`;
}

function stepWhat() {
  const c = state.choices;
  const ci = c.parts.includes('ci');
  return `<h2 tabindex="-1">What you get</h2>
    <p>This is the recommended setup. You can download it as it is.</p>
    <ul class="${state.modify ? 'plain' : ''}">${partsList()}</ul>
    ${
      state.modify && ci
        ? `<h3>CI checks</h3>
          ${field('branches', 'Branches', c.branches, 'Comma separated, such as main, develop.')}
          ${lists.checks.map(checkEditor).join('')}`
        : ''
    }
    <p><button type="button" class="quiet" id="toggle-modify">${state.modify ? 'Back to the summary' : 'Change the setup'}</button></p>`;
}

// Draws file paths as a folder tree, folders first.
function fileTree(paths, name) {
  const root = {};
  for (const path of paths) {
    let node = root;
    for (const piece of path.split('/')) {
      node[piece] ??= {};
      node = node[piece];
    }
  }
  const lines = [`${name}/`];
  const walk = (node, prefix) => {
    const entries = Object.keys(node).sort((a, b) => {
      const folders = Number(Object.keys(node[b]).length > 0) - Number(Object.keys(node[a]).length > 0);
      return folders || a.localeCompare(b);
    });
    entries.forEach((entry, i) => {
      const last = i === entries.length - 1;
      const folder = Object.keys(node[entry]).length > 0;
      lines.push(`${prefix}${last ? '└── ' : '├── '}${entry}${folder ? '/' : ''}`);
      walk(node[entry], `${prefix}${last ? '    ' : '│   '}`);
    });
  };
  walk(root, '');
  return lines.join('\n');
}

function stepDownload() {
  const files = buildPackage(state.choices, bundle);
  const paths = Object.keys(files).sort();
  return `<h2 tabindex="-1">Download</h2>
    <p>${paths.length} files, built in your browser.</p>
    <p><button type="button" id="download">Download ${esc(state.choices.package)}.zip</button></p>
    <details><summary>See every file</summary><pre>${esc(fileTree(paths, state.choices.package))}</pre></details>
    <p class="warn">Some files start with a dot, such as <code>.github</code>, and your computer hides them. They're in the zip, and they're what makes CI work.</p>`;
}

function stepNext() {
  const c = state.choices;
  if (state.repo === 'none') {
    return `<h2 tabindex="-1">Next steps</h2>
      <ol><li>Unzip the folder.</li><li>Open <code>${esc(c.package)}.Rproj</code> in RStudio, or open the folder in Positron.</li><li>Run <code>devtools::check()</code>.</li></ol>`;
  }
  const query = new URLSearchParams({ name: c.package, description: c.title, visibility: c.visibility, owner: c.owner || '@me' });
  const repo = c.owner ? `https://github.com/${c.owner}/${c.package}` : '';
  const newRepo = `https://github.com/new?${query}`;
  const repoStep =
    state.repo === 'existing' && repo
      ? `<li>Open <a href="${esc(repo)}">your repository</a>.</li>`
      : `<li><a href="${esc(newRepo)}">Create the repository on GitHub</a>. The form is filled in for you. Leave README, .gitignore and licence off.</li>`;
  return `<h2 tabindex="-1">Next steps</h2>
    <div class="routes">
      <section class="panel">
        <h3>With R</h3>
        <p class="hint">This route needs a GitHub token R can find, and <code>gh</code> set up. <a href="https://usethis.r-lib.org/articles/git-credentials.html">How to set them up</a>.</p>
        <ol>
          <li>Unzip, then open <code>${esc(c.package)}.Rproj</code> in RStudio, or the folder in Positron.</li>
          <li>Run these in the R console:
            <pre>usethis::use_git()
usethis::use_github(private = ${c.visibility === 'private' ? 'TRUE' : 'FALSE'})</pre></li>
          <li>Set up labels and checklists:
            <pre>source("https://raw.githubusercontent.com/insightsurge/launchR/v${lists.settings.kit_version}/cli/setup-github.R")</pre></li>
        </ol>
      </section>
      <p class="or">OR</p>
      <section class="panel">
        <h3>Without typing</h3>
        <ol>
          ${repoStep}
          <li>In RStudio, choose File, New Project, Version Control, Git, and paste the repository's address.</li>
          <li>Unzip into that project folder, including the hidden files. On a Mac, press Cmd+Shift+. in Finder to show them.</li>
          <li>Open the Git pane, tick everything, commit and push.</li>
          <li>On GitHub, open Actions, choose "Set up this repository", then Run workflow. Untick "Only show what would change" when you're ready.</li>
        </ol>
      </section>
    </div>
    <details><summary>I've never used GitHub</summary>
      <p>Create a free account at <a href="https://github.com/signup">github.com</a>, install <a href="https://desktop.github.com">git</a>, then follow "Without typing" above. Your package already works without GitHub, so nothing is lost if you stop here.</p>
    </details>
    <h3>After that</h3>
    <p>Open your repository's Issues tab. The checklists are your plan, and repository settings are listed there with what to pick.</p>`;
}

function render() {
  const body = [stepName, stepWhere, stepWhat, stepDownload, stepNext][state.step]();
  const rail = steps.map((name, i) => `<li ${i === state.step ? 'aria-current="step"' : ''}>${i + 1}. ${name}</li>`).join('');
  const last = state.step === steps.length - 1;
  root.innerHTML = `<nav aria-label="Steps"><ol class="rail">${rail}</ol></nav>
    <form novalidate><section>${body}</section>
    <div class="actions">
      ${state.step > 0 ? '<button type="button" class="quiet" id="back">Back</button>' : ''}
      ${last ? '' : '<button type="submit" id="next">Continue</button>'}
    </div></form>`;
  root.querySelector('h2').focus();
}

// Accepts a pasted GitHub link or @name, and returns just the user or organisation.
function readOwner(text) {
  const link = text.match(/^(?:https?:\/\/)?(?:www\.)?github\.com\/([^/\s]+)/i);
  return (link ? link[1] : text).replace(/^@/, '').replace(/\/+$/, '');
}

const validOwner = (owner) => /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(owner) && owner.length <= 39;

function saveInputs() {
  const c = state.choices;
  const value = (id) => root.querySelector(`#${id}`)?.value.trim();
  for (const key of ['package', 'title', 'email', 'owner', 'branches']) {
    const v = value(key);
    if (v !== undefined) c[key] = key === 'owner' ? readOwner(v) : v;
  }
  const author = value('author');
  if (author !== undefined) {
    state.author = author;
    const words = author.split(/\s+/);
    c.given = words[0] ?? '';
    c.family = words.slice(1).join(' ');
  }
}

function validate() {
  const c = state.choices;
  const errors = {};
  if (state.step === 0) {
    const name = checkPackageName(c.package);
    if (name) errors.package = name;
    if (!c.title) errors.title = 'Add a one-line title.';
    if (!c.family) errors.author = 'Add your first and last name.';
    if (!/.+@.+/.test(c.email)) errors.email = 'Add an email address.';
  }
  if (state.step === 1 && c.owner && !validOwner(c.owner)) {
    errors.owner = 'Use just the name, such as insightsurge. It can have letters, numbers and single hyphens.';
  }
  if (state.step === 1 && state.repo === 'existing' && !c.owner) errors.owner = 'Add the user or organisation that owns the repository.';
  state.errors = errors;
  return Object.keys(errors).length === 0;
}

function setRepo(value) {
  const c = state.choices;
  state.repo = value;
  const github = ['ci', 'github', 'website'];
  if (value === 'none') {
    c.owner = '';
    c.parts = c.parts.filter((part) => !github.includes(part));
  } else {
    c.parts = [...new Set([...c.parts, ...defaultChoices(lists).parts])];
  }
}

function setCron(key) {
  const check = state.choices.checks[key];
  const get = (part) => root.querySelector(`[data-cron="${key}"][data-part-of="${part}"]`)?.value;
  const every = get('every');
  const hour = get('hour');
  const cron = { day: `0 ${hour} * * *`, week: `0 ${hour} * * ${get('day') ?? '1'}`, month: `0 ${hour} 1 * *` };
  check.cron = cron[every];
}

async function download() {
  const zip = new JSZip();
  const name = state.choices.package;
  for (const [path, text] of Object.entries(buildPackage(state.choices, bundle))) {
    zip.file(`${name}/${path}`, text);
  }
  const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = `${name}.zip`;
  link.click();
  URL.revokeObjectURL(link.href);
  state.step = steps.length - 1;
  render();
}

function onChange(event) {
  const t = event.target;
  const c = state.choices;
  if (t.name === 'repo') setRepo(t.value);
  else if (t.name === 'visibility' || t.name === 'release') c[t.name] = t.value;
  else if (t.dataset.part) c.parts = t.checked ? [...c.parts, t.dataset.part] : c.parts.filter((p) => p !== t.dataset.part);
  else if (t.dataset.check) c.checks[t.dataset.check].on = t.checked;
  else if (t.dataset.event) {
    const check = c.checks[t.dataset.for];
    check.events = t.checked ? [...check.events, t.dataset.event] : check.events.filter((e) => e !== t.dataset.event);
  } else if (t.dataset.platforms) c.checks[t.dataset.platforms].platforms = t.value.trim();
  else if (t.dataset.cron) setCron(t.dataset.cron);
  else return;
  saveInputs();
  const open = [...root.querySelectorAll('details[open] [data-check]')].map((el) => el.dataset.check);
  render();
  for (const key of open) root.querySelector(`[data-check="${key}"]`)?.closest('details')?.setAttribute('open', '');
}

// Shows the name taken from a pasted link while the person types.
function onInput(event) {
  if (event.target.id !== 'owner') return;
  const typed = event.target.value.trim();
  const owner = readOwner(typed);
  let note = root.querySelector('#owner-note');
  if (!note) {
    note = document.createElement('p');
    note.id = 'owner-note';
    note.className = 'hint';
    note.setAttribute('role', 'status');
    event.target.after(note);
  }
  note.textContent = owner !== typed && validOwner(owner) ? `We'll use ${owner}.` : '';
}

function onClick(event) {
  const id = event.target.id;
  if (id === 'back') {
    saveInputs();
    state.errors = {};
    state.step -= 1;
    render();
  } else if (id === 'toggle-modify') {
    saveInputs();
    state.modify = !state.modify;
    render();
  } else if (id === 'download') {
    download();
  }
}

function onSubmit(event) {
  event.preventDefault();
  saveInputs();
  if (!validate()) {
    render();
    root.querySelector('[aria-invalid="true"]')?.focus();
    return;
  }
  state.step += 1;
  render();
}

export async function start(element) {
  root = element;
  try {
    bundle = await (await fetch('/kit/bundle.json')).json();
  } catch {
    root.innerHTML = '<p class="warn">The form could not load. Please refresh the page.</p>';
    return;
  }
  lists = readLists(bundle);
  state = fresh();
  root.addEventListener('change', onChange);
  root.addEventListener('click', onClick);
  root.addEventListener('input', onInput);
  root.addEventListener('submit', onSubmit);
  render();
}
