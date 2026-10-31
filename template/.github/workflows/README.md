# How CI works here

Each file in this folder is one check. The check itself lives in the launchR repository and this file only says when
and where it runs, so it stays short. Nothing needs installing: GitHub runs these by itself.

| File | What it does |
| --- | --- |
| `r-cmd-check.yaml` | R CMD check, the core check |
| `lint.yaml` | Style, docs in sync and spelling |
| `no-suggests.yaml` | Checks the package works without its optional packages |
| `secret-scan.yaml` | Catches passwords and tokens committed by mistake |
| `coverage.yaml` | Measures how much code your tests run |
| `full-tests.yaml` | Runs every test, including browser and snapshot tests that CRAN skips |
| `extended-tests.yaml` | A full check on other systems, including any detailed tests you have marked |

Your package may not have all of these. The kit's guides list them, and a missing file means that check is off.

## Changing a check

- **Which branches or times:** edit the `on:` block at the top of the file. Times are UTC.
- **Which systems and R versions:** edit `platforms` under `with:`.
- **Turn a check off:** delete its file.
- **Keep a check but run it only by hand:** keep only `workflow_dispatch:` under `on:`.

Scheduled runs use the default branch only, and GitHub pauses them on public repositories after 60 days with no activity.

## Updates

Dependabot opens a pull request when the kit has a new version, and changes only the `@v...` part of these files.

- To decline one version, close the pull request.
- To stop for good, comment `@dependabot ignore this dependency` on it, or delete `.github/dependabot.yml`.

Your CI keeps working on the old version either way.

## Leaving the kit

To keep your own copy of the checks, for example if your organisation blocks outside workflows, run the kit's `eject`
command. The checks then live in this repository and nothing depends on the kit.
