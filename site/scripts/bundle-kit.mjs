// Copies the shared template and lists into the site as one file, so the browser builds the zip from what the CLI uses.
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const walk = (folder) =>
  readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });

export function readBundle() {
  const template = {};
  for (const path of walk(join(root, 'template'))) {
    template[relative(join(root, 'template'), path)] = readFileSync(path, 'utf8');
  }
  const lists = {};
  for (const name of readdirSync(join(root, 'lists'))) {
    lists[name] = readFileSync(join(root, 'lists', name), 'utf8');
  }
  return { template, lists };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = join(root, 'site', 'public', 'kit');
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'bundle.json'), JSON.stringify(readBundle()));
}
