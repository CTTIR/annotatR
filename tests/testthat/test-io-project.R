test_that("project RDS round-trips identically", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".rds")
  at_save_project(proj, p)
  p2 <- at_load_project(p)
  expect_equal(at_rois(proj)$geometry, at_rois(p2)$geometry)
  expect_identical(at_rois(proj)$label, at_rois(p2)$label)
  expect_equal(at_layers(proj), at_layers(p2))
})

test_that("a newer-version file triggers a migration warning", {
  proj <- demo_project()
  proj$provenance$saved_with <- "99.0.0"
  p <- withr::local_tempfile(fileext = ".rds")
  saveRDS(proj, p)
  expect_warning(at_load_project(p), "newer")
})

test_that("at_save_project refuses to clobber", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".rds")
  at_save_project(proj, p)
  expect_error(at_save_project(proj, p), "already exists")
})

test_that("session save/load round-trips", {
  sess <- demo_session(3)
  sess <- at_set_status(sess, 1, "complete")
  at_save_session(sess)
  loaded <- at_load_session(file.path(sess$out_dir, "_session.rds"))
  expect_s3_class(loaded, "annot_session")
  expect_identical(at_session_status(loaded)$status[1], "complete")
})
