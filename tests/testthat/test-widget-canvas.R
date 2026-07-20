# The canvas is JavaScript; here it is tested at the R contract boundary
# (widget construction, tile source, proxy messages, coordinate handling).
skip_if_not_installed("htmlwidgets")

mock_session <- function() {
  msgs <- list()
  list(
    session = list(sendCustomMessage = function(type, message) {
      msgs[[length(msgs) + 1L]] <<- list(type = type, message = message)
    }),
    messages = function() msgs
  )
}

test_that("at_canvas returns a configured htmlwidget", {
  skip_if_not_installed("tiff")
  w <- at_canvas(at_example_image("tissue"))
  expect_s3_class(w, "htmlwidget")
  expect_true(all(c("tileSource", "annotations", "tool") %in% names(w$x)))
  expect_identical(w$x$annotations$type, "FeatureCollection")
})

test_that("at_canvas seeds annotations from a project", {
  skip_if_not_installed("tiff")
  w <- at_canvas(at_example_image("tissue"), project = at_example_project())
  expect_length(w$x$annotations$features, 3L)
})

test_that("at_tile_source describes the image", {
  ts <- at_tile_source(small_image(), embed = FALSE)
  expect_identical(ts$width, 100L)
  expect_identical(ts$height, 100L)
  expect_identical(ts$maxLevel, 2L)
  expect_identical(ts$nBands, 3L)
})

test_that("proxy setters send correctly-addressed messages", {
  m <- mock_session()
  px <- at_canvas_proxy("cv", session = m$session)
  at_canvas_set_tool(px, "polygon")
  at_canvas_set_band(px, 2L)
  at_canvas_fit(px, c(0, 0, 50, 50))
  msgs <- m$messages()
  types <- vapply(msgs, `[[`, character(1), "type")
  expect_identical(types, c("atcanvas-set_tool", "atcanvas-set_band", "atcanvas-fit_bounds"))
  expect_true(all(vapply(msgs, function(x) identical(x$message$id, "cv"), logical(1))))
  expect_identical(msgs[[1]]$message$tool, "polygon")
})

test_that("at_canvas_set_annotations sends a FeatureCollection", {
  skip_if_not_installed("tiff")
  m <- mock_session()
  px <- at_canvas_proxy("cv", session = m$session)
  at_canvas_set_annotations(px, at_example_project())
  msg <- m$messages()[[1]]
  expect_identical(msg$type, "atcanvas-set_annotations")
  expect_identical(msg$message$annotations$type, "FeatureCollection")
})

test_that("tools validate against the allowed set", {
  m <- mock_session()
  px <- at_canvas_proxy("cv", session = m$session)
  expect_error(at_canvas_set_tool(px, "bogus"), "must be one of")
})

test_that("drawn level-0 coordinates rasterise to the drawn pixels", {
  # A feature emitted by the JS at level-0 pixels (2,2)-(5,5) must land on
  # mask rows/cols 3-5 (the coordinate contract across the JS -> R boundary).
  g <- sf::st_polygon(list(rbind(c(2, 2), c(5, 2), c(5, 5), c(2, 5), c(2, 2))))
  roi <- at_roi_from_sf(sf::st_sfc(g, crs = sf::NA_crs_), label = "drawn")
  idx <- which(as.matrix(at_mask(roi, "binary", dims = c(10, 10))), arr.ind = TRUE)
  expect_identical(sort(unique(idx[, 1])), 3:5)
  expect_identical(sort(unique(idx[, 2])), 3:5)
})

test_that("the widget JavaScript makes no external requests", {
  js <- readLines(system.file("htmlwidgets", "atcanvas.js", package = "annotatR"))
  expect_false(any(grepl("https?://", js)))
})

test_that("Shiny output/render helpers are defined", {
  expect_true(is.function(atCanvasOutput))
  expect_true(is.function(renderAtCanvas))
})
