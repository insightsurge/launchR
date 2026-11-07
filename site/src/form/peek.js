// What the shared preview window shows, read at build time: the stage checklists as their issues read
// (lists/checklists.tsv and lists/stages.tsv) and the issue forms as GitHub shows them (template/.github/ISSUE_TEMPLATE/).
// Runs in Setup.astro's frontmatter only, never in the browser.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(process.cwd(), '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');

function tsv(name) {
  const lines = read('lists', name).split('\n').filter((line) => line && !line.startsWith('#'));
  const header = lines.shift().split('\t');
  return lines.map((line) => Object.fromEntries(line.split('\t').map((cell, i) => [header[i], cell ?? ''])));
}

// What a box needs before it appears, in words (the needs column holds a path).
const NEEDS = {
  '.github/workflows': 'with CI',
  '.github/workflows/r-cmd-check.yaml': 'with R CMD check',
  '.github/workflows/coverage.yaml': 'with the coverage check',
  '_pkgdown.yml': 'with a website',
};

// The QC choice has no issue of its own: its boxes (release qc) are sections of the Next release issue, so its preview
// shows those, and the Next release preview leaves them out.
export function checklists() {
  const rows = tsv('checklists.tsv');
  return tsv('stages.tsv').map((stage) => {
    const qc = stage.key === 'qc';
    const sections = [];
    const shown = rows.filter((r) => (qc ? r.release === 'qc' : r.stage === stage.stage && r.release !== 'qc'));
    for (const row of shown) {
      let section = sections.find((s) => s.name === row.section);
      if (!section) sections.push((section = { name: row.section, boxes: [] }));
      section.boxes.push({
        text: row.text,
        where: row.where,
        pick: row.pick,
        auto: !['manual', 'group'].includes(row.kind),
        cran: row.release === 'cran',
        optional: row.optional === 'yes',
        sub: shown.some((r) => r.id === row.parent),
        needs: NEEDS[row.needs] ?? '',
      });
    }
    return { key: stage.key, stage: stage.stage, title: qc ? 'Added to Checklist: Next release' : `Checklist: ${stage.stage}`, opens: stage.opens, sections };
  });
}

// The issue forms: the few YAML shapes the templates use (name, description, and body items with attributes and
// validations), read line by line. Template blocks are resolved as for a public package without JS or CSS.
function template(text) {
  const out = [];
  const skip = [];
  for (const line of text.split('\n')) {
    const block = line.match(/^\{\{([#^/])(\w+)\}\}$/);
    if (block) {
      if (block[1] === '/') skip.pop();
      else skip.push(block[1] === '#'); // {{#x}} is for a choice this preview leaves off; {{^x}} for one it keeps
      continue;
    }
    if (!skip.includes(true)) out.push(line);
  }
  return out.join('\n').replaceAll('{{package}}', 'yourpkg');
}

const unquote = (value) => value.trim().replace(/^'(.*)'$/, '$1').replace(/^"(.*)"$/, '$1');

function parseForm(text) {
  const lines = template(text).split('\n');
  const form = { name: '', description: '', body: [] };
  let item = null;
  let block = null; // [object, key, indent]
  for (const line of lines) {
    const indent = line.length - line.trimStart().length;
    if (block && (line.trim() === '' || indent > block[2])) {
      block[0][block[1]] += (block[0][block[1]] ? '\n' : '') + line.slice(block[2] + 2);
      continue;
    }
    block = null;
    const top = line.match(/^(name|description): (.*)$/);
    if (top) { form[top[1]] = unquote(top[2]); continue; }
    const start = line.match(/^ {2}- type: (\w+)/);
    if (start) { form.body.push((item = { type: start[1], required: false })); continue; }
    const pair = line.match(/^ {6}(\w+): ?(.*)$/);
    if (item && pair) {
      if (pair[1] === 'required') item.required = pair[2].trim() === 'true';
      else if (pair[2].trim() === '|') { item[pair[1]] = ''; block = [item, pair[1], indent]; }
      else item[pair[1]] = unquote(pair[2]);
    }
  }
  for (const part of form.body) for (const key of ['value', 'description']) if (part[key]) part[key] = part[key].trim();
  return form;
}

export function issueForms() {
  return tsv('forms.tsv').map((row) => ({ key: row.key, title: row.title, label: row.label, ...parseForm(read('template', '.github', 'ISSUE_TEMPLATE', row.file)) }));
}
