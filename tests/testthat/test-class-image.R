test_that("accessors return the right values and types", {
  img <- small_image()
  expect_identical(at_dims(img, 0), c(100L, 100L))
  expect_identical(at_dims(img, 2), c(25L, 25L))
  expect_identical(at_n_levels(img), 3L)
  expect_identical(at_n_bands(img), 3L)
  expect_true(at_is_pyramidal(img))
  expect_false(at_is_spectral(img))
  expect_identical(at_pixel_size(img), c(0.5, 0.5))
})

test_that("at_bands always has n_bands rows with correct columns", {
  img <- small_image()
  b <- at_bands(img)
  expect_s3_class(b, "tbl_df")
  expect_equal(nrow(b), 3L)
  expect_identical(names(b), c("index", "name", "wavelength", "unit"))
  expect_identical(b$name, c("R", "G", "B"))
  expect_true(all(is.na(b$wavelength)))
})

test_that("spectral images expose wavelengths", {
  cube <- cube_image()
  expect_true(at_is_spectral(cube))
  expect_length(at_wavelengths(cube), 10L)
  expect_equal(range(at_wavelengths(cube)), c(450, 900))
  b <- at_bands(cube)
  expect_false(any(is.na(b$wavelength)))
  expect_identical(unique(b$unit), "nm")
})

test_that("non-spectral images return numeric(0) wavelengths", {
  expect_length(at_wavelengths(small_image()), 0L)
})

test_that("at_dims errors when level exceeds the pyramid", {
  expect_error(at_dims(small_image(), 5), "exceed")
})

test_that("at_meta returns the list or a single element", {
  img <- small_image()
  expect_type(at_meta(img), "list")
  expect_identical(at_meta(img, "pixel_unit"), "um")
  expect_identical(at_meta(img, "backend"), "tiff")
})

test_that("print, format, dim behave", {
  img <- small_image()
  expect_output(print(img), "annot_image")
  expect_type(format(img), "character")
  expect_identical(dim(img), c(100L, 100L, 3L))
})

test_that("accessors reject non-images", {
  expect_error(at_dims(1), "annot_image")
  expect_error(at_n_bands("x"), "annot_image")
})
