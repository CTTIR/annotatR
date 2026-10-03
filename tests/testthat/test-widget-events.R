skip_if_not_installed("shiny")
for (module in c("mod_state.R", "mod_canvas.R")) {
  source(system.file("shiny", "annotatR", "modules", module, package = "annotatR"), local = TRUE)
}

test_that("widget and keyboard ingress reject raw, partial, stale and malformed events immediately", {
  shiny::isolate({
    s <- demo_session(1); s$autosave <- FALSE
    rv <- shiny::reactiveValues(session = s, cursor = 1L,
      project = at_project(tiny_image(), at_layer("base", labels = "a")))
    .state_init(rv)
    for (kind in c("widget", "keyboard")) {
      decode <- function(value) do.call(.state_event, c(list(rv = rv, value = value), setNames(list(TRUE), kind)))
      expect_null(decode(1))
      expect_null(decode(list(geometry = list(type = "Point", coordinates = c(1, 2)))))
      expect_null(decode(list(entry_id = rv$entry_id, revision = rv$revision)))
      expect_null(decode(list(entry_id = rv$entry_id, revision = NA_real_, payload = 1)))
      expect_null(decode(list(entry_id = rv$entry_id, revision = Inf, payload = 1)))
      expect_null(decode(list(entry_id = rv$entry_id, revision = -1, payload = 1)))
      expect_null(decode(list(entry_id = "old", revision = rv$revision, payload = 1)))
      expect_equal(decode(c(.state_stamp(rv), list(payload = "point")))$payload, "point")
    }
  })
})

test_that("widget exposes project identity and edit preserves attributes and anisotropic stored level", {
  testthat::local_mocked_bindings(.image_data_uri = function(...) NULL)
  img <- new_annot_image(source = "synthetic", backend = "tiff", dims = c(100L, 90L),
    n_levels = 2L, level_dims = list(c(100L, 90L), c(40L, 30L)), n_bands = 1L)
  original <- at_roi_rect(4, 3, 12, 9, "a", level = 1L,
    note = "keep", score = 7, author = "owner")
  s <- demo_session(1); s$autosave <- FALSE
  rv <- shiny::reactiveValues(session = s, cursor = 1L, tool = "edit",
    project = at_project(img, at_layer_add(at_layer("base", labels = "a"), original)))
  .state_init(rv)
  shiny::isolate({
    expect_equal(at_canvas(img, rv$project)$x$identity, .state_stamp(rv))
  })
  shiny::testServer(mod_canvas_server, args = list(id = "canvas", rv = rv), {
    session$flushReact()
    geometry <- list(type = "Polygon", coordinates = list(list(c(20, 18), c(40, 18),
      c(40, 36), c(20, 36), c(20, 18))))
    session$setInputs(canvas_edited = c(.state_stamp(rv), list(payload = list(
      roi_id = original$id, geometry = geometry, label = "a"))))
    result <- rv$project$layers$base$rois[[1]]
    expect_equal(result$level, 1L)
    expect_equal(unname(sf::st_bbox(result$geometry)), c(8, 6, 16, 12), ignore_attr = TRUE)
    for (field in c("id", "attributes", "author", "created", "source", "label")) {
      expect_identical(result[[field]], original[[field]])
    }
    expect_equal(length(rv$undo), 1L)
    expect_equal(rv$revision, 1)
  })
})

test_that("queued creation uses its original valid target and rejects missing targets", {
  testthat::local_mocked_bindings(.image_data_uri = function(...) NULL)
  s <- demo_session(1); s$autosave <- FALSE
  rv <- shiny::reactiveValues(session = s, cursor = 1L, tool = "point",
    project = at_project(tiny_image(), at_layer("base", labels = c("first", "second"))))
  .state_init(rv)
  shiny::testServer(mod_canvas_server, args = list(id = "canvas", rv = rv), {
    session$flushReact()
    rv$active_label <- "second"
    f <- list(type = "Feature", geometry = list(type = "Point", coordinates = c(2, 2)),
      properties = list(), target = list(layer = "base", label = "first"))
    session$setInputs(canvas_created = c(.state_stamp(rv), list(payload = f)))
    expect_identical(rv$project$layers$base$rois[[1]]$label, "first")
    expect_identical(rv$active_label, "second")
    f$target <- NULL
    session$setInputs(canvas_created = c(.state_stamp(rv), list(payload = f)))
    expect_equal(nrow(at_rois(rv$project)), 1L)
  })
})
