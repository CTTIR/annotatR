# Run from the repository root; no image decoder or private fixture is needed.
pkgload::load_all(quiet = TRUE)
for (module in c("mod_state.R", "mod_canvas.R")) {
  source(file.path("inst/shiny/annotatR/modules", module))
}
img <- annotatR:::new_annot_image(source = "synthetic", backend = "tiff",
  dims = c(100L, 90L), n_levels = 2L,
  level_dims = list(c(100L, 90L), c(40L, 30L)), n_bands = 1L)
ring <- function(x0, y0, x1, y1) rbind(c(x0,y0),c(x1,y0),c(x1,y1),c(x0,y1),c(x0,y0))
donut <- at_roi_polygon(list(ring(0,0,40,30),ring(12,10,28,20)), "donut", level = 1L,
  note = "keep", score = 7, author = "owner")
multi <- at_roi_from_sf(sf::st_sfc(sf::st_multipolygon(list(
  list(ring(2,2,8,8)), list(ring(32,22,38,28))))), "multi", level = 1L, note = "keep", score = 7, author = "owner")
ui <- shiny::fluidPage(
  shiny::fluidRow(shiny::column(6, shiny::uiOutput("mount")),
    shiny::column(6, atCanvasOutput("b-canvas", height = "360px"))),
  shiny::actionButton("point_a", "Point A"), shiny::actionButton("point_b", "Point B"),
  shiny::actionButton("erase_a", "Erase A"), shiny::actionButton("edit_b", "Edit B"),
  shiny::actionButton("remount", "Remount A"), shiny::actionButton("overlay_a", "Overlay A"),
  shiny::verbatimTextOutput("state"))
server <- function(input, output, session) {
  states <- lapply(c("a", "b"), function(id) {
    path <- tempfile(); writeLines("synthetic", path)
    sess <- at_session(path, out_dir = tempdir()); sess$autosave <- FALSE
    shiny::reactiveValues(session = sess, cursor = 1L, tool = "erase",
      project = at_project(img, at_layer_add(at_layer("base", labels = c("donut", "multi")),
        if (id == "a") donut else multi)))
  })
  output$mount <- shiny::renderUI({ input$remount; atCanvasOutput("a-canvas", height = "360px") })
  mod_canvas_server("a", states[[1]]); mod_canvas_server("b", states[[2]])
  for (spec in list(c("point_a", "a-canvas", "point"), c("point_b", "b-canvas", "point"),
                    c("erase_a", "a-canvas", "erase"), c("edit_b", "b-canvas", "edit"))) local({
    value <- spec
    shiny::observeEvent(input[[value[1]]], {
      at_canvas_set_tool(at_canvas_proxy(value[2], session), value[3])
      session$sendCustomMessage("fixture-ack", value[1])
    })
  })
  shiny::observeEvent(input$overlay_a, {
    session$sendCustomMessage("atcanvas-set_overlay", list(
      id = "a-canvas", overlay = "/slow-overlay.svg", alpha = 0.5))
    session$sendCustomMessage("fixture-ack", "overlay_a")
  })
  output$state <- shiny::renderText(jsonlite::toJSON(lapply(states, function(rv) {
    p <- rv$project
    list(entry_id = rv$entry_id, revision = rv$revision, rois = lapply(p$layers$base$rois, function(r) {
      list(id = r$id, label = r$label, level = r$level, attributes = r$attributes,
        author = r$author, geometry = annotatR:::.sfg_to_geojson(r$geometry[[1]]))
    }))
  }), auto_unbox = TRUE))
}
# Stable white pixels permit exact hole-fill checks without any native decoder.
uri <- paste0("data:image/svg+xml,", utils::URLencode(
  '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="90"><rect width="100" height="90" fill="white"/></svg>', reserved = TRUE))
shiny::addResourcePath("widget-fixture", normalizePath("inst/shiny/annotatR/www"))
ui <- htmltools::tagList(shiny::tags$script(src = "widget-fixture/keys.js"), ui)
testthat::with_mocked_bindings(
  shiny::runApp(shiny::shinyApp(ui, server), host = "127.0.0.1",
    port = as.integer(Sys.getenv("ANNOTATR_BROWSER_PORT", "5818")), launch.browser = FALSE),
  .image_data_uri = function(...) uri, .package = "annotatR")
