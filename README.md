# launchR

> **Early work: not ready to use.** Names, files and workflow inputs change without notice, nothing here is released,
> and the shared workflows have only just started running on GitHub. Please don't depend on it yet.

launchR sets up R packages, and offers ready-to-use CI with a quality gate: one short YAML caller file per check
in your package, with the checks themselves kept here. This is the proof of concept.

| Folder | What it holds |
| --- | --- |
| `cli/` | The command line: `kit.R`, with the work in functions under `R/` |
| `site/` | The Astro app: landing page, form, guide. The form's logic is in `src/form/` |
| `template/` | The package files, with `{{placeholders}}` |
| `lists/` | Tab-separated lists read by both R and the app |
| `quality-gate/` | The quality gate |
| `.github/` | The reusable workflows, actions and scripts that packages call |
| `tests/` | Checks that the two routes match, the zip is sound and generated packages pass the gate |

## Try it

```bash
npm --prefix site install
npm --prefix site run dev
```

```bash
Rscript cli/kit.R new mypkg
```

## Test it

```bash
node tests/compare-routes.mjs
node tests/check-zip.mjs
tests/gate-matrix.sh
```
