# launchR

launchR sets up R packages, and offers ready-to-use CI with a quality gate: one short YAML caller file per check
in your package, with the checks themselves kept here.

| Folder | What it holds |
| --- | --- |
| `cli/` | The command line: `kit.R`, with the work in functions under `R/` |
| `site/` | The Astro app: landing page and form. The form's logic is in `src/form/` |
| `template/` | The package files, with `{{placeholders}}` |
| `lists/` | Tab-separated lists read by both R and the app |
| `quality-gate/` | The quality gate |
| `.github/` | The reusable workflows, actions and scripts that packages call |
| `tests/` | Checks that the command line works, the two routes match, the zip is sound and generated packages pass the gate |

## Try it

```bash
npm --prefix site install
npm --prefix site run dev
```

```bash
Rscript cli/kit.R new mypkg
```

## Publish the site

The site is at <https://launch-r.web.app>, on Firebase Hosting. `.github/workflows/deploy-site.yaml` publishes it when
a change to the site, `template/` or `lists/` reaches `main`, or when the workflow is started by hand.

Google Analytics loads only on that address, and only after a visitor accepts it in the cookie banner. See
`site/src/consent.js`.

## Test it

```bash
Rscript tests/cli-tests.R
node tests/compare-routes.mjs
node tests/check-zip.mjs
tests/gate-matrix.sh
```

`tests/cli-tests.R` needs only base R, `jq` and git. It runs the command line against `tests/fake-gh/gh`, a stand-in for
`gh`, so it creates nothing on GitHub. It takes about a minute and a half.

## Licence

launchR is under the MIT licence (`LICENSE`). The files in `template/`, which are what end up in the packages you make,
are under the Zero-Clause BSD licence (`template-LICENSE`), which asks nothing of you. A package made with launchR
carries no conditions from either licence: no notice to keep, no credit to give. It keeps the licence you choose for it.
