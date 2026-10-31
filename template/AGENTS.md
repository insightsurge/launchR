# {{package}}

Rules for everyone working in this repository, person or AI.

- Every exported function has `@returns` and an offline `@examples`, written in roxygen2.
- `man/` and `NAMESPACE` come from `devtools::document()`, never from hand edits.
- Add a test for every change and a `NEWS.md` line for anything users see.
- Add a package to `DESCRIPTION` before using it, and call it as `pkg::fn()`.
- CI runs from `.github/workflows/`. Read the README there before changing a check.
- Keep this file short: all of it loads in every AI session.
