test_that("at_session builds a manifest over existing paths", {
  sess <- demo_session(4)
  expect_s3_class(sess, "annot_session")
  m <- at_session_status(sess)
  expect_equal(nrow(m), 4L)
  expect_identical(unique(m$status), "pending")
  expect_identical(sess$cursor, 1L)
})

test_that("at_session rejects missing paths and non-character input", {
  expect_error(at_session(character()), "non-empty")
  expect_error(at_session(tempfile()), "must exist")
})

test_that("navigation clamps at both ends", {
  sess <- demo_session(3)
  sess <- at_next(at_next(at_next(sess)))
  expect_identical(sess$cursor, 3L)
  sess <- at_prev(at_prev(at_prev(sess)))
  expect_identical(sess$cursor, 1L)
})

test_that("at_goto validates the index", {
  sess <- demo_session(3)
  expect_identical(at_goto(sess, 2)$cursor, 2L)
  expect_error(at_goto(sess, 99), "out of range")
})

test_that("at_set_status validates the status value", {
  sess <- demo_session(3)
  sess <- at_set_status(sess, 1, "complete")
  expect_identical(at_session_status(sess)$status[1], "complete")
  expect_error(at_set_status(sess, 1, "bogus"), "must be one of")
})

test_that("navigation and status do not modify their input", {
  sess <- demo_session(3)
  snapshot <- sess
  invisible(at_next(sess))
  invisible(at_set_status(sess, 1, "flagged"))
  expect_identical(sess, snapshot)
})

test_that("at_manifest adds per-label count columns", {
  sess <- demo_session(3, labels = c("tumour", "stroma"))
  man <- at_manifest(sess)
  expect_true(all(c("idx", "name", "status", "n_rois", "tumour", "stroma") %in% names(man)))
  expect_equal(nrow(man), 3L)
})

test_that("session save/load round-trips identically", {
  sess <- demo_session(3)
  sess <- at_set_status(sess, 1, "complete")
  path <- at_session_save(sess)$out_dir
  loaded <- at_resume(file.path(sess$out_dir, "_session.rds"))
  expect_identical(loaded, sess)
})

test_that("at_session_save returns the session invisibly", {
  sess <- demo_session(2)
  expect_invisible(at_session_save(sess))
})

test_that("print produces output", {
  expect_output(print(demo_session(2)), "annot_session")
})
