# A deterministic image whose pixel [i, j] value is i*10 + j, so statistics are
# computable by hand.
known_image <- function() {
  arr <- array(0, dim = c(10, 10, 1))
  for (i in 1:10) for (j in 1:10) arr[i, j, 1] <- i * 10 + j
  new_annot_image("k.tif", "raster", c(10L, 10L), 1L, list(c(10L, 10L)), 1L,
                  handle = list(data = arr), dtype = "uint16")
}

test_that("at_extract mean/sum match manual computation", {
  img <- known_image()
  proj <- at_project(img, at_layer_add(at_layer("l"),
                                       at_roi_rect(2, 2, 5, 5, label = "a")))
  arr <- img$handle$data
  ex <- at_extract(proj, stat = "mean")
  expect_equal(ex$value, mean(arr[3:5, 3:5, 1]))
  expect_equal(ex$n_px, 9L)
  exs <- at_extract(proj, stat = "sum")
  expect_equal(exs$value, sum(arr[3:5, 3:5, 1]))
})

test_that("tile-wise extraction equals full-image computation", {
  img <- known_image()
  arr <- img$handle$data
  proj <- at_project(img, at_layer_add(at_layer("l"),
                                       at_roi_rect(0, 0, 10, 10, label = "a")))
  ex <- at_extract(proj, stat = "mean")
  expect_equal(ex$value, mean(arr[, , 1]))
  expect_equal(ex$n_px, 100L)
})

test_that("at_extract stat = 'all' yields one row per statistic", {
  img <- known_image()
  proj <- at_project(img, at_layer_add(at_layer("l"),
                                       at_roi_rect(2, 2, 5, 5, label = "a")))
  ex <- at_extract(proj, stat = "all")
  expect_setequal(ex$stat, c("mean", "median", "sd", "min", "max", "sum", "n"))
})

test_that("at_extract is type-stable on empty input", {
  ex <- at_extract(at_project(known_image()), stat = "mean")
  expect_s3_class(ex, "tbl_df")
  expect_equal(nrow(ex), 0L)
  expect_identical(names(ex), names(.empty_extract_tbl()))
})

test_that("spectral extraction recovers the planted cube signatures", {
  skip_if_not_installed("tiff")
  cube <- at_example_image("cube")
  lyr <- at_layer("regions", labels = c("r1", "r2"))
  lyr <- at_layer_add(lyr, at_roi_circle(38, 38, 4, label = "r1"))
  lyr <- at_layer_add(lyr, at_roi_circle(90, 77, 4, label = "r2"))
  sp <- at_extract_spectrum(at_project(cube, lyr), stat = "mean")
  s1 <- sp$value[sp$label == "r1"]
  s2 <- sp$value[sp$label == "r2"]
  expect_length(s1, 40L)
  expect_gt(mean(abs(s1 - s2)), 1000)
  # sorted by wavelength within an ROI
  one <- sp[sp$roi_id == sp$roi_id[1], ]
  expect_false(is.unsorted(one$wavelength))
})

test_that("at_extract_spectrum errors on non-spectral images", {
  expect_error(at_extract_spectrum(at_project(known_image())), "spectral")
})

test_that("at_extract_pixels returns per-pixel rows and guards on size", {
  img <- known_image()
  proj <- at_project(img, at_layer_add(at_layer("l"),
                                       at_roi_rect(2, 2, 5, 5, label = "a")))
  px <- at_extract_pixels(proj)
  expect_equal(nrow(px), 9L)
  expect_identical(names(px), c("roi_id", "layer", "label", "x", "y", "band", "value"))
  expect_error(at_extract_pixels(proj, max_px = 2), "max_px")
})
