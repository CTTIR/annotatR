skip_if_not(requireNamespace("magick", quietly = TRUE) ||
              requireNamespace("tiff", quietly = TRUE))

test_that("the tissue example reads as a 512x512 RGB raster", {
  img <- at_example_image("tissue")
  expect_s3_class(img, "annot_image")
  expect_identical(at_dims(img), c(512L, 512L))
  expect_identical(at_n_bands(img), 3L)
  expect_identical(at_n_levels(img), 1L)
  expect_false(at_is_pyramidal(img))
  expect_false(at_is_spectral(img))
})

test_that("raster tiles carry 0-255 intensities", {
  img <- at_example_image("tissue")
  tile <- at_tile(img, xrange = c(1, 8), yrange = c(1, 8))
  expect_true(all(tile >= 0 & tile <= 255))
})

test_that("raster detection matches image extensions", {
  expect_true(.raster_detect("a.png"))
  expect_true(.raster_detect("a.JPG"))
  expect_false(.raster_detect("a.cu3"))
})
