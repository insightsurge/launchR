# Docs

- **Help pages come from roxygen2 comments** in `R/`. Run `devtools::document()` and commit the changed `man/` files
  with the source.
- **`NEWS.md`:** one bullet per user-facing change, in the same pull request, present tense, starting with the
  function or feature and ending with the issue number: `` * `clean()` gains a `quiet` argument (#12). `` Release
  headings and version numbers belong to the maintainer.
- **Docs follow behaviour.** A change updates every text that describes it, in the same pull request: help pages,
  examples, README, articles, `NEWS.md`, CONTRIBUTING, workflow comments and these rules. It works both ways: an edited
  article or example must still agree with the help page. Search for the old wording before you finish.
- **If there is a `README.Rmd`,** edit it, not `README.md`, then run `devtools::build_readme()`.
- **Spelling:** an unknown word fails the check. List new words in the pull request; the maintainer adds agreed ones
  to `inst/WORDLIST`.
- Plain words, short sentences, made-up data in examples and screenshots.
