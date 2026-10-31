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
const cases = [
  { name: 'everything', flags: ['--owner', 'sample-org'], set: { owner: 'sample-org' } },
  { name: 'public', flags: ['--owner', 'sample-org', '--public'], set: { owner: 'sample-org', visibility: 'public' } },
  { name: 'internal', flags: ['--owner', 'sample-org', '--internal'], set: { owner: 'sample-org', release: 'internal' } },
  { name: 'noowner', flags: [], set: {} },
  { name: 'starter', flags: ['--owner', 'sample-org', '--preset', 'starter'], set: { owner: 'sample-org' }, preset: 'starter' },
];
let failed = 0;
for (const item of cases) {
  const r = join(out, item.name, 'r');
  execFileSync('Rscript', [
    join(root, 'cli', 'kit.R'), 'new', 'samplepkg', '--recommended', '--title', base.title, '--author', base.author.join(' '),
    '--email', base.email, '--year', base.year, '--no-git', '--out', r, ...item.flags,
  ], { stdio: 'ignore' });
  const choices = { ...defaultChoices(lists, item.preset), package: 'samplepkg', title: base.title, given: base.author[0],
    family: base.author[1], email: base.email, year: base.year, ...item.set };
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
