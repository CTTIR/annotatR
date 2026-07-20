test_that("at_style validates and stores its fields", {
  s <- at_style(fill_alpha = 0.5, z = 3)
  expect_s3_class(s, "annot_style")
  expect_identical(s$z, 3L)
  expect_error(at_style(fill_alpha = 2), "range")
  expect_error(at_style(visible = NA), "TRUE")
})

test_that("at_layer resolves a stable colour mapping", {
  lyr <- at_layer("l", labels = c("a", "b"))
  expect_named(lyr$style$colour, c("a", "b"))
  expect_identical(unname(lyr$style$colour["a"]), "#999999")
  expect_identical(at_layer_n(lyr), 0L)
})

test_that("at_layer_add appends and extends labels", {
  lyr <- at_layer("l", labels = "a")
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 1, 1, label = "a"))
  lyr <- at_layer_add(lyr, at_roi_rect(2, 2, 3, 3, label = "new"))
  expect_identical(at_layer_n(lyr), 2L)
  expect_true("new" %in% lyr$labels)
  expect_true("new" %in% names(lyr$style$colour))
})

test_that("at_layer_add re-mints colliding identifiers", {
  lyr <- at_layer("l", labels = "a")
  r <- at_roi_rect(0, 0, 1, 1, label = "a", id = "dup")
  lyr <- at_layer_add(lyr, r)
  lyr <- at_layer_add(lyr, r)
  ids <- vapply(lyr$rois, `[[`, character(1), "id")
  expect_length(unique(ids), 2L)
})

test_that("at_layer_add does not modify its input", {
  lyr <- at_layer("l", labels = "a")
  snapshot <- lyr
  invisible(at_layer_add(lyr, at_roi_rect(0, 0, 1, 1, label = "a")))
  expect_identical(lyr, snapshot)
})

test_that("at_layer_remove drops the ROI or warns", {
  lyr <- at_layer("l", labels = "a")
  r <- at_roi_rect(0, 0, 1, 1, label = "a", id = "keepme")
  lyr <- at_layer_add(lyr, r)
  lyr2 <- at_layer_remove(lyr, "keepme")
  expect_identical(at_layer_n(lyr2), 0L)
  expect_warning(at_layer_remove(lyr, "nope"), "nothing removed")
})

test_that("at_layer_rois honours the query contract when empty", {
  t <- at_layer_rois(at_layer("l"))
  expect_equal(nrow(t), 0L)
  expect_identical(names(t), names(.empty_roi_tbl()))
})
