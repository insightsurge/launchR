# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

R developers, many in regulated industries such as pharma, many of whom avoid the terminal. The first reader is someone starting a new R package who has not set up tests, CI or GitHub before and wants it done properly. A second reader already has a package and wants ready-made CI with a quality gate instead of writing their own. A third works on a private company package, where GitHub minutes cost money and CRAN does not matter, and may need CI frozen so nothing changes under a validated process.

## Product Purpose

launchR sets up new R packages and offers ready-to-use CI to existing ones. A person answers a few questions, including what they plan for the package, and downloads a zip named after their package, with tests, CI and GitHub files in place, then follows next steps to put it on GitHub. Success is a package that passes its checks on day one, set up by someone who never opened a terminal.

## Positioning

A properly set up R package from a form, with no terminal and nothing to delete afterwards. The result is an ordinary package that never needs the site again, and the zip is built in the visitor's browser.

## Operating Context

- People arrive from search or AI answers, on a work computer, often with RStudio or Positron open.
- After the zip they open the package in RStudio or Positron, then choose a route to GitHub: with R (`usethis`), or without typing.
- Terminal users have a separate route through the CLI, which makes the same files.
- People come back months later to add a website or go public. They should be asked only the new choice.

## Capabilities and Constraints

- The setup asks four things: name, description, author (first and last name) and plan. Email is optional, and nothing should look like signing in. The plan is one of four: public and going to CRAN; public, not going to CRAN; private now, public and CRAN later; private for good.
- Everything else sits under Modify and appears only when it applies: shared CI or a snapshot, checks, platforms, schedule, PR report, JS or CSS in the package, website options, GitHub setup and badges. AI instruction files are shown as coming soon.
- A private-for-good package gets no release features. Planned: it gets one QC checklist, which does not exist in the kit yet.
- Someone with a package already picks what to add, such as CI, a website or checklists. Nothing in `R/`, `tests/` or `DESCRIPTION` changes.
- Pasting a public GitHub link shows what is missing and fills in the choices. It reads public files from the visitor's browser, is limited to 60 GitHub calls an hour per visitor, and is designed now but built after the basic setup works. Private repositories use the CLI.
- The kit supports GitHub only.
- The zip is built in the browser. Nothing typed leaves the browser, and there is no server.
- The site is Astro. Hosting is planned on Firebase; the final address is not decided.
- The site has no guides section: articles live in the R Engineering Playbook, which the site links to. The site itself must still work for search engines and AI citation, with structured data, a sitemap and `llms.txt`.
- Form logic shared with tests lives in `site/src/form/engine.js`. It stays free of page layout and must produce exactly what the CLI produces.

## Brand Commitments

- The look is calm, precise and drawn by a person. It must never look AI-generated.
- The Start control sits inside the animation and grows into the form. No other text sits on the animation.
- Space Grotesk is the only typeface, apart from monospace for file names.
- Two themes, Paper (light) and Ember (dark), with a light and dark switch in the navbar that follows the system setting until the visitor chooses.
- The page wording is approved. Change it only when the owner asks.
- InsightSurge is named as the maker, with an author section. No data is collected, and the site says so.
- launchR is MIT licensed.
- "Coming soon" appears on only a few items. Nothing is marked paid.

## Evidence on Hand

- Real product material: the form itself, the generated file tree and the list of CI checks.
- No testimonials, user numbers, customer names or benchmarks exist. Never invent them.

## Product Principles

- The recommended setup comes first. Changing it is possible and never required.
- Ask what the person plans, not only what is true today.
- Say what will happen before it happens, in plain sentences.
- Never strand someone who avoids the terminal: every step has a route without typing.
- What the visitor downloads is theirs, with nothing left over to delete.

## Accessibility & Inclusion

Labelled controls, visible focus, text contrast of at least 4.5:1, nothing signalled by colour alone, and a reduced-motion path. Works at phone width with no sideways scrolling.
