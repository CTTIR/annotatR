skip_if_not(requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE))
skip_if_not_installed("tiff")

handoff_fixture <- function(formats = c("qupath_geojson", "geojson", "mask_tiff", "mask_npy")) {
  proj <- at_example_project()
  dest <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "handoff")
  rc <- at_export_qupflowr(proj, dest, formats = formats)
  list(proj = proj, dest = dest, rc = rc)
}

# Independent integrity digest: build the canonical inventory string by hand
# (keys in byte order: files, format_version; per file: path, sha256, size_bytes).
independent_digest <- function(dir) {
  files <- sort(setdiff(list.files(dir, recursive = TRUE, all.files = TRUE), "integrity.json"),
                method = "radix")
  parts <- vapply(files, function(f) {
    sprintf('{"path":"%s","sha256":"%s","size_bytes":%d}', f,
            unname(tools::sha256sum(file.path(dir, f))), file.size(file.path(dir, f)))
  }, character(1))
  canon <- sprintf('{"files":[%s],"format_version":"1.0"}', paste(parts, collapse = ","))
  unname(tools::sha256sum(bytes = charToRaw(canon)))
}

rewrite_integrity <- function(dir) {
  .write_json_atomic(.build_integrity(dir), file.path(dir, "integrity.json"))
}

test_that("export writes the neutral handoff layout with a verifiable inventory", {
  f <- handoff_fixture()
  files <- sort(list.files(f$dest, recursive = TRUE))
  expect_identical(files, sort(c(
    "annotations.geojson", "annotations_qupath.geojson", "image.json", "integrity.json",
    "manifest.json", "masks/regions_labelled.npy", "masks/regions_labelled.npy.legend.json",
    "masks/regions_labelled.tif", "masks/regions_labelled.tif.legend.json"
  )))
  expect_identical(f$rc$handoff_digest, independent_digest(f$dest))
  expect_false(any(grepl("partial|previous", list.files(dirname(f$dest), all.files = TRUE))))
  man <- jsonlite::read_json(file.path(f$dest, "manifest.json"))
  expect_identical(man$consumer, "qupflowR")
  expect_length(man$masks, 2L)
  # The labelled mask joins to ROI ids through its legend; values are exact.
  m <- tiff::readTIFF(file.path(f$dest, "masks/regions_labelled.tif"), as.is = TRUE)
  rt <- at_rois(f$proj)
  expect_identical(as.integer(m[151 + 20, 121 + 20]), 1L)   # inside tumour (120,150)-(260,290)
  expect_identical(as.integer(m[1, 1]), 0L)
  lg <- jsonlite::read_json(file.path(f$dest, "masks/regions_labelled.tif.legend.json"),
                            simplifyVector = TRUE)$legend
  expect_identical(lg$roi_id[lg$value == 1L], rt$roi_id[1])
  q <- jsonlite::read_json(file.path(f$dest, "annotations_qupath.geojson"))
  expect_identical(q$features[[1]]$properties$objectType, "annotation")
  expect_identical(q$features[[1]]$properties$metadata$annotatr_roi_id, rt$roi_id[1])
  expect_match(q$features[[1]]$id, "^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-")
})

test_that("import validates the contract and returns namespaced annotatR objects", {
  f <- handoff_fixture()
  rep <- at_import_qupflowr(f$dest, expected_revision = at_annotation_revision(f$proj))
  expect_s3_class(rep, "at_import_report")
  expect_identical(rep$format, "handoff")
  expect_identical(rep$handoff_digest, f$rc$handoff_digest)
  expect_true(all(rep$checks$status %in% c("ok", "warn")))
  lyr <- rep$objects$layers$regions
  expect_s3_class(lyr, "annot_layer")
  expect_identical(vapply(lyr$rois, `[[`, character(1), "id"), at_rois(f$proj)$roi_id)
  expect_true(all(vapply(lyr$rois, `[[`, character(1), "source") == "imported"))
  expect_identical(lyr$rois[[1]]$attributes$qupflowr$handoff_digest, f$rc$handoff_digest)
  expect_identical(nrow(rep$conversion), 3L)
  expect_true(all(rep$conversion$geometry_match == "exact"))
  expect_length(rep$objects$masks, 2L)
  expect_identical(as.matrix(rep$objects$masks[[1]]),
                   { m <- as.matrix(at_mask(f$proj, "labelled")); storage.mode(m) <- "integer"; m })
  expect_identical(at_import_qupflowr(file.path(f$dest, "manifest.json"))$handoff_digest,
                   f$rc$handoff_digest)
})

test_that("a stale expected revision is a classified conflict", {
  f <- handoff_fixture("qupath_geojson")
  err <- tryCatch(at_import_qupflowr(f$dest, expected_revision = "sha256:0"), error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "REVISION_CONFLICT")
})

expect_import_code <- function(dir, code) {
  err <- tryCatch(at_import_qupflowr(dir), error = function(e) e)
  expect_s3_class(err, "at_error")
  expect_identical(err$code, code)
}

test_that("missing, extra, altered, duplicate and unsorted inventories are rejected", {
  f <- handoff_fixture("qupath_geojson")
  writeLines("x", file.path(f$dest, "extra.txt"))
  expect_import_code(f$dest, "INTEGRITY_EXTRA")
  unlink(file.path(f$dest, "extra.txt"))

  g <- handoff_fixture("qupath_geojson")
  unlink(file.path(g$dest, "image.json"))
  expect_import_code(g$dest, "INTEGRITY_MISSING")

  h <- handoff_fixture("qupath_geojson")
  p <- file.path(h$dest, "annotations_qupath.geojson")
  bytes <- readBin(p, "raw", file.size(p))
  bytes[20] <- as.raw(bitwXor(as.integer(bytes[20]), 1L))
  writeBin(bytes, p)
  expect_import_code(h$dest, "INTEGRITY_MISMATCH")

  k <- handoff_fixture("qupath_geojson")
  inv <- jsonlite::read_json(file.path(k$dest, "integrity.json"))
  inv$files <- c(inv$files, inv$files[1])
  inv$files <- inv$files[order(vapply(inv$files, `[[`, character(1), "path"))]
  jsonlite::write_json(inv, file.path(k$dest, "integrity.json"), auto_unbox = TRUE)
  expect_import_code(k$dest, "INTEGRITY_DUPLICATE")

  u <- handoff_fixture("qupath_geojson")
  inv <- jsonlite::read_json(file.path(u$dest, "integrity.json"))
  inv$files <- rev(inv$files)
  jsonlite::write_json(inv, file.path(u$dest, "integrity.json"), auto_unbox = TRUE)
  expect_import_code(u$dest, "INTEGRITY_INVALID")

  n <- handoff_fixture("qupath_geojson")
  unlink(file.path(n$dest, "integrity.json"))
  expect_import_code(n$dest, "INTEGRITY_MISSING")
})

test_that("corrupt, empty, foreign and future-version manifests are rejected", {
  f <- handoff_fixture("qupath_geojson")
  writeLines("{ not json", file.path(f$dest, "manifest.json"))
  rewrite_integrity(f$dest)
  expect_import_code(f$dest, "INVALID_JSON")

  g <- handoff_fixture("qupath_geojson")
  file.create(file.path(g$dest, "manifest.json"))
  rewrite_integrity(g$dest)
  expect_import_code(g$dest, "INVALID_JSON")

  h <- handoff_fixture("qupath_geojson")
  man <- jsonlite::read_json(file.path(h$dest, "manifest.json"))
  man$schema <- "some-other-contract"
  jsonlite::write_json(man, file.path(h$dest, "manifest.json"), auto_unbox = TRUE, null = "null")
  rewrite_integrity(h$dest)
  expect_import_code(h$dest, "PROTOCOL_MISMATCH")

  v <- handoff_fixture("qupath_geojson")
  man <- jsonlite::read_json(file.path(v$dest, "manifest.json"))
  man$schema_version <- "2.0"
  jsonlite::write_json(man, file.path(v$dest, "manifest.json"), auto_unbox = TRUE, null = "null")
  rewrite_integrity(v$dest)
  expect_import_code(v$dest, "PROTOCOL_MISMATCH")

  x <- handoff_fixture("qupath_geojson")
  man <- jsonlite::read_json(file.path(x$dest, "manifest.json"))
  man$unexpected_top_level <- TRUE
  jsonlite::write_json(man, file.path(x$dest, "manifest.json"), auto_unbox = TRUE, null = "null")
  rewrite_integrity(x$dest)
  expect_import_code(x$dest, "SCHEMA_INVALID")
})

test_that("symbolic links inside a handoff are rejected", {
  skip_on_os("windows")
  f <- handoff_fixture("qupath_geojson")
  file.symlink(file.path(f$dest, "image.json"), file.path(f$dest, "link.json"))
  expect_import_code(f$dest, "INTEGRITY_SYMLINK")
})

test_that("ID joins, labels and mask legends are validated", {
  f <- handoff_fixture("qupath_geojson")
  p <- file.path(f$dest, "annotations_qupath.geojson")
  q <- jsonlite::read_json(p)
  q$features[[1]]$properties$metadata$annotatr_roi_id <- "someone-else"
  jsonlite::write_json(q, p, auto_unbox = TRUE, digits = I(17))
  rewrite_integrity(f$dest)
  expect_import_code(f$dest, "ID_JOIN_MISMATCH")

  g <- handoff_fixture("qupath_geojson")
  p <- file.path(g$dest, "annotations_qupath.geojson")
  q <- jsonlite::read_json(p)
  q$features[[2]]$properties$classification$name <- "renamed"
  jsonlite::write_json(q, p, auto_unbox = TRUE, digits = I(17))
  rewrite_integrity(g$dest)
  expect_import_code(g$dest, "LABEL_MISMATCH")

  h <- handoff_fixture(c("qupath_geojson", "mask_npy"))
  side <- file.path(h$dest, "masks/regions_labelled.npy.legend.json")
  man <- jsonlite::read_json(file.path(h$dest, "manifest.json"))
  man$masks[[1]]$legend <- man$masks[[1]]$legend[1]
  man$masks[[1]]$legend_sha256 <- .digest_json(man$masks[[1]]$legend)
  jsonlite::write_json(man, file.path(h$dest, "manifest.json"), auto_unbox = TRUE, null = "null",
                       digits = NA)
  rewrite_integrity(h$dest)
  expect_import_code(h$dest, "LEGEND_INCOMPLETE")

  k <- handoff_fixture(c("qupath_geojson", "mask_npy"))
  man <- jsonlite::read_json(file.path(k$dest, "manifest.json"))
  man$masks[[1]]$width <- 10L
  jsonlite::write_json(man, file.path(k$dest, "manifest.json"), auto_unbox = TRUE, null = "null",
                       digits = NA)
  rewrite_integrity(k$dest)
  expect_import_code(k$dest, "MASK_DIMENSIONS")
})

test_that("single neutral files import; RDS is refused", {
  f <- handoff_fixture(c("qupath_geojson", "mask_tiff"))
  rep <- at_import_qupflowr(file.path(f$dest, "annotations_qupath.geojson"))
  expect_identical(rep$format, "qupath_geojson")
  expect_identical(rep$objects$layers$regions$rois[[1]]$id, at_rois(f$proj)$roi_id[1])
  mrep <- at_import_qupflowr(file.path(f$dest, "masks/regions_labelled.tif"))
  expect_identical(mrep$format, "mask")
  rds <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(), rds)
  expect_import_code(rds, "FORMAT_NOT_NEUTRAL")
})

test_that("overwrite replaces only an existing handoff directory", {
  proj <- at_example_project()
  base <- withr::local_tempdir()
  dest <- file.path(base, "h")
  at_export_qupflowr(proj, dest)
  err <- tryCatch(at_export_qupflowr(proj, dest), error = function(e) e)
  expect_identical(err$code, "DESTINATION_EXISTS")
  rc <- at_export_qupflowr(proj, dest, formats = "qupath_geojson", overwrite = TRUE)
  expect_true(rc$overwritten)
  expect_false(file.exists(file.path(dest, "masks")))
  foreign <- file.path(base, "not-a-handoff")
  dir.create(foreign)
  writeLines("keep me", file.path(foreign, "notes.txt"))
  err <- tryCatch(at_export_qupflowr(proj, foreign, overwrite = TRUE), error = function(e) e)
  expect_identical(err$code, "DESTINATION_NOT_HANDOFF")
  expect_identical(readLines(file.path(foreign, "notes.txt")), "keep me")
})

test_that("session handoffs export materialised entries and record skipped ones", {
  sess <- at_example_session(3)
  sess$projects[[2]] <- at_example_project()
  dest <- file.path(withr::local_tempdir(), "s")
  rc <- at_export_qupflowr(sess, dest)
  expect_identical(rc$skipped, c("entry-0001", "entry-0003"))
  expect_true(file.exists(file.path(dest, "entries/entry-0002/annotations_qupath.geojson")))
  rep <- at_import_qupflowr(dest)
  expect_identical(names(rep$objects$layers), "entry-0002")
})

stage_fixture <- function() {
  proj <- at_example_project()
  ids <- at_rois(proj)$roi_id
  partner <- proj$layers$regions
  partner$rois[[1]]$geometry <- sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(9, 0), c(9, 9), c(0, 9), c(0, 0)))))
  partner$rois <- partner$rois[1:2]
  partner <- at_layer_add(partner, at_roi_rect(1, 1, 3, 3, label = "tumour", id = "partner-new"))
  list(proj = proj, ids = ids, partner = partner)
}

test_that("staging classifies creates, updates, unchanged, deletes and conflicts", {
  s <- stage_fixture()
  st <- at_stage_qupflowr(s$proj, s$partner, expected_revision = at_annotation_revision(s$proj))
  ops <- stats::setNames(st$operations$op, st$operations$roi_id)
  expect_identical(unname(ops[c(s$ids[1], s$ids[2], "partner-new")]), c("update", "unchanged", "create"))
  expect_identical(st$summary$conflict, 0L)
  expect_identical(at_annotation_revision(s$proj), st$base_revision)  # input untouched
  del <- at_stage_qupflowr(s$proj, s$partner, delete_missing = TRUE)
  expect_identical(del$operations$op[del$operations$roi_id == s$ids[3]], "delete")

  reviewed <- s$proj
  reviewed$layers$regions$rois[[1]]$attributes$review_status <- "reviewed"
  reviewed$layers$regions$rois[[3]]$attributes$locked <- TRUE
  st2 <- at_stage_qupflowr(reviewed, s$partner, delete_missing = TRUE)
  conf <- st2$operations[st2$operations$op == "conflict", ]
  expect_setequal(conf$roi_id, s$ids[c(1, 3)])
  kept <- .find_roi(st2$proposed, s$ids[1])$roi
  expect_identical(.geometry_sha256(kept$geometry),
                   .geometry_sha256(reviewed$layers$regions$rois[[1]]$geometry))

  err <- tryCatch(at_stage_qupflowr(s$proj, s$partner, expected_revision = "sha256:stale"),
                  error = function(e) e)
  expect_identical(err$code, "REVISION_CONFLICT")
})

test_that("commit is idempotent per key and refuses a reused key for another patch", {
  s <- stage_fixture()
  st <- at_stage_qupflowr(s$proj, s$partner)
  rc <- at_commit_qupflowr(st, idempotency_key = "test-commit-1")
  expect_identical(rc$state, "committed")
  expect_identical(nrow(rc$applied), 2L)
  expect_identical(rc$new_revision, at_annotation_revision(rc$project))
  again <- at_commit_qupflowr(st, idempotency_key = "test-commit-1")
  expect_true(again$replayed)
  expect_identical(again$new_revision, rc$new_revision)
  other <- at_stage_qupflowr(s$proj, s$proj$layers$regions)
  err <- tryCatch(at_commit_qupflowr(other, idempotency_key = "test-commit-1"), error = function(e) e)
  expect_identical(err$code, "IDEMPOTENCY_CONFLICT")
})

test_that("committing to a file re-checks its revision and needs explicit overwrite", {
  s <- stage_fixture()
  d <- withr::local_tempdir()
  path <- file.path(d, "project.rds")
  lite <- s$proj
  lite$image$handle <- NULL
  at_save_project(lite, path)
  st <- at_stage_qupflowr(path, s$partner)
  err <- tryCatch(at_commit_qupflowr(st, idempotency_key = "file-1"), error = function(e) e)
  expect_identical(err$code, "DESTINATION_EXISTS")
  # Someone else changes the file after staging.
  changed <- at_add_roi(lite, "regions", at_roi_rect(5, 5, 8, 8, label = "stroma"))
  at_save_project(changed, path, overwrite = TRUE)
  err <- tryCatch(at_commit_qupflowr(st, idempotency_key = "file-2", overwrite = TRUE),
                  error = function(e) e)
  expect_identical(err$code, "REVISION_CONFLICT")
  at_save_project(lite, path, overwrite = TRUE)
  rc <- at_commit_qupflowr(st, idempotency_key = "file-3", overwrite = TRUE)
  expect_identical(at_annotation_revision(at_load_project(path)), rc$new_revision)
  side <- jsonlite::read_json(paste0(path, ".commit.json"))
  expect_identical(side$idempotency_key, "file-3")
  # A new R session (empty registry) still recognises the key from the sidecar.
  rm(list = ls(.commit_registry), envir = .commit_registry)
  replay <- at_commit_qupflowr(st, idempotency_key = "file-3", overwrite = TRUE)
  expect_true(replay$replayed)
})
