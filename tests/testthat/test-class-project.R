test_that("at_project builds provenance and normalises layers", {
  proj <- demo_project()
  expect_s3_class(proj, "annot_project")
  expect_identical(proj$provenance$annotatR_version, as.character(utils::packageVersion("annotatR")))
  expect_named(proj$layers, c("tissue", "tumour"))
})

test_that("at_rois returns the exact contracted tibble (populated)", {
  proj <- demo_project()
  t <- at_rois(proj)
  expect_s3_class(t, "tbl_df")
  expect_equal(nrow(t), 3L)
  expect_identical(names(t), names(.empty_roi_tbl()))
  empty <- .empty_roi_tbl()
  types <- vapply(t[-14], function(x) class(x)[[1]], character(1))
  etypes <- vapply(empty[-14], function(x) class(x)[[1]], character(1))
  expect_identical(types, etypes)
  expect_true(inherits(t$geometry, "sfc"))
})

test_that("at_rois is type-stable on empty input", {
  proj <- at_project(small_image())
  t <- at_rois(proj)
  expect_s3_class(t, "tbl_df")
  expect_equal(nrow(t), 0L)
  expect_identical(names(t), names(.empty_roi_tbl()))
})

test_that("at_rois filters by layer and label", {
  proj <- demo_project()
  expect_equal(nrow(at_rois(proj, layer = "tumour")), 1L)
  expect_equal(nrow(at_rois(proj, label = "tissue")), 2L)
  expect_equal(nrow(at_rois(proj, label = "absent")), 0L)
})

test_that("at_layers reports one row per layer, empty-safe", {
  proj <- demo_project()
  l <- at_layers(proj)
  expect_equal(nrow(l), 2L)
  expect_identical(names(l), c("name", "n_rois", "labels", "visible", "locked", "z"))
  expect_identical(l$z, c(1L, 2L))
  expect_equal(nrow(at_layers(at_project(small_image()))), 0L)
})

test_that("at_add_layer rejects duplicate names", {
  proj <- demo_project()
  expect_error(at_add_layer(proj, at_layer("tissue")), "already exists")
})

test_that("at_add_roi requires an existing layer and keeps ids unique", {
  proj <- demo_project()
  expect_error(at_add_roi(proj, "nope", at_roi_point(1, 1, label = "x")), "No layer")
  proj2 <- at_add_roi(proj, "tissue", at_roi_point(1, 1, label = "tissue"))
  ids <- at_rois(proj2)$roi_id
  expect_length(unique(ids), length(ids))
})

test_that("mutators do not modify their input", {
  proj <- demo_project()
  snapshot <- proj
  invisible(at_add_roi(proj, "tissue", at_roi_point(1, 1, label = "tissue")))
  invisible(at_remove_layer(proj, "tumour"))
  expect_identical(proj, snapshot)
})

test_that("at_remove_roi removes across layers or warns", {
  proj <- demo_project()
  id <- at_rois(proj)$roi_id[1]
  proj2 <- at_remove_roi(proj, id)
  expect_equal(nrow(at_rois(proj2)), nrow(at_rois(proj)) - 1L)
  expect_warning(at_remove_roi(proj, "no-such-id"), "nothing removed")
})

test_that("edit log grows with each mutation", {
  proj <- demo_project()
  n0 <- length(proj$provenance$edit_log)
  proj <- at_add_roi(proj, "tissue", at_roi_point(1, 1, label = "tissue"))
  expect_equal(length(proj$provenance$edit_log), n0 + 1L)
})

test_that("at_validate passes clean projects and flags duplicate ids", {
  proj <- demo_project()
  expect_s3_class(at_validate(proj), "annot_project")
  proj$layers$tissue$rois[[2]]$id <- proj$layers$tissue$rois[[1]]$id
  expect_error(at_validate(proj), "unique")
})

test_that("at_summary returns per-label counts", {
  s <- at_summary(demo_project())
  expect_s3_class(s, "annot_summary")
  expect_identical(s$n_layers, 2L)
  expect_identical(s$n_rois, 3L)
  expect_true(all(c("tissue", "tumour") %in% s$per_label$label))
})

test_that("print methods produce output", {
  expect_output(print(demo_project()), "annot_project")
  expect_output(print(at_summary(demo_project())), "annot_summary")
})

test_that("at_project rejects a non-layer layers argument", {
  expect_error(at_project(small_image(), layers = 42), "annot_layer")
  expect_error(at_project(small_image(), layers = list(1, 2)), "Every element")
})

test_that("at_rois errors on an unknown layer filter", {
  expect_error(at_rois(demo_project(), layer = "nope"), "No layer")
  expect_error(at_add_roi(demo_project(), "nope", at_roi_point(1, 1, label = "x")), "No layer")
  expect_error(at_remove_layer(demo_project(), "nope"), "No layer")
})

test_that("summary.annot_project dispatches to at_summary", {
  expect_s3_class(summary(demo_project()), "annot_summary")
})

test_that("at_project detects duplicate layer names on construction", {
  a <- at_layer("dup")
  expect_error(.normalize_layers(list(a, a)), "unique")
})
