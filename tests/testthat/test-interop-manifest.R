skip_if_not(requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE))

test_that("the project manifest describes identity, convention and annotations without local paths", {
  proj <- at_example_project()
  m <- at_interop_manifest(proj)
  expect_s3_class(m, "at_interop_manifest")
  expect_identical(m$schema, "annotatr-handoff-v1")
  expect_identical(m$object_kind, "project")
  expect_identical(m$coordinate_convention$origin, "top_left")
  expect_identical(m$coordinate_convention$y_axis, "down")
  img <- m$images[[1]]
  # Independent image id: sha256 over the canonical {"files":["<file sha256>"]}.
  file_sha <- unname(tools::sha256sum(at_example_path("tissue")))
  expected <- substr(.sha256_bytes(sprintf('{"files":["%s"]}', file_sha)), 1, 16)
  expect_identical(img$image_id, paste0("sha256:", expected))
  expect_identical(img$source_name, "example_tissue.png")
  expect_identical(c(img$width, img$height), c(512L, 512L))
  expect_identical(m$annotations$count, 3L)
  ids <- vapply(m$annotations$rois, `[[`, character(1), "roi_id")
  expect_identical(ids, at_rois(proj)$roi_id)
  txt <- jsonlite::toJSON(unclass(m), auto_unbox = TRUE, null = "null", na = "null")
  expect_false(grepl(dirname(at_example_path("tissue")), txt, fixed = TRUE))
  expect_false(grepl(tempdir(), txt, fixed = TRUE))
  expect_length(.schema_validate(.as_json_value(unclass(m)),
                                 .schema_load("annotatr-handoff-v1", "manifest")), 0L)
})

test_that("the annotation revision follows content, not timestamps", {
  proj <- at_example_project()
  r0 <- at_annotation_revision(proj)
  expect_match(r0, "^sha256:[0-9a-f]{64}$")
  touched <- proj
  touched$layers$regions$rois[[1]]$modified <- Sys.time() + 3600
  touched$provenance$modified <- Sys.time() + 3600
  expect_identical(at_annotation_revision(touched), r0)
  moved <- proj
  moved$layers$regions$rois[[1]]$geometry <- sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(5, 0), c(5, 5), c(0, 5), c(0, 0)))))
  expect_false(identical(at_annotation_revision(moved), r0))
  relabelled <- proj
  relabelled$layers$regions$rois[[1]]$label <- "stroma"
  expect_false(identical(at_annotation_revision(relabelled), r0))
  locked <- proj
  locked$layers$regions$style$locked <- TRUE
  expect_false(identical(at_annotation_revision(locked), r0))
})

test_that("circles are declared approximated and hierarchy unknown", {
  proj <- at_add_roi(at_example_project(), "regions", at_roi_circle(40, 40, 10, label = "stroma"))
  rois <- at_interop_manifest(proj)$annotations$rois
  fid <- vapply(rois, `[[`, character(1), "geometry_fidelity")
  expect_identical(fid, c("exact", "exact", "exact", "approximated"))
  expect_true(all(vapply(rois, `[[`, character(1), "hierarchy") == "unknown"))
})

test_that("session, image, layer, ROI and mask manifests are schema-valid", {
  sess <- at_example_session(2)
  sess$projects[[2]] <- at_example_project()
  ms <- at_interop_manifest(sess)
  expect_identical(ms$object_kind, "session")
  q <- ms$session$queue
  expect_identical(vapply(q, `[[`, character(1), "entry_id"), c("entry-0001", "entry-0002"))
  expect_identical(vapply(q, `[[`, logical(1), "materialised"), c(FALSE, TRUE))
  schema <- .schema_load("annotatr-handoff-v1", "manifest")
  for (obj in list(sess, at_example_image("cube"), at_example_project()$layers$regions,
                   at_roi_rect(0, 0, 2, 2, label = "a"), at_mask(at_example_project(), "labelled"))) {
    man <- at_interop_manifest(obj, hash_sources = FALSE)
    expect_length(.schema_validate(.as_json_value(unclass(man)), schema), 0L)
  }
  cube <- at_interop_manifest(at_example_image("cube"))$images[[1]]
  expect_identical(cube$image_kind, "spectral")
  expect_identical(length(cube$bands), 40L)
  expect_equal(cube$bands[[1]]$wavelength, 450)
  expect_identical(vapply(cube$source_files, `[[`, character(1), "role"), c("header", "data"))
})

test_that("writing a manifest never overwrites", {
  d <- withr::local_tempdir()
  at_interop_manifest(at_example_project(), d)
  expect_true(file.exists(file.path(d, "manifest.json")))
  err <- tryCatch(at_interop_manifest(at_example_project(), d), error = function(e) e)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "DESTINATION_EXISTS")
  expect_error(at_interop_manifest(42), class = "at_validation_error")
})
