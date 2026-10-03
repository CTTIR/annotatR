workflow_example <- function() {
  env <- new.env(parent = globalenv())
  sys.source(test_path("..", "..", "inst", "examples", "reproducible-analysis.R"), env)
  env
}

test_that("persisted analytical workflow repeats exactly and matches independent estimands", {
  example <- workflow_example()
  fixture <- normalizePath(test_path("fixtures", "analytical"))
  work <- tempfile(); dir.create(work)
  withr::defer(unlink(work, recursive = TRUE))
  project <- file.path(work, "annotations.rds")
  example$prepare_analytical_example(fixture, project)
  before <- readBin(project, "raw", n = file.info(project)$size)
  a <- example$run_analytical_example(project, fixture, file.path(work, "first"))
  b <- example$run_analytical_example(project, fixture, file.path(work, "second"))
  expect_identical(a, b)
  expect_identical(readBin(project, "raw", n = file.info(project)$size), before)
  files <- list.files(file.path(work, "first"))
  expect_setequal(files, c(paste0(names(a$tables), ".csv"), "settings.json"))
  expect_identical(unname(tools::md5sum(file.path(work, "first", files))),
                   unname(tools::md5sum(file.path(work, "second", files))))
  expect_error(example$prepare_analytical_example(fixture, project), "exists")
  expect_error(example$run_analytical_example(project, fixture, file.path(work, "first")),
               "exists")

  expected <- jsonlite::read_json(file.path(fixture, "analysis-expected.json"))
  expect_identical(a$settings$sampling_units,
                   expected$sampling_units[names(a$settings$sampling_units)])
  expect_equal(unname(as.matrix(a$tables$mask)), do.call(rbind, lapply(expected$bitfield, unlist)))
  for (e in expected$finite_omit_statistics) {
    rows <- subset(a$tables$roi_statistics, label == e$roi & band == e$band)
    expect_equal(rows$n_px, rep(e$n_selected, 7))
    expect_equal(rows$n_valid, rep(e$n_valid, 7))
    expect_equal(rows$n_invalid, rep(e$n_invalid, 7))
    for (s in c("mean", "median", "sd", "min", "max", "sum"))
      expect_equal(rows$value[rows$stat == s], e[[s]], tolerance = 1e-12)
    expect_equal(rows$value[rows$stat == "n"], e$n_selected)
  }
  for (e in expected$union_pixel_statistics) {
    row <- subset(a$tables$image_statistics, band == e$band)
    for (s in c("n_selected", "n_valid", "n_invalid", "mean", "median", "sd", "min", "max", "sum"))
      expect_equal(row[[s]], e[[s]], tolerance = 1e-12)
    expect_identical(row$estimand, "unique selected pixels within image")
  }
  expect_equal(nrow(a$tables$pixel_memberships), 54L)
  expect_equal(nrow(a$tables$unique_pixels), 48L)
  expect_equal(sum(a$tables$pixel_memberships$sample_status != "finite"), 5L)
  expect_equal(sum(a$tables$unique_pixels$sample_status != "finite"), 4L)
  expect_equal(a$tables$spectra$value,
               a$tables$roi_statistics$value[a$tables$roi_statistics$stat == "mean"])
  expect_false(isTRUE(all.equal(a$tables$image_statistics$mean[1],
                               mean(a$tables$spectra$value[a$tables$spectra$band == 1]))))
  expect_equal(a$tables$counts$n_background, 4L)
  expect_equal(a$tables$counts$n_overlap, 2L)
  expect_equal(a$tables$counts$n_excluded_rois, 0L)

  agreement <- jsonlite::read_json(file.path(fixture, "agreement-expected.json"))
  for (case in c("categorical", "bitfield")) {
    actual <- subset(a$tables$agreement, comparison == case)
    for (e in agreement[[case]]$per_class) {
      row <- actual[actual$label == e$label, ]
      for (s in c("n_true", "n_pred", "tp", "fp", "fn"))
        expect_equal(row[[s]], e[[s]])
      for (s in c("dice", "iou"))
        if (is.null(e[[s]])) expect_true(is.na(row[[s]])) else
          expect_equal(row[[s]], e[[s]]$value, tolerance = 1e-12)
    }
  }
  overall <- a$tables$agreement_overall
  expect_equal(overall$accuracy, c(3/4, 3/4, 2/3))
  expect_equal(overall$kappa, c(5/8, 5/8, NA))
  expect_identical(overall$code_alignment, c("strict", "by-label", "strict"))
  expect_identical(a$settings$extraction$nonfinite, "omit")
  expect_identical(a$settings$annotation$entry_id, "analytical-image-001")
  expect_identical(a$settings$annotation$revision, 0L)
  expect_identical(a$settings$annotation$roi_ids, c(
    "00000000-0000-0000-0000-00000000012a", "00000000-0000-0000-0000-00000000012b"))
  expect_identical(a$settings$calibration$physical_status, "unknown")
  expect_identical(a$settings$backend$plugin_version, "unknown")
  expect_identical(a$settings$extraction$sample_contract, "raw-scalar-v1")
  expect_true(all(a$tables$spectra$unit == "nm"))
  expect_identical(a$settings$source$descriptor$options, list())
  expect_true(all(nzchar(unlist(a$settings$versions$packages))))
  expect_equal(length(a$settings$inputs$md5), 9L)
  expect_false(any(c("created", "read_generation", "cache_identity") %in%
                     names(a$settings)))
})

test_that("workflow requires persisted revision and records changed annotations", {
  example <- workflow_example()
  fixture <- normalizePath(test_path("fixtures", "analytical"))
  work <- tempfile(); dir.create(work)
  withr::defer(unlink(work, recursive = TRUE))
  path <- file.path(work, "annotations.rds")
  example$prepare_analytical_example(fixture, path)
  p <- at_load_project(path)
  original <- example$run_analytical_example(path, fixture)
  p$meta$annotation_revision <- NULL
  at_save_project(p, path, overwrite = TRUE)
  expect_error(example$run_analytical_example(path, fixture), "annotation_revision")
  p <- at_remove_roi(p, "00000000-0000-0000-0000-00000000012b")
  p$meta$annotation_revision <- 1L
  at_save_project(p, path, overwrite = TRUE)
  changed <- example$run_analytical_example(path, fixture)
  expect_identical(changed$settings$annotation$revision, 1L)
  expect_equal(changed$tables$counts$n_roi, 1L)
  expect_equal(changed$tables$counts$n_unique_selected, 9L)
  expect_equal(changed$tables$counts$n_roi_memberships, 9L)
  expect_equal(changed$tables$counts$n_overlap, 0L)
  expect_equal(changed$tables$image_statistics$mean[1], 987/8)
  expect_false(identical(original$settings$inputs$md5$persisted_project,
                         changed$settings$inputs$md5$persisted_project))
  p <- at_remove_roi(p, "00000000-0000-0000-0000-00000000012a")
  p$meta$annotation_revision <- 2L
  at_save_project(p, path, overwrite = TRUE)
  empty <- example$run_analytical_example(path, fixture)
  expect_equal(empty$tables$image_statistics$n_selected, rep(0L, 3L))
  expect_true(all(is.na(empty$tables$image_statistics$sum)))
  expect_equal(empty$tables$counts$n_background, 20L)
})
