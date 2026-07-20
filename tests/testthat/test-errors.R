# Snapshots of the most important user-facing error messages, so their
# informativeness is reviewed and regressions are caught. Kept to stable,
# high-value paths to avoid brittle snapshots.

test_that("ROI constructor errors are informative", {
  expect_snapshot(at_roi_rect(4, 0, 0, 4, label = "a"), error = TRUE)
  expect_snapshot(at_roi_point("x", 1, label = "a"), error = TRUE)
  expect_snapshot(at_roi_polygon("nope", label = "a"), error = TRUE)
})

test_that("image and tile errors are informative", {
  expect_snapshot(at_read_image("/no/such/file.png"), error = TRUE)
  # Level validation happens before any pixel access, so a metadata-only image
  # is enough to exercise it.
  expect_snapshot(at_tile(small_image(), level = 9), error = TRUE)
  expect_snapshot(at_dims(small_image(), level = 9), error = TRUE)
})

test_that("project and mask errors are informative", {
  expect_snapshot(at_project(small_image(), layers = 42), error = TRUE)
  expect_snapshot(at_rois(demo_project(), layer = "nope"), error = TRUE)
  expect_snapshot(at_mask(42), error = TRUE)
})

test_that("io clobber errors mention the overwrite option", {
  # Not snapshotted: the message contains a temporary path, which varies.
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  expect_error(at_write_geojson(proj, p), "already exists")
})
