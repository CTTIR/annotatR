skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("shinyjs")
skip_if_not_installed("htmlwidgets")
skip_if_not(requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE))

rect_feature <- function(x0, y0, x1, y1) {
  list(type = "Feature", properties = list(),
       geometry = list(type = "Polygon",
                       coordinates = list(list(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0)))))
}

test_that("at_app builds an app object from explicit arguments without global options", {
  withr::local_options(annotatR.session = NULL)
  app <- at_app(session = at_example_session(2))
  expect_s3_class(app, "shiny.appobj")
  expect_s3_class(at_app(input = at_example_project()), "shiny.appobj")
  expect_error(at_app(input = at_example_project(), session = at_example_session(1)), "not both")
  expect_error(at_app(control = "loopback"), "must be")
  expect_error(at_app(session = at_example_session(1), unexpected = 1))
  expect_null(getOption("annotatR.session"))
})

test_that("the compatibility app directory builds through at_app", {
  app_dir <- system.file("shiny", "annotatR", package = "annotatR")
  expect_false(dir.exists(file.path(app_dir, "modules")))
  withr::local_options(annotatR.session = at_example_session(1))
  appobj <- withr::with_dir(app_dir, source("app.R", local = new.env(parent = globalenv()))$value)
  expect_s3_class(appobj, "shiny.appobj")
})

test_that("navigation keeps unsaved edits in their own queue entry", {
  sess <- at_example_session(3)
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    expect_identical(rv$cursor, 1L)
    session$setInputs(`canvas-canvas_created` = rect_feature(10, 10, 60, 60))
    expect_identical(nrow(at_rois(rv$project)), 1L)
    rid <- at_rois(rv$project)$roi_id
    session$setInputs(key_next = 1)
    expect_identical(rv$cursor, 2L)
    expect_identical(nrow(at_rois(rv$project)), 0L)
    session$setInputs(key_prev = 1)
    expect_identical(rv$cursor, 1L)
    expect_identical(at_rois(rv$project)$roi_id, rid)
    expect_identical(nrow(at_rois(rv$session$projects[[2]])), 0L)
  })
})

test_that("read-only sessions refuse edits and drawing tools", {
  shiny::testServer(.app_server(at_example_session(1), read_only = TRUE), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = rect_feature(1, 1, 20, 20))
    expect_identical(nrow(at_rois(rv$project)), 0L)
    session$setInputs(`canvas-tool_rect` = 1)
    expect_identical(rv$tool, "pan")
    session$setInputs(`canvas-tool_probe` = 1)
    expect_identical(rv$tool, "probe")
    expect_identical(.annotation_status(rv), "read_only")
  })
})

test_that("band views are validated and applied as display state only", {
  cube_dir <- withr::local_tempdir()
  file.copy(c(at_example_path("cube"), sub("\\.hdr$", ".dat", at_example_path("cube"))), cube_dir)
  sess <- at_session(file.path(cube_dir, "example_cube.hdr"), out_dir = cube_dir)
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    rev0 <- at_annotation_revision(rv$project)
    session$setInputs(`view-mode` = "normalized_difference", `view-b1` = "30", `view-b2` = "10",
                      `view-apply` = 1)
    expect_identical(rv$view, list(operation = "normalized_difference", bands = c(30L, 10L)))
    expect_identical(at_annotation_revision(rv$project), rev0)
    session$setInputs(`view-mode` = "single", `view-b1` = "99", `view-apply` = 2)
    expect_identical(rv$view$operation, "normalized_difference")
    session$setInputs(`canvas-canvas_probed` = list(x = 5.5, y = 7.2))
    expect_equal(unname(rv$probe), c(5.5, 7.2))
    sp <- .pixel_spectrum(rv$project$image, 5.5, 7.2)
    expect_identical(nrow(sp), 40L)
    expect_equal(sp$value, as.numeric(at_tile(rv$project$image, xrange = c(6, 6), yrange = c(8, 8))))
  })
})

test_that("a partner handoff is staged, shown and committed from the app", {
  proj <- at_example_project()
  handoff <- file.path(withr::local_tempdir(), "partner")
  partner <- at_add_roi(proj, "regions", at_roi_rect(5, 5, 40, 40, label = "stroma", id = "partner-1"))
  at_export_qupflowr(partner, handoff, formats = "qupath_geojson")
  sess <- at_example_session(1)
  sess$projects[[1]] <- proj
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`data-handoff` = handoff, `data-stage` = 1)
    expect_s3_class(rv$staged, "at_staged_patch")
    expect_identical(rv$staged$summary$create, 1L)
    expect_identical(.annotation_status(rv), "staged")
    session$setInputs(`staging-commit` = 1)
    expect_null(rv$staged)
    expect_true("partner-1" %in% at_rois(rv$project)$roi_id)
    session$flushReact()
    expect_identical(.annotation_status(rv), "committed")
  })
})

test_that("an app attached to a control hub follows commands and reports its edits", {
  skip_if_not_installed("httpuv")
  h <- at_control_start(at_example_session(3), serve = FALSE)
  on.exit(at_control_stop(h), add = TRUE)
  hub <- .control_hub(h)
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    st <- at_control_state(h)
    at_control_command(h, list(operation = "context.goto", payload = list(queue_index = 3),
                               expected_revision = st$state_revision))
    session$elapse(600)
    expect_identical(rv$cursor, 3L)
    st <- at_control_state(h)
    at_control_command(h, list(operation = "context.view",
                               payload = list(band_group = list(operation = "rgb", bands = list(3, 2, 1))),
                               expected_revision = st$state_revision))
    session$elapse(600)
    expect_identical(rv$view$bands, c(3L, 2L, 1L))
    before <- hub$revision
    session$setInputs(`canvas-canvas_created` = rect_feature(1, 1, 30, 30))
    session$flushReact()
    expect_gt(hub$revision, before)
    expect_identical(hub$last_origin, "app")
    ev <- at_control_events(h)$events
    expect_identical(ev[[length(ev)]]$type, "annotations.edited")
    expect_identical(ev[[length(ev)]]$origin$kind, "app")
    expect_identical(length(at_control_state(h)$current$rois), 1L)
  })
})

test_that("at_annotate builds through at_app and hands the app object to runApp", {
  captured <- NULL
  local_mocked_bindings(runApp = function(appDir, launch.browser, port, ...) {
    captured <<- list(app = appDir, launch.browser = launch.browser, port = port)
    invisible(NULL)
  }, .package = "shiny")
  withr::local_options(annotatR.session = NULL)
  expect_null(at_annotate(at_example_session(1), launch.browser = FALSE, port = 5555L))
  expect_s3_class(captured$app, "shiny.appobj")
  expect_false(captured$launch.browser)
  expect_identical(captured$port, 5555L)
  expect_null(getOption("annotatR.session"))
  expect_error(.check_app_pkgs(), NA)
})
