#!/usr/bin/env Rscript
# launchR's command line. All the work is in the functions under R/; this file only starts them.
#
#   Rscript cli/kit.R new mypkg     create a package; asks its questions, or use --recommended
#   Rscript cli/kit.R gate [mode]   run the quality gate in the current package
#   Rscript cli/kit.R github        show, then make, the GitHub changes (--dry-run, --yes, --repo owner/name)
#   Rscript cli/kit.R eject         copy the kit's CI into the current package

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
cli_dir <- dirname(normalizePath(script))
for (file in list.files(file.path(cli_dir, "R"), pattern = "[.]R$", full.names = TRUE)) sys.source(file, envir = globalenv())
options(kit.root = dirname(cli_dir))

status <- kit_main(commandArgs(TRUE))
quit(save = "no", status = status)
