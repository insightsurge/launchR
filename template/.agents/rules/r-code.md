# R code

- **Every exported function** has roxygen2 docs with `@param` for each argument, `@returns`, and an `@examples` that
  runs offline in a few seconds. Internal helpers get `@noRd`.
- **Other packages:** call them as `pkg::fn()`, after adding them to `DESCRIPTION`. `Imports` for what the package
  needs; `Suggests` for what is optional, checked first with `rlang::check_installed()` or `requireNamespace()`.
  Never `library()` or `require()` in `R/`, and never `:::` into another package.
- **Ask before adding a dependency.** Prefer base R or a package already in `DESCRIPTION`.
- **Check arguments** at the top of exported functions. Error messages say what went wrong and what to do next
  (`cli::cli_abort()`).
- **Messages** go through cli (`cli::cli_inform()`, `cli::cli_warn()`), never `print()` or `cat()`; a `print()`
  method is the exception.
- **Leave the user's session as it was:** no `setwd()`, `options()`, `Sys.setenv()` or `set.seed()` without restoring
  it; use `withr::local_*()`. Write files only where the user asks, or under `tempdir()`.
- **Style:** Air formats the code (`air format .`, settings in `air.toml`; Air is installed on its own, see
  `checks.md`); lintr checks it (rules in `.lintr`).
  snake_case names, lines of at most 120 characters, `TRUE` and `FALSE` in full.
- Keep functions small and named for what they do. Comment why, not what.
