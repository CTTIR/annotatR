# Systematic adversarial inputs across the categories in the robustness table.

test_that("NULL is rejected with an informative error", {
  expect_error(at_dims(NULL), "annot_image")
  expect_error(at_rois(NULL), "annot_project")
  expect_error(at_mask(NULL), "annot_roi")
  expect_error(at_layers(NULL), "annot_project")
  expect_error(at_read_image(NULL), "single string")
})

test_that("NA is rejected where a value is required", {
  expect_error(at_roi_point(NA_real_, 1, label = "a"), "finite number")
  expect_error(at_roi_rect(NA, 0, 4, 4, label = "a"), "finite number")
  expect_error(at_roi_point(1, 1, label = NA_character_), "single string")
})

test_that("wrong class is rejected naming the expected class", {
  proj <- demo_project()
  expect_error(at_add_roi(proj, "tissue", "not-an-roi"), "annot_roi")
  expect_error(at_add_layer(proj, 42), "annot_layer")
  expect_error(at_mask_stats(42), "annot_mask")
  expect_error(at_next(42), "annot_session")
})

test_that("wrong length is rejected", {
  expect_error(at_roi_point(c(1, 2), 3, label = "a"), "finite number")
  expect_error(at_clamp(at_roi_rect(0, 0, 4, 4, label = "a"), c(1, 2, 3)), "length-2")
})

test_that("negative where positive is required is rejected", {
  expect_error(at_roi_circle(5, 5, r = -1, label = "a"), "range")
  expect_error(at_mask(demo_project(), level = -1), "at least 0")
  expect_error(at_style(fill_alpha = -0.5), "range")
})

test_that("non-existent and unreadable paths error with the path", {
  expect_error(at_read_image(tempfile()), "existing file")
  expect_error(at_load_project(tempfile()), "existing file")
  # A corrupt file that no backend recognises.
  f <- withr::local_tempfile(fileext = ".xyz")
  writeLines("garbage", f)
  expect_error(at_read_image(f), "No backend")
})

test_that("out-of-range levels and bands are rejected stating the valid range", {
  img <- small_image()
  expect_error(at_dims(img, 9), "exceed")
  expect_error(at_tile(img, level = 9), "exceed")
  # tile band range needs pixel data
  di <- new_annot_image("k.tif", "raster", c(4L, 4L), 1L, list(c(4L, 4L)), 2L,
                        handle = list(data = array(1, dim = c(4, 4, 2))))
  expect_error(at_tile(di, bands = 9), "out of range")
})

test_that("duplicate layer names and ROI ids are caught", {
  proj <- demo_project()
  expect_error(at_add_layer(proj, at_layer("tissue")), "already exists")
  proj$layers$tissue$rois[[2]]$id <- proj$layers$tissue$rois[[1]]$id
  expect_error(at_validate(proj), "unique")
})

test_that("a very large per-pixel extraction is guarded before allocation", {
  img <- new_annot_image("k.tif", "raster", c(100L, 100L), 1L, list(c(100L, 100L)), 1L,
                         handle = list(data = array(1, dim = c(100, 100, 1))))
  proj <- at_project(img, at_layer_add(at_layer("l"), at_roi_rect(0, 0, 100, 100, label = "a")))
  expect_error(at_extract_pixels(proj, max_px = 10), "max_px")
})

test_that("empty inputs yield type-stable empty results, not errors or NULL", {
  proj <- at_project(small_image())
  expect_equal(nrow(at_rois(proj)), 0L)
  expect_equal(nrow(at_layers(proj)), 0L)
  expect_equal(nrow(at_extract(proj)), 0L)
  expect_equal(nrow(at_check_geometry(proj)), 0L)
  expect_true(all(as.matrix(at_mask(proj, "labelled")) == 0L))
})

test_that("at_roi_from_geojson converts a feature and rejects malformed input", {
  feat <- list(geometry = list(type = "Polygon",
    coordinates = list(list(c(0, 0), c(4, 0), c(4, 4), c(0, 4), c(0, 0)))))
  roi <- at_roi_from_geojson(feat, label = "region")
  expect_s3_class(roi, "annot_roi")
  expect_equal(at_roi_area(roi), 16)
  expect_error(at_roi_from_geojson(list(a = 1)), "geometry")
})
