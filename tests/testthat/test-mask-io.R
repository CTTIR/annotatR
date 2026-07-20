skip_if_not_installed("tiff")

test_that("mask TIFF round-trips values and writes a legend sidecar", {
  m <- at_mask(demo_project(), "labelled")
  p <- withr::local_tempfile(fileext = ".tif")
  at_write_mask(m, p)
  expect_true(file.exists(p))
  expect_true(file.exists(paste0(p, ".legend.json")))
})

test_that("at_write_mask refuses to clobber without overwrite", {
  m <- at_mask(demo_project(), "labelled")
  p <- withr::local_tempfile(fileext = ".tif")
  at_write_mask(m, p)
  expect_error(at_write_mask(m, p), "already exists")
  expect_invisible(at_write_mask(m, p, overwrite = TRUE))
})

test_that("PNG masks reject values above 255", {
  lg <- tibble::tibble(value = 300L, label = "x", layer = NA_character_,
                       roi_id = NA_character_, n_px = 16L, colour = "#000000")
  big <- .new_annot_mask(matrix(300L, 4, 4), lg, 0L, c(4L, 4L), "labelled")
  p <- withr::local_tempfile(fileext = ".png")
  expect_error(at_write_mask(big, p, format = "png"), "8-bit")
})

test_that("PNG masks write for small label counts", {
  skip_if_not(requireNamespace("tiff", quietly = TRUE) ||
                requireNamespace("magick", quietly = TRUE))
  m <- at_mask(demo_project(), "labelled")
  p <- withr::local_tempfile(fileext = ".png")
  expect_invisible(at_write_mask(m, p, format = "png"))
})

test_that("read_mask -> mask round-trips pixel sets exactly for rectangles", {
  lyr <- at_layer_add(at_layer_add(at_layer("l"),
                                   at_roi_rect(2, 2, 6, 6, label = "a")),
                      at_roi_rect(10, 10, 15, 15, label = "b"))
  proj <- at_project(small_image(), lyr)
  m <- at_mask(proj, "labelled", dims = c(20, 20))
  p <- withr::local_tempfile(fileext = ".tif")
  at_write_mask(m, p)
  lyr2 <- at_read_mask(p)
  m2 <- at_mask(lyr2, "labelled", dims = c(20, 20))
  expect_identical(as.matrix(m) != 0, as.matrix(m2) != 0)
})

test_that("read_mask recovers labels from the legend sidecar", {
  lyr <- at_layer_add(at_layer("l"), at_roi_rect(2, 2, 6, 6, label = "tumour"))
  proj <- at_project(small_image(), lyr)
  m <- at_mask(proj, "labelled", dims = c(20, 20))
  p <- withr::local_tempfile(fileext = ".tif")
  at_write_mask(m, p)
  lyr2 <- at_read_mask(p)
  expect_identical(lyr2$rois[[1]]$label, "tumour")
  expect_identical(lyr2$rois[[1]]$source, "mask")
})

test_that("read_mask round-trips curved shapes within a stated tolerance", {
  # Polygonisation of a rasterised circle is exact on pixels but the recovered
  # boundary is staircased; require Jaccard of pixel sets >= 0.95.
  lyr <- at_layer_add(at_layer("l"), at_roi_circle(25, 25, 15, label = "a"))
  proj <- at_project(small_image(), lyr)
  m <- at_mask(proj, "binary", dims = c(50, 50))
  p <- withr::local_tempfile(fileext = ".tif")
  at_write_mask(m, p)
  m2 <- at_mask(at_read_mask(p), "binary", dims = c(50, 50))
  s1 <- as.matrix(m)
  s2 <- as.matrix(m2)
  jac <- sum(s1 & s2) / sum(s1 | s2)
  expect_gt(jac, 0.95)
})

test_that("mask RDS round-trips full fidelity", {
  m <- at_mask(demo_project(), "labelled")
  p <- withr::local_tempfile(fileext = ".rds")
  at_write_mask(m, p, format = "rds")
  m2 <- readRDS(p)
  expect_identical(as.matrix(m), as.matrix(m2))
  expect_equal(at_mask_legend(m), at_mask_legend(m2))
})

test_that("at_write_masks emits a receipt and files per scope", {
  proj <- demo_project()
  dir <- withr::local_tempdir()
  receipt <- at_write_masks(proj, dir, per = "layer")
  expect_s3_class(receipt, "tbl_df")
  expect_identical(names(receipt), c("path", "type", "n_px", "bytes"))
  expect_true(all(file.exists(receipt$path)))
})

test_that("at_write_masks supports every split", {
  proj <- demo_project()
  for (per in c("roi", "class", "project")) {
    dir <- withr::local_tempdir()
    receipt <- at_write_masks(proj, dir, per = per)
    expect_true(nrow(receipt) >= 1L)
    expect_true(all(file.exists(receipt$path)))
  }
})
