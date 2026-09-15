# Server-level behaviour of the app modules that live in R/: data loading,
# layers, masks, spectra, region downloads, exports, sessions, staging and the
# UI tree. Assertions are on reactive state, rendered outputs and written files.
skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("shinyjs")
skip_if_not_installed("htmlwidgets")
skip_if_not_installed("tiff")
skip_if_not(requireNamespace("magick", quietly = TRUE))

rect_feature <- function(x0, y0, x1, y1) {
  list(type = "Feature", properties = list(),
       geometry = list(type = "Polygon",
                       coordinates = list(list(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0)))))
}

cube_session <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  file.copy(c(at_example_path("cube"), sub("\\.hdr$", ".dat", at_example_path("cube"))), d)
  file.copy(at_example_path("tissue"), file.path(d, "tissue.png"))
  at_session(c(file.path(d, "example_cube.hdr"), file.path(d, "tissue.png")),
             labels = c("tumour", "stroma"), out_dir = file.path(d, "out"))
}

test_that("the full UI tree renders every page, module and asset reference", {
  ui <- .app_ui()
  html <- as.character(htmltools::renderTags(ui)$html)
  for (id in c("queue-list", "canvas-canvas", "view-mode", "mask-overlay", "region-download",
               "export-handoff", "data-stage", "session-badge", "control-status", "help-show")) {
    expect_match(html, id, fixed = TRUE, label = id)
  }
  expect_match(html, "annotatR-www/custom.css", fixed = TRUE)
  expect_match(html, "Impressum", fixed = TRUE)
  expect_match(html, "\u00a7 5 DDG", fixed = TRUE)
})

test_that("layers, labels, masks, overlap warnings and statistics respond to input", {
  sess <- cube_session()
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`layers-new_layer` = "artefact", `layers-add_layer` = 1)
    expect_true("artefact" %in% names(rv$project$layers))
    expect_identical(rv$active_layer, "artefact")
    session$setInputs(`layers-new_label` = "blood", `layers-add_label` = 1)
    expect_true("blood" %in% rv$project$layers$artefact$labels)
    expect_identical(rv$active_label, "blood")
    session$setInputs(`layers-layer` = "annotations")
    expect_identical(rv$active_layer, "annotations")
    session$setInputs(`canvas-canvas_created` = rect_feature(2, 2, 40, 40))
    session$setInputs(`canvas-canvas_created` = rect_feature(20, 20, 60, 60))
    expect_identical(nrow(at_rois(rv$project)), 2L)
    session$setInputs(`mask-type` = "multiclass", `mask-overlap` = "first")
    expect_identical(rv$mask_type, "multiclass")
    expect_type(output$`mask-overlap_warn`, "list")
    stats <- output$`mask-stats`
    expect_match(stats, "tumour|annotations", perl = TRUE)
    session$setInputs(`mask-overlay` = TRUE)
    expect_true(rv$overlay_on)
    session$setInputs(`mask-export` = 1)
    expect_true(file.exists(file.path(sess$out_dir, "masks", "example_cube.tif")))
    # Edit and erase through the canvas contract keep ids and history.
    rid <- at_rois(rv$project)$roi_id[1]
    session$setInputs(`canvas-canvas_edited` = list(roi_id = rid, layer = "annotations", label = "tumour",
                                                    geometry = rect_feature(5, 5, 30, 30)$geometry))
    expect_true(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(`canvas-canvas_erased` = rid)
    expect_false(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(key_undo = 1)
    expect_true(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(key_redo = 1)
    expect_false(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(`roitable-del_id` = at_rois(rv$project)$roi_id[1], `roitable-select` = 1)
    expect_length(rv$selection, 1L)
    session$setInputs(`canvas-canvas_selected` = list("x"))
    expect_identical(rv$selection, "x")
    session$setInputs(`canvas-canvas_viewport` = list(bounds = list(1, 2, 30, 40)))
    expect_equal(rv$viewport, c(1, 2, 30, 40))
    expect_match(output$`roitable-table`, "unreviewed")
    session$setInputs(key_tool = "polygon", key_label = 1, key_flag = 1)
    expect_identical(rv$tool, "polygon")
    expect_identical(at_session_status(rv$session)$status[1], "flagged")
    session$setInputs(key_delete = 1)
    expect_identical(nrow(at_rois(rv$project)), 0L)
  })
})

test_that("spectra follow the selected source and the cube status reports metadata", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = rect_feature(10, 10, 30, 30))
    expect_match(output$`view-status`, "spectral")
    expect_match(output$`view-status`, "450-900 nm")
    for (mode in c("rgb", "ratio", "band_mean", "wavelength_window_mean", "single", "natural")) {
      session$setInputs(`view-mode` = mode)
      expect_no_error(output$`view-band_inputs`)
    }
    session$setInputs(`view-mode` = "wavelength_window_mean", `view-wmin` = 500, `view-wmax` = 600,
                      `view-apply` = 1)
    expect_identical(rv$view$operation, "wavelength_window_mean")
    session$setInputs(`view-mode` = "natural", `view-apply` = 2)
    expect_null(rv$view)
  })
  proj <- at_project(at_read_image(sess$manifest$path[1]),
                     at_layer_add(at_layer("annotations", labels = "tumour"),
                                  at_roi_rect(10, 10, 30, 30, label = "tumour", id = "r1")))
  rv <- shiny::reactiveValues(project = proj, probe = NULL)
  shiny::testServer(mod_spectrum_server, args = list(id = "sp", rv = rv), {
    expect_no_error(output$panel)
    session$setInputs(source = "layer", layer = "annotations")
    expect_identical(nrow(spectra()), 40L)
    session$setInputs(source = "roi", roi = "r1")
    expect_identical(unique(spectra()$roi_id), "r1")
    rv$probe <- c(x = 3, y = 4)
    session$setInputs(source = "pixel")
    expect_identical(spectra()$roi_id[1], "pixel(4,5)")
    expect_equal(spectra()$value, as.numeric(at_tile(proj$image, xrange = c(4, 4), yrange = c(5, 5))))
    expect_match(output$caption, "original cube")
    expect_no_error(output$source_sel)
  })
})

test_that("region downloads, exports and handoffs write verifiable files", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = rect_feature(4, 4, 12, 10))
    rid <- at_rois(rv$project)$roi_id
    rv$selection <- rid
    session$setInputs(`region-extent` = "roi")
    zip_path <- output$`region-download`
    files <- utils::unzip(zip_path, list = TRUE)$Name
    expect_setequal(files, c("region.dat", "region.hdr", "region.json"))
    ex <- withr::local_tempdir()
    utils::unzip(zip_path, exdir = ex)
    expect_equal(at_tile(at_read_image(file.path(ex, "region.hdr"))),
                 at_tile(rv$project$image, xrange = c(5, 12), yrange = c(5, 10)), tolerance = 0)
    meta <- jsonlite::read_json(file.path(ex, "region.json"))
    expect_false(meta$display_product)
    expect_identical(meta$bounds$xmax, 12L)
    session$setInputs(`region-extent` = "custom", `region-xmin` = 0, `region-ymin` = 0,
                      `region-xmax` = 5000, `region-ymax` = 5000)
    expect_setequal(utils::unzip(output$`region-download`, list = TRUE)$Name,
                    c("region.dat", "region.hdr", "region.json"))
    session$setInputs(`export-formats` = c("mask_tiff", "geojson", "qupath", "csv"), `export-scope` = "current")
    exp_zip <- output$`export-run`
    expect_setequal(utils::unzip(exp_zip, list = TRUE)$Name,
                    c("example_cube.tif", "example_cube.tif.legend.json", "example_cube.geojson",
                      "example_cube_qupath.geojson", "example_cube_rois.csv"))
    session$setInputs(`export-handoff_name` = "partner/../h1", `export-handoff` = 1)
    dest <- file.path(sess$out_dir, "handoff", "partner_.._h1")
    expect_match(output$`export-handoff_status`, "digest")
    expect_true(file.exists(file.path(sess$out_dir, "handoff")))
    hz <- output$`export-handoff_zip`
    expect_true("integrity.json" %in% utils::unzip(hz, list = TRUE)$Name)
  })
})

test_that("sessions save, complete, flag and reload from the data page", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = rect_feature(1, 1, 9, 9))
    session$setInputs(`session-save` = 1)
    expect_identical(rv$saved, "saved")
    expect_true(file.exists(file.path(sess$out_dir, "_session.rds")))
    saved <- at_load_session(file.path(sess$out_dir, "_session.rds"))
    expect_null(saved$projects[[1]]$image$handle)
    session$setInputs(`session-complete` = 1)
    expect_identical(at_session_status(rv$session)$status[1], "complete")
    session$setInputs(`session-flag` = 1)
    expect_identical(at_session_status(rv$session)$status[1], "flagged")
    expect_match(as.character(output$`session-badge`$html), "saved")
    session$setInputs(key_commit_advance = 1)
    expect_identical(rv$cursor, 2L)
    expect_identical(at_session_status(rv$session)$status[1], "complete")
    session$setInputs(key_next_pending = 1, key_save = 1, key_help = 1, key_paste_forward = 1)
    expect_match(output$`dashboard-status`, "complete")
    expect_type(output$`dashboard-tiles`, "list")
    session$setInputs(`queue-filter` = "complete")
    expect_match(output$`queue-list`, "✓")
    expect_match(output$`queue-progress`, "/ 2 complete")
    session$setInputs(`data-dir` = "/no/such/folder", `data-load` = 1)
    expect_identical(output$`data-msg`, "Folder not found.")
    empty <- withr::local_tempdir()
    session$setInputs(`data-dir` = empty, `data-load` = 2)
    expect_match(output$`data-msg`, "No supported images")
    folder <- withr::local_tempdir()
    file.copy(at_example_path("tissue"), file.path(folder, c("a.png", "b.png")))
    session$setInputs(`data-dir` = folder, `data-load` = 3)
    expect_match(output$`data-msg`, "Loaded 2 image")
    expect_identical(rv$generation, 1L)
    expect_identical(nrow(rv$session$manifest), 2L)
    expect_match(output$`data-table`, "a")
    session$setInputs(`data-handoff` = "/missing", `data-stage` = 1)
    expect_identical(output$`data-stage_msg`, "Handoff not found.")
  })
})

test_that("staged patches can be discarded and stale commits are refused", {
  proj <- at_example_project()
  handoff <- file.path(withr::local_tempdir(), "partner")
  at_export_qupflowr(at_add_roi(proj, "regions", at_roi_rect(1, 1, 9, 9, label = "stroma", id = "p-1")),
                     handoff, formats = "qupath_geojson")
  sess <- at_example_session(1)
  sess$projects[[1]] <- proj
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`data-handoff` = handoff, `data-stage` = 1)
    expect_match(output$`staging-ops`, "p-1")
    session$setInputs(`staging-discard` = 1)
    expect_null(rv$staged)
    session$setInputs(`data-stage` = 2)
    session$setInputs(`canvas-canvas_created` = rect_feature(50, 50, 70, 70))
    session$setInputs(`staging-commit` = 1)
    expect_false("p-1" %in% at_rois(rv$project)$roi_id)
    expect_s3_class(rv$staged, "at_staged_patch")
  })
})

test_that("the control status panel reports the attached hub", {
  skip_if_not_installed("httpuv")
  h <- at_control_start(at_example_session(1), serve = FALSE)
  on.exit(at_control_stop(h), add = TRUE)
  shiny::testServer(mod_control_status_server, args = list(id = "c", rv = shiny::reactiveValues(),
                                                           hub = .control_hub(h)), {
    expect_match(as.character(output$status$html), "control: running")
  })
  shiny::testServer(mod_control_status_server, args = list(id = "c", rv = shiny::reactiveValues(), hub = NULL), {
    expect_null(output$status)
  })
})
