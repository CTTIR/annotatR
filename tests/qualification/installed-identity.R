# Installed-package regression for process-local persisted identities.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript tests/qualification/installed-identity.R <library>")
}
library_path <- normalizePath(args[[1]], mustWork = TRUE)
if (!requireNamespace("tiff", quietly = TRUE)) {
  stop("The installed identity regression requires the suggested tiff package")
}

work_dir <- tempfile("annotatr-installed-identity-")
dir.create(work_dir)
on.exit(unlink(work_dir, recursive = TRUE), add = TRUE)
image_path <- file.path(work_dir, "pixels.tif")
project_path <- file.path(work_dir, "project.rds")
child_path <- file.path(work_dir, "child.R")
invisible(tiff::writeTIFF(matrix(0, 2, 2), image_path, bits.per.sample = 8L,
                          compression = "none"))

writeLines(c(
  "args <- commandArgs(trailingOnly = TRUE)",
  "library(annotatR, lib.loc = args[[1]])",
  "annotatR:::.reset_id_counter()",
  "set.seed(20260910)",
  "rng_before <- .Random.seed",
  "session <- at_session(c(args[[3]], args[[3]]), out_dir = dirname(args[[3]]))",
  "if (args[[2]] == 'save') {",
  "  image <- at_read_image(args[[3]])",
  "  snapshot <- image; snapshot$source_descriptor <- NULL; snapshot$source <- 'memory:snapshot'",
  "  project <- at_project(snapshot, entry_id = session$manifest$entry_id[[1]])",
  "  at_save_project(project, args[[4]])",
  "  loaded_pixels <- as.vector(at_tile(image))",
  "  fresh_pixels <- loaded_pixels",
  "  loaded_read <- image$read_generation",
  "  loaded_cache <- image$cache_identity",
  "} else {",
  "  project <- at_load_project(args[[4]])",
  "  annotatR:::.tile_cache_clear()",
  "  loaded_pixels <- as.vector(at_tile(project$image))",
  "  image <- at_read_image(args[[3]])",
  "  fresh_pixels <- as.vector(at_tile(image))",
  "  loaded_read <- project$image$read_generation",
  "  loaded_cache <- project$image$cache_identity",
  "}",
  "result <- list(",
  "  entry_id = session$manifest$entry_id[[1]],",
  "  export_stem = session$manifest$export_stem[[1]],",
  "  read_generation = image$read_generation,",
  "  cache_identity = image$cache_identity,",
  "  loaded_read = loaded_read,",
  "  loaded_cache = loaded_cache,",
  "  persisted_entry = project$meta$entry_id,",
  "  loaded_pixels = loaded_pixels,",
  "  fresh_pixels = fresh_pixels,",
  "  rng_unchanged = identical(rng_before, .Random.seed),",
  "  roi_id = at_roi_point(1, 1, 'label')$id",
  ")",
  "saveRDS(result, args[[5]])"
), child_path)

run_child <- function(mode) {
  output_path <- file.path(work_dir, paste0(mode, ".rds"))
  log_path <- file.path(work_dir, paste0(mode, ".log"))
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c(child_path, library_path, mode, image_path, project_path, output_path),
    stdout = log_path,
    stderr = log_path
  )
  if (status != 0L) {
    stop(paste(readLines(log_path, warn = FALSE), collapse = "\n"))
  }
  readRDS(output_path)
}

first <- run_child("save")
invisible(tiff::writeTIFF(matrix(1, 2, 2), image_path, bits.per.sample = 8L,
                          compression = "none"))
second <- run_child("reload")

stopifnot(
  !identical(first$entry_id, second$entry_id),
  !identical(first$export_stem, second$export_stem),
  !identical(first$read_generation, second$read_generation),
  !identical(first$cache_identity, second$cache_identity),
  is.null(second$loaded_read),
  !identical(second$loaded_cache, first$cache_identity),
  !identical(second$loaded_cache, second$cache_identity),
  identical(second$persisted_entry, first$persisted_entry),
  identical(first$loaded_pixels, rep(0, 4)),
  identical(second$loaded_pixels, rep(0, 4)),
  identical(second$fresh_pixels, rep(255, 4)),
  grepl("^[A-Za-z0-9._-]+$", first$export_stem),
  grepl("^[A-Za-z0-9._-]+$", second$export_stem),
  first$rng_unchanged,
  second$rng_unchanged,
  identical(first$roi_id, "roi_000000001"),
  identical(second$roi_id, "roi_000000001")
)

cat("installed identity: queue, read, cache, pixels, RNG, and ROI checks passed\n")
