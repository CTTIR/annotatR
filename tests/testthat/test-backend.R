test_that("all six backends are registered with availability flags", {
  bl <- at_backend_list()
  expect_s3_class(bl, "tbl_df")
  expect_setequal(bl$name, c("raster", "tiff", "ometiff", "cuvis", "tivita", "envi"))
  expect_identical(names(bl), c("name", "description", "extensions", "available"))
  expect_type(bl$available, "logical")
})

test_that("core backends are available; Bioc/vendor backends reflect installation", {
  bl <- at_backend_list()
  avail <- setNames(bl$available, bl$name)
  expect_true(avail[["raster"]])
  expect_true(avail[["envi"]])
  expect_identical(avail[["cuvis"]], nzchar(system.file(package = "cuvis.r")))
  expect_identical(avail[["ometiff"]], requireNamespace("RBioFormats", quietly = TRUE))
})

test_that("at_backend_get errors on unknown backends", {
  expect_error(at_backend_get("nope"), "No backend")
})

test_that("at_backend_detect picks the right backend by content/extension", {
  expect_identical(at_backend_detect(at_example_path("tissue")), "raster")
  expect_identical(at_backend_detect(at_example_path("cube")), "envi")
})

test_that("at_tile returns [y, x, band] arrays for every access pattern", {
  skip_if_not_installed("tiff")
  img <- at_example_image("multiplex")
  expect_identical(dim(at_tile(img)), c(512L, 512L, 4L))
  expect_identical(dim(at_tile(img, xrange = c(1, 16), yrange = c(1, 32))), c(32L, 16L, 4L))
  expect_identical(dim(at_tile(img, bands = 1L)), c(512L, 512L, 1L))
  expect_identical(dim(at_tile(img, bands = c(1L, 3L))), c(512L, 512L, 2L))
  expect_identical(dim(at_tile(img, level = 2L)), c(128L, 128L, 4L))
})

test_that("at_tile is always 3-dimensional even for single band", {
  skip_if_not_installed("tiff")
  img <- at_example_image("tissue")
  expect_length(dim(at_tile(img, bands = 1L)), 3L)
})

test_that("at_tile validates ranges, level, and bands", {
  skip_if_not_installed("tiff")
  img <- at_example_image("tissue")
  expect_error(at_tile(img, xrange = c(1, 9999)), "out of bounds")
  expect_error(at_tile(img, level = 5), "exceed")
  expect_error(at_tile(img, bands = 99), "out of range")
})

test_that("at_read_image errors informatively on unreadable/unknown files", {
  expect_error(at_read_image(tempfile()), "existing file")
  f <- withr::local_tempfile(fileext = ".xyz")
  writeLines("x", f)
  expect_error(at_read_image(f), "No backend recognises")
})
