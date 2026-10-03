# A new R process loads this exact checkout, not an installed older package.
audit_fresh <- function(code, args) {
  root <- normalizePath(testthat::test_path("..",".."))
  script <- tempfile(fileext=".R"); result <- tempfile(fileext=".rds")
  log <- tempfile(fileext=".log")
  on.exit(unlink(c(script,result,log)))
  writeLines(c(
    sprintf(".libPaths(%s)",paste(deparse(.libPaths()),collapse="")),
    sprintf("pkgload::load_all(%s, quiet=TRUE)", deparse(root)),
    sprintf("args <- %s",paste(deparse(args),collapse="")),
    paste0("result <- local({",code,"})"),
    sprintf("saveRDS(result,%s)",deparse(result))),script)
  status <- system2(file.path(R.home("bin"),"Rscript"),shQuote(script),stdout=log,stderr=log)
  if (status != 0L) stop(paste(readLines(log,warn=FALSE),collapse="\n"))
  readRDS(result)
}

