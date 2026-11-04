// Copies the shared template and lists into the site as one file, so the browser builds the zip from what the CLI uses.
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const walk = (folder) =>
  readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });

// Text with \n line endings and keys with / whatever the system, as cli/R/paths.R reads files: a checkout with Windows
// line endings or backslash paths builds the same package.
const readText = (path) => readFileSync(path, 'utf8').replaceAll('\r\n', '\n');
const key = (base, path) => relative(base, path).split(sep).join('/');

export function readBundle() {
  const template = {};
  for (const path of walk(join(root, 'template'))) {
    template[key(join(root, 'template'), path)] = readText(path);
  }
  const lists = {};
  for (const name of readdirSync(join(root, 'lists'))) {
    lists[name] = readText(join(root, 'lists', name));
  }
  return { template, lists };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = join(root, 'site', 'public', 'kit');
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'bundle.json'), JSON.stringify(readBundle()));
}
