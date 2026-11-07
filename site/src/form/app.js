// The form: the first screen's questions and a plan, or every setting in four more steps; someone with a package already; and what to
// do after the download.
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
let custom = false;
let currentStep = 2;
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
    minR: lists.settings.min_r, samePlatforms: false, ...weeklyTime(), website: false, github: true, frontend: false, ai: false,
    ...modifyExtras(),
  };
}

/* the licence, badges, navbar, forms, labels, checklists and CI report comment the plan starts from (engine.js's
   planExtras, as the CLI reads them), with each list as ticks: key -> on. The Set up with launchR badge is always on. */
function modifyExtras() {
  const extras = planExtras(lists, planRow(lists, plan()));
  const ticks = (rows, key, on) => Object.fromEntries(rows.map((row) => [row[key], on.includes(row[key])]));
  return {
    ciReport: extras.ciReport, licence: extras.licence,
    badges: { ...ticks(lists.badges, 'key', extras.badges), [ALWAYS_BADGE]: true }, navbar: ticks(lists.navbar, 'key', extras.navbar),
    forms: ticks(lists.forms, 'key', extras.forms), labels: ticks(lists.labels, 'name', extras.labels),
    checklists: ticks(lists.stages, 'key', extras.checklists),
  };
}

/* the README badge every package made here carries: a small credit that links to launchR */
const ALWAYS_BADGE = 'launchr';
/* the checklists a package can have on its plan: Before public only while private, Before CRAN and After acceptance
   only for a package going to CRAN (cli/R/github.R open_stages never opens them otherwise) */
const CRAN_STAGES = ['before-cran', 'after-acceptance'];
const stageOffered = (row) => (row.key === 'before-public' ? !isPublic() : CRAN_STAGES.includes(row.key) ? release() === 'cran' : true);
const chosenStages = () => lists.stages.filter((row) => S.checklists[row.key] && stageOffered(row));
/* the checklists Set up this repository opens on its first run, as cli/R/github.R open_stages does for a new
   repository: the others open when their stage arrives */
function openNow() {
  const chosen = chosenStages().map((row) => row.stage);
  const visibility = isPublic() ? 'After public' : 'Before public';
  const state = release() === 'internal' ? [visibility, 'Next release'] : [visibility, 'Before CRAN'];
  return ['Set up', ...state].filter((stage) => chosen.includes(stage));
}

/* the checks whose results go in the CI report comment: all but r-cmd-check-extended (.github/pr-report.json) */
const REPORTING = ['r_cmd_check', 'coverage', 'full_tests', 'no_suggests', 'secret_scan', 'lint'];
const keys = (ticks) => Object.entries(ticks).filter(([, on]) => on).map(([key]) => key);
const formOn = (row) => S.forms[row.key] && (row.part !== 'ai' || S.ai);
/* why a badge can't be chosen yet, from its needs in lists/badges.tsv */
function badgeWhy(row) {
  const needs = row.needs.split(',').filter(Boolean);
  if (needs.includes('owner') && !v('owner')) return 'Needs your GitHub name, on the first screen.';
  if (needs.includes('cran') && release() !== 'cran') return 'For a package going to CRAN.';
  const check = needs.find((need) => need !== 'owner' && need !== 'cran');
  if (check && !S.checks[check]) return `Needs the ${lists.checks.find((c) => c.key === check)?.check} check.`;
  return '';
}

const help = (text, warn) => `<span class="tip${warn ? ' warn' : ''}" tabindex="0" role="note" aria-label="${esc(text)}"><svg aria-hidden="true"><use href="#i-info" /></svg><span role="tooltip" aria-hidden="true">${esc(text)}</span></span>`;
const bullets = (list) => `<span class="tip wide-tip" tabindex="0" role="note" aria-label="${esc(list.map(([k, w]) => `${k}: ${w}`).join(' '))}"><svg aria-hidden="true"><use href="#i-info" /></svg><span role="tooltip" aria-hidden="true"><ul>${list.map(([k, w]) => `<li><b>${esc(k)}:</b> ${esc(w)}</li>`).join('')}</ul></span></span>`;
const sw = (id, text, why, on, soon) => `<div class="opt"><label class="sw"><input type="checkbox" id="${id}"${on ? ' checked' : ''}${soon ? ' disabled' : ''} /><i aria-hidden="true"></i><b>${text}</b></label>${soon ? '<span class="tag">Coming soon</span>' : ''}${help(why)}</div>`;
const swList = (id, text, list, on) => `<div class="opt"><label class="sw"><input type="checkbox" id="${id}"${on ? ' checked' : ''} /><i aria-hidden="true"></i><b>${text}</b></label>${bullets(list)}</div>`;
const pill = (attrs, text, on) => `<label class="pill"><input type="checkbox" ${attrs}${on ? ' checked' : ''} /><span>${text}</span></label>`;
const nest = (html) => `<div class="nest">${html}</div>`;
const head3 = (text, why) => `<h4>${text}${Array.isArray(why) ? bullets(why) : why ? help(why) : ''}</h4>`;

function paint() {
  if (!S) return;
  const weekly = WEEKLY.some((k) => S.checks[k]);
  const extra = S.checks.full_tests || S.checks.r_cmd_check_extended;
  $('#bodyCi').innerHTML = `
    ${head3('Checks to run', [...CHECKS.map(([, n, w]) => [n, w]), ...(REPORTING.some((k) => S.checks[k]) ? [['ci-report', 'Not a check: one comment on each pull request with the results of the checks you chose, updated as each one finishes: failures with links to their logs, test counts, coverage and its change, style findings. Off leaves the comment out; each run still shows its results on its own page under Actions. You can change it later: ci-report in each file in .github/workflows/.']] : [])])}
    ${nest(`<div class="ticks">${CHECKS.map(([k, name]) => pill(`data-check="${k}"`, `<code>${name}</code>`, S.checks[k])).join('')}${REPORTING.some((k) => S.checks[k]) ? `<span class="tick-divider" aria-hidden="true"></span>${pill('id="ciReport"', '<code>ci-report</code>', S.ciReport)}` : ''}</div>`)}
    ${head3('R CMD check: R versions × systems', [['release', 'The current R.'], ['oldrel-1', 'The R release before it. Linux only.'], ['devel', 'The next R, not released yet: it shows early what will break. Linux only.'], ['Oldest R your package supports', 'Type it as x.y, from 4.1 up, such as 4.3. DESCRIPTION then says R (>= 4.3.0), and Linux also checks the newest 4.3. The default is 4.1.'], ['Systems', 'launchR picks the system version: Ubuntu 26.04, and the latest Windows and macOS on GitHub.'], ['Cost', 'Free on a public repository. A private one gets 2,000 free minutes a month on GitHub\'s free plan, and Mac minutes count ten times, Windows twice.']])}
    <div class="nest"><div class="line"><label for="minR">Oldest R your package supports</label><span class="when affix"><input id="minR" class="short" type="text" inputmode="decimal" autocomplete="off" maxlength="3" size="3" placeholder="4.1" aria-describedby="minRZero" value="${esc(S.minR)}" /><span class="unit" id="minRZero">.0</span></span></div>
    <p class="fieldnote" id="minRNote" role="status"></p>
    <table class="rmatrix"><thead><tr><td></td>${RS.map(([, x]) => `<th scope="col"><code>${x}</code></th>`).join('')}</tr></thead><tbody>${SYSTEMS.map(([k, t]) => `<tr><th scope="row">${t}</th>${RS.map(([v, x]) => (k === 'ubuntu' || v === 'release' ? `<td><label class="cell"><input type="checkbox" data-matrix="${k}/${v}" aria-label="${t}, ${x}"${S.matrix[`${k}/${v}`] ? ' checked' : ''} /><span><svg aria-hidden="true"><use href="#i-tick" /></svg></span></label></td>` : '<td class="none"></td>')).join('')}</tr>`).join('')}</tbody></table></div>
    ${extra ? nest(sw('samePlatforms', 'Use the same systems for browser and extended tests', 'Runs full-tests and r-cmd-check-extended on the systems and R versions above, as R CMD check does. Off, they keep the systems launchR picks for them.', S.samePlatforms)) : ''}
    ${weekly ? `${head3('Weekly checks', 'The weekly run of r-cmd-check, full-tests and r-cmd-check-extended, whichever are on. Weekly, because R and the packages yours uses keep changing: it catches a break even when you changed nothing. The time is in 24-hour UTC, as GitHub uses, and the run may start a few minutes late when GitHub is busy.')}<div class="nest"><div class="line"><label for="day">Run on</label><span class="when"><select id="day">${[...DAYS.slice(1), DAYS[0]].map((d) => `<option${d === S.day ? ' selected' : ''}>${d}</option>`).join('')}</select><label class="sr" for="time">Time in 24-hour UTC</label><input id="time" class="short" type="text" inputmode="numeric" autocomplete="off" maxlength="5" value="${esc(S.time)}" /><span class="unit">UTC</span></span></div><p class="fieldnote" id="timeNote" role="status"></p></div>` : ''}
    ${head3('How the checks reach your package')}
    <div class="pick nest">
      <div class="opt"><label><input type="radio" name="delivery" checked /><b>Shared</b></label>${help('Your workflow files call the checks kept in launchR, at a fixed version. When a new minor version is out, Dependabot opens a pull request that moves them to it, so you get its fixes and updates once you merge it. Patch releases come with the next minor one.')}</div>
      <div class="opt"><label class="soon"><input type="radio" name="delivery" disabled /><b>Snapshot</b></label><span class="tag">Coming soon</span>${help("The checks are copied into your repository and frozen, so nothing changes under a validated process. When a new launchR version is released, you won't get any updates, security fixes included.")}</div>
    </div>`;
  const pagesNote = isPublic() ? '' : `<p class="fieldnote" id="pagesNote">On GitHub's free plan a private repository can't publish a website. The site is still built and checked on every push, and goes online once the repository is public or on a paid plan.</p>`;
  const nav = (side, title) => `<p class="sublabel">${title}</p>${nest(`<div class="ticks">${lists.navbar.filter((row) => row.side === side).map((row) => pill(`data-nav="${row.key}"`, row.label, S.navbar[row.key])).join('')}</div>`)}`;
  const shown = lists.badges.filter((row) => row.key !== ALWAYS_BADGE);
  $('#bodySite').innerHTML = `<div class="new-only">${head3('README badges', [['README badges', 'Small images at the top of the README, also shown on the website\'s home page. In the README they sit between the lines badges: start and badges: end, where you can add or remove one later.'], ...shown.map((row) => [row.label, row.help])])}
    ${nest(`<div class="shields">${shown.map(shield).join('')}</div>`)}</div>
    ${sw('website', 'Add a website', 'A pkgdown site published to GitHub Pages. Its address comes from your GitHub name. A private repository needs a paid GitHub plan for this.', S.website)}${pagesNote}
    ${S.website ? nest(`${head3('Navbar', [['Navbar', 'The links across the top of every page of the website, on the left and on the right.'], ...lists.navbar.map((row) => [`${row.label} (${row.side})`, row.help]), ['_pkgdown.yml', 'Your choices are saved there, under navbar: structure. Change them there any time.']])}${nest(`${nav('left', 'Left')}${nav('right', 'Right')}`)}`) : ''}
    <div class="opt soonline"><span>Theme colours</span><span class="tag">Coming soon</span></div>`;
  $('#bodyGit').innerHTML = `
    ${sw('github', 'Issue forms, labels and checklists', 'Adds the issue forms and labels you tick below, a pull request template and the stage checklists. Set up this repository then creates the labels on GitHub, next to GitHub\'s own, and can remove those.', S.github)}
    ${S.github ? gitChoices() : ''}`;
  const rules = lists.files.filter((row) => row.path.startsWith('.agents/rules/')).map((row) => row.path.replace(/^.*\/|\.md$/g, ''));
  $('#bodyMore').innerHTML = `${head3('Licence', [['MIT', 'Others may use, change and share the code, as long as they keep the copyright notice. CRAN accepts it.'], ['Proprietary', 'All rights reserved: for a package used only inside the organisation that owns it. CRAN does not accept it.']])}
    <div class="pick nest">${[['mit', 'MIT'], ['proprietary', 'Proprietary']].map(([k, t]) => `<div class="opt"><label><input type="radio" name="licence" value="${k}"${S.licence === k ? ' checked' : ''} /><b>${t}</b></label>${k === 'proprietary' && release() === 'cran' ? help('CRAN only accepts open-source licences, and R CMD check as CRAN gives a NOTE for this one, so the check fails. Choose MIT, or the plan Private for good.', S.licence === k) : ''}</div>`).join('')}</div>
    ${swList('frontend', 'My package ships its own JS or CSS', [['Browser tests', 'tests/testthat/test-demo-browser.R drives Chrome through chromote (added to Suggests). To run them on your computer, install Google Chrome.'], ['Style checks', 'Biome formats and lints the JS and CSS in inst/, with its settings in biome.json. To run them on your computer, install Biome: biomejs.dev.'], ['Starter files', 'A demo page, JS and CSS in inst/www/, to replace with your own.']], S.frontend)}
    <div class="ai-row">${swList('ai', 'Instructions for AI assistants', [['AGENTS.md', 'The instructions, the same for every package, read by Codex, Gemini, Copilot and others.'], ['CLAUDE.md', 'Loads AGENTS.md for Claude.'], ['.agents/rules/', `One rules file each for ${rules.join(', ')}.`], ['SKILL.md', 'launchR\'s skill, which AGENTS.md points to: how the checks, the CI report and upgrades work.'], ['Issue form', 'AI instructions change, for proposing a change to them.']], S.ai)}${peekLink('skill', 'Preview launchR\'s skill for AI agents')}</div>`;
  summary();
}

/* a README badge as it looks in the README: its words and colours are the badge's own, drawn here so nothing is
   fetched. The Set up with launchR credit isn't shown: every package gets it. */
const SHIELDS = {
  check: ['R-CMD-check', 'passing', '#2ea44f'], lifecycle: ['lifecycle', 'experimental', '#fe7d37'], codecov: ['codecov', '87%', '#2ea44f'],
  cran: ['CRAN status', 'not published', '#9f9f9f'], downloads: ['downloads', '120/month', '#2ea44f'], universe: ['r-universe', '0.1.0', '#3e7cc4'],
  launchr: ['set up with', 'launchR', '#f6ab85'],
};
function shield(row) {
  const [left, right, colour] = SHIELDS[row.key] ?? [row.label, '', '#9f9f9f'];
  const why = badgeWhy(row);
  const on = S.badges[row.key] && !why;
  return `<div class="opt shield-opt"><label class="shield" title="${esc(row.label)}"><input type="checkbox" data-badge="${row.key}" aria-label="${esc(row.label)}"${on ? ' checked' : ''}${why ? ' disabled' : ''} /><span><b>${esc(left)}</b><i style="--sc:${colour}">${esc(right)}</i>${why ? `<span class="tip shield-why" tabindex="0" role="note" aria-label="${esc(why)}"><em aria-hidden="true">!</em><span role="tooltip" aria-hidden="true">${esc(why)}</span></span>` : ''}</span></label></div>`;
}

const peekLink = (target, label) => `<button type="button" class="peek-link" data-open="${target}" aria-label="${esc(label)}">Preview</button>`;

/* the issue forms, each with the label it sets; the other labels; and the stage checklists */
function gitChoices() {
  const forms = lists.forms.filter((row) => row.part !== 'ai' || S.ai);
  const locked = new Set([...lists.forms.filter(formOn).map((row) => row.label), ...lists.labels.filter((row) => row.kept).map((row) => row.name)]);
  const colour = (name) => `#${lists.labels.find((row) => row.name === name)?.color ?? 'cfd3d7'}`;
  const chip = (name) => `<span class="label-chip" style="--lc:${colour(name)}" title="${esc(lists.labels.find((row) => row.name === name)?.description ?? '')}">${esc(name)}</span>`;
  const kept = lists.labels.filter((row) => row.kept);
  /* the other labels; a label whose form was taken off goes last */
  const freed = new Set(forms.filter((row) => !S.forms[row.key]).map((row) => row.label));
  const others = lists.labels.filter((row) => !locked.has(row.name));
  const free = [...others.filter((row) => !freed.has(row.name)), ...others.filter((row) => freed.has(row.name))];
  const stages = lists.stages.filter(stageOffered);
  const notOffered = lists.stages.filter((row) => !stageOffered(row));
  return `<div class="git-head">${head3('Issue forms', 'The forms people fill in when they open an issue on GitHub. Each sets its own label. They are saved in .github/ISSUE_TEMPLATE/.')}${peekLink(`form-${forms[0].key}`, 'Preview the issue forms')}</div>
    <div class="fcards nest">${forms.map((row) => `<label class="fcard"><input type="checkbox" data-form="${row.key}"${S.forms[row.key] ? ' checked' : ''} /><span><b>${esc(row.title)}</b><small>${esc(row.help)}</small><span class="fcard-label">${chip(row.label)}<span class="auto"><svg aria-hidden="true"><use href="#i-lock" /></svg>${S.forms[row.key] ? 'auto-applied' : (() => { const other = forms.find((f) => f !== row && f.label === row.label && S.forms[f.key]); return other ? `still set by ${esc(other.title)}` : 'not added'; })()}</span></span></span></label>`).join('')}</div>
    ${kept.map((row) => `<p class="kept-line nest">${chip(row.name)}<span class="auto"><svg aria-hidden="true"><use href="#i-lock" /></svg>always created</span> ${esc(row.description)}. ${esc(row.kept)}</p>`).join('')}
    ${head3('Labels', [['Labels', 'Set up this repository creates them on GitHub. A label that an issue form sets stays on while the form is on.'], ...lists.labels.map((row) => [row.name, `${row.description}${locked.has(row.name) ? (row.kept ? '. Always created.' : '. Set by an issue form you chose.') : '.'}`])])}
    <div class="ticks nest">${free.map((row) => `<label class="pill" title="${esc(row.description)}"><input type="checkbox" data-label="${esc(row.name)}"${S.labels[row.name] ? ' checked' : ''} /><span><i class="dot" style="--lc:${colour(row.name)}"></i>${esc(row.name)}</span></label>`).join('')}</div>
    <div class="git-head">${head3('Checklists', stages.map((row) => [row.stage, row.opens]))}${peekLink(`cl-${(chosenStages()[0] ?? stages[0] ?? lists.stages[0]).key}`, 'Preview the checklists')}</div>
    <div class="ticks nest">${stages.map((row) => pill(`data-stage="${row.key}"`, row.stage, S.checklists[row.key])).join('')}</div>
    ${notOffered.length ? `<p class="sw-note nest">${[isPublic() && 'Before public is for a private package.', release() !== 'cran' && 'Before CRAN and After acceptance are for a package going to CRAN.'].filter(Boolean).join(' ')}</p>` : ''}`;
}

function summary() {
  if (!S) return;
  const on = CHECKS.filter(([k]) => S.checks[k]).length;
  const sysText = SYSTEMS.filter(([k]) => RS.some(([r]) => S.matrix[`${k}/${r}`])).map(([, t]) => t).join(', ') || 'None';
  $('#pvChecks').textContent = on === 7 ? 'All seven' : WORDS[on];
  $('#pvSystems').textContent = sysText;
  $('#pvSite').textContent = S.website ? 'On' : 'Off';
  $('#pvCustom').hidden = !changed;
  /* the checklists in the preview follow the ticks; animated only when they change */
  const shown = mode === 'new' && S.github ? chosenStages().map((row) => row.stage) : [];
  const key = shown.join('|');
  if ($('#pvLists').dataset.key !== key) {
    $('#pvLists').dataset.key = key;
    $('#pvLists').innerHTML = shown.length ? shown.map((stage, i) => `<li style="animation-delay:${i * 50}ms">${esc(stage)}</li>`).join('') : '<li class="none">None</li>';
  }
  $('#modReset').disabled = !changed;
  $('#planLine').textContent = `${on === 7 ? 'All seven' : WORDS[on]} ${on === 1 ? 'check' : 'checks'} and ${shown.length ? `${shown.length} ${shown.length === 1 ? 'checklist' : 'checklists'}` : 'no checklists'}. ${{ a: 'Release features up to CRAN and after.', b: 'Release features for GitHub or R-universe.', c: 'Release features once you go public.', d: 'No release features: it stays private.' }[plan()]}`;
}

function offLabel(name) {
  const stillSet = lists.forms.some((row) => formOn(row) && row.label === name) || lists.labels.some((row) => row.kept && row.name === name);
  if (!stillSet) S.labels[name] = false;
}

function touched(fn) { fn(); changed = true; summary(); }

const body = $('#modifyView');
body.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset.check) { touched(() => { S.checks[t.dataset.check] = t.checked; }); paint(); return; }
  if (t.dataset.matrix) { touched(() => { S.matrix[t.dataset.matrix] = t.checked; }); return; }
  for (const [data, list] of [['badge', 'badges'], ['nav', 'navbar'], ['form', 'forms'], ['label', 'labels'], ['stage', 'checklists']]) {
    if (t.dataset[data] !== undefined) {
      touched(() => {
        S[list][t.dataset[data]] = t.checked;
        // QC is sections of Next release: choosing QC chooses Next release, and leaving Next release out leaves QC out
        if (data === 'stage' && t.dataset.stage === 'qc' && t.checked) S.checklists['next-release'] = true;
        if (data === 'stage' && t.dataset.stage === 'next-release' && !t.checked) S.checklists.qc = false;
      });
      // show the coupled pill without redrawing the step, so the focus stays on the one just used
      if (data === 'stage') document.querySelectorAll('[data-stage]').forEach((box) => { box.checked = !!S.checklists[box.dataset.stage]; });
      // a form taken off leaves its label unticked, unless another chosen form still sets it
      if (data === 'form') { if (!t.checked) offLabel(lists.forms.find((row) => row.key === t.dataset.form).label); paint(); }
      return;
    }
  }
  if (t.name === 'licence') { touched(() => { S.licence = t.value; }); paint(); return; }
  if (t.id === 'day') { touched(() => { S.day = t.value; }); return; }
  if (t.type === 'checkbox' && t.id in S) { touched(() => { S[t.id] = t.checked; }); if (mode === 'existing') add.website = S.website; if (['website', 'github', 'ai', 'frontend'].includes(t.id)) paint(); return; }
  if (t.id === 'minR') { touched(() => { S.minR = t.value; }); minRProblem(); }
  if (t.id === 'time') { touched(() => { S.time = t.value; }); timeProblem(); }
});
body.addEventListener('input', (e) => {
  // the oldest R is x.y with one digit each side: a second digit gets the dot put in front of it ("44" reads 4.4)
  if (e.target.id === 'minR') {
    const digits = e.target.value.replace(/\D/g, '').slice(0, 2);
    e.target.value = digits.length === 2 ? `${digits[0]}.${digits[1]}` : digits + (digits && e.target.value.includes('.') ? '.' : '');
  }
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

/* the steps: Your package (the questions and the plan), then the four groups of settings. A package that exists already gets
   Checks and Website only. */
const STEP_TITLES = { 2: 'CI checks', 3: 'Issues and checklists', 4: 'README and website', 5: 'Extras' };
const stepList = () => (mode === 'new' ? [1, 2, 3, 4, 5] : [2, 4]);

function view(name, focus) {
  dialog.dataset.view = name;
  dialog.dataset.mode = mode;
  $('#form').hidden = name !== 'main';
  $('#modifyView').hidden = name !== 'modify';
  $('#nextView').hidden = name !== 'next';
  $('#existingView').hidden = name !== 'existing';
  paintSteps();
  dialog.scrollTop = 0;
  focus?.focus({ preventScroll: true });
  alignPreview();
}

/* the preview card's top sits level with the end of the view's subtitle, so it starts at the same height on every view */
function alignPreview() {
  const card = $('#setup .setup-grid > .preview');
  const sub = [...dialog.querySelectorAll('.setup-grid .sub')].find((el) => el.offsetParent);
  if (!card || !sub || !card.offsetParent || dialog.scrollTop > 0) return;
  // where the card would start with no margin, then the margin that moves it to the subtitle's end
  const natural = card.getBoundingClientRect().top - (parseFloat(getComputedStyle(card).marginTop) || 0);
  card.style.setProperty('--pv-top', `${Math.max(0, Math.round(sub.getBoundingClientRect().bottom - natural))}px`);
}
// realign when the dialog opens (once its opening motion has settled), when the grid changes size, and on resize
new MutationObserver(() => { if (dialog.open) [60, 700].forEach((ms) => setTimeout(alignPreview, ms)); }).observe(dialog, { attributes: true, attributeFilter: ['open'] });
new ResizeObserver(() => alignPreview()).observe($('#setup .setup-grid'));
window.addEventListener('resize', alignPreview);

function paintSteps() {
  const name = dialog.dataset.view;
  const list = stepList();
  const current = name === 'main' ? 1 : currentStep;
  // the bar keeps its room on every view, so the form never moves; it shows while there are steps to take
  $('#stepBar').classList.toggle('off', !(name === 'modify' || (name === 'main' && custom)));
  $$('#stepBar button').forEach((b) => {
    const n = Number(b.dataset.step);
    b.parentElement.hidden = !list.includes(n);
    b.querySelector('i').textContent = String(list.indexOf(n) + 1 || n);
    if (n === current) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current');
    b.classList.toggle('done', list.indexOf(n) < list.indexOf(current));
  });
}

function goStep(n) {
  if (n === 1) { view('main', $('#pkg')); return; }
  currentStep = n;
  $$('#modifyView .mod').forEach((section) => { section.hidden = Number(section.dataset.step) !== n; });
  $('#stepTitle').textContent = mode === 'existing' && n === 4 ? 'Website' : STEP_TITLES[n];
  const list = stepList();
  const last = list[list.length - 1] === n;
  $('#stepNext').hidden = last;
  $('#modDownload').hidden = !last;
  $('#modPkg').textContent = mode === 'new' ? pkg() : 'your package';
  $('#modDownload').textContent = mode === 'new' ? `Download ${pkg()}.zip` : 'Download the files';
  view('modify', $('#modTitle'));
}

/* the first screen: Use a plan (the plan and Download), or Customise a plan (the plan to start from, and Next) */
function paintMain() {
  $('#planLegend').textContent = custom ? 'Start from this plan' : 'What is the plan for this package?';
  $('#download').hidden = custom;
  $('#modify').hidden = !custom;
  paintSteps();
  missing();
}

/* what the first screen still needs, said under the button; the button looks off until then and, when pressed,
   shows each message beside its field */
function missing() {
  if (!lists) return;
  const need = [
    !v('pkg') || nameProblem(v('pkg'), '') ? 'a package name' : '',
    checkTitle(v('what')) ? 'a one-line title' : '',
    checkPerson(v('first'), 'first') || checkPerson(v('last'), 'last') ? 'the author\'s name' : '',
    !v('owner') || ownerProblem(v('owner')) ? 'your GitHub name' : '',
  ].filter(Boolean);
  const other = checkDescription(v('details'), v('pkg')) || checkEmail(v('email'));
  const words = need.length > 1 ? `${need.slice(0, -1).join(', ')} and ${need[need.length - 1]}` : need[0];
  const to = custom ? 'go on' : 'download';
  $('#missing').textContent = need.length ? `Add ${words} to ${to}.` : other ? `Fix the ${checkEmail(v('email')) ? 'email' : 'description'} to ${to}.` : '';
  const off = need.length > 0 || !!other;
  ['#download', '#modify'].forEach((id) => $(id).setAttribute('aria-disabled', String(off)));
}

$('#how').addEventListener('change', () => {
  custom = $('#custom').checked;
  if (!custom && changed) {
    S = recommended();
    changed = false;
    paint();
    $('#planNote').textContent = 'Your own settings were reset to the plan\'s.';
  } else $('#planNote').textContent = '';
  paintMain();
});
$('#modify').addEventListener('click', () => { if (basics()) { paint(); goStep(2); } });
$('#stepBar').addEventListener('click', (e) => {
  const b = e.target.closest('button[data-step]');
  if (!b) return;
  const n = Number(b.dataset.step);
  if (n === 1) { goStep(1); return; }
  if (mode === 'new' && !basics()) return;
  if (dialog.dataset.view === 'modify' && currentStep === 2 && n !== 2 && !modifyValid()) return;
  paint();
  goStep(n);
});
$('#stepNext').addEventListener('click', () => {
  if (currentStep === 2 && !modifyValid()) return;
  const list = stepList();
  goStep(list[list.indexOf(currentStep) + 1]);
});
$('#modBack').addEventListener('click', () => {
  const list = stepList();
  const at = list.indexOf(currentStep);
  if (at > 0) goStep(list[at - 1]); else view('existing', $('#exModify'));
});
$('#modReset').addEventListener('click', () => { S = recommended(); changed = false; paint(); });
$('#plans').addEventListener('change', () => {
  $('#planNote').textContent = changed ? 'A new plan starts from its own defaults, so your changes were reset.' : '';
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

function basics() {
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
  return true;
}

function valid() {
  return basics() && modifyValid();
}

function modifyValid() {
  const open = () => goStep(2);
  if (minRProblem()) { open(0); $('#minR').focus(); return false; }
  if (WEEKLY.some((k) => S.checks[k]) && timeProblem()) { open(0); $('#time').focus(); return false; }
  if (S.checks.r_cmd_check && !platforms()) { open(0); $('#minRNote').textContent = 'Choose at least one R version for R CMD check.'; $('[data-matrix]').focus(); return false; }
  return true;
}

['pkg', 'what', 'details', 'first', 'last', 'email', 'owner'].forEach((id) => $(`#${id}`).addEventListener('input', () => { put(id, ''); missing(); }));
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
    ciReport: S.ciReport, licence: S.licence,
    checklists: chosenStages().map((row) => row.key),
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
$('#nextChange').addEventListener('click', () => (mode === 'existing' ? view('existing', $('#exDownload')) : view('main', custom ? $('#modify') : $('#download'))));
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
$('#exModify').addEventListener('click', () => { paint(); goStep(2); });

function existingValid() {
  const name = nameProblem(v('exPkg'), 'Add your package\'s name, as in its DESCRIPTION file.');
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
$('#exBack').addEventListener('click', () => {
  mode = 'new';
  $('#planNote').textContent = changed ? 'Your own settings were reset to the plan\'s.' : '';
  S = recommended();
  changed = false;
  paint();
  view('main', $('#pkg'));
});

/* the page after the download */
const copy = (text, block) => `<div class="cmd${block ? ' block' : ''}"><code>${esc(text)}</code><button type="button" class="copy" data-copy="${esc(text)}">Copy</button></div>`;
const code = (t) => `<code>${esc(t)}</code>`;
const finderNote = 'On a Mac, Finder hides folders whose name starts with a dot, such as .github: press Cmd+Shift+. to see them.';
const setupButton = 'On GitHub, go to Actions, open <em>Set up this repository</em>, click Run workflow, untick <em>Only show what would change</em>, and run it.';
const setupMore = "Its first run, from your push, only listed what it would make. This run makes your labels and checklists. Labels that aren't launchR's, such as GitHub's own and any you made, stay. To remove them, also tick <em>Also remove labels that aren't launchR's</em>; Dependabot's labels are kept.";
/* the step on GitHub's Actions page: the checks that run on the push, then Set up this repository; one step when both apply */
const actionsStep = (checksRun, github) => {
  if (checksRun && github) return [step('Open the repository on GitHub and go to Actions: your checks are running. Then open <em>Set up this repository</em>, click Run workflow, untick <em>Only show what would change</em>, and run it.', '', setupMore)];
  if (checksRun) return [step('Open the repository on GitHub and go to Actions: your checks are running.')];
  return github ? [step(setupButton, '', setupMore)] : [];
};
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
  const list = [step(`Unzip ${code('launchR-files.zip')} and copy what's inside into your package folder. ${finderNote}`, '', `Nothing in ${code('R/')} or ${code('tests/')} changes; ${code('DESCRIPTION')} gets only the line below, if one is shown.`)];
  list.push(step(`Add these lines to ${code('.Rbuildignore')}, if they aren't there yet.`, copy(ignoreLines().join('\n'), true), 'They keep these files out of the built package, so R CMD check does not note them as unexpected hidden files or folders.'));
  const settings = ['.lintr', 'air.toml', 'codecov.yml'].filter((file) => file in buildPackage(choices(), bundle));
  if (settings.length) list.push(step(`If your package already has ${settings.map(code).join(', ')}, keep yours instead of the copy in the zip.`, '', 'The checks read these settings files. Copying over yours would replace your own lint, formatting or coverage settings; merge in only the lines you want.'));
  if (add.ci) list.push(step(`Delete any old files in ${code('.github/workflows')} that do the same job.`, '', `If your package already has ${code('.github/workflows/README.md')}, keep yours and copy in only the new rows from the one in the zip.`));
  if (add.ci && release() === 'internal') list.push(step(`Add this line to ${code('DESCRIPTION')}.`, copy('Config/quality-gate/target: internal'), "Your package won't go to CRAN, so the checks then leave out what only CRAN asks for."));
  list.push(step("Commit and push, from RStudio's Git pane or GitHub Desktop."));
  list.push(...actionsStep(add.ci && CHECKS.some(([k]) => S.checks[k]), add.github));
  $('#stepList').innerHTML = list.join('');
  $('#nextAfter').innerHTML = after([
    add.ci && ['Run the checks on your computer', `Before a pull request, follow <em>Run the checks on your computer</em> in ${code('.github/workflows/README.md')}.${S.checks.lint ? ` The style step needs <a href="https://posit-dev.github.io/air/" target="_blank" rel="noopener">Air</a>${S.frontend && mode === 'new' ? ', and <a href="https://biomejs.dev" target="_blank" rel="noopener">Biome</a> for the JS and CSS' : ''}: install ${S.frontend && mode === 'new' ? 'them' : 'it'} once.` : ''}${S.frontend && mode === 'new' ? ' The browser tests need Google Chrome.' : ''}`],
    ['Later', `${add.ci ? codecov() : ''}To add anything else, come back here and choose only that.`],
  ]);
}

/* After that: a few short bullets, each with a word in bold */
const after = (items) => `<h3>After that</h3><ul>${items.filter(Boolean).map(([lead, text]) => `<li><b>${lead}.</b> ${text}</li>`).join('')}</ul>`;
const listWords = (names) => names.map((name) => `<em>${esc(name)}</em>`).join(names.length > 2 ? ', ' : ' and ').replace(/, (?=[^,]*$)/, ' and ');

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
  const checksRun = CHECKS.some(([k]) => S.checks[k]);
  const label = (text) => `<p class="cmd-label">${text}</p>`;
  const list = route === 'desktop' ? [
    step(`${unzip} Then, in RStudio, choose Build, then Test Package, to see your first test pass; in Positron, run ${code('devtools::test()')} in the console.`, '', `The first time, install the tools: in RStudio choose Tools, then Install Packages, and install ${code('devtools')}; in Positron, run ${code('install.packages("devtools")')}. Skip this if you already have it.`),
    step('Install <a href="https://desktop.github.com" target="_blank" rel="noopener">GitHub Desktop</a> and sign in with your GitHub account.', '', 'It brings Git with it. Skip this if you already use it.'),
    step(`In GitHub Desktop, choose File, then Add local repository, pick the ${code(name)} folder, and accept when it offers to create the repository.`),
    step(`Click Publish repository. ${priv ? 'Leave Keep this code private ticked.' : 'Untick Keep this code private.'} If ${code(owner)} is an organisation, pick it under Organization.`, '', `Already made the repository on GitHub? Keep it empty (no README or licence) and, in place of Publish repository, choose Repository, then Repository settings, paste ${code(`https://github.com/${owner}/${name}.git`)} as the remote, save, and click Publish branch. If it already has files, delete it on GitHub first, or come back and press <em>Already have a package?</em>.`),
    ...actionsStep(checksRun, S.github),
  ] : [
    step(`${unzip} Then, in the R console, install the tools (skip any you already have) and run your first test.`,
      `${copy('install.packages(c("devtools", "gitcreds", "pak"))')}${copy('pak::local_install_dev_deps()')}${copy('devtools::test()')}`,
      'devtools brings usethis and testthat. The second line installs the packages your package uses. In RStudio, Build, then Test Package, does the same as the third line.'),
    step('Let R talk to GitHub, once. Skip this if R already can.',
      `${copy('usethis::create_github_token()')}${copy('gitcreds::gitcreds_set()')}`,
      `The first line opens a GitHub page with the right boxes already ticked: scroll down, click Generate token, and copy the token. The second asks for it: paste it there. It is kept in your computer's password store (Keychain on a Mac, Credential Manager on Windows), where usethis and pak find it. Don't save it in a file such as ${code('.Renviron')}: that is plain text. If it says a login is already saved, choose <em>Replace these credentials</em>.`),
    step('Put the package on GitHub: run the first line and answer yes to each question; after RStudio restarts, run the line for your account.',
      `${copy('usethis::use_git()')}${label('Your own account:')}${copy(`usethis::use_github(private = ${privArg})`)}${label('An organisation, such as a company\'s:')}${copy(`usethis::use_github(organisation = "${owner}", private = ${privArg})`)}`,
      `The first line asks to commit your files and then to restart RStudio; the yes answer moves around, so read each one. ${code('DESCRIPTION')} already links to ${code(`github.com/${owner}/${name}`)}, so the repository should be made there. Already made the repository on GitHub? Keep it empty (no README or licence) and, in place of ${code('use_github()')}, run ${code(`usethis::use_git_remote("origin", "https://github.com/${owner}/${name}.git")`)} and then ${code('gert::git_push(set_upstream = TRUE)')}. If it already has files, delete it on GitHub first, or come back and press <em>Already have a package?</em>.`),
    ...actionsStep(checksRun, S.github),
  ];
  $('#stepList').innerHTML = list.join('');
  // The checklists Set up this repository opens on its first run (cli/R/github.R open_stages), and the ones that wait.
  const now = openNow();
  /* QC has no stage of its own: it adds its sections to Next release, so it never "arrives" */
  const qc = chosenStages().some((row) => row.key === 'qc');
  const later = chosenStages().map((row) => row.stage).filter((stage) => !now.includes(stage) && stage !== lists.settings.qc_stage);
  const email = v('email') ? '' : `Replace the placeholder email in ${code('DESCRIPTION')} before you release. `;
  $('#nextAfter').innerHTML = after([
    S.github && (now.length || later.length || qc) && ['Your checklists', `${now.length ? `${listWords(now)} ${now.length === 1 ? 'opens' : 'open'} in your repository's issues on the first run of Set up this repository.` : ''}${later.length ? ` ${listWords(later)} ${later.length === 1 ? 'opens' : 'open'} on a later run, once ${later.length === 1 ? 'its' : 'their'} stage arrives.` : ''}${qc ? ' QC adds its sections to each Next release checklist.' : ''}`],
    S.github && ['Keep them up to date', `Run <em>Set up this repository</em> on GitHub again at any time: it ticks the boxes it can check and opens each checklist when its stage arrives. A few boxes are repository settings you change by hand; each says where. From R instead: with ${gh} installed and signed in, run ${code(setup)}.`],
    checksRun && ['Run the checks on your computer', `Before a pull request, follow <em>Run the checks on your computer</em> in ${code('.github/workflows/README.md')}.${S.checks.lint ? ` The style step needs <a href="https://posit-dev.github.io/air/" target="_blank" rel="noopener">Air</a>${S.frontend && mode === 'new' ? ', and <a href="https://biomejs.dev" target="_blank" rel="noopener">Biome</a> for the JS and CSS' : ''}: install ${S.frontend && mode === 'new' ? 'them' : 'it'} once.` : ''}${S.frontend && mode === 'new' ? ' The browser tests need Google Chrome.' : ''}`],
    ['Later', `${email}${codecov()}To add a website or anything else, come back here and choose only that.`],
  ]);
}

$('#routes').addEventListener('change', steps);
$('#nextView').addEventListener('click', (e) => {
  const b = e.target.closest('.copy');
  if (!b) return;
  Promise.resolve(navigator.clipboard?.writeText(b.dataset.copy) ?? Promise.reject()).then(() => { b.textContent = 'Copied'; }, () => { b.textContent = 'Select it'; });
  setTimeout(() => { b.textContent = 'Copy'; }, 1400);
});

/* page.js writes the plan's release words beside the form; the plan line under the cards repeats them */
new MutationObserver(summary).observe($('#pvRelease'), { childList: true, characterData: true, subtree: true });
dialog.addEventListener('close', () => {
  if (mode === 'existing' && lists) { S = recommended(); changed = false; paint(); }
  mode = 'new';
  view('main');
});

/* the shared preview window: one entry shown at a time, chosen from the list; a Preview link opens it at its section */
const peekWin = $('#peek');
function showPeek(target) {
  $$('#peek [data-peek]').forEach((el) => {
    const on = el.dataset.peek === target;
    if (el.tagName === 'BUTTON') el.setAttribute('aria-current', String(on)); else el.hidden = !on;
  });
  $('#peek .peek-pane').scrollTop = 0;
}
document.addEventListener('click', (e) => {
  /* a Preview link in the form, or the landing page's SKILL.md link (its address stays for agents and without script) */
  const link = e.target.closest('.peek-link, a[data-open]');
  if (link) { e.preventDefault(); showPeek(link.dataset.open); peekWin.showModal(); $(`#peek button[data-peek="${link.dataset.open}"]`)?.focus(); return; }
  const item = e.target.closest('#peek button[data-peek]');
  if (item) showPeek(item.dataset.peek);
});
$('#peekClose').addEventListener('click', () => peekWin.close());
peekWin.addEventListener('click', (e) => { if (e.target === peekWin) peekWin.close(); });

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
      paintMain();
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
