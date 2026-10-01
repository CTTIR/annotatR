tiff_process_fixture <- function(mode, target) {
  callr::r(
    function(root, development, libraries, mode, target) {
      .libPaths(libraries)
      if (development) {
        pkgload::load_all(root, quiet = TRUE)
      } else {
        library(annotatR)
      }
      ns <- asNamespace("annotatR")
      p <- tempfile(fileext = ".tif")
      warmup <- p
      on.exit(unlink(warmup))
      tiff::writeTIFF(matrix(c(0, 1, 1, 0), 2, 2), p,
        bits.per.sample = 8L, compression = "none"
      )
      if (mode != "control") {
        im <- magick::image_read(p)
        if (mode == "destroy") {
          rm(im)
          invisible(gc())
        }
        if (mode == "inherited") Sys.setenv(R_DEFAULT_PACKAGES = "magick")
      }
      p <- system.file("extdata", "example_multiplex.tif", package = "annotatR")
      warnings <- character()
      value <- withCallingHandlers(
        {
          if (target == "mask") {
            get(".read_mask_matrix", ns)(p, call = rlang::current_env())
          } else {
            if (target == "raster") {
              reader <- get(".raster_read", ns)
              scope <- new.env(parent = environment(reader))
              scope$requireNamespace <- function(package, ...) {
                if (package == "magick") {
                  FALSE
                } else {
                  base::requireNamespace(package, ...)
                }
              }
              environment(reader) <- scope
              img <- reader(p)
            } else {
              img <- annotatR::at_read_image(p, backend = "tiff")
            }
            list(
              pixels = annotatR::at_tile(img), dims = img$dims,
              meta = img$meta, dtype = img$dtype
            )
          }
        },
        warning = function(w) {
          warnings <<- c(warnings, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      )
      list(value = value, warnings = warnings)
    },
    args = list(
      root = getNamespaceInfo(asNamespace("annotatR"), "path"),
      development = pkgload::is_dev_package("annotatR"),
      libraries = .libPaths(), mode = mode, target = target
    ),
    timeout = 60
  )
}

test_that("TIFF callers survive callback state and preserve results", {
  skip_if_not_installed("tiff")
  skip_if_not_installed("magick")
  skip_if_not_installed("callr")
  skip_if_not_installed("pkgload")
  for (target in c("image", "mask", "raster")) {
    expected <- tiff_process_fixture("control", target)
    for (mode in c("retained", "destroy", "inherited")) {
      expect_identical(tiff_process_fixture(mode, target), expected,
        info = paste(target, mode)
      )
    }
  }
})

test_that("isolated mask decoding keeps integer codes and orientation", {
  skip_if_not_installed("tiff")
  path <- file.path(withr::local_tempdir(), "mask with spaces.tif")
  expected <- matrix(c(0L, 1L, 256L, 4096L, 65535L, 32768L), 2, 3)
  tiff::writeTIFF(expected / 65535, path,
    bits.per.sample = 16L,
    compression = "none"
  )
  actual <- .read_mask_matrix(path, call = rlang::current_env())
  expect_identical(actual$m, expected)
})

test_that("decoder errors and invalid execution bounds fail closed", {
  skip_if_not_installed("tiff")
  path <- file.path(withr::local_tempdir(), "invalid with spaces.tif")
  writeLines("not a TIFF", path)
  expect_error(.tiff_read_isolated(path), "TIFF|image|cannot")
  expect_error(.tiff_read_isolated(paste0(path, "missing")))
  for (value in list(NA_real_, Inf, 0, 0.1, 1.5, 2^31, "120", c(1, 2))) {
    withr::local_options(annotatR.tiff_timeout = value)
    expect_error(.tiff_read_isolated(path), "finite integer")
  }
})

test_that("abnormal decoder exit and missing responses are rejected", {
  path <- file.path(withr::local_tempdir(), "input.tif")
  writeLines("fixture", path)
  for (code in c(134L, 0L)) {
    decoder <- .tiff_read_isolated
    scope <- new.env(parent = environment(decoder))
    scope$system2 <- function(...) code
    environment(decoder) <- scope
    before <- list.files(
      tempdir(),
      pattern = "^annotatr-tiff-", full.names = TRUE
    )
    expect_error(decoder(path), "no image returned")
    after <- list.files(
      tempdir(),
      pattern = "^annotatr-tiff-", full.names = TRUE
    )
    expect_identical(after, before)
  }
})

test_that("a real child timeout cleans temporary decoder files", {
  path <- file.path(withr::local_tempdir(), "input.tif")
  writeLines("fixture", path)
  sleeper <- tempfile(fileext = ".R")
  withr::defer(unlink(sleeper))
  writeLines("Sys.sleep(30)", sleeper)
  withr::local_options(annotatR.tiff_timeout = 1L)
  decoder <- .tiff_read_isolated
  scope <- new.env(parent = environment(decoder))
  scope$system2 <- function(command, args, stdout, stderr, timeout) {
    base::system2(command, shQuote(c("--vanilla", sleeper)),
      stdout = stdout,
      stderr = stderr, timeout = timeout
    )
  }
  environment(decoder) <- scope
  before <- list.files(
    tempdir(),
    pattern = "^annotatr-tiff-", full.names = TRUE
  )
  expect_error(suppressWarnings(decoder(path)), "exit 124")
  after <- list.files(
    tempdir(),
    pattern = "^annotatr-tiff-", full.names = TRUE
  )
  expect_identical(after, before)
})
