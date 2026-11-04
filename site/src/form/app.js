// The form: five questions, Modify, someone with a package already, and what to do after the download.
// Choices live here; engine.js turns them into files, the same way the CLI does.
import JSZip from 'jszip';
import { countZip } from '../consent.js';
import { buildPackage, checkDescription, checkEmail, checkMinR, checkPackageName, checkPerson, checkTitle, defaultChoices, planExtras, planRow, readLists } from './engine.js';

const $ = (q) => document.querySelector(q);
const $$ = (q) => [...document.querySelectorAll(q)];
const esc = (text) => String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const dialog = $('#setup');
// The checks and which run weekly come from lists/checks.tsv once the kit is loaded: [key, name, tip].
let CHECKS = [];
let WEEKLY = [];
const SYSTEMS = [['ubuntu', 'Linux'], ['windows', 'Windows'], ['macos', 'Mac']];
const RS = [['release', 'release'], ['oldrel-1', 'oldrel-1'], ['devel', 'devel']];
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const WORDS = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'All seven'];
const PARTS = [['ci', 'Automatic checks on GitHub (CI)'], ['website', 'Website'], ['github', 'Issue forms, labels and checklists']];

let bundle = null;
let lists = null;
let mode = 'new';
let changed = false;
let S = null;
const add = { ci: true, website: false, github: false };

const plan = () => $('input[name=plan]:checked').value;
const visibility = () => planRow(lists, plan()).visibility;
const release = () => planRow(lists, plan()).release;
const isPublic = () => visibility() === 'public';
const pkg = () => (mode === 'new' ? $('#pkg').value.trim() : $('#exPkg').value.trim()) || 'fooBarPkg';

function kitPlatforms() {
  const row = lists.checks.find((check) => check.key === 'r_cmd_check');
  return row[`platforms_${visibility()}`].split(',').map((entry) => entry.trim());
}

/* the day and time of the weekly checks, from the cron in lists/checks.tsv ("17 5 * * 1" is Monday, 05:17) */
function weeklyTime() {
  const row = lists.checks.find((check) => check.events.split(',').includes('schedule'));
  const [minute, hour, , , day] = row.cron.split(' ');
  return { day: DAYS[Number(day)], time: `${hour.padStart(2, '0')}:${minute.padStart(2, '0')}` };
}

/* what each plan starts from: the starter column and lists/plans.tsv, read by engine.js as the CLI reads them */
function recommended() {
  const start = kitPlatforms();
  return {
    checks: Object.fromEntries(Object.entries(defaultChoices(lists, 'starter', plan()).checks).map(([key, check]) => [key, check.on])),
    matrix: Object.fromEntries(SYSTEMS.flatMap(([s]) => RS.map(([r]) => [`${s}/${r}`, start.includes(`${s}/${r}`)]))),
    minR: '', samePlatforms: false, ...weeklyTime(), website: false, github: true, frontend: false, ai: false,
    ...modifyExtras(),
  };
}

/* the licence, badges, navbar, forms, labels, QC checklist and CI report comment the plan starts from (engine.js's
   planExtras, as the CLI reads them), with each list as ticks: key -> on */
function modifyExtras() {
  const extras = planExtras(lists, planRow(lists, plan()));
  const ticks = (rows, key, on) => Object.fromEntries(rows.map((row) => [row[key], on.includes(row[key])]));
  return {
    ciReport: extras.ciReport, licence: extras.licence, qc: extras.qc,
    badges: ticks(lists.badges, 'key', extras.badges), navbar: ticks(lists.navbar, 'key', extras.navbar),
    forms: ticks(lists.forms, 'key', extras.forms), labels: ticks(lists.labels, 'name', extras.labels),
  };
}

/* the checks whose results go in the CI report comment: all but r-cmd-check-extended (.github/pr-report.json) */
const REPORTING = ['r_cmd_check', 'coverage', 'full_tests', 'no_suggests', 'secret_scan', 'lint'];
const keys = (ticks) => Object.entries(ticks).filter(([, on]) => on).map(([key]) => key);
const formOn = (row) => S.forms[row.key] && (row.part !== 'ai' || S.ai);
/* why a badge can't be chosen yet, from its needs in lists/badges.tsv */
function badgeWhy(row) {
  const needs = row.needs.split(',').filter(Boolean);
  if (needs.includes('owner') && !v('owner')) return 'Needs your GitHub name in the form.';
  if (needs.includes('cran') && release() !== 'cran') return 'For a package going to CRAN.';
  const check = needs.find((need) => need !== 'owner' && need !== 'cran');
  if (check && !S.checks[check]) return `Needs the ${lists.checks.find((c) => c.key === check)?.check} check.`;
  return '';
}

const help = (text) => `<span class="tip" tabindex="0" role="note" aria-label="${esc(text)}"><svg aria-hidden="true"><use href="#i-info" /></svg><span role="tooltip" aria-hidden="true">${esc(text)}</span></span>`;
const bullets = (list) => `<span class="tip wide-tip" tabindex="0" role="note" aria-label="${esc(list.map(([k, w]) => `${k}: ${w}`).join(' '))}"><svg aria-hidden="true"><use href="#i-info" /></svg><span role="tooltip" aria-hidden="true"><ul>${list.map(([k, w]) => `<li><b>${esc(k)}</b> ${esc(w)}</li>`).join('')}</ul></span></span>`;
const sw = (id, text, why, on, soon) => `<div class="opt"><label class="sw"><input type="checkbox" id="${id}"${on ? ' checked' : ''}${soon ? ' disabled' : ''} /><i aria-hidden="true"></i><b>${text}</b></label>${soon ? '<span class="tag">Coming soon</span>' : ''}${help(why)}</div>`;
const pill = (attrs, text, on) => `<label class="pill"><input type="checkbox" ${attrs}${on ? ' checked' : ''} /><span><svg aria-hidden="true"><use href="#i-tick" /></svg>${text}</span></label>`;
const tick = (attrs, text, on, why, off) => `<div class="opt"><label class="pill"><input type="checkbox" ${attrs}${on ? ' checked' : ''}${off ? ' disabled' : ''} /><span><svg aria-hidden="true"><use href="#i-tick" /></svg>${text}</span></label>${why ? help(why) : ''}</div>`;
const head3 = (text, why) => `<h4>${text}${Array.isArray(why) ? bullets(why) : why ? help(why) : ''}</h4>`;

function paint() {
  if (!S) return;
  const weekly = WEEKLY.some((k) => S.checks[k]);
  const extra = S.checks.full_tests || S.checks.r_cmd_check_extended;
  $('#bodyCi').innerHTML = `
    ${head3('Checks to run', CHECKS.map(([, n, w]) => [n, w]))}
    <div class="ticks">${CHECKS.map(([k, name]) => pill(`data-check="${k}"`, `<code>${name}</code>`, S.checks[k])).join('')}</div>
    ${REPORTING.some((k) => S.checks[k]) ? sw('ciReport', 'CI report comment', 'One comment on each pull request with the results of the checks you chose, updated as each one finishes: failures with links to their logs, test counts, coverage and its change, style findings. Off leaves the comment out; each run still shows its results on its own page under Actions. You can change it later: ci-report in each file in .github/workflows/.', S.ciReport) : ''}
    ${head3('R versions to check, by system', [['release', 'The current R.'], ['oldrel-1', 'The R release before it. Linux only.'], ['devel', 'The next R, not released yet: it shows early what will break. Linux only.'], ['Minimum R version', 'The oldest R your package supports, as x.y from 4.1 up, such as 4.3. DESCRIPTION gets 4.3.0, as R CMD check asks, and Linux checks the newest 4.3. Leave it empty if you do not know yet.'], ['Systems', 'launchR picks the system version: Ubuntu 26.04, and the latest Windows and macOS on GitHub.'], ['Cost', 'Free on a public repository. A private one gets 2,000 free minutes a month on GitHub\'s free plan, and Mac minutes count ten times, Windows twice.']])}
    <div class="line"><label for="minR">Minimum R version</label><span class="when"><input id="minR" class="short" type="text" inputmode="decimal" autocomplete="off" maxlength="3" placeholder="4.1" aria-describedby="minRZero" value="${esc(S.minR)}" /><span class="unit" id="minRZero">.0</span></span></div>
    <p class="fieldnote" id="minRNote" role="status"></p>
    <table class="rmatrix"><thead><tr><td></td>${RS.map(([, x]) => `<th scope="col"><code>${x}</code></th>`).join('')}</tr></thead><tbody>${SYSTEMS.map(([k, t]) => `<tr><th scope="row">${t}</th>${RS.map(([v, x]) => (k === 'ubuntu' || v === 'release' ? `<td><label class="cell"><input type="checkbox" data-matrix="${k}/${v}" aria-label="${t}, ${x}"${S.matrix[`${k}/${v}`] ? ' checked' : ''} /><span><svg aria-hidden="true"><use href="#i-tick" /></svg></span></label></td>` : '<td class="none"></td>')).join('')}</tr>`).join('')}</tbody></table>
    ${extra ? sw('samePlatforms', 'Use the same systems for browser and extended tests', 'Runs full-tests and r-cmd-check-extended on the systems and R versions above, as R CMD check does. Off keeps their recommended ones.', S.samePlatforms) : ''}
    ${weekly ? `<div class="line"><label for="day">Weekly checks run on</label>${help('The weekly run of r-cmd-check, full-tests and r-cmd-check-extended, whichever are on. Why weekly: R and the packages yours uses keep changing, so it shows a break even when you changed nothing. It shows here when any of them is on, and the workflows README lists the time. Time is in 24-hour UTC, which is what GitHub uses. It may run some minutes late when GitHub is busy.')}<span class="when"><select id="day">${[...DAYS.slice(1), DAYS[0]].map((d) => `<option${d === S.day ? ' selected' : ''}>${d}</option>`).join('')}</select><label class="sr" for="time">Time in 24-hour UTC</label><input id="time" class="short" type="text" inputmode="numeric" autocomplete="off" maxlength="5" value="${esc(S.time)}" /><span class="unit">UTC</span></span></div><p class="fieldnote" id="timeNote" role="status"></p>` : ''}
    ${head3('How the checks reach your package')}
    <div class="pick">
      <div class="opt"><label><input type="radio" name="delivery" checked /><b>Shared</b></label>${help('Your files call the checks kept in launchR, so you get fixes and updates by themselves.')}</div>
      <div class="opt"><label class="soon"><input type="radio" name="delivery" disabled /><b>Snapshot</b></label><span class="tag">Coming soon</span>${help("The checks are copied into your repository and frozen, so nothing changes under a validated process. When a new launchR version is released, you won't get any updates, security fixes included.")}</div>
    </div>`;
  const pagesNote = isPublic() ? '' : `<p class="fieldnote" id="pagesNote">On GitHub's free plan a private repository can't publish a website. The site is still built and checked on every push, and goes online once the repository is public or on a paid plan.</p>`;
  const nav = (side, title) => `${head3(title, lists.navbar.filter((row) => row.side === side).map((row) => [row.label, row.help]))}<div class="ticks">${lists.navbar.filter((row) => row.side === side).map((row) => pill(`data-nav="${row.key}"`, row.label, S.navbar[row.key])).join('')}</div>`;
  $('#bodySite').innerHTML = `${sw('website', 'Add a website', 'A pkgdown site published to GitHub Pages. Its address comes from your GitHub name. A private repository needs a paid GitHub plan for this.', S.website)}${pagesNote}
    ${S.website ? `${nav('left', 'Navbar, left')}${nav('right', 'Navbar, right')}<p class="fieldnote">Saved in _pkgdown.yml, under navbar: structure. Change it there any time.</p>` : ''}
    <div class="opt soonline"><span>Theme colours</span><span class="tag">Coming soon</span></div>`;
  $('#bodyGit').innerHTML = `
    ${sw('github', 'Issue forms, labels and checklists', 'The issue forms and labels you tick below, a pull request template, and the stage checklists. The Set up this repository button creates the labels on GitHub, next to GitHub\'s own (it can remove those).', S.github)}
    ${S.github ? gitChoices() : ''}`;
  $('#bodyMore').innerHTML = `${sw('frontend', 'My package ships its own JS or CSS', 'Adds browser tests and the style checks for them.', S.frontend)}
    ${sw('ai', 'Instructions for AI assistants', 'AGENTS.md and rules files in .agents/rules/ (R code, tests, docs, checks, JS and CSS, git), the same for every package, read by Codex, Gemini, Copilot and others, and a CLAUDE.md that loads AGENTS.md for Claude. Also an issue form for changing them.', S.ai)}
    ${head3('Licence', [['MIT', 'Others may use, change and share the code, as long as they keep the copyright notice. CRAN accepts it.'], ['Proprietary', 'All rights reserved: for a package used only inside the organisation that owns it. CRAN does not accept it.']])}
    <div class="pick">${[['mit', 'MIT'], ['proprietary', 'Proprietary']].map(([k, t]) => `<div class="opt"><label><input type="radio" name="licence" value="${k}"${S.licence === k ? ' checked' : ''} /><b>${t}</b></label></div>`).join('')}</div>
    ${S.licence === 'proprietary' && release() === 'cran' ? '<p class="fieldnote">CRAN only accepts open-source licences, and R CMD check as CRAN gives a NOTE for this one, so the check fails. Choose MIT, or the plan Private for good.</p>' : ''}
    ${head3('README badges', 'Small images at the top of the README, also shown on the website\'s home page. They sit between the badges: start and end lines, where you can add or remove one later.')}
    ${lists.badges.map((row) => { const why = badgeWhy(row); return tick(`data-badge="${row.key}"`, row.label, S.badges[row.key] && !why, why ? `${row.help} ${why}` : row.help, !!why); }).join('')}`;
  summary();
}

/* the issue forms, their labels and the QC checklist: a form's own label stays on while the form is on */
function gitChoices() {
  const forms = lists.forms.filter((row) => row.part !== 'ai' || S.ai);
  const locked = new Set(lists.forms.filter(formOn).map((row) => row.label));
  return `${head3('Issue forms', 'The forms people fill in when they open an issue on GitHub. Each sets its label. Files in .github/ISSUE_TEMPLATE/.')}
    ${forms.map((row) => tick(`data-form="${row.key}"`, row.title, S.forms[row.key], row.help)).join('')}
    ${head3('Labels', 'Created on GitHub by the Set up this repository button. A form\'s label stays on while the form is on.')}
    ${lists.labels.map((row) => tick(`data-label="${esc(row.name)}"`, esc(row.name), S.labels[row.name] || locked.has(row.name), locked.has(row.name) ? `${row.description}. Kept: an issue form uses it.` : row.description, locked.has(row.name))).join('')}
    ${isPublic() ? '' : sw('qc', 'QC checklist', 'A checklist issue, QC before release, with boxes for the scope, tests, review and release evidence of a private package, for teams with a quality process. Opened by the Set up this repository button in place of Before public.', S.qc)}`;
}

function summary() {
  if (!S) return;
  const on = CHECKS.filter(([k]) => S.checks[k]).length;
  const sysText = SYSTEMS.filter(([k]) => RS.some(([r]) => S.matrix[`${k}/${r}`])).map(([, t]) => t).join(', ') || 'None';
  $('#sumCi').textContent = `${WORDS[on]} ${on === 1 ? 'check' : 'checks'} on ${sysText}`;
  $('#sumSite').textContent = S.website ? 'On' : 'Off';
  const forms = lists.forms.filter((row) => row.part !== 'ai' || S.ai);
  const formCount = forms.filter(formOn).length;
  const locked = new Set(lists.forms.filter(formOn).map((row) => row.label));
  const labelCount = lists.labels.filter((row) => S.labels[row.name] || locked.has(row.name)).length;
  $('#sumGit').textContent = !S.github ? 'Off' : formCount === forms.length && labelCount === lists.labels.length
    ? `All issue forms and labels${S.qc && !isPublic() ? ', QC checklist' : ''}`
    : `${formCount} of ${forms.length} issue forms, ${labelCount} of ${lists.labels.length} labels${S.qc && !isPublic() ? ', QC checklist' : ''}`;
  const badgeCount = lists.badges.filter((row) => S.badges[row.key] && !badgeWhy(row)).length;
  $('#sumMore').textContent = [S.licence === 'mit' ? 'MIT licence' : 'Proprietary licence', badgeCount ? `${badgeCount} ${badgeCount === 1 ? 'badge' : 'badges'}` : 'no badges', S.frontend && 'JS or CSS', S.ai && 'AI instructions'].filter(Boolean).join(', ');
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
  for (const [data, list] of [['badge', 'badges'], ['nav', 'navbar'], ['form', 'forms'], ['label', 'labels']]) {
    if (t.dataset[data] !== undefined) { touched(() => { S[list][t.dataset[data]] = t.checked; }); if (data === 'form') paint(); return; }
  }
  if (t.name === 'licence') { touched(() => { S.licence = t.value; }); paint(); return; }
  if (t.id === 'day') { touched(() => { S.day = t.value; }); return; }
  if (t.type === 'checkbox' && t.id in S) { touched(() => { S[t.id] = t.checked; }); if (mode === 'existing') add.website = S.website; if (['website', 'github', 'ai'].includes(t.id)) paint(); return; }
  if (t.id === 'minR') { touched(() => { S.minR = t.value; }); minRProblem(); }
  if (t.id === 'time') { touched(() => { S.time = t.value; }); timeProblem(); }
});
body.addEventListener('input', (e) => {
  if (e.target.id === 'minR') e.target.value = e.target.value.replace(/[^0-9.]/g, '').replace(/^(\d\.?\d?).*/, '$1').slice(0, 3);
});

function minRProblem() {
  const ok = !S.minR || !checkMinR(S.minR);
  $('#minR')?.classList.toggle('bad', !ok);
  const note = $('#minRNote');
  if (note) note.textContent = ok ? '' : checkMinR(S.minR);
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
  return checkPackageName(name, lists);
}

function ownerProblem(owner) {
  return !owner || /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/.test(owner) ? '' : 'Use only your GitHub name, such as insightsurge, not a link.';
}

function valid() {
  const rules = [
    ['pkg', nameProblem(v('pkg'), 'Give your package a name, such as fooBarPkg.')],
    ['what', checkTitle(v('what'))],
    ['details', checkDescription(v('details'), v('pkg'))],
    ['first', checkPerson(v('first'), 'first')],
    ['last', checkPerson(v('last'), 'last')],
    ['email', checkEmail(v('email'))],
    ['owner', v('owner') ? ownerProblem(v('owner')) : 'Give your GitHub username or organisation, such as insightsurge. No account yet? Sign up free at github.com/signup.'],
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
  return true;
}

['pkg', 'what', 'details', 'first', 'last', 'email', 'owner'].forEach((id) => $(`#${id}`).addEventListener('input', () => put(id, '')));
['exPkg', 'exOwner'].forEach((id) => $(`#${id}`).addEventListener('input', () => put(id, '')));

function cron() {
  const [hour, minute] = (timeProblem() ? weeklyTime().time : S.time).split(':').map(Number);
  return `${minute} ${hour} * * ${DAYS.indexOf(S.day)}`;
}

function platforms() {
  const list = Object.entries(S.matrix).filter(([, on]) => on).map(([entry]) => entry);
  if (S.minR && S.minR !== lists.settings.min_r) list.push(`ubuntu/${S.minR}`);
  return list.join(', ');
}

function choices() {
  const base = defaultChoices(lists, 'starter', plan());
  const start = kitPlatforms().join(', ');
  const parts = mode === 'new'
    ? ['skeleton', 'ci', ...(S.github ? ['github'] : []), ...(S.website ? ['website'] : []), ...(S.frontend ? ['frontend'] : []), ...(S.ai ? ['ai'] : [])]
    : PARTS.map(([k]) => k).filter((k) => add[k]);
  const chosen = platforms() === start ? null : platforms();
  const checks = Object.fromEntries(Object.entries(base.checks).map(([key, row]) => [key, {
    ...row,
    on: S.checks[key],
    cron: cron(),
    platforms: key === 'r_cmd_check' ? chosen : S.samePlatforms && (key === 'full_tests' || key === 'r_cmd_check_extended') ? platforms() : null,
  }]));
  const email = mode === 'new' ? v('email') : '';
  return {
    ...base, parts, checks, existing: mode === 'existing', visibility: visibility(), release: release(), owner: mode === 'new' ? v('owner') : v('exOwner'),
    package: pkg(), title: mode === 'new' ? v('what') : '', description: mode === 'new' ? v('details') : '', given: v('first'), family: v('last'), email,
    minR: minRProblem() ? base.minR : S.minR || base.minR,
    ciReport: S.ciReport, licence: S.licence, qc: S.qc && !isPublic(),
    badges: keys(S.badges), navbar: keys(S.navbar), forms: keys(S.forms), labels: keys(S.labels),
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
  $('#exFinder').textContent = finderNote;
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

async function goExisting() {
  /* the lists may still be loading when the button is pressed early */
  if (!lists && !(await loadKit())) {
    /* said next to the button that was pressed, which is far from the form */
    const note = $('#existingNote') ?? Object.assign(document.createElement('span'), { id: 'existingNote', role: 'status' });
    note.textContent = ' The form could not load its files. Check your connection and try again.';
    $('#existingStart').after(note);
    return;
  }
  $('#existingNote')?.remove();
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
const copy = (text, block) => `<div class="cmd${block ? ' block' : ''}"><code>${esc(text)}</code><button type="button" class="copy" data-copy="${esc(text)}">Copy</button></div>`;
const code = (t) => `<code>${esc(t)}</code>`;
const finderNote = 'On a Mac, Finder hides folders whose name starts with a dot, such as .github: press Cmd+Shift+. to see them.';
const setupButton = 'On GitHub, go to Actions, open <em>Set up this repository</em>, click Run workflow, untick <em>Only show what would change</em>, and run it.';
const setupMore = "Its first run, from your push, only listed what it would make. This run makes your labels and checklists. Labels that aren't launchR's, such as GitHub's own and any you made, stay. To remove them, also tick <em>Also remove labels that aren't launchR's</em>; Dependabot's labels are kept.";
const actions = 'Open the repository on GitHub and go to Actions: your checks are running.';
const local = `To run the same checks on your computer before a pull request, see <em>Run the checks on your computer</em> in ${code('.github/workflows/README.md')}. `;
// Optional, and only with the coverage check: the check works without Codecov.
const codecov = () => (S.checks.coverage ? `Optional: to show coverage on Codecov too, follow <em>Codecov</em> in ${code('.github/workflows/README.md')}. ` : '');
// One step: what to do in a line, the commands, and the explanations folded away.
const step = (lead, cmds = '', more = '') => `<li><p class="lead">${lead}</p>${cmds}${more ? `<details class="more"><summary>Why, and more</summary><p>${more}</p></details>` : ''}</li>`;

/* the lines R CMD check needs in .Rbuildignore for what the zip holds: one for each top-level file or folder, and the
   file a secret-scan false alarm goes in */
function ignoreLines() {
  const tops = [...new Set(Object.keys(buildPackage(choices(), bundle)).map((path) => path.split('/')[0]))];
  if (add.ci && S.checks.secret_scan) tops.push('.gitleaksignore');
  return tops.map((name) => `^${name.replace(/\./g, '\\.')}$`);
}

function existingSteps() {
  const list = [step(`Unzip ${code('launchR-files.zip')} and copy what's inside into your package folder. ${finderNote}`, '', `Nothing in ${code('R/')}, ${code('tests/')} or ${code('DESCRIPTION')} changes.`)];
  list.push(step(`Add these lines to ${code('.Rbuildignore')}, if they aren't there yet.`, copy(ignoreLines().join('\n'), true), 'They keep these files out of the built package, so R CMD check does not note them as unexpected hidden files or folders.'));
  const settings = ['.lintr', 'air.toml', 'codecov.yml'].filter((file) => file in buildPackage(choices(), bundle));
  if (settings.length) list.push(step(`If your package already has ${settings.map(code).join(', ')}, keep yours instead of the copy in the zip.`, '', 'The checks read these settings files. Copying over yours would replace your own lint, formatting or coverage settings; merge in only the lines you want.'));
  if (add.ci) list.push(step(`Delete any old files in ${code('.github/workflows')} that do the same job.`, '', `If your package already has ${code('.github/workflows/README.md')}, keep yours and copy in only the new rows from the one in the zip.`));
  if (add.ci && release() === 'internal') list.push(step(`Add this line to ${code('DESCRIPTION')}.`, copy('Config/quality-gate/target: internal'), "Your package won't go to CRAN, so the checks then leave out what only CRAN asks for."));
  list.push(step("Commit and push, from RStudio's Git pane or GitHub Desktop."));
  if (add.ci && CHECKS.some(([k]) => S.checks[k])) list.push(step(actions));
  if (add.github) list.push(step(setupButton, '', setupMore));
  $('#stepList').innerHTML = list.join('');
  $('#nextAfter').innerHTML = `<b>After that.</b> ${add.ci ? local + codecov() : ''}To add something later, come back and choose only that.`;
}

function steps() {
  if (mode === 'existing') { existingSteps(); return; }
  const name = pkg();
  const priv = !isPublic();
  const privArg = priv ? 'TRUE' : 'FALSE';
  const owner = v('owner');
  const unzip = `Unzip ${code(`${name}.zip`)} and open ${code(`${name}.Rproj`)} in RStudio, or the folder in Positron.`;
  const gh = '<a href="https://cli.github.com" target="_blank" rel="noopener">GitHub CLI</a>';
  const route = $('input[name=route]:checked').value;
  const setup = `source("https://raw.githubusercontent.com/insightsurge/launchR/v${lists.settings.kit_version}/cli/github-setup.R")`;
  const running = CHECKS.some(([k]) => S.checks[k]) ? [step(actions)] : [];
  const label = (text) => `<p class="cmd-label">${text}</p>`;
  const list = route === 'desktop' ? [
    step(`${unzip} Then, in RStudio, choose Build, then Test Package, to see your first test pass; in Positron, run ${code('devtools::test()')} in the console.`, '', `The first time, install the tools: in RStudio choose Tools, then Install Packages, and install ${code('devtools')}; in Positron, run ${code('install.packages("devtools")')}. Skip this if you already have it.`),
    step('Install <a href="https://desktop.github.com" target="_blank" rel="noopener">GitHub Desktop</a> and sign in with your GitHub account.', '', 'It brings Git with it. Skip this if you already use it.'),
    step(`In GitHub Desktop, choose File, then Add local repository, pick the ${code(name)} folder, and accept when it offers to create the repository.`),
    step(`Click Publish repository. ${priv ? 'Leave Keep this code private ticked.' : 'Untick Keep this code private.'} If ${code(owner)} is an organisation, pick it under Organization.`),
    ...running,
    ...(S.github ? [step(setupButton, '', setupMore)] : []),
  ] : [
    step(`${unzip} Then, in the R console, install the tools (skip any you already have) and run your first test.`,
      `${copy('install.packages(c("devtools", "gitcreds", "pak"))')}${copy('pak::local_install_dev_deps()')}${copy('devtools::test()')}`,
      'devtools brings usethis and testthat. The second line installs the packages your package uses. In RStudio, Build, then Test Package, does the same as the third line.'),
    step('Let R talk to GitHub, once. Skip this if R already can.',
      `${copy('usethis::create_github_token()')}${copy('gitcreds::gitcreds_set()')}`,
      `The first line opens a GitHub page with the right boxes already ticked: scroll down, click Generate token, and copy the token. The second asks for it: paste it there. It is kept in your computer's password store (Keychain on a Mac, Credential Manager on Windows), where usethis and pak find it. Don't save it in a file such as ${code('.Renviron')}: that is plain text.`),
    step('Put the package on GitHub: run the first line and answer yes to each question; after RStudio restarts, run the line for your account.',
      `${copy('usethis::use_git()')}${label('Your own account:')}${copy(`usethis::use_github(private = ${privArg})`)}${label('An organisation, such as a company\'s:')}${copy(`usethis::use_github(organisation = "${owner}", private = ${privArg})`)}`,
      `The first line asks to commit your files and then to restart RStudio; the yes answer moves around, so read each one. ${code('DESCRIPTION')} already links to ${code(`github.com/${owner}/${name}`)}, so the repository should be made there.`),
    ...running,
    ...(S.github ? [step(setupButton, '', setupMore)] : []),
  ];
  $('#stepList').innerHTML = list.join('');
  // A private package with the QC checklist starts there (cli/R/github.R opens it in place of Before public).
  const first = S.qc && !isPublic() ? lists.settings.qc_stage : planRow(lists, plan()).first_checklist;
  const email = v('email') ? '' : `Replace the placeholder email in ${code('DESCRIPTION')} before you release. `;
  const settings = S.github ? `Your checklists list a few repository settings to change by hand. Optional: with ${gh} installed and signed in, ${code(setup)} in the R console ticks those boxes for you. ` : '';
  $('#nextAfter').innerHTML = `<b>After that.</b> ${email}${first && S.github ? `Open the <em>${first}</em> checklist in your repository's issues when you reach that stage. ` : ''}${settings}${running.length ? local : ''}${codecov()}To add something later, such as a website, come back and choose only that.`;
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

/* one load at a time: a button pressed while the page is still loading waits for the same fetch; a failed load can be
   tried again */
let kitLoading = null;
function loadKit() {
  kitLoading ??= (async () => {
    try {
      const response = await fetch('/kit/bundle.json');
      if (!response.ok) return false;
      bundle = await response.json();
      lists = readLists(bundle);
      CHECKS = lists.checks.map((row) => [row.key, row.check, row.help]);
      WEEKLY = lists.checks.filter((row) => row.events.split(',').includes('schedule')).map((row) => row.key);
      S ??= recommended();
      paint();
      return true;
    } catch {
      return false;
    }
  })().then((ok) => {
    if (!ok) kitLoading = null;
    return ok;
  });
  return kitLoading;
}

view('main');
await loadKit();
