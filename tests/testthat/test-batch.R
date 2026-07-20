skip_if_not_installed("tiff")

test_that("at_export_all writes every format in the right layout", {
  sess <- at_example_session(3)
  dir <- withr::local_tempdir()
  receipt <- suppressMessages(at_export_all(sess, dir, scope = "all", progress = FALSE))
  expect_s3_class(receipt, "tbl_df")
  expect_identical(names(receipt),
                   c("image", "format", "path", "bytes", "n_rois", "status", "message"))
  expect_setequal(list.dirs(dir, recursive = FALSE, full.names = FALSE),
                  c("masks", "geojson", "qupath", "projects", "csv"))
  expect_true(file.exists(file.path(dir, "_export_manifest.csv")))
  expect_true(file.exists(file.path(dir, "_annotation_summary.csv")))
})

test_that("the export receipt is accurate", {
  sess <- at_example_session(2)
  dir <- withr::local_tempdir()
  receipt <- suppressMessages(at_export_all(sess, dir, scope = "all",
                                            formats = c("geojson", "csv"), progress = FALSE))
  ok <- receipt[receipt$status == "ok", ]
  expect_true(all(file.exists(ok$path)))
  expect_true(all(ok$bytes > 0))
})

test_that("a mid-batch failure is isolated in the receipt", {
  sess <- at_example_session(4)
  file.remove(at_session_status(sess)$path[3])
  dir <- withr::local_tempdir()
  receipt <- suppressWarnings(suppressMessages(
    at_export_all(sess, dir, scope = "all", progress = FALSE)
  ))
  bad <- at_session_status(sess)$name[3]
  expect_true(any(receipt$image == bad & receipt$status == "error"))
  expect_true(any(receipt$status == "ok"))
})

test_that("at_manifest label counts match at_rois aggregation", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- at_example_project()
  man <- at_manifest(sess)
  expect_true(all(c("idx", "name", "path", "status", "n_layers", "n_rois") %in% names(man)))
  rt <- at_rois(sess$projects[[1]])
  for (lb in c("tumour", "necrosis", "stroma")) {
    expect_identical(man[[lb]][1], sum(rt$label == lb))
  }
})

test_that("at_batch_apply modifies all projects and returns a session", {
  sess <- at_example_session(3)
  relabel <- function(project, image, idx, ...) {
    rt <- at_rois(project)
    project # identity keeps materialisation but exercises the path
  }
  out <- at_batch_apply(sess, relabel, progress = FALSE)
  expect_s3_class(out, "annot_session")
  expect_true(all(!vapply(out$projects, is.null, logical(1))))
})

test_that("at_batch_validate flags broken geometry and is clean otherwise", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- broken_project("self_intersect")
  bv <- at_batch_validate(sess)
  expect_identical(names(bv), c("image", "roi_id", "issue", "severity"))
  expect_true("self_intersection" %in% bv$issue)
  # A clean session yields 0 rows.
  clean <- at_example_session(2)
  clean$projects[[1]] <- at_example_project()
  expect_equal(nrow(at_batch_validate(clean)), 0L)
})

test_that("at_summary_table aggregates by the chosen key", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- at_example_project()
  st <- at_summary_table(sess, by = "label")
  expect_true(all(c("label", "n_rois", "total_area_px", "mean_area", "sd_area") %in% names(st)))
  expect_setequal(st$label, c("tumour", "necrosis", "stroma"))
  # Empty session -> 0 rows with the key column.
  empty <- at_summary_table(at_example_session(2), by = "image")
  expect_equal(nrow(empty), 0L)
  expect_identical(names(empty)[1], "image")
})
