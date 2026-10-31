# r-pkg-kit (proof of concept)

Sets up R packages, and offers ready-to-use CI with a quality gate. This is stage 1 of the proof of concept: everything
runs on this computer.

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
