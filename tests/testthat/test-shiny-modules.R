skip_if_not_installed("shiny")

# Source the app's module files so their servers can be tested with testServer.
.mod_dir <- system.file("shiny", "annotatR", "modules", package = "annotatR")
for (.f in list.files(.mod_dir, pattern = "\\.R$", full.names = TRUE)) {
  source(.f, local = TRUE)
}

make_rv <- function(project = demo_project(), session = demo_session(3)) {
  shiny::reactiveValues(
    session = session, cursor = 1L, project = project, tool = "pan",
    active_layer = "tissue", active_label = "tissue", mask_type = "labelled",
    overlap = "last", undo = list(), redo = list(), saved = "saved",
    paste_forward = NULL
  )
}

test_that("queue module navigates the session", {
  rv <- make_rv()
  shiny::testServer(mod_queue_server, args = list(id = "q", rv = rv), {
    session$setInputs(filter = "all", nxt = 1)
    expect_identical(rv$cursor, 2L)
    session$setInputs(prev = 1)
    expect_identical(rv$cursor, 1L)
  })
})

test_that("layers module tracks the active layer and label", {
  rv <- make_rv()
  shiny::testServer(mod_layers_server, args = list(id = "l", rv = rv), {
    session$setInputs(layer = "tumour", label = "tumour")
    expect_identical(rv$active_layer, "tumour")
    expect_identical(rv$active_label, "tumour")
  })
})

test_that("mask module toggles type and overlap", {
  rv <- make_rv()
  shiny::testServer(mod_mask_server, args = list(id = "m", rv = rv), {
    session$setInputs(type = "binary", overlap = "first")
    expect_identical(rv$mask_type, "binary")
    expect_identical(rv$overlap, "first")
  })
})

test_that("canvas module commits a drawn ROI and marks unsaved", {
  rv <- make_rv()
  shiny::testServer(mod_canvas_server, args = list(id = "c", rv = rv), {
    before <- nrow(at_rois(rv$project))
    feat <- list(geometry = list(type = "Polygon",
                                 coordinates = list(list(c(2, 2), c(6, 2), c(6, 6), c(2, 6), c(2, 2)))))
    session$setInputs(canvas_created = feat)
    expect_identical(nrow(at_rois(rv$project)), before + 1L)
    expect_identical(rv$saved, "unsaved")
    expect_length(rv$undo, 1L)
  })
})

test_that("copy-forward makes editable ROIs with new ids and source 'copied'", {
  from <- demo_project()
  to <- at_project(from$image)
  result <- .copy_forward(from, to)
  rt <- at_rois(result)
  from_rt <- at_rois(from)
  expect_identical(nrow(rt), nrow(from_rt))
  expect_true(all(rt$source == "copied"))
  expect_length(intersect(rt$roi_id, from_rt$roi_id), 0L)
})

test_that("roitable module deletes an ROI", {
  rv <- make_rv()
  shiny::testServer(mod_roitable_server, args = list(id = "t", rv = rv), {
    id <- at_rois(rv$project)$roi_id[1]
    session$setInputs(del_id = id, delete = 1)
    expect_false(id %in% at_rois(rv$project)$roi_id)
  })
})

test_that("spectrum module shows a panel only for spectral images", {
  rv_rgb <- make_rv()
  shiny::testServer(mod_spectrum_server, args = list(id = "s", rv = rv_rgb), {
    expect_null(output$panel)
  })
  cube <- cube_image()
  # Give the cube real pixel data so the spectrum actually extracts (a bare
  # metadata fixture would push a data-less image through the tile path).
  cube$handle <- list(data = array(as.numeric(seq_len(32L * 32L * 10L)),
                                   dim = c(32L, 32L, 10L)))
  rv_cube <- make_rv(project = at_project(cube,
                                          at_layer_add(at_layer("l", labels = "a"),
                                                       at_roi_circle(16, 16, 4, label = "a"))))
  shiny::testServer(mod_spectrum_server, args = list(id = "s", rv = rv_cube), {
    rv$active_layer <- "l"
    expect_false(is.null(output$panel))
  })
})

test_that("session module saves and reports status", {
  rv <- make_rv()
  shiny::testServer(mod_session_server, args = list(id = "s", rv = rv), {
    session$setInputs(save = 1)
    expect_identical(rv$saved, "saved")
    session$setInputs(complete = 1)
    expect_identical(at_session_status(rv$session)$status[1], "complete")
  })
})

test_that("export writes the selected formats for the scope", {
  rv <- make_rv()
  dir <- tempfile("atexport"); dir.create(dir)
  rc <- shiny::isolate(.write_exports(rv, c("geojson", "csv"), "current", dir))
  expect_true(any(grepl("\\.geojson$", list.files(dir))))
  expect_true(any(grepl("\\.csv$", list.files(dir))))
  expect_setequal(rc$format, c("geojson", "csv"))
})

test_that("export scope 'all' covers every annotated image, skipping empties", {
  rv <- make_rv()  # 3-image session, only the current image has a project/ROIs
  dir <- tempfile("atexport"); dir.create(dir)
  rc <- shiny::isolate(.write_exports(rv, "geojson", "all", dir))
  expect_true(nrow(rc) >= 1L)
  expect_length(attr(rc, "skipped"), 2L)  # the two unvisited images
})

test_that("export zips selected files flat, by basename", {
  skip_if_not_installed("zip")
  dir <- tempfile("atzip"); dir.create(dir)
  writeLines("x", file.path(dir, "a.geojson"))
  writeLines("y", file.path(dir, "b.tif"))
  zf <- tempfile(fileext = ".zip")
  .zip_into(zf, file.path(dir, c("a.geojson", "b.tif")), dir)
  expect_true(file.exists(zf))
  expect_setequal(zip::zip_list(zf)$filename, c("a.geojson", "b.tif"))
})

test_that("help module renders the shortcut table", {
  rv <- make_rv()
  shiny::testServer(mod_help_server, args = list(id = "h", rv = rv), {
    expect_s3_class(.shortcut_table(), "data.frame")
  })
})

test_that("live mask preview matches at_mask at the same settings", {
  rv <- make_rv()
  shiny::isolate({
    m_direct <- as.matrix(at_mask(rv$project, "labelled", overlap = "last"))
    m_module <- as.matrix(.current_mask(rv))
    expect_identical(m_direct, m_module)
  })
})

test_that("at_annotate normalises inputs and rejects bad ones", {
  expect_s3_class(.to_session(demo_session(2), character(), NULL, tempdir()), "annot_session")
  expect_error(.to_session(42, character(), NULL, tempdir()), "must be a session")
})

test_that("the app contains no library()/require() calls", {
  files <- list.files(system.file("shiny", "annotatR", package = "annotatR"),
                      pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  hits <- unlist(lapply(files, function(f) grep("library\\(|require\\(", readLines(f), value = TRUE)))
  expect_length(hits, 0L)
})

test_that("app www assets make no external requests", {
  www <- list.files(system.file("shiny", "annotatR", "www", package = "annotatR"),
                    full.names = TRUE)
  hits <- unlist(lapply(www, function(f) {
    lines <- readLines(f)
    # XML/SVG namespace URIs (xmlns=...) are identifiers, not network fetches;
    # an <img>-embedded SVG needs its xmlns to render. Only real resource
    # references (a fetched script, stylesheet, font, or image) count.
    lines <- gsub("xmlns(:[[:alnum:]]+)?=\"https?://[^\"]*\"", "", lines)
    grep("https?://", lines, value = TRUE)
  }))
  expect_length(hits, 0L)
})

test_that("the keyboard handler guards against text-field focus", {
  js <- readLines(system.file("shiny", "annotatR", "www", "keys.js", package = "annotatR"))
  expect_true(any(grepl("inTextField", js)))
  expect_true(any(grepl("TEXTAREA", js)))
})
