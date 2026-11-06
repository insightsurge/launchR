// Builds the same choices through the CLI and through the app's engine, and compares every file.
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readBundle } from '../site/scripts/bundle-kit.mjs';
import { buildPackage, defaultChoices, readLists } from '../site/src/form/engine.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const bundle = readBundle();
const lists = readLists(bundle);
const out = mkdtempSync(join(tmpdir(), 'kit-compare-'));
const base = { title: 'Sample Tools For Tables', author: ['Asha', 'Rao'], email: 'asha@example.com', year: '2026' };
// Every plan with both presets, from the defaults both routes read (lists/plans.tsv, settings.tsv), plus one case with
// no email and a title ending in a full stop, which both routes tidy the same way.
const cases = lists.plans.flatMap(({ plan }) => ['starter', 'everything'].map((preset) => ({
  name: `${plan}-${preset}`, plan, preset, flags: ['--plan', plan, '--preset', preset],
})));
cases.push({ name: 'no-email', plan: 'd', preset: 'starter', flags: ['--plan', 'd'], title: 'Tools For Tables.', email: '' });
cases.push({ name: 'min-r', plan: 'a', preset: 'everything', flags: ['--plan', 'a', '--preset', 'everything', '--min-r', '4.3'], minR: '4.3' });
cases.push({ name: 'min-r-private', plan: 'c', preset: 'starter', flags: ['--plan', 'c', '--min-r', '4.4'], minR: '4.4' });
cases.push({ name: 'description', plan: 'd', preset: 'starter', flags: ['--plan', 'd', '--description', 'Builds   tables for clinical reports'], description: 'Builds   tables for clinical reports' });
// The Modify choices (issue 21): each through the CLI's flags and the engine's choices.
cases.push({ name: 'modify-public', plan: 'a', preset: 'everything',
  flags: ['--plan', 'a', '--preset', 'everything', '--no-ci-report', '--badges', 'check,codecov,cran,downloads,universe,launchr', '--navbar', 'reference,search', '--forms', 'bug,docs', '--labels', 'priority: high'],
  extra: { ciReport: false, badges: ['check', 'codecov', 'cran', 'downloads', 'universe', 'launchr'], navbar: ['reference', 'search'], forms: ['bug', 'docs'], labels: ['priority: high'] } });
cases.push({ name: 'modify-private', plan: 'c', preset: 'everything',
  flags: ['--plan', 'c', '--preset', 'everything', '--licence', 'mit', '--qc', '--badges', 'lifecycle,cran', '--forms', 'none', '--labels', 'none'],
  extra: { licence: 'mit', checklists: ['before-public', 'after-public', 'before-cran', 'after-acceptance', 'next-release', 'qc'], badges: ['lifecycle', 'cran'], forms: [], labels: [] } });
cases.push({ name: 'modify-no-qc', plan: 'd', preset: 'starter', flags: ['--plan', 'd', '--no-qc', '--licence', 'mit', '--badges', 'none'],
  extra: { checklists: [], licence: 'mit', badges: [] } });
cases.push({ name: 'checklists', plan: 'a', preset: 'everything', flags: ['--plan', 'a', '--preset', 'everything', '--checklists', 'after-public,next-release'],
  extra: { checklists: ['after-public', 'next-release'] } });
// One case per setup the user journeys use, with the Modify choices that journey makes. Beginner defaults is a-starter
// above. The CLI picks parts by preset only, so "website without the AI and front-end parts" and "CI files only" can't
// be built by both routes, and a frozen (snapshot) setup doesn't exist yet: those three are not here.
const journeys = [
  { name: 'journey-open-source-site', plan: 'a', preset: 'everything',
    flags: ['--badges', 'check,lifecycle,cran,downloads', '--navbar', 'reference,news,articles,search,github'],
    extra: { badges: ['check', 'lifecycle', 'cran', 'downloads'], navbar: ['reference', 'news', 'articles', 'search', 'github'] } },
  { name: 'journey-web-component', plan: 'a', preset: 'everything',
    flags: ['--min-r', '4.3', '--badges', 'check,lifecycle,codecov', '--labels', 'bug,enhancement,documentation'],
    extra: { minR: '4.3', badges: ['check', 'lifecycle', 'codecov'], labels: ['bug', 'enhancement', 'documentation'] } },
  { name: 'journey-public-no-cran', plan: 'b', preset: 'everything',
    flags: ['--licence', 'mit', '--badges', 'check,lifecycle,universe', '--navbar', 'reference,news,search,github,lightswitch'],
    extra: { licence: 'mit', badges: ['check', 'lifecycle', 'universe'], navbar: ['reference', 'news', 'search', 'github', 'lightswitch'] } },
  { name: 'journey-polish-first', plan: 'c', preset: 'starter',
    flags: ['--qc', '--forms', 'bug,feature,docs', '--badges', 'check,lifecycle'],
    extra: { checklists: ['before-public', 'after-public', 'before-cran', 'after-acceptance', 'next-release', 'qc'], forms: ['bug', 'feature', 'docs'], badges: ['check', 'lifecycle'] } },
  { name: 'journey-company', plan: 'd', preset: 'starter',
    flags: ['--licence', 'proprietary', '--badges', 'none', '--forms', 'bug,docs', '--labels', 'bug,documentation,chore', '--no-ci-report'],
    extra: { licence: 'proprietary', badges: [], forms: ['bug', 'docs'], labels: ['bug', 'documentation', 'chore'], ciReport: false } },
];
for (const j of journeys) cases.push({ ...j, flags: ['--plan', j.plan, '--preset', j.preset, ...j.flags] });
let failed = 0;
for (const item of cases) {
  const r = join(out, item.name, 'r');
  const title = item.title ?? base.title;
  const email = item.email ?? base.email;
  execFileSync('Rscript', [
    join(root, 'cli', 'launchr.R'), 'new', 'samplepkg', '--yes', '--title', title, '--author', base.author.join(' '),
    ...(email ? ['--email', email] : []), '--owner', 'sample-org', '--year', base.year, '--no-git', '--path', r, ...item.flags,
  ], { stdio: 'ignore' });
  const choices = { ...defaultChoices(lists, item.preset, item.plan), package: 'samplepkg', title, given: base.author[0],
    family: base.author[1], email, owner: 'sample-org', year: base.year, ...(item.minR ? { minR: item.minR } : {}),
    ...(item.description ? { description: item.description } : {}), ...(item.extra ?? {}) };
  const js = join(out, item.name, 'js');
  const files = buildPackage(choices, bundle);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(js, path)), { recursive: true });
    writeFileSync(join(js, path), text);
  }
  const diff = spawnSync('diff', ['-r', r, js], { encoding: 'utf8' });
  console.log(`${diff.status === 0 ? 'SAME' : 'DIFFERENT'} ${item.name}: ${Object.keys(files).length} files`);
  if (diff.status !== 0) {
    failed += 1;
    console.log(diff.stdout.slice(0, 1500));
  }
}
process.exit(failed);
