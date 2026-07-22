# Export module: format/scope selection and a progress receipt.

mod_export_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Export"),
    shiny::checkboxGroupInput(ns("formats"), "Formats",
                              choices = c("mask_tiff", "geojson", "qupath", "csv"),
                              selected = c("mask_tiff", "geojson")),
    shiny::selectInput(ns("scope"), "Scope",
                       choices = c("current", "complete", "all", "flagged")),
    shiny::actionButton(ns("run"), "Export"),
    shiny::tableOutput(ns("receipt"))
  )
}

# Images to export for a given scope. The current image always uses the live
# (possibly unsaved) project; others use the last saved project in the session.
.export_targets <- function(rv, scope) {
  st <- annotatR::at_session_status(rv$session)
  switch(scope,
         current  = rv$cursor,
         complete = which(st$status == "complete"),
         flagged  = which(st$status == "flagged"),
         all      = seq_len(nrow(st)))
}

mod_export_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    receipt <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$run, {
      shiny::req(rv$project)
      dir <- file.path(rv$session$out_dir, "export")
      if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
      st <- annotatR::at_session_status(rv$session)
      idx <- .export_targets(rv, input$scope %||% "current")
      overlap <- rv$overlap %||% "last"

      rows <- list(); skipped <- character(0); failed <- character(0)
      for (i in idx) {
        name <- st$name[i]
        proj <- if (i == rv$cursor) rv$project else rv$session$projects[[i]]
        if (is.null(proj) || nrow(annotatR::at_rois(proj)) == 0L) {
          skipped <- c(skipped, name); next
        }
        ok <- tryCatch({
          if ("mask_tiff" %in% input$formats) {
            p <- file.path(dir, paste0(name, ".tif"))
            annotatR::at_write_mask(
              annotatR::at_mask(proj, "labelled", overlap = overlap),
              p, overwrite = TRUE)
            rows[[length(rows) + 1L]] <- data.frame(image = name, format = "mask_tiff", path = p)
          }
          if ("geojson" %in% input$formats) {
            p <- file.path(dir, paste0(name, ".geojson"))
            annotatR::at_write_geojson(proj, p, overwrite = TRUE)
            rows[[length(rows) + 1L]] <- data.frame(image = name, format = "geojson", path = p)
          }
          if ("qupath" %in% input$formats) {
            p <- file.path(dir, paste0(name, "_qupath.geojson"))
            annotatR::at_write_qupath(proj, p, overwrite = TRUE)
            rows[[length(rows) + 1L]] <- data.frame(image = name, format = "qupath", path = p)
          }
          if ("csv" %in% input$formats) {
            p <- file.path(dir, paste0(name, "_rois.csv"))
            annotatR::at_write_rois_csv(proj, p, overwrite = TRUE)
            rows[[length(rows) + 1L]] <- data.frame(image = name, format = "csv", path = p)
          }
          TRUE
        }, error = function(e) {
          failed <<- c(failed, sprintf("%s (%s)", name, conditionMessage(e)))
          FALSE
        })
      }

      if (length(skipped)) {
        shiny::showNotification(
          sprintf("Skipped %d image(s) with no ROIs.", length(skipped)),
          type = "message")
      }
      if (length(failed)) {
        shiny::showNotification(
          paste("Export failed for:", paste(failed, collapse = "; ")),
          type = "error", duration = NULL)
      }
      if (!length(rows) && !length(failed)) {
        shiny::showNotification("Nothing to export: no annotated images in scope.",
                                type = "warning")
      }
      receipt(if (length(rows)) do.call(rbind, rows) else NULL)
    })
    output$receipt <- shiny::renderTable(receipt())
    receipt
  })
}
