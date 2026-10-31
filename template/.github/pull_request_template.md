<!-- Delete the sections that don't apply and keep the rest short. The contributor guide explains the workflow:
https://github.com/{{owner}}/{{package}}/blob/main/.github/CONTRIBUTING.md#workflow -->

## In brief
<!-- One plain sentence on what changes and why, then a few bullets for a reader with no context. -->

Closes #

<!-- If this is stacked on another PR, name that PR and its base branch here. -->

## What's new
<!-- One bullet per capability: what a user can do, then the function, argument or file names. Delete if none. -->

## What's fixed
<!-- The symptom, its cause and the fix, in plain words, then the relevant function or file names. Delete if none. -->

## Before and after
<!-- A small example, table or screenshot showing the change. Delete if nothing a user can see or run changes. -->

## Try it
<!-- Numbered scenarios: the R snippet or command to run, then what should happen.
For a visual change, give the browser and version and the steps. Delete if nothing can be tried. -->

## Details
<!-- Only details needed to review the change, such as a changed default, compatibility or a deprecation plan.
Delete if the sections above cover it. -->

## Not in this PR
<!-- Known limits and follow-ups, with issue numbers where you have them. Delete if none. -->

## Checks
<!-- For each command you ran, report its result and any failing or skipped step.
Name checks you did not run and why. Do not mark an unrun check as passed.
Only repeatable checks belong in the table; one-off observations go in Notes below.
CI runs the full checks on this pull request; local results do not replace it. -->

| Command | Result, or not run and why |
| --- | --- |
| `devtools::document()` | |
| `devtools::test()` | |
| `devtools::check()` | |

<!-- Keep the items that apply. Tick only completed items; leave pending work unticked. -->

- [ ] The linked issue's "done when" list is met.
- [ ] I have reviewed the whole diff, understand the changes and can explain the checks reported above.
- [ ] A suggested type label is named in Notes (`enhancement`, `bug`, `documentation` or `chore`); the maintainer applies it, and the release notes are built from it.
- [ ] A user-facing change has a `NEWS.md` bullet.
- [ ] New behaviour and each fixed bug have a test.
- [ ] Changes to exported functions keep their help pages, `NAMESPACE` and examples in step (`devtools::document()`).
- [ ] JavaScript and CSS changes keep meaning off colour alone and honour `prefers-reduced-motion`. Delete if there are none.
- [ ] Every text that describes the changed behaviour is updated: help pages, articles, the README, `NEWS.md`, examples, workflow comments, `AGENTS.md` and `CLAUDE.md` if the repository has them, and any other page or file that describes it. Search terms used for the old wording:

Notes: <!-- One-off observations, browser and OS versions, screenshots, suggested labels, or words for the spelling list.
Use made-up data and leave out private data, credentials and machine paths. -->
