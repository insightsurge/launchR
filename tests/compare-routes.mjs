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
    family: base.author[1], email, owner: 'sample-org', year: base.year, ...(item.minR ? { minR: item.minR } : {}) };
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
