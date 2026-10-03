#!/usr/bin/env Rscript
# Run from checkout root. Every assertion is evaluated; any failure exits 1.
args <- commandArgs(trailingOnly=TRUE)
groups <- c("geometry","io","mask","persistence","app")
if (length(args) != 1L || !args %in% groups) {
  stop("Usage: Rscript tests/audit/run-regressions.R <geometry|io|mask|persistence|app>")
}
cat("COMMAND: Rscript tests/audit/run-regressions.R",args,"\n")
cat("REVISION:",system2("git",c("rev-parse","HEAD"),stdout=TRUE),"\n")
cat("R:",R.version.string,"\n")
cat("PLATFORM:",R.version$platform,"\n")
for (pkg in c("pkgload","testthat","sf","stars","terra","tiff","shiny","ggplot2","magick")) {
  version <- if (requireNamespace(pkg,quietly=TRUE)) as.character(packageVersion(pkg)) else "unavailable"
  cat("DEPENDENCY:",pkg,version,"\n")
}
if (requireNamespace("sf",quietly=TRUE)) print(sf::sf_extSoftVersion())
testthat::set_max_fails(Inf)
results <- testthat::test_local(filter=paste0("^audit-",args,"$"),
                                 reporter="silent",stop_on_failure=FALSE)
for (case in results) {
  cat("\nTEST:",case$test,"\n")
  for (result in case$results) {
    if (inherits(result,"expectation_success")) next
    cat("RESULT:",class(result)[1],"\n",conditionMessage(result),"\n")
  }
}
df <- as.data.frame(results)
cat(sprintf("\nTOTAL: tests=%d failed_assertions=%d error_cases=%d warnings=%d skipped=%d passed_assertions=%d\n",
            nrow(df),sum(df$failed),sum(df$error),sum(df$warning),sum(df$skipped),sum(df$passed)))
quit(status=if (any(df$failed > 0L | df$error)) 1L else 0L)
