// Writes a real zip the way the app does, then checks unzip reads it and that the hidden files are inside.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import JSZip from '../site/node_modules/jszip/lib/index.js';
import { readBundle } from '../site/scripts/bundle-kit.mjs';
import { buildPackage, defaultChoices, readLists } from '../site/src/form/engine.js';

const bundle = readBundle();
const choices = { ...defaultChoices(readLists(bundle)), package: 'zippkg', title: 'Zip Tools', given: 'Asha', family: 'Rao', email: 'a@example.com', owner: 'sample-org' };
const zip = new JSZip();
for (const [path, text] of Object.entries(buildPackage(choices, bundle))) zip.file(`zippkg/${path}`, text);
const out = mkdtempSync(join(tmpdir(), 'kit-zip-'));
writeFileSync(join(out, 'zippkg.zip'), await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
execFileSync('unzip', ['-q', 'zippkg.zip'], { cwd: out });
const listing = execFileSync('ls', ['-A', 'zippkg'], { cwd: out, encoding: 'utf8' }).split('\n');
for (const hidden of ['.github', '.gitignore', '.Rbuildignore', '.lintr']) {
  if (!listing.includes(hidden)) throw new Error(`Missing ${hidden}`);
}
console.log(`Zip unpacked with ${listing.length - 1} top-level items, hidden files included: ${out}`);
