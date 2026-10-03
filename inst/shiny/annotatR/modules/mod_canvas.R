# Canvas module: hosts the atcanvas widget, tracks the tool, and commits drawn
# ROIs into the current project (with autosave and undo).
#
# Compatible renders reuse loaded base pixels and preserve the viewport.

.canvas_tools <- c("pan", "rect", "polygon", "freehand", "circle", "point", "edit", "erase")

mod_canvas_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-toolbar",
      lapply(.canvas_tools, function(t) .at_action(ns(paste0("tool_", t)), t)),
      .at_action(ns("undo"), "Undo"), .at_action(ns("redo"), "Redo"),
      .at_action(ns("copy"), "Copy previous")
    ),
    shiny::p("Focus the canvas with Tab. Arrows move 1 image pixel (Shift: 10). Enter or Space anchors a point/rectangle; polygon: Space adds a vertex, Enter finishes. Escape cancels. Shift+Enter saves, completes and advances."),
    shiny::div(role = "status", `aria-live` = "polite", shiny::textOutput(ns("display"))),
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
    if (isTRUE(to$layers[[nm]]$style$locked)) next
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
    .state_init(rv)
    # Render on image / ROI / tool change. The widget caches the base image by
    # data-URI and preserves the viewport, so re-rendering after an ROI edit is
    # a cheap overlay redraw (no image reload, no view reset) -- the tool and
    # annotations are always baked in correctly.
    output$canvas <- annotatR::renderAtCanvas({
      if (is.null(rv$project)) return(htmlwidgets::createWidget("atcanvas",
        x = list(tileSource = list(width = 1, height = 1, displayError = rv$display_error),
          identity = .state_stamp(rv), annotations = list(features = list()), tool = "pan"),
        package = "annotatR"))
      annotatR::at_canvas(rv$project$image, project = rv$project,
                          tool = rv$tool %||% "pan",
                          options = list(creationTarget = list(
                            layer = rv$active_layer, label = rv$active_label,
                            locked = isTRUE(rv$project$layers[[rv$active_layer]]$style$locked))))
    })

    output$display <- shiny::renderText({
      paste(rv$session$manifest$name[rv$cursor], "—",
        if (isTRUE(rv$display_ready)) "Image ready" else rv$display_error %||% "Waiting for display")
    })
    shiny::observeEvent(input$canvas_ready, {
      event <- .state_event(rv, input$canvas_ready, widget = TRUE)
      shiny::req(event)
      rv$display_ready <- isTRUE(event$payload$ready) && !is.null(rv$project)
      rv$display_error <- if (rv$display_ready) NULL else event$payload$error %||% "Image display unavailable."
    })
    shiny::outputOptions(output, "canvas", suspendWhenHidden = FALSE)
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
        shiny::observeEvent(input[[paste0("tool_", tool)]], {
          event <- .state_event(rv, input[[paste0("tool_", tool)]])
          if (!is.null(event)) rv$tool <- tool
        })
      })
    }

    shiny::observeEvent(input$undo, .state_undo(rv, event = .state_event(rv, input$undo)))
    shiny::observeEvent(input$redo, .state_undo(rv, redo = TRUE, event = .state_event(rv, input$redo)))
    shiny::observeEvent(input$copy, {
      event <- .state_event(rv, input$copy)
      shiny::req(event, rv$cursor > 1L)
      previous <- rv$session$projects[[rv$cursor - 1L]]
      shiny::req(previous)
      .state_mutate(rv, function(p) .copy_forward(previous, p), event)
    })
    # Decode identity/revision before parsing geometry or touching history.
    shiny::observeEvent(input$canvas_created, {
      event <- .state_event(rv, input$canvas_created, widget = TRUE)
      shiny::req(event, rv$project, is.list(event$payload))
      target <- event$payload$target
      shiny::req(is.list(target), is.character(target$layer), length(target$layer) == 1L,
                 is.character(target$label), length(target$label) == 1L)
      layer <- target$layer; label <- target$label
      shiny::req(layer %in% names(rv$project$layers), label %in% rv$project$layers[[layer]]$labels,
                 !isTRUE(rv$project$layers[[layer]]$style$locked))
      roi <- tryCatch(.feature_to_roi(event$payload, label), error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Could not add ROI:", conditionMessage(roi)), type = "warning")
        return()
      }
      .state_mutate(rv, function(p) annotatR::at_add_roi(p, layer, roi), event)
    })

    shiny::observeEvent(input$canvas_erased, {
      event <- .state_event(rv, input$canvas_erased, widget = TRUE)
      shiny::req(event, rv$project, is.character(event$payload), length(event$payload) == 1L, !is.na(event$payload))
      .state_mutate(rv, function(p) annotatR::at_remove_roi(p, event$payload), event)
    })

    shiny::observeEvent(input$canvas_edited, {
      event <- .state_event(rv, input$canvas_edited, widget = TRUE)
      shiny::req(event, rv$project, is.list(event$payload))
      ed <- event$payload
      shiny::req(ed$roi_id, ed$geometry)
      # Locate the existing object by its stable ID; do not recreate an ROI
      # (which would lose its ID, attributes, author and creation timestamp).
      rt <- annotatR::at_rois(rv$project)
      row <- match(ed$roi_id, rt$roi_id)
      shiny::req(!is.na(row))
      layer <- rt$layer[row]
      ids <- vapply(rv$project$layers[[layer]]$rois, `[[`, character(1), "id")
      index <- match(ed$roi_id, ids)
      original <- rv$project$layers[[layer]]$rois[[index]]
      roi <- tryCatch(annotatR::at_transform(
        .feature_to_roi(list(type = "Feature", geometry = ed$geometry, properties = list()),
                        original$label),
        from_level = 0L, to_level = original$level, img = rv$project$image),
                      error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Edit failed:", conditionMessage(roi)), type = "warning")
        return()
      }
      .state_mutate(rv, function(p) {
        original$geometry <- roi$geometry
        original$modified <- Sys.time()
        p$layers[[layer]]$rois[[index]] <- original
        p
      }, event)
    })

    # Compatibility hook for standalone module callers; app keyboard actions
    # call the shared mutation synchronously with their original event stamp.
    shiny::observeEvent(rv$paste_forward, {
      event <- .state_event(rv, rv$paste_forward)
      shiny::req(event, rv$cursor > 1L)
      prev <- rv$session$projects[[rv$cursor - 1L]]
      shiny::req(prev)
      .state_mutate(rv, function(p) .copy_forward(prev, p), event)
    }, ignoreInit = TRUE)
  })
}
