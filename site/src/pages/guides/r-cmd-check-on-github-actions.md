---
layout: ../../layouts/Guide.astro
title: How do I run R CMD check on GitHub Actions the way CRAN does?
description: Run R CMD check with --as-cran and NOT_CRAN false on GitHub Actions, so tests behave as they do on CRAN, using one short workflow file.
updated: 2026-10-31
---

Run `R CMD check --as-cran` with the `NOT_CRAN` environment variable set to `false`, and treat any note as a failure. The `--as-cran` flag turns on CRAN's extra checks, and `NOT_CRAN=false` makes `skip_on_cran()` skip tests just as CRAN does.

## Why isn't `devtools::check()` enough?

`devtools::check()` sets `NOT_CRAN=true` by default, so tests that CRAN skips still run on your computer. A package can pass there and still behave differently on CRAN.

## What's the shortest way to set this up?

Add one file to your package as `.github/workflows/r-cmd-check.yaml`:

```yaml
name: R-CMD-check

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  check:
    uses: insightsurge/launchR/.github/workflows/r-cmd-check.yaml@v0.0.1
    with:
      platforms: ubuntu/release, windows/release, macos/release
```

Commit it and push. GitHub starts the check by itself, and there's nothing to install.

## How do I choose the systems and R versions?

Each entry in `platforms` is a system and an R version. Use `ubuntu`, `windows` or `macos`, then `release`, `devel`, `oldrel-1` or a number such as `4.1`. On a private repository, start with `ubuntu/release`, because macOS uses about ten times the minutes.

## Which R CMD check notes can I ignore?

For CRAN, plan on none. A first submission always shows a "New submission" note, and that one is expected.

## Related

- [Start a package with this CI already in place](/start)
