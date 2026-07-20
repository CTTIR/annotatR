# Regression tests for defects found and fixed during Refine Loop 1 (correctness).
# Each test would fail against the pre-fix code.

test_that("overlap='max' paints covered pixels even when background exceeds the value", {
  # The 'max' branch previously lacked the fresh-pixel guard the 'min' branch has,
  # so pmax(background, value) left covered pixels as background when background > value.
  proj <- at_project(
    tiny_image(),
    at_layer_add(at_layer("l", labels = "a"), at_roi_rect(2, 2, 5, 5, label = "a"))
  )
  mm <- as.matrix(at_mask(proj, type = "labelled", overlap = "max", background = 5L))
  expect_equal(sum(mm == 1L), 9L)              # the 3x3 ROI survives, not swallowed by bg
  expect_true(all(mm[mm != 1L] == 5L))
  # It agrees with overlap='last' on which pixels the ROI covers.
  ml <- as.matrix(at_mask(proj, type = "labelled", overlap = "last", background = 5L))
  expect_identical(mm == 1L, ml == 1L)
})

test_that("at_write_masks returns a typed 0-row receipt (not NULL) for a project with no ROIs", {
  proj <- at_project(tiny_image())             # no layers -> no mask jobs
  dir <- withr::local_tempdir()
  r <- at_write_masks(proj, dir, per = "roi")
  expect_s3_class(r, "tbl_df")
  expect_equal(nrow(r), 0L)
  expect_identical(names(r), c("path", "type", "n_px", "bytes"))
})

test_that("at_roi_overlaps normalises pyramid levels before intersecting", {
  # roi1 at level 0 covers px 200..300; roi2 declared at level 2 with raw coords
  # 60..70 maps to level-0 240..280 -> physically inside roi1.
  roi1 <- at_roi_rect(200, 200, 300, 300, label = "a")
  roi2 <- new_annot_roi(
    geometry = sf::st_sfc(sf::st_polygon(list(rbind(
      c(60, 60), c(70, 60), c(70, 70), c(60, 70), c(60, 60)
    ))), crs = sf::NA_crs_),
    id = "r2", label = "b", level = 2L
  )
  expect_true(at_roi_overlaps(roi1, roi2))     # false without level normalisation
})

test_that("at_fix_geometry clamps out-of-bounds vertices into the image bounds", {
  proj <- broken_project("out_of_bounds")      # tiny_image() is 10x10; polygon to 9999
  # at_check_geometry advertises out_of_bounds as fixable; at_fix_geometry must honour it.
  expect_true("out_of_bounds" %in% at_check_geometry(proj)$issue)
  fixed <- at_fix_geometry(proj, verbose = FALSE)
  xy <- sf::st_coordinates(fixed$layers[["broken"]]$rois[[1]]$geometry)[, c("X", "Y")]
  expect_true(all(xy[, 1] >= 0 & xy[, 1] <= 10))
  expect_true(all(xy[, 2] >= 0 & xy[, 2] <= 10))
  expect_false("out_of_bounds" %in% at_check_geometry(fixed)$issue)
})

test_that("at_roi_union and at_roi_intersect reject an empty ROI set with an informative error", {
  empty <- at_layer("e")
  expect_error(at_roi_union(empty), "at least one ROI")
  expect_error(at_roi_intersect(empty), "at least one ROI")
})

test_that(".resolve_palette maps a named colour vector by label, not by position", {
  labels <- c("tumour", "stroma", "tissue")
  cols <- c(tissue = "#111111", tumour = "#222222")  # out of label order, partial
  pal <- .resolve_palette(labels, cols)
  expect_equal(pal[["tumour"]], "#222222")
  expect_equal(pal[["tissue"]], "#111111")
  # 'stroma' was unnamed in the input -> filled from the palette, not a supplied colour.
  expect_false(pal[["stroma"]] %in% c("#111111", "#222222"))
})

test_that(".to_level0 is the exact inverse of .geom_to_level for an anisotropic pyramid", {
  # Level-1 downsamples x by 4 and y by 2 (anisotropic): a single scale factor is wrong.
  img <- new_annot_image("a.tif", "tiff", c(100L, 80L), 2L,
                         list(c(100L, 80L), c(25L, 40L)), 1L)
  g0 <- sf::st_sfc(sf::st_point(c(50, 40)), crs = sf::NA_crs_)
  back <- .to_level0(.geom_to_level(g0, 1L, img), 1L, img)
  expect_equal(sf::st_coordinates(back), sf::st_coordinates(g0), tolerance = 1e-9)
})

test_that(".check_choice gives a typed error (not 'subscript out of bounds') for length-0 input", {
  expect_error(.check_choice(character(0), c("a", "b")), "must be one of")
})
