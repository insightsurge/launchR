# Checks

- **The pass mark is CRAN's:** R CMD check with 0 errors, 0 warnings and 0 notes. On top of that: style (Air, lintr,
  and Biome when there is a `biome.json`), help pages in sync with roxygen, a documented return value for every export,
  spelling, tests, coverage, a test for every new R line, a check without the `Suggests` packages, and a secret scan.
- **Tools on your computer:** the R packages the checks need are listed in `.github/workflows/README.md`. Air (R
  formatting) and Biome (JS and CSS, only with a `biome.json`) are separate programs, not R packages: install them from
  <https://posit-dev.github.io/air/> and <https://biomejs.dev>. When one is missing, say which and ask before
  installing it.
- **CI** runs these on every pull request, one file per check in `.github/workflows/`; its `README.md` says what each
  does and how to change one.
- **Before a pull request,** run the quality gate in `full` mode ("Run the checks on your computer" in
  `.github/workflows/README.md`). It prints one PASS, FAIL or SKIP line per step. Without it, run at least
  `devtools::document()`, `devtools::test()`, `devtools::check()` and `air format .`.
- **Reading the gate:** exit 0 passed; 1 a step failed (start with the first FAIL line and its log); 2 it couldn't
  judge the package, for example a missing tool or package: name it and ask before installing anything; 3 the only
  failures passed when re-run (a probable flake): not a pass, say so. A partial run (`--steps`, `--filter`,
  `--no-coverage`) is not evidence that a pull request is ready.
- **Don't make a check pass by weakening it.** Without being asked, don't edit workflow files, their `@v` versions or
  `permissions:` blocks, `.lintr`, `air.toml` or the coverage limit, and don't add `# nolint`,
  `# nocov` or `skip()`. Explain the failure instead.
- **A new file or folder at the top level** goes in `.Rbuildignore` if it doesn't belong in the built package;
  otherwise R CMD check notes it, and a note fails.
- **Code and tests work without the `Suggests` packages;** a job checks this.
- **Secrets:** a found secret is removed and its key rotated. `gitleaks:allow` is only for a false alarm.
