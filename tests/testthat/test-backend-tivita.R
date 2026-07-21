# Write a tiny TIVITA SpecCube.dat from a known [y, x, band] array, so reads can
# be checked exactly. TIVITA cubes are big-endian float32 with three leading
# header floats and a numpy C-order (cols=x, rows=y, band) layout, i.e. the band
# axis varies fastest, then rows (y), then cols (x).
write_speccube <- function(arr, path, header = c(0, 0, 0)) {
  # [y, x, band] -> file order (band fastest, then y, then x)
  v <- as.vector(aperm(arr, c(3, 1, 2)))
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.double(header), con, size = 4L, endian = "big")
  writeBin(as.double(v), con, size = 4L, endian = "big")
}

test_that("a bare SpecCube.dat reads with correct [y, x, band] orientation", {
  arr <- array(as.double(1:24), dim = c(3, 4, 2)) # [y = 3, x = 4, band = 2]
  dir <- withr::local_tempdir()
  p <- file.path(dir, "case_SpecCube.dat")
  write_speccube(arr, p)

  img <- at_read_image(p, backend = "tivita", nx = 4L, ny = 3L, nb = 2L)
  expect_s3_class(img, "annot_image")
  expect_identical(at_dims(img), c(4L, 3L)) # c(width, height)
  expect_identical(at_n_bands(img), 2L)
  expect_equal(at_tile(img), arr, tolerance = 0)
})

test_that("a 100-band SpecCube carries the canonical TIVITA wavelength grid", {
  arr <- array(runif(2 * 2 * 100), dim = c(2, 2, 100)) # [y, x, band]
  dir <- withr::local_tempdir()
  p <- file.path(dir, "spectral_SpecCube.dat")
  write_speccube(arr, p)

  img <- at_read_image(p, backend = "tivita", nx = 2L, ny = 2L, nb = 100L)
  expect_identical(at_n_bands(img), 100L)
  expect_true(at_is_spectral(img))
  expect_equal(at_wavelengths(img), seq(500, 995, by = 5))
  expect_identical(at_meta(img, "vendor"), "Diaspective Vision Tivita")
})

test_that("a wrong-size SpecCube.dat aborts informatively", {
  dir <- withr::local_tempdir()
  p <- file.path(dir, "truncated_SpecCube.dat")
  con <- file(p, "wb"); writeBin(as.double(1:10), con, size = 4L, endian = "big"); close(con)
  expect_error(at_read_image(p, backend = "tivita"), "size")
})

test_that("a bare SpecCube.dat auto-detects as the tivita backend", {
  dir <- withr::local_tempdir()
  p <- file.path(dir, "auto_SpecCube.dat")
  write_speccube(array(0, dim = c(2, 2, 2)), p)
  expect_true(.tivita_detect(p))
  expect_identical(at_backend_detect(p), "tivita")
})

test_that("a SpecCube.dat with a sibling .hdr is left to the envi backend", {
  dir <- withr::local_tempdir()
  file.create(file.path(dir, "x_SpecCube.dat"))
  writeLines("ENVI", file.path(dir, "x_SpecCube.hdr"))
  expect_false(.tivita_detect(file.path(dir, "x_SpecCube.dat")))
})

test_that("reads a real TIVITA cube from the workbench (integration)", {
  cube <- Sys.glob(file.path(
    "..", "..", "hsi-workbench", "data", "burn", "*", "*", "*", "*", "*_SpecCube.dat"
  ))[1]
  skip_if(is.na(cube), "no workbench TIVITA cube present")
  img <- at_read_image(cube) # auto-detect
  expect_identical(at_meta(img, "backend"), "tivita")
  expect_identical(at_dims(img), c(640L, 480L))
  expect_identical(at_n_bands(img), 100L)
  expect_equal(range(at_wavelengths(img)), c(500, 995))
  tile <- at_tile(img, xrange = c(320, 320), yrange = c(240, 240))
  expect_identical(dim(tile), c(1L, 1L, 100L))
  expect_gt(mean(tile > 0 & tile < 1), 0.5) # reflectance-valued
})
