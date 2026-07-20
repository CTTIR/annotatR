# Write a tiny ENVI file with a chosen interleave/dtype from a known
# [y, x, band] array, so reads can be checked exactly.
write_envi <- function(arr, dir, interleave = "bsq", data_type = 12L,
                       wavelengths = NULL) {
  sz_y <- dim(arr)[1]; sz_x <- dim(arr)[2]; nb <- dim(arr)[3]
  vec <- switch(
    interleave,
    "bsq" = as.vector(aperm(arr, c(2, 1, 3))),
    "bil" = as.vector(aperm(arr, c(2, 3, 1))),
    "bip" = as.vector(aperm(arr, c(3, 2, 1)))
  )
  dat <- file.path(dir, "cube.dat")
  con <- file(dat, "wb")
  size <- if (data_type == 4L) 4L else 2L
  if (data_type == 4L) writeBin(as.double(vec), con, size = 4L) else writeBin(as.integer(vec), con, size = 2L)
  close(con)
  hdr <- c(
    "ENVI",
    sprintf("samples = %d", sz_x), sprintf("lines = %d", sz_y),
    sprintf("bands = %d", nb), "header offset = 0",
    sprintf("data type = %d", data_type),
    sprintf("interleave = %s", interleave), "byte order = 0"
  )
  if (!is.null(wavelengths)) {
    hdr <- c(hdr, "wavelength units = Nanometers",
             paste0("wavelength = {", paste(wavelengths, collapse = ", "), "}"))
  }
  writeLines(hdr, file.path(dir, "cube.hdr"))
  file.path(dir, "cube.hdr")
}

test_that("ENVI round-trips exactly for all three interleaves", {
  set.seed(1)
  arr <- array(sample(0:60000, 4 * 5 * 3), dim = c(4, 5, 3)) # [y, x, band]
  for (il in c("bsq", "bil", "bip")) {
    dir <- withr::local_tempdir()
    hdr <- write_envi(arr, dir, interleave = il)
    img <- at_read_image(hdr)
    got <- at_tile(img)
    expect_equal(got, arr, tolerance = 0, info = il)
  }
})

test_that("ENVI reads float32 and preserves wavelengths", {
  arr <- array(runif(4 * 4 * 5), dim = c(4, 4, 5))
  dir <- withr::local_tempdir()
  hdr <- write_envi(arr, dir, interleave = "bsq", data_type = 4L,
                    wavelengths = c(450, 500, 550, 600, 650))
  img <- at_read_image(hdr)
  expect_true(at_is_spectral(img))
  expect_equal(at_wavelengths(img), c(450, 500, 550, 600, 650))
  expect_equal(at_tile(img), arr, tolerance = 1e-6)
})

test_that("the example cube reads with 40 bands and planted signatures", {
  cube <- at_example_image("cube")
  expect_identical(at_n_bands(cube), 40L)
  expect_true(at_is_spectral(cube))
  # The two planted regions have clearly different spectra.
  s1 <- apply(at_tile(cube, xrange = c(38, 40), yrange = c(38, 40)), 3, mean)
  s2 <- apply(at_tile(cube, xrange = c(89, 91), yrange = c(76, 78)), 3, mean)
  expect_gt(mean(abs(s1 - s2)), 1000)
})

test_that("ENVI detection recognises headers", {
  expect_true(.envi_detect("a.hdr"))
  expect_false(.envi_detect("a.png"))
})
