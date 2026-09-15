cube_with <- function(arr, wavelengths = seq_len(dim(arr)[3]) * 10 + 400, meta = list()) {
  new_annot_image(source = "mem.hdr", backend = "envi", dims = c(dim(arr)[2], dim(arr)[1]),
                  n_levels = 1L, level_dims = list(c(dim(arr)[2], dim(arr)[1])),
                  n_bands = dim(arr)[3], wavelengths = wavelengths, wavelength_unit = "nm",
                  dtype = "float32", handle = list(data = arr), meta = meta)
}

test_that("image kind is spectral only with wavelengths", {
  arr <- array(1, dim = c(2, 2, 5))
  expect_identical(at_hsi_meta(cube_with(arr))$image_kind, "spectral")
  expect_identical(at_hsi_meta(cube_with(arr, wavelengths = NULL))$image_kind, "multichannel")
  expect_identical(at_hsi_meta(small_image())$image_kind, "rgb")
  expect_identical(at_hsi_meta(tiny_image())$image_kind, "grayscale")
  hm <- at_hsi_meta(cube_with(arr))
  expect_identical(hm$origin, "top_left")
  expect_identical(hm$y_direction, "down")
  expect_identical(hm$value_unit, "unknown")
  expect_identical(hm$calibration$status, "missing")
  expect_match(hm$transform_digest, "^[0-9a-f]{64}$")
  expect_false(identical(hm$transform_digest, at_hsi_meta(small_image())$transform_digest))
})

test_that("band tables flag missing, duplicate and non-numeric wavelengths without inventing them", {
  expect_identical(.wavelength_status(c(1, 2, 2), 3L), c("ok", "duplicate", "duplicate"))
  expect_identical(.wavelength_status(c(1, NA, 3), 3L), c("ok", "missing", "ok"))
  expect_identical(.wavelength_status(c("500", "x"), 2L), c("ok", "non_numeric"))
  expect_identical(.wavelength_status(NULL, 2L), c("missing", "missing"))
  img <- cube_with(array(1, dim = c(1, 1, 3)), wavelengths = c(500, NA, 520))
  b <- at_bands(img)
  expect_true(is.na(b$wavelength[2]))
  expect_identical(b$order, 1:3)
})

test_that("value conversions follow their formulas and refuse missing calibration", {
  raw <- c(100, 550, 1000)
  r <- at_convert_values(raw, from = "raw", to = "reflectance",
                         calibration = list(white = 1000, dark = 100))
  expect_equal(as.numeric(r), c(0, 0.5, 1))
  expect_identical(attr(r, "value_unit"), "reflectance")
  a <- at_convert_values(c(1, 0.1, 0), from = "reflectance", to = "absorbance")
  expect_equal(as.numeric(a), c(0, 1, NA))
  arr <- array(c(10, 20, 30, 40), dim = c(1, 2, 2))
  cal <- at_convert_values(arr, from = "raw", to = "reflectance",
                           calibration = list(white = c(20, 50), dark = c(0, 10)))
  expect_equal(cal[1, , 1], c(0.5, 1))
  expect_equal(cal[1, , 2], c(0.5, 0.75))
  err <- tryCatch(at_convert_values(raw, from = "raw", to = "reflectance"), error = function(e) e)
  expect_s3_class(err, "at_capability_error")
  expect_identical(err$code, "CALIBRATION_MISSING")
  expect_identical(tryCatch(at_convert_values(raw, to = "absorbance"), error = function(e) e$code),
                   "VALUE_UNIT_UNKNOWN")
  expect_identical(tryCatch(at_convert_values(raw, from = "radiance", to = "reflectance"),
                            error = function(e) e$code), "CONVERSION_UNSUPPORTED")
})

test_that("only whitelisted band operations run, with independent arithmetic", {
  arr <- array(0, dim = c(2, 2, 3))
  arr[, , 1] <- matrix(c(1, 2, 3, 4), 2)
  arr[, , 2] <- matrix(c(4, 2, 0, 1), 2)
  arr[, , 3] <- 7
  img <- cube_with(arr, wavelengths = c(500, 600, 700))
  nd <- at_band_view(img, "normalized_difference", bands = c(1, 2))
  expect_equal(nd[, , 1], matrix(c((1 - 4) / 5, 0, 1, (4 - 1) / 5), 2))
  ratio <- at_band_view(img, "ratio", bands = c(1, 2))
  expect_equal(ratio[, , 1], matrix(c(0.25, 1, NA, 4), 2))
  mean_view <- at_band_view(img, "wavelength_window_mean",
                            params = list(wavelength_min = 550, wavelength_max = 700))
  expect_equal(mean_view[, , 1], (arr[, , 2] + arr[, , 3]) / 2)
  expect_identical(attr(mean_view, "bands"), 2:3)
  expect_true(attr(nd, "display_product"))
  expect_match(attr(nd, "parent_digest"), "^[0-9a-f]{64}$")
  expect_error(at_band_view(img, "custom_expression"), "must be one of")
  expect_identical(tryCatch(at_band_view(img, "ratio", bands = 1L), error = function(e) e$code),
                   "BAND_COUNT")
  expect_identical(tryCatch(at_band_view(img, "single", bands = 9L), error = function(e) e$code),
                   "BAND_OUT_OF_RANGE")
  expect_error(at_band_view(img, "ratio", bands = 1:2, params = list(k = 1)), "takes no parameter")
  expect_setequal(at_band_operations()$operation,
                  c("single", "rgb", "ratio", "normalized_difference", "band_mean",
                    "wavelength_window_mean"))
})

test_that("display previews read only the displayed bands", {
  skip_if_not_installed("magick")
  arr <- array(seq_len(8 * 8 * 20), dim = c(8, 8, 20))
  img <- cube_with(arr)
  img$handle <- NULL
  seen <- integer()
  local_mocked_bindings(at_tile = function(img, level = 0L, xrange = NULL, yrange = NULL,
                                           bands = NULL, call = NULL) {
    seen <<- c(seen, bands)
    array(1, dim = c(yrange[2] - yrange[1] + 1, xrange[2] - xrange[1] + 1, length(bands)))
  })
  uri <- .image_data_uri(img, view = list(operation = "rgb", bands = c(5L, 3L, 1L)))
  expect_match(uri, "^data:image/png;base64,")
  expect_setequal(unique(seen), c(5L, 3L, 1L))
})

test_that("a TIFF is spectral only when wavelengths are declared", {
  skip_if_not_installed("tiff")
  img <- at_example_image("multiplex")
  expect_false(at_is_spectral(img))
  expect_identical(at_hsi_meta(img)$image_kind, "multichannel")
  spec <- at_read_image(at_example_path("multiplex"), wavelengths = c(450, 520, 600, 680))
  expect_true(at_is_spectral(spec))
  expect_identical(spec$meta$wavelength_source, "declared")
  expect_identical(tryCatch(at_read_image(at_example_path("multiplex"), wavelengths = 1:2),
                            error = function(e) e$code), "VALIDATION_FAILED")
})
