# Independent TIVITA SpecCube byte fixtures: storage index of (x, y, band) is
# ((x * height + y) * bands + band), written with explicit loops.

speccube_value <- function(y, x, b) 1000 * b + 10 * y + x + 0.5

write_cube <- function(path, width, height, bands, header = c(3, 2, 1), endian = "big",
                       value_bytes = 4L) {
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.double(header), con, size = value_bytes, endian = endian)
  for (x in seq_len(width)) for (y in seq_len(height)) for (b in seq_len(bands)) {
    writeBin(speccube_value(y, x, b), con, size = value_bytes, endian = endian)
  }
}

test_that("profiles validate their layout and wavelength count", {
  p <- at_tivita_profile()
  expect_s3_class(p, "at_tivita_profile")
  expect_identical(c(p$width, p$height, p$bands), c(640L, 480L, 100L))
  expect_equal(range(p$wavelengths), c(500, 995))
  expect_error(at_tivita_profile("x", bands = 3, wavelengths = 1:2), class = "at_validation_error")
  expect_error(at_tivita_profile("x", value_bytes = 2), class = "at_validation_error")
  expect_error(at_tivita_profile("x", axis_order = "band,y,x"), class = "at_validation_error")
})

test_that("an explicit profile decodes the cube exactly, little or big endian", {
  for (endian in c("big", "little")) {
    d <- withr::local_tempdir()
    f <- file.path(d, "case_SpecCube.dat")
    write_cube(f, 5, 4, 3, endian = endian)
    prof <- at_tivita_profile("bench", width = 5, height = 4, bands = 3, endian = endian,
                              wavelengths = c(600, 650, 700), value_unit = "raw")
    img <- at_read_image(f, backend = "tivita", profile = prof)
    expect_identical(at_dims(img), c(5L, 4L))
    tile <- at_tile(img)
    for (y in 1:4) for (x in 1:5) for (b in 1:3) {
      expect_identical(tile[y, x, b], speccube_value(y, x, b))
    }
    expect_identical(at_hsi_meta(img)$value_unit, "raw")
    expect_identical(img$meta$profile, "bench")
    expect_equal(unlist(img$meta$header_values), c(3, 2, 1))
  }
})

test_that("a sidecar declares a different device; mismatches abort instead of guessing", {
  d <- withr::local_tempdir()
  f <- file.path(d, "dev_SpecCube.dat")
  write_cube(f, 3, 2, 4, header = numeric(0))
  err <- tryCatch(at_read_image(f), error = function(e) e)
  expect_identical(err$code, "PROFILE_MISMATCH")
  side <- list(profile_version = "1.0", name = "lab_3x2x4", width = 3L, height = 2L, bands = 4L,
               header_values = 0L, value_bytes = 4L, endian = "big", axis_order = "x,y,band",
               wavelengths = c(500, 510, 520, 530), wavelength_unit = "nm", value_unit = "reflectance")
  jsonlite::write_json(side, paste0(f, ".tivita.json"), auto_unbox = TRUE)
  img <- at_read_image(f)
  expect_identical(img$meta$profile, "lab_3x2x4")
  expect_identical(img$meta$profile_source, "sidecar")
  expect_identical(at_tile(img, xrange = c(3, 3), yrange = c(2, 2))[1, 1, ],
                   speccube_value(2, 3, 1:4))
  side$bands <- 5L
  jsonlite::write_json(side, paste0(f, ".tivita.json"), auto_unbox = TRUE)
  expect_error(at_read_image(f), class = "at_validation_error")
  side$bands <- 4L
  side$surprise <- TRUE
  jsonlite::write_json(side, paste0(f, ".tivita.json"), auto_unbox = TRUE)
  expect_identical(tryCatch(at_read_image(f), error = function(e) e$code), "SCHEMA_INVALID")
})

test_that("windowed SpecCube reads read only the window's columns", {
  d <- withr::local_tempdir()
  f <- file.path(d, "w_SpecCube.dat")
  write_cube(f, 20, 10, 6)
  img <- at_read_image(f, backend = "tivita",
                       profile = at_tivita_profile("w", width = 20, height = 10, bands = 6,
                                                   wavelengths = NULL))
  expect_false(at_is_spectral(img))
  .tile_cache_clear()
  at_read_stats(img, reset = TRUE)
  t <- at_tile(img, xrange = c(4, 5), yrange = c(3, 7), bands = c(6L, 1L))
  expect_identical(t[5, 2, 1], speccube_value(7, 5, 6))
  expect_identical(t[1, 1, 2], speccube_value(3, 4, 1))
  expect_identical(at_read_stats(img)$file_bytes, 2 * 5 * 6 * 4)
})
