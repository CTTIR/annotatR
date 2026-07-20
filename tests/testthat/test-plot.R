is_gg <- function(p) inherits(p, "ggplot")

test_that("spatial plots return ggplot objects", {
  skip_if_not_installed("tiff")
  proj <- at_example_project()
  expect_true(is_gg(at_plot_image(at_example_image("tissue"))))
  expect_true(is_gg(at_plot_project(proj)))
  expect_true(is_gg(at_plot_overlay(proj)))
  expect_true(is_gg(at_plot_summary(proj)))
  expect_true(is_gg(at_plot_mask(at_mask(proj, "labelled"))))
})

test_that("RGB and spectral false-colour composites work", {
  skip_if_not_installed("tiff")
  expect_true(is_gg(at_plot_image(at_example_image("multiplex"), rgb = c(4, 2, 1))))
  expect_true(is_gg(at_plot_image(at_example_image("cube"), rgb = c(650, 550, 450))))
})

test_that("at_plot_spectrum returns a ggplot", {
  skip_if_not_installed("tiff")
  cube <- at_example_image("cube")
  lyr <- at_layer_add(at_layer("r", labels = "a"), at_roi_circle(38, 38, 4, label = "a"))
  sp <- at_extract_spectrum(at_project(cube, lyr))
  expect_true(is_gg(at_plot_spectrum(sp)))
  expect_true(is_gg(at_plot_spectrum(sp, colour_by = "roi_id")))
})

test_that("the at_plot generic and autoplot dispatch", {
  proj <- demo_project()
  data_img <- new_annot_image("k.tif", "raster", c(4L, 4L), 1L, list(c(4L, 4L)), 1L,
                              handle = list(data = array(1, dim = c(4, 4, 1))),
                              dtype = "uint8")
  expect_true(is_gg(at_plot(proj)))
  expect_true(is_gg(at_plot(data_img)))
  expect_true(is_gg(at_plot(proj$layers$tissue)))
  expect_true(is_gg(ggplot2::autoplot(proj)))
  expect_true(is_gg(ggplot2::autoplot(at_mask(proj, "labelled"))))
})

test_that("plots do not error on empty input", {
  ep <- at_project(small_image())
  expect_true(is_gg(at_plot_project(ep)))
  expect_true(is_gg(at_plot_summary(ep)))
  expect_true(is_gg(at_plot_spectrum(.empty_extract_tbl())))
})

test_that("no plot function draws to a device when called", {
  # ggplot construction is lazy; building must not open a device.
  before <- length(grDevices::dev.list())
  invisible(at_plot_project(demo_project()))
  invisible(at_plot_summary(demo_project()))
  expect_equal(length(grDevices::dev.list()), before)
})
