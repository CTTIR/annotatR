skip_if_not_installed("tiff")

test_that("the multiplex example reads as a 3-level 4-channel pyramid", {
  img <- at_example_image("multiplex")
  expect_identical(at_dims(img, 0), c(512L, 512L))
  expect_identical(at_dims(img, 1), c(256L, 256L))
  expect_identical(at_dims(img, 2), c(128L, 128L))
  expect_identical(at_n_bands(img), 4L)
  expect_true(at_is_pyramidal(img))
})

test_that("multiplex band names are set by the example helper", {
  img <- at_example_image("multiplex")
  expect_identical(at_bands(img)$name, c("DAPI", "CD3", "CD8", "PanCK"))
})

test_that("tiff detection excludes OME/qptiff (handled by ometiff)", {
  expect_true(.tiff_detect("a.tif"))
  expect_true(.tiff_detect("a.tiff"))
  expect_false(.tiff_detect("a.ome.tif"))
  expect_false(.tiff_detect("a.qptiff"))
})

test_that("pyramid levels shrink in size", {
  img <- at_example_image("multiplex")
  d0 <- at_dims(img, 0)
  d2 <- at_dims(img, 2)
  expect_true(all(d2 < d0))
})
