# Focused acceptance coverage for stable queue, ROI, and source identity.

identity_backend <- function() {
  name <- "identity-test"
  at_backend_register(
    name,
    read_fn = function(path, multiplier = 1) {
      value <- as.numeric(readLines(path, warn = FALSE)) * multiplier
      new_annot_image(
        path, name, c(2L, 2L), 1L, list(c(2L, 2L)), 1L,
        handle = list(data = array(value, c(2L, 2L, 1L)))
      )
    },
    tile_fn = function(img, level, xrange, yrange, bands) {
      img$handle$data[yrange[1]:yrange[2], xrange[1]:xrange[2], , drop = FALSE]
    },
    detect_fn = function(path) FALSE,
    available_fn = function() TRUE
  )
  withr::defer(rm(list = name, envir = .backend_registry), envir = parent.frame())
  name
}

identity_fresh <- function(code, args) {
  root <- normalizePath(testthat::test_path("..", ".."))
  script <- tempfile(fileext = ".R")
  result <- tempfile(fileext = ".rds")
  log <- tempfile(fileext = ".log")
  on.exit(unlink(c(script, result, log)))
  writeLines(c(
    sprintf(".libPaths(%s)", paste(deparse(.libPaths()), collapse = "")),
    sprintf("pkgload::load_all(%s, quiet=TRUE)", deparse(root)),
    sprintf("args <- %s", paste(deparse(args), collapse = "")),
    paste0("result <- local({", code, "})"),
    sprintf("saveRDS(result,%s)", deparse(result))
  ), script)
  status <- system2(file.path(R.home("bin"), "Rscript"), shQuote(script),
                    stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

test_that("queue entries have persisted identities independent of path and name", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "A"))
  dir.create(file.path(dir, "B"))
  paths <- c(
    file.path(dir, "A", "same.tif"),
    file.path(dir, "B", "same.tif"),
    file.path(dir, "A", "same.tif"),
    file.path(dir, "A", "SAME.tif")
  )
  invisible(lapply(unique(paths), writeLines, text = "0"))

  .reset_id_counter()
  set.seed(20260910)
  rng_before <- .Random.seed
  session <- at_session(paths, out_dir = dir)
  manifest <- at_session_status(session)

  expect_identical(manifest$name, c("same", "same", "same", "SAME"))
  expect_identical(manifest$path, normalizePath(paths, mustWork = FALSE))
  expect_identical(anyDuplicated(manifest$entry_id), 0L)
  expect_identical(anyDuplicated(manifest$export_stem), 0L)
  expect_true(all(grepl("^[A-Za-z0-9._-]+$", manifest$export_stem)))
  expect_identical(.Random.seed, rng_before)
  expect_identical(at_roi_point(1, 1, "a")$id, "roi_000000001")

  saved <- file.path(dir, "session.rds")
  at_save_session(session, saved)
  loaded <- at_load_session(saved)
  expect_identical(loaded$manifest$entry_id, manifest$entry_id)
  expect_identical(loaded$manifest$export_stem, manifest$export_stem)
})

test_that("independent R processes cannot mint the same queue identity", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "image.tif")
  writeLines("0", path)
  mint <- function() identity_fresh(
    paste(
      ".reset_id_counter()",
      "set.seed(20260910)",
      "rng <- .Random.seed",
      "s <- at_session(args$path)",
      paste0(
        "list(entry_id=s$manifest$entry_id, export_stem=s$manifest$export_stem,",
        "rng_unchanged=identical(rng,.Random.seed),",
        "roi_id=at_roi_point(1,1,'a')$id)"
      ),
      sep = ";"
    ),
    list(path = path)
  )

  first <- mint()
  second <- mint()

  expect_false(identical(first$entry_id, second$entry_id))
  expect_false(identical(first$export_stem, second$export_stem))
  expect_true(first$rng_unchanged && second$rng_unchanged)
  expect_identical(c(first$roi_id, second$roi_id),
                   c("roi_000000001", "roi_000000001"))
})

test_that("saved image identity cannot alias a fresh read after restart", {
  skip_if_not_installed("tiff")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "pixels.tif")
  saved <- file.path(dir, "project.rds")
  tiff::writeTIFF(matrix(0, 2, 2), path, bits.per.sample = 8L,
                  compression = "none")
  identity_fresh(
    paste(
      "p <- at_project(at_read_image(args$path))",
      "at_save_project(p,args$saved)",
      "p$image$cache_identity",
      sep = ";"
    ),
    list(path = path, saved = saved)
  )

  result <- identity_fresh(
    paste(
      "p <- at_load_project(args$saved)",
      ".tile_cache_clear()",
      "old <- at_tile(p$image)",
      "tiff::writeTIFF(matrix(1,2,2),args$path,bits.per.sample=8L,compression='none')",
      "fresh <- at_read_image(args$path)",
      "got <- at_tile(fresh)",
      ".tile_cache_clear()",
      "actual <- at_tile(fresh)",
      paste0(
        "list(loaded_id=p$image$cache_identity,fresh_id=fresh$cache_identity,",
        "old=as.vector(old),got=as.vector(got),actual=as.vector(actual))"
      ),
      sep = ";"
    ),
    list(path = path, saved = saved)
  )

  expect_false(identical(result$loaded_id, result$fresh_id))
  expect_equal(result$old, rep(0, 4))
  expect_equal(result$got, rep(255, 4))
  expect_equal(result$actual, rep(255, 4))
})

test_that("session loading rejects aliased queue identities", {
  session <- demo_session(2)
  path <- file.path(session$out_dir, "duplicate-identity.rds")
  session$manifest$entry_id[2] <- session$manifest$entry_id[1]
  saveRDS(session, path)
  expect_error(at_load_session(path), "entry.*unique|unique.*entry")

  session <- demo_session(2)
  path <- file.path(session$out_dir, "duplicate-stem.rds")
  session$manifest$export_stem[2] <- session$manifest$export_stem[1]
  saveRDS(session, path)
  expect_error(at_load_session(path), "export.*unique|unique.*export")
})

test_that("a not-yet-created session output directory keeps its original cwd", {
  root <- withr::local_tempdir()
  other <- withr::local_tempdir()
  image <- file.path(root, "image.tif")
  writeLines("0", image)
  session <- withr::with_dir(
    root,
    at_session("image.tif", out_dir = "future-output")
  )
  expected <- file.path(normalizePath(root), "future-output")

  expect_identical(session$out_dir, expected)
  withr::with_dir(other, at_save_session(session))
  expect_true(file.exists(file.path(expected, "_session.rds")))
})

test_that("package exports use entry stems and receipts identify queue entries", {
  dir <- withr::local_tempdir()
  source_dir <- file.path(dir, c("A", "B"))
  invisible(lapply(source_dir, dir.create))
  paths <- file.path(source_dir, "same.tif")
  invisible(lapply(paths, writeLines, text = "0"))
  session <- at_session(paths, out_dir = dir)
  session$projects <- lapply(c("first", "second"), function(label) {
    at_project(tiny_image(), at_layer_add(at_layer("L"), square_roi(label)))
  })

  receipt <- suppressMessages(at_export_all(
    session, file.path(dir, "out"), formats = "geojson", scope = "all",
    overwrite = TRUE, progress = FALSE
  ))
  expected_paths <- file.path(
    dir, "out", "geojson", paste0(session$manifest$export_stem, ".geojson")
  )

  expect_identical(receipt$entry_id, session$manifest$entry_id)
  expect_identical(receipt$path, expected_paths)
  expect_identical(anyDuplicated(receipt$path), 0L)
  labels <- vapply(receipt$path, function(path) at_read_geojson(path)[[1]]$labels,
                   character(1))
  expect_identical(unname(labels), c("first", "second"))
})

test_that("a materialized project records its queue entry identity", {
  skip_if_not_installed("tiff")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "image.tif")
  tiff::writeTIFF(matrix(0, 2, 2), path)
  session <- at_session(path, out_dir = dir)

  project <- at_current(session)

  expect_identical(project$meta$entry_id, session$manifest$entry_id[1])
})

test_that("the actual app materializer records repeated queue entry identities", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("shinyjs")
  skip_if_not_installed("tiff")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "repeated.tif")
  tiff::writeTIFF(matrix(0, 2, 2), path)
  session <- at_session(c(path, path), out_dir = dir)
  app_dir <- system.file("shiny", "annotatR", package = "annotatR")
  app_env <- new.env(parent = globalenv())
  withr::with_dir(app_dir, source("app.R", local = app_env))

  projects <- lapply(1:2, function(i) app_env$.materialise(session, i))

  expect_identical(vapply(projects, function(p) p$meta$entry_id %||% NA_character_,
                          character(1)),
                   session$manifest$entry_id)
})

test_that("image summaries keep repeated display names separated by entry ID", {
  session <- demo_session(2)
  session$manifest$name[] <- "same"
  session$projects <- lapply(c("first", "second"), function(label) {
    at_project(tiny_image(), at_layer_add(at_layer("L"), square_roi(label)))
  })
  session$manifest$n_rois[] <- 1L

  summary <- at_summary_table(session, by = "image")

  expect_equal(nrow(summary), 2L)
  expect_identical(summary$entry_id, session$manifest$entry_id)
  expect_identical(summary$image, c("same", "same"))
  expect_identical(summary$n_rois, c(1L, 1L))
})

test_that("at_project repairs collisions without consuming later valid ROI IDs", {
  .reset_id_counter()
  one <- at_roi_rect(0, 0, 1, 1, "a", id = "roi_000000001")
  duplicate <- at_roi_rect(1, 1, 2, 2, "a", id = "roi_000000001")
  reserved <- at_roi_rect(2, 2, 3, 3, "a", id = "roi_000000002")
  first <- at_layer("first")
  first$rois <- list(one, duplicate)
  second <- at_layer("second")
  second$rois <- list(reserved)

  project <- at_project(tiny_image(), list(first, second))
  ids <- at_rois(project)$roi_id

  expect_identical(ids[c(1, 3)], c("roi_000000001", "roi_000000002"))
  expect_identical(ids[2], "roi_000000003")
  expect_identical(anyDuplicated(ids), 0L)
})

test_that("populated layer insertion validates IDs against the whole project", {
  .reset_id_counter()
  base <- at_layer("base")
  base$rois <- list(at_roi_rect(0, 0, 1, 1, "a", id = "roi_000000001"))
  project <- at_project(tiny_image(), base)
  incoming <- at_layer("incoming")
  incoming$rois <- list(
    at_roi_rect(1, 1, 2, 2, "a", id = "roi_000000001"),
    at_roi_rect(2, 2, 3, 3, "a", id = "roi_000000002")
  )

  project <- at_add_layer(project, incoming)
  ids <- at_rois(project)$roi_id

  expect_identical(ids[c(1, 3)], c("roi_000000001", "roi_000000002"))
  expect_identical(ids[2], "roi_000000003")
  expect_identical(anyDuplicated(ids), 0L)
})

test_that("single ROI insertion mints until the project ID is unique", {
  .reset_id_counter()
  layer <- at_layer("L")
  layer$rois <- lapply(1:4, function(i) {
    at_roi_rect(i, i, i + 1, i + 1, "a", id = sprintf("roi_%09d", i))
  })
  project <- at_project(tiny_image(), layer)

  project <- at_add_roi(
    project, "L", at_roi_rect(6, 6, 7, 7, "a", id = "roi_000000001")
  )

  expect_identical(at_rois(project)$roi_id[5], "roi_000000005")
  expect_identical(anyDuplicated(at_rois(project)$roi_id), 0L)
})

test_that("source identity uses canonical path, reader options, and fresh reads", {
  backend <- identity_backend()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "pixels.identity")
  writeLines("2", path)
  .tile_cache_clear()
  withr::defer(.tile_cache_clear())

  first <- withr::with_dir(dir, at_read_image("pixels.identity", backend, multiplier = 2))
  second <- at_read_image(path, backend, multiplier = 3)

  expect_identical(first$source, normalizePath(path))
  expect_identical(first$source_descriptor$path, normalizePath(path))
  expect_identical(first$source_descriptor$options, list(multiplier = 2))
  expect_false(identical(first$read_generation, second$read_generation))
  expect_false(identical(
    .tile_key(first, 0L, c(1L, 2L), c(1L, 2L), NULL),
    .tile_key(second, 0L, c(1L, 2L), c(1L, 2L), NULL)
  ))
  expect_equal(as.vector(at_tile(first)), rep(4, 4))
  expect_equal(as.vector(at_tile(second)), rep(6, 4))

  writeLines("5", path)
  replacement <- at_read_image(path, backend, multiplier = 3)
  expect_equal(as.vector(at_tile(replacement)), rep(15, 4))
})

test_that("distinct constructed image handles cannot alias cached pixels", {
  backend <- identity_backend()
  .tile_cache_clear()
  withr::defer(.tile_cache_clear())
  make_image <- function(value) new_annot_image(
    "memory", backend, c(2L, 2L), 1L, list(c(2L, 2L)), 1L,
    handle = list(data = array(value, c(2L, 2L, 1L)))
  )
  first <- make_image(1)
  second <- make_image(2)

  expect_equal(as.vector(at_tile(first)), rep(1, 4))
  expect_equal(as.vector(at_tile(first)), rep(1, 4))
  expect_equal(as.vector(at_tile(second)), rep(2, 4))
})
