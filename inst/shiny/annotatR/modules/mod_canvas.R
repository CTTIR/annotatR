# Canvas module: hosts the atcanvas widget, tracks the tool, and commits drawn
# ROIs into the current project (with autosave and undo).
#
# The widget is rendered ONCE per image; ROI edits and tool changes are pushed
# through the canvas proxy (partial updates) so the base image is not reloaded
# and the viewport is not reset every time an ROI is drawn.

.canvas_tools <- c("pan", "rect", "polygon", "freehand", "circle", "point", "edit", "erase")

mod_canvas_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-toolbar",
      lapply(.canvas_tools, function(t) shiny::actionButton(ns(paste0("tool_", t)), t))
    ),
    annotatR::atCanvasOutput(ns("canvas"), height = "620px")
  )
}

# Turn a drawn GeoJSON feature (level-0 pixels) into an annot_roi.
.feature_to_roi <- function(feature, label, level = 0L) {
  annotatR::at_roi_from_geojson(feature, label = label, level = level)
}

# Copy every ROI of `from` into `to` as fresh, editable ROIs (new ids,
# source = "copied"). This powers the Shift+V copy-forward throughput feature.
.copy_forward <- function(from, to) {
  for (nm in names(from$layers)) {
    if (!(nm %in% names(to$layers))) {
      to <- annotatR::at_add_layer(to, annotatR::at_layer(nm, labels = from$layers[[nm]]$labels))
    }
    for (r in from$layers[[nm]]$rois) {
      cp <- annotatR::at_roi_from_sf(r$geometry, label = r$label, level = r$level,
                                     source = "copied")
      to <- annotatR::at_add_roi(to, nm, cp)
    }
  }
  to
}

mod_canvas_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    # Render on image / ROI / tool change. The widget caches the base image by
    # data-URI and preserves the viewport, so re-rendering after an ROI edit is
    # a cheap overlay redraw (no image reload, no view reset) -- the tool and
    # annotations are always baked in correctly.
    output$canvas <- annotatR::renderAtCanvas({
      shiny::req(rv$project)
      annotatR::at_canvas(rv$project$image, project = rv$project,
                          tool = rv$tool %||% "pan")
    })

    # Highlight the active tool button.
    shiny::observeEvent(rv$tool, {
      for (t in .canvas_tools) {
        shinyjs::toggleClass(id = paste0("tool_", t), class = "active",
                             condition = identical(rv$tool, t))
      }
    }, ignoreInit = FALSE)

    for (t in .canvas_tools) {
      local({
        tool <- t
        shiny::observeEvent(input[[paste0("tool_", tool)]], rv$tool <- tool)
      })
    }

    # Commit a drawn ROI into the active layer. Default the layer/label so a draw
    # never silently fails before the selection inputs have initialised.
    shiny::observeEvent(input$canvas_created, {
      shiny::req(rv$project)
      layer <- rv$active_layer %||% names(rv$project$layers)[1]
      label <- rv$active_label %||% (rv$project$layers[[layer]]$labels[1] %||% "unlabelled")
      roi <- tryCatch(.feature_to_roi(input$canvas_created, label),
                      error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Could not add ROI:", conditionMessage(roi)),
                                type = "warning")
        return()
      }
      rv$undo <- c(rv$undo, list(rv$project))
      rv$redo <- list()
      rv$project <- annotatR::at_add_roi(rv$project, layer, roi)
      rv$saved <- "unsaved"
    })

    # Erase tool: click an ROI to remove it.
    shiny::observeEvent(input$canvas_erased, {
      shiny::req(rv$project, input$canvas_erased)
      rv$undo <- c(rv$undo, list(rv$project))
      rv$redo <- list()
      rv$project <- annotatR::at_remove_roi(rv$project, input$canvas_erased)
      rv$saved <- "unsaved"
    })

    # Edit tool: drag an ROI to move it; commit the new geometry in place.
    shiny::observeEvent(input$canvas_edited, {
      ed <- input$canvas_edited
      shiny::req(rv$project, ed$roi_id, ed$geometry)
      roi <- tryCatch(.feature_to_roi(list(type = "Feature", geometry = ed$geometry,
                                           properties = list()),
                                      ed$label %||% "unlabelled"),
                      error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Edit failed:", conditionMessage(roi)), type = "warning")
        return()
      }
      rv$undo <- c(rv$undo, list(rv$project))
      rv$redo <- list()
      proj <- annotatR::at_remove_roi(rv$project, ed$roi_id)
      proj <- annotatR::at_add_roi(proj, ed$layer %||% names(proj$layers)[1], roi)
      rv$project <- proj
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
