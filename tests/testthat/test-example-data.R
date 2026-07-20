test_that("at_example_path returns existing files", {
  for (w in c("tissue", "multiplex", "cube")) {
    expect_true(file.exists(at_example_path(w)))
  }
  expect_error(at_example_path("nope"), "must be one of")
})

test_that("at_example_image reads each example", {
  skip_if_not_installed("tiff")
  expect_s3_class(at_example_image("tissue"), "annot_image")
  expect_s3_class(at_example_image("multiplex"), "annot_image")
  expect_s3_class(at_example_image("cube"), "annot_image")
})

test_that("at_example_project is populated and honours the query contract", {
  skip_if_not_installed("tiff")
  proj <- at_example_project()
  expect_s3_class(proj, "annot_project")
  t <- at_rois(proj)
  expect_equal(nrow(t), 3L)
  expect_setequal(t$label, c("tumour", "necrosis", "stroma"))
  expect_identical(names(t), names(.empty_roi_tbl()))
})

test_that("at_example_session builds a queue over real files", {
  sess <- at_example_session(4)
  expect_s3_class(sess, "annot_session")
  expect_equal(nrow(at_session_status(sess)), 4L)
  expect_true(all(file.exists(at_session_status(sess)$path)))
})
