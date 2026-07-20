test_that(".check_string accepts a string and rejects non-strings", {
  expect_invisible(.check_string("a"))
  expect_error(.check_string(1), "must be a single string")
  expect_error(.check_string(c("a", "b")), "must be a single string")
  expect_error(.check_string(NA_character_), "must be a single string")
  expect_invisible(.check_string(NULL, allow_null = TRUE))
})

test_that(".check_flag requires a single TRUE/FALSE", {
  expect_invisible(.check_flag(TRUE))
  expect_error(.check_flag(NA), "TRUE")
  expect_error(.check_flag(c(TRUE, FALSE)), "TRUE")
  expect_error(.check_flag("yes"), "TRUE")
})

test_that(".check_number enforces finiteness and bounds", {
  expect_invisible(.check_number(1.5))
  expect_error(.check_number(Inf), "finite")
  expect_error(.check_number(NA_real_), "finite")
  expect_error(.check_number(5, max = 4), "range")
  expect_error(.check_number(-1, min = 0), "range")
})

test_that(".check_count requires a non-negative whole number", {
  expect_identical(.check_count(3), 3L)
  expect_error(.check_count(1.5), "whole number")
  expect_error(.check_count(-1), "at least")
})

test_that(".check_choice matches one of the allowed values", {
  expect_identical(.check_choice(c("a", "b"), c("a", "b")), "a")
  expect_identical(.check_choice("b", c("a", "b")), "b")
  expect_error(.check_choice("z", c("a", "b")), "must be one of")
})

test_that(".check_file and .check_dir validate existence", {
  f <- withr::local_tempfile()
  writeLines("x", f)
  expect_invisible(.check_file(f))
  expect_error(.check_file(tempfile()), "existing file")
  expect_invisible(.check_dir(dirname(f)))
  expect_error(.check_dir(tempfile()), "existing directory")
})

test_that(".check_class and domain checkers dispatch on class", {
  expect_error(.check_image(1), "annot_image")
  expect_error(.check_roi(1), "annot_roi")
  expect_error(.check_layer(1), "annot_layer")
  expect_error(.check_project(1), "annot_project")
})

test_that(".empty_roi_tbl has the contracted structure", {
  t <- .empty_roi_tbl()
  expect_s3_class(t, "tbl_df")
  expect_equal(nrow(t), 0L)
  expect_identical(
    names(t),
    c("roi_id", "layer", "label", "geom_type", "level", "area_px",
      "centroid_x", "centroid_y", "n_vertices", "created", "modified",
      "author", "source", "geometry")
  )
  expect_true(inherits(t$geometry, "sfc"))
})

test_that(".resolve_palette cycles Okabe-Ito and honours names", {
  p <- .resolve_palette(c("a", "b", "c"))
  expect_named(p, c("a", "b", "c"))
  expect_identical(unname(p[1]), "#999999")
  p2 <- .resolve_palette(c("a", "b"), c(a = "#000000"))
  expect_identical(unname(p2["a"]), "#000000")
  expect_length(.resolve_palette(character()), 0L)
})

test_that(".new_id is unique and counter resets deterministically", {
  .reset_id_counter()
  expect_identical(.new_id("roi"), "roi_000000001")
  expect_identical(.new_id("roi"), "roi_000000002")
  .reset_id_counter()
  expect_identical(.new_id("roi"), "roi_000000001")
})
