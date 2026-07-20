# Canvas module: hosts the atcanvas widget, tracks the tool, and commits drawn
# ROIs into the current project (with autosave and undo).

.canvas_tools <- c("pan", "rect", "polygon", "freehand", "circle", "point", "edit", "erase")

mod_canvas_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-toolbar",
      lapply(.canvas_tools, function(t) shiny::actionButton(ns(paste0("tool_", t)), t))
    ),
    annotatR::atCanvasOutput(ns("canvas"), height = "560px")
  )
}

# Turn a drawn GeoJSON feature (level-0 pixels) into an annot_roi.
.feature_to_roi <- function(feature, label, level = 0L) {
  g <- annotatR:::.geojson_to_sfg(feature$geometry)
  annotatR::at_roi_from_sf(sf::st_sfc(g, crs = sf::NA_crs_), label = label,
                          level = level, source = "manual")
}

# Copy every ROI of `from` into `to` as fresh, editable ROIs (new ids,
# source = "copied"). This powers the Shift+V copy-forward throughput feature.
.copy_forward <- function(from, to) {
  for (nm in names(from$layers)) {
    if (!(nm %in% names(to$layers))) {
      to <- annotatR::at_add_layer(to, annotatR::at_layer(nm, labels = from$layers[[nm]]$labels))
    }
    for (r in from$layers[[nm]]$rois) {
      r$source <- "copied"
      r$id <- annotatR:::.new_id("roi") # fresh, editable ROI
      to <- annotatR::at_add_roi(to, nm, r)
    }
  }
  to
}

mod_canvas_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$canvas <- annotatR::renderAtCanvas({
      shiny::req(rv$project)
      annotatR::at_canvas(rv$project$image, project = rv$project, tool = rv$tool %||% "pan")
    })
    for (t in .canvas_tools) {
      local({
        tool <- t
        shiny::observeEvent(input[[paste0("tool_", tool)]], rv$tool <- tool)
      })
    }
    # Commit a drawn ROI.
    shiny::observeEvent(input$canvas_created, {
      shiny::req(rv$project, rv$active_layer, rv$active_label)
      roi <- .feature_to_roi(input$canvas_created, rv$active_label)
      rv$undo <- c(rv$undo, list(rv$project))
      rv$redo <- list()
      rv$project <- annotatR::at_add_roi(rv$project, rv$active_layer, roi)
      rv$saved <- "unsaved"
    })
    # Shift+V: paste the previous image's ROIs as editable geometry.
    shiny::observeEvent(rv$paste_forward, {
      shiny::req(rv$project, rv$cursor > 1L)
      prev <- rv$session$projects[[rv$cursor - 1L]]
      shiny::req(prev)
      rv$undo <- c(rv$undo, list(rv$project))
      rv$project <- .copy_forward(prev, rv$project)
      rv$saved <- "unsaved"
    }, ignoreInit = TRUE)
  })
}
