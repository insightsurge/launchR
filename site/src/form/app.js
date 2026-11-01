// The form: four questions, Modify, someone with a package already, and what to do after the download.
// Choices live here; engine.js turns them into files, the same way the CLI does.
import JSZip from 'jszip';
import { countZip } from '../consent.js';
import { buildPackage, checkPackageName, defaultChoices, readLists } from './engine.js';

const $ = (q) => document.querySelector(q);
const $$ = (q) => [...document.querySelectorAll(q)];
const esc = (text) => String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const dialog = $('#setup');
const CHECKS = [
  ['r_cmd_check', 'r-cmd-check', 'R CMD check, the core check. It runs on every pull request and push, and weekly.'],
  ['lint', 'lint', 'Checks style, that the docs are in sync, and spelling.'],
  ['secret_scan', 'secret-scan', 'Catches passwords and tokens committed by mistake.'],
  ['coverage', 'coverage', 'Measures how much of your code the tests run.'],
  ['no_suggests', 'no-suggests', 'Checks the package works without its optional packages.'],
  ['full_tests', 'full-tests', 'Runs the tests CRAN skips: test files ending in -browser, -snap or -extended. Runs on Linux.'],
  ['extended_tests', 'extended-tests', 'Every week, a full check on Mac and Windows, including test files ending in -extended.'],
];
const SYSTEMS = [['ubuntu', 'Linux'], ['windows', 'Windows'], ['macos', 'Mac']];
const RS = [['release', 'release'], ['oldrel-1', 'oldrel-1'], ['devel', 'devel']];
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const WORDS = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'All seven'];
const WEEKLY = ['r_cmd_check', 'full_tests', 'extended_tests'];
const BASE_PACKAGES = ['R', 'base', 'compiler', 'datasets', 'graphics', 'grDevices', 'grid', 'methods', 'parallel', 'splines', 'stats', 'stats4', 'tcltk', 'tools', 'utils'];
const PARTS = [['ci', 'CI checks'], ['website', 'Website'], ['github', 'Issue forms, labels and checklists']];

let bundle = null;
let lists = null;
let mode = 'new';
let changed = false;
let S = null;
const add = { ci: true, website: false, github: false };

const plan = () => $('input[name=plan]:checked').value;
const isPublic = () => 'ab'.includes(plan());
const release = () => ('ac'.includes(plan()) ? 'cran' : 'internal');
const visibility = () => (isPublic() ? 'public' : 'private');
const pkg = () => (mode === 'new' ? $('#pkg').value.trim() : $('#exPkg').value.trim()) || 'fooBarPkg';

function kitPlatforms() {
  const row = lists.checks.find((check) => check.key === 'r_cmd_check');
  return row[`platforms_${visibility()}`].split(',').map((entry) => entry.trim());
}

/* what each plan starts from: the kit's own list, so an untouched form matches the CLI */
function recommended() {
  const start = kitPlatforms();
  return {
    checks: Object.fromEntries(CHECKS.map(([k]) => [k, !(k === 'extended_tests' && plan() === 'd')])),
    matrix: Object.fromEntries(SYSTEMS.flatMap(([s]) => RS.map(([r]) => [`${s}/${r}`, start.includes(`${s}/${r}`)]))),
    minR: '', samePlatforms: false, day: 'Monday', time: '05:00', website: false, github: true, owner: '', frontend: false,
  };
}

const help = (text) => `<span class="tip" tabindex="0" role="note" aria-label="${esc(text)}"><svg aria-hidden="true"><use href="#i-info" /></svg><span role="tooltip" aria-hidden="true">${esc(text)}</span></span>`;
const bullets = (list) => `<span class="tip wide-tip" tabindex="0" role="note" aria-label="${esc(list.map(([k, w]) => `${k}: ${w}`).join(' '))}"><svg aria-hidden="true"><use href="#i-info" /></svg><span role="tooltip" aria-hidden="true"><ul>${list.map(([k, w]) => `<li><b>${esc(k)}</b> ${esc(w)}</li>`).join('')}</ul></span></span>`;
const sw = (id, text, why, on, soon) => `<div class="opt"><label class="sw"><input type="checkbox" id="${id}"${on ? ' checked' : ''}${soon ? ' disabled' : ''} /><i aria-hidden="true"></i><b>${text}</b></label>${soon ? '<span class="tag">Coming soon</span>' : ''}${help(why)}</div>`;
const pill = (attrs, text, on) => `<label class="pill"><input type="checkbox" ${attrs}${on ? ' checked' : ''} /><span><svg aria-hidden="true"><use href="#i-tick" /></svg>${text}</span></label>`;
const head3 = (text, why) => `<h4>${text}${Array.isArray(why) ? bullets(why) : why ? help(why) : ''}</h4>`;

function paint() {
  if (!S) return;
  const weekly = WEEKLY.some((k) => S.checks[k]);
  const extra = S.checks.full_tests || S.checks.extended_tests;
  $('#bodyCi').innerHTML = `
    ${head3('Checks to run', CHECKS.map(([, n, w]) => [n, w]))}
    <div class="ticks">${CHECKS.map(([k, name]) => pill(`data-check="${k}"`, `<code>${name}</code>`, S.checks[k])).join('')}</div>
    ${head3('R versions to check, by system', [['release', 'The current R.'], ['oldrel-1', 'The R release before it. Linux only.'], ['devel', 'The next R, still in development. Linux only.'], ['Minimum R version', 'The oldest R your package supports, from 4.1 up. It is checked on Linux. Leave it empty if you do not know yet.'], ['Systems', 'launchR picks the system version: Ubuntu 26.04, and the latest Windows and macOS on GitHub.'], ['Cost', 'On a private repository, Mac minutes count ten times and Windows twice.']])}
    <div class="line"><label for="minR">Minimum R version</label><input id="minR" class="short" type="text" inputmode="decimal" autocomplete="off" placeholder="4.1" value="${esc(S.minR)}" /></div>
    <p class="fieldnote" id="minRNote" role="status"></p>
    <table class="rmatrix"><thead><tr><td></td>${RS.map(([, x]) => `<th scope="col"><code>${x}</code></th>`).join('')}</tr></thead><tbody>${SYSTEMS.map(([k, t]) => `<tr><th scope="row">${t}</th>${RS.map(([v, x]) => (k === 'ubuntu' || v === 'release' ? `<td><label class="cell"><input type="checkbox" data-matrix="${k}/${v}" aria-label="${t}, ${x}"${S.matrix[`${k}/${v}`] ? ' checked' : ''} /><span><svg aria-hidden="true"><use href="#i-tick" /></svg></span></label></td>` : '<td class="none"></td>')).join('')}</tr>`).join('')}</tbody></table>
    ${extra ? sw('samePlatforms', 'Use the same systems for browser and extended tests', 'Runs test files ending in -browser or -extended on the systems above. Off keeps the recommended ones.', S.samePlatforms) : ''}
    ${weekly ? `<div class="line"><label for="day">Weekly checks run on</label>${help('Time is in 24-hour UTC, which is what GitHub uses. It may run some minutes late when GitHub is busy.')}<span class="when"><select id="day">${[...DAYS.slice(1), DAYS[0]].map((d) => `<option${d === S.day ? ' selected' : ''}>${d}</option>`).join('')}</select><label class="sr" for="time">Time in 24-hour UTC</label><input id="time" class="short" type="text" inputmode="numeric" autocomplete="off" maxlength="5" value="${esc(S.time)}" /><span class="unit">UTC</span></span></div><p class="fieldnote" id="timeNote" role="status"></p>` : ''}
    ${head3('How the checks reach your package')}
    <div class="pick">
      <div class="opt"><label><input type="radio" name="delivery" checked /><b>Shared</b></label>${help('Your files call the checks kept in launchR, so you get fixes and updates by themselves.')}</div>
      <div class="opt"><label class="soon"><input type="radio" name="delivery" disabled /><b>Snapshot</b></label><span class="tag">Coming soon</span>${help("The checks are copied into your repository and frozen, so nothing changes under a validated process. When a new launchR version is released, you won't get any updates, security fixes included.")}</div>
    </div>`;
  $('#bodySite').innerHTML = `${sw('website', 'Add a website', 'A pkgdown site published to GitHub Pages. It needs your GitHub name below. A private repository needs a paid GitHub plan for this.', S.website)}
    <div class="opt soonline"><span>Navbar choices and theme colours</span><span class="tag">Coming soon</span></div>`;
  $('#bodyGit').innerHTML = `
    <div class="field"><div class="field-head"><label for="owner">GitHub username or organisation <span class="opt-word">(optional)</span></label>${help('Fills in the links in your README and DESCRIPTION. Left empty, they show your-github-name until you edit them.')}</div><input id="owner" type="text" autocomplete="off" spellcheck="false" value="${esc(S.owner)}" /><p class="err" id="err-owner"></p></div>
    ${sw('github', 'Issue forms, labels and checklists', 'Five issue forms, a pull request template, eleven labels, and the stage checklists.', S.github)}
    <div class="opt soonline"><span>Choosing each form and label</span><span class="tag">Coming soon</span></div>`;
  $('#bodyMore').innerHTML = `${sw('frontend', 'My package ships its own JS or CSS', 'Adds browser tests and the style checks for them.', S.frontend)}
    <div class="opt soonline"><span>Badges, licence choice, PR report choice, AI instruction files</span><span class="tag">Coming soon</span></div>`;
  summary();
}

function summary() {
  if (!S) return;
  const on = CHECKS.filter(([k]) => S.checks[k]).length;
  const sysText = SYSTEMS.filter(([k]) => RS.some(([r]) => S.matrix[`${k}/${r}`])).map(([, t]) => t).join(', ') || 'None';
  $('#sumCi').textContent = `${WORDS[on]} ${on === 1 ? 'check' : 'checks'} on ${sysText}`;
  $('#sumSite').textContent = S.website ? 'On' : 'Off';
  $('#sumGit').textContent = S.github ? 'Forms, labels and checklists' : 'Off';
  $('#sumMore').textContent = S.frontend ? 'JS or CSS' : 'Nothing added';
  $('#pvChecks').textContent = on === 7 ? 'All seven' : WORDS[on];
  $('#pvSystems').textContent = sysText;
  $('#pvSite').textContent = S.website ? 'On' : 'Off';
  $('#modReset').hidden = !changed;
  const count = $$('#pvLists li:not(.none)').length;
  $('#planLine').textContent = `${on === 7 ? 'All seven' : WORDS[on]} ${on === 1 ? 'check' : 'checks'}, ${count ? `${count} ${count === 1 ? 'checklist' : 'checklists'}` : 'no checklists'}. ${$('#pvRelease').textContent.replace(/^None\. /, '')}`;
}

function touched(fn) { fn(); changed = true; summary(); }

const body = $('#modifyView');
body.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset.check) { touched(() => { S.checks[t.dataset.check] = t.checked; }); paint(); return; }
  if (t.dataset.matrix) { touched(() => { S.matrix[t.dataset.matrix] = t.checked; }); return; }
  if (t.id === 'day') { touched(() => { S.day = t.value; }); return; }
  if (t.type === 'checkbox' && t.id in S) { touched(() => { S[t.id] = t.checked; }); if (mode === 'existing') add.website = S.website; return; }
  if (t.id === 'minR') { touched(() => { S.minR = t.value; }); minRProblem(); }
  if (t.id === 'time') { touched(() => { S.time = t.value; }); timeProblem(); }
});
body.addEventListener('input', (e) => {
  if (e.target.id === 'minR') e.target.value = e.target.value.replace(/[^0-9.]/g, '').replace(/^(\d+\.\d*).*/, '$1').slice(0, 4);
  if (e.target.id === 'owner') { S.owner = e.target.value.trim(); $('#err-owner').textContent = ''; }
});

function minRProblem() {
  const [major, minor] = S.minR.split('.').map(Number);
  const ok = !S.minR || (/^\d+\.\d+$/.test(S.minR) && (major > 4 || (major === 4 && minor >= 1)));
  $('#minR')?.classList.toggle('bad', !ok);
  const note = $('#minRNote');
  if (note) note.textContent = ok ? '' : 'Use a version from R 4.1 up, such as 4.3.';
  return !ok;
}

function timeProblem() {
  const ok = /^([01]\d|2[0-3]):[0-5]\d$/.test(S.time);
  $('#time')?.classList.toggle('bad', !ok);
  const note = $('#timeNote');
  if (note) note.textContent = ok ? '' : 'Use 24-hour time, such as 05:00.';
  return !ok;
}

function view(name, focus) {
  dialog.dataset.view = name;
  dialog.dataset.mode = mode;
  $('#form').hidden = name !== 'main';
  $('#modifyView').hidden = name !== 'modify';
  $('#nextView').hidden = name !== 'next';
  $('#existingView').hidden = name !== 'existing';
  dialog.scrollTop = 0;
  focus?.focus({ preventScroll: true });
}

$('#modify').addEventListener('click', () => { $('#modPkg').textContent = pkg(); $('#modDownload').textContent = `Download ${pkg()}.zip`; paint(); view('modify', $('#modTitle')); });
$('#modBack').addEventListener('click', () => (mode === 'existing' ? view('existing', $('#exModify')) : view('main', $('#modify'))));
$('#modReset').addEventListener('click', () => { S = recommended(); changed = false; paint(); });
$('#plans').addEventListener('change', () => {
  $('#planNote').textContent = changed ? 'A new plan starts from its own defaults, so your Modify changes were reset.' : '';
  S = recommended();
  changed = false;
  paint();
});

/* what the kit needs, with a message beside whatever needs fixing */
const put = (id, text) => {
  const el = $(`#${id}`);
  $(`#err-${id}`).textContent = text;
  el.toggleAttribute('aria-invalid', !!text);
  if (text) el.setAttribute('aria-errormessage', `err-${id}`); else el.removeAttribute('aria-errormessage');
};
const v = (id) => $(`#${id}`).value.trim();

function nameProblem(name, empty) {
  if (!name) return empty;
  if (name.length > 60) return 'Keep the name under 60 characters.';
  if (BASE_PACKAGES.includes(name)) return `${name} is part of R itself, so choose another name.`;
  return checkPackageName(name);
}

function titleProblem(title) {
  if (!title) return 'Say in one line what it does. This goes in DESCRIPTION.';
  if (title.length > 65) return `Keep it to 65 characters. It is ${title.length} now.`;
  if (/["\\{}%]/.test(title)) return 'Use plain words here: no double quotes, backslashes, braces or percent signs.';
  return '';
}

function personProblem(name, which) {
  if (!name) return `Add a ${which} name. DESCRIPTION needs an author.`;
  return /["\\]/.test(name) ? 'Names can\'t contain double quotes or backslashes.' : '';
}

function ownerProblem(owner) {
  return !owner || /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/.test(owner) ? '' : 'Use only your GitHub name, such as insightsurge, not a link.';
}

function valid() {
  const rules = [
    ['pkg', nameProblem(v('pkg'), 'Give your package a name, such as fooBarPkg.')],
    ['what', titleProblem(v('what'))],
    ['first', personProblem(v('first'), 'first')],
    ['last', personProblem(v('last'), 'last')],
    ['email', !v('email') || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v('email')) ? '' : 'That email looks incomplete, or leave it empty.'],
  ];
  rules.forEach(([id, text]) => put(id, text));
  const bad = rules.find(([, text]) => text);
  if (bad) { view('main'); $(`#${bad[0]}`).focus(); return false; }
  return modifyValid();
}

function modifyValid() {
  const open = (index) => { $$('.mod')[index].open = true; view('modify'); };
  if (minRProblem()) { open(0); $('#minR').focus(); return false; }
  if (WEEKLY.some((k) => S.checks[k]) && timeProblem()) { open(0); $('#time').focus(); return false; }
  if (S.checks.r_cmd_check && !platforms()) { open(0); $('#minRNote').textContent = 'Choose at least one R version for R CMD check.'; $('[data-matrix]').focus(); return false; }
  const owner = mode !== 'new' ? '' : ownerProblem(S.owner) || (S.website && !S.owner ? 'A website needs your GitHub name, so it has an address.' : '');
  if (owner) { open(2); $('#err-owner').textContent = owner; $('#owner').focus(); return false; }
  return true;
}

['pkg', 'what', 'first', 'last', 'email'].forEach((id) => $(`#${id}`).addEventListener('input', () => put(id, '')));
['exPkg', 'exOwner'].forEach((id) => $(`#${id}`).addEventListener('input', () => put(id, '')));

function cron() {
  const [hour, minute] = (timeProblem() ? '05:00' : S.time).split(':').map(Number);
  return `${minute} ${hour} * * ${DAYS.indexOf(S.day)}`;
}

function platforms() {
  const list = Object.entries(S.matrix).filter(([, on]) => on).map(([entry]) => entry);
  if (S.minR) list.push(`ubuntu/${S.minR}`);
  return list.join(', ');
}

function choices() {
  const base = defaultChoices(lists);
  const start = kitPlatforms().join(', ');
  const parts = mode === 'new'
    ? ['skeleton', 'ci', ...(S.github ? ['github'] : []), ...(S.website ? ['website'] : []), ...(S.frontend ? ['frontend'] : [])]
    : PARTS.map(([k]) => k).filter((k) => add[k]);
  const chosen = platforms() === start ? null : platforms();
  const checks = Object.fromEntries(Object.entries(base.checks).map(([key, row]) => [key, {
    ...row,
    on: S.checks[key],
    cron: cron(),
    platforms: key === 'r_cmd_check' || (S.samePlatforms && (key === 'full_tests' || key === 'extended_tests')) ? chosen : null,
  }]));
  const email = mode === 'new' ? v('email') : '';
  return {
    ...base, parts, checks, visibility: visibility(), release: release(), owner: mode === 'new' ? S.owner : v('exOwner'),
    package: pkg(), title: mode === 'new' ? v('what').replace(/[.\s]+$/, '') : '', given: v('first'), family: v('last'),
    email: email || 'your.email@example.com',
  };
}

async function saveZip() {
  const zip = new JSZip();
  const name = pkg();
  const folder = mode === 'new' ? `${name}/` : '';
  for (const [path, text] of Object.entries(buildPackage(choices(), bundle))) zip.file(`${folder}${path}`, text);
  const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = mode === 'new' ? `${name}.zip` : 'launchR-files.zip';
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
}

const buttons = ['#download', '#modDownload', '#exDownload'].map($);
let saving = false;

async function download() {
  if (saving) return;
  const fail = (text) => {
    if (mode === 'existing') { $('#exNote').textContent = text; view('existing'); } else { $('#planNote').textContent = text; view('main'); }
  };
  if (!bundle && !(await loadKit())) { fail('The form could not load its files. Check your connection and press Download again.'); return; }
  if (mode === 'new' ? !valid() : !existingValid()) return;
  saving = true;
  buttons.forEach((b) => { b.disabled = true; });
  try {
    await saveZip();
    countZip();
  } catch {
    fail('The zip could not be built. Press Download to try again.');
    return;
  } finally {
    saving = false;
    buttons.forEach((b) => { b.disabled = false; });
    if (mode === 'existing') paintExisting();
  }
  $('#planNote').textContent = '';
  $('#nextName').textContent = mode === 'new' ? pkg() : 'launchR-files';
  $('#routes').hidden = mode === 'existing';
  steps();
  view('next', $('#nextTitle'));
  /* a fresh address, so the launch plays from the start after every download */
  $('#launchHex').src = `/logo-launch.svg?${Date.now()}`;
  $('#launchHex').hidden = false;
}
$('#download').addEventListener('click', download);
$('#modDownload').addEventListener('click', download);
$('#exDownload').addEventListener('click', download);
$('#nextChange').addEventListener('click', () => (mode === 'existing' ? view('existing', $('#exDownload')) : view('main', $('#modify'))));
$('#nextDone').addEventListener('click', () => $('#close').click());

/* someone with a package already: only the files they choose */
function paintExisting() {
  $('#exRows').innerHTML = PARTS.map(([k, t]) => `<div class="exrow">${pill(`data-part="${k}"`, t, add[k])}</div>`).join('');
  $('#exModify').hidden = !add.ci;
  $('#exDownload').disabled = !PARTS.some(([k]) => add[k]);
  $('#exNote').textContent = '';
}
$('#exRows').addEventListener('change', (e) => { add[e.target.dataset.part] = e.target.checked; S.website = add.website; paintExisting(); });
$('#exPlans').addEventListener('change', (e) => { $(`input[name=plan][value=${e.target.value}]`).checked = true; S = recommended(); S.website = add.website; paint(); });
$('#exModify').addEventListener('click', () => { $('#modPkg').textContent = 'your package'; $('#modDownload').textContent = 'Download the files'; paint(); view('modify', $('#modTitle')); });

function existingValid() {
  const name = nameProblem(v('exPkg'), 'Add the name in your DESCRIPTION file.');
  const owner = ownerProblem(v('exOwner')) || (add.website && !v('exOwner') ? 'A website needs your GitHub name, so it has an address.' : '');
  put('exPkg', name);
  put('exOwner', owner);
  if (name || owner) { view('existing'); $(name ? '#exPkg' : '#exOwner').focus(); return false; }
  return modifyValid();
}

function goExisting() {
  mode = 'existing';
  S = recommended();
  S.website = add.website;
  paintExisting();
  paint();
  view('existing', $('#exTitle'));
}
$('#toExisting').addEventListener('click', goExisting);
$('#existingStart').addEventListener('click', goExisting);
$('#exBack').addEventListener('click', () => { mode = 'new'; S = recommended(); paint(); view('main', $('#pkg')); });

/* the page after the download */
const copy = (text) => `<div class="cmd"><code>${esc(text)}</code><button type="button" class="copy" data-copy="${esc(text)}">Copy</button></div>`;
const code = (t) => `<code>${esc(t)}</code>`;
const setupButton = 'open Set up this repository, click Run workflow, untick Only show what would change, and run it. This makes your labels and checklists.';
const actions = 'Open the repository on GitHub and go to Actions. Your checks are running.';

function existingSteps() {
  const list = [`Unzip ${code('launchR-files.zip')} and copy what's inside into your package folder. Nothing in ${code('R/')}, ${code('tests/')} or ${code('DESCRIPTION')} changes.`];
  if (add.ci) list.push(`Delete any old files in ${code('.github/workflows')} that do the same job.`);
  list.push("Commit and push, from RStudio's Git pane or GitHub Desktop.");
  if (add.ci && CHECKS.some(([k]) => S.checks[k])) list.push(actions);
  if (add.github) list.push(`On GitHub, go to Actions, ${setupButton}`);
  $('#stepList').innerHTML = list.map((t) => `<li>${t}</li>`).join('');
  $('#nextAfter').innerHTML = '<b>After that.</b> To add something later, come back and choose only that.';
}

function steps() {
  if (mode === 'existing') { existingSteps(); return; }
  const name = pkg();
  const priv = !isPublic();
  const open = `Unzip ${code(`${name}.zip`)}, then open ${code(`${name}.Rproj`)} in RStudio, or the folder in Positron. In RStudio, choose Build, then Test Package, to see your first test pass.`;
  const gh = '<a href="https://cli.github.com" target="_blank" rel="noopener">GitHub CLI</a>';
  const route = $('input[name=route]:checked').value;
  const setup = `source("https://raw.githubusercontent.com/insightsurge/launchR/v${lists.settings.kit_version}/cli/setup-github.R")`;
  const running = CHECKS.some(([k]) => S.checks[k]) ? [actions] : [];
  const list = route === 'desktop' ? [
    open,
    'Make a free <a href="https://github.com/signup" target="_blank" rel="noopener">GitHub account</a>, if you don\'t have one.',
    `Install <a href="https://desktop.github.com" target="_blank" rel="noopener">GitHub Desktop</a> and sign in. It brings Git with it. ${gh} is optional: your checklists show the repository settings to change by hand, and it lets the setup line tick those boxes for you.`,
    `In GitHub Desktop, choose File, then Add local repository, and pick the ${code(name)} folder. It offers to create the repository: accept.`,
    `Click Publish repository. ${priv ? 'Leave Keep this code private ticked.' : 'Untick Keep this code private.'}`,
    ...running,
    ...(S.github ? [`On GitHub, go to Actions, ${setupButton}`] : []),
  ] : [
    open,
    `Run these in the R console. GitHub asks you to make a token: paste it when R asks.${copy('install.packages(c("usethis", "gitcreds"))')}${copy('usethis::create_github_token()')}${copy('gitcreds::gitcreds_set()')}`,
    `Put the package on GitHub.${copy('usethis::use_git()')}${copy(`usethis::use_github(private = ${priv ? 'TRUE' : 'FALSE'})`)}`,
    ...(S.github ? [
      `Install ${gh}, then sign in once from the Terminal tab next to your console.${copy('gh auth login')}`,
      `Back in the R console, set up the labels and checklists. It asks before it changes anything. Your checklists then show the repository settings to change.${copy(setup)}`,
    ] : []),
    ...running,
  ];
  $('#stepList').innerHTML = list.map((t) => `<li>${t}</li>`).join('');
  const first = { a: 'After public', b: 'After public', c: 'Before public' }[plan()];
  const email = v('email') ? '' : `Replace the placeholder email in ${code('DESCRIPTION')} before you release. `;
  $('#nextAfter').innerHTML = `<b>After that.</b> ${email}${first && S.github ? `Open the <em>${first}</em> checklist in your repository's issues when you reach that stage. ` : ''}To add something later, such as a website, come back and choose only that.`;
}

$('#routes').addEventListener('change', steps);
$('#stepList').addEventListener('click', (e) => {
  const b = e.target.closest('.copy');
  if (!b) return;
  Promise.resolve(navigator.clipboard?.writeText(b.dataset.copy) ?? Promise.reject()).then(() => { b.textContent = 'Copied'; }, () => { b.textContent = 'Select it'; });
  setTimeout(() => { b.textContent = 'Copy'; }, 1400);
});

new MutationObserver(summary).observe($('#pvLists'), { childList: true });
dialog.addEventListener('close', () => {
  if (mode === 'existing' && lists) { S = recommended(); changed = false; paint(); }
  mode = 'new';
  view('main');
});

/* tooltips open on hover and focus, and on a tap; Escape or a tap elsewhere closes them */
const shut = (keep) => $$('.tip.open').forEach((t) => { if (t !== keep) t.classList.remove('open'); });
dialog.addEventListener('click', (e) => {
  const t = e.target.closest('.tip');
  shut(t);
  if (t) { e.preventDefault(); t.classList.toggle('open'); }
});
dialog.addEventListener('keydown', (e) => {
  const t = e.target.closest('.tip');
  if (t && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); t.classList.toggle('open'); }
  if (e.key === 'Escape' && (t || $('.tip.open'))) {
    e.preventDefault();
    e.stopPropagation();
    shut();
    if (t) { t.classList.add('quiet-tip'); t.addEventListener('blur', () => t.classList.remove('quiet-tip'), { once: true }); }
  }
});

async function loadKit() {
  try {
    const response = await fetch('/kit/bundle.json');
    if (!response.ok) return false;
    bundle = await response.json();
    lists = readLists(bundle);
    S ??= recommended();
    paint();
    return true;
  } catch {
    return false;
  }
}

view('main');
await loadKit();
