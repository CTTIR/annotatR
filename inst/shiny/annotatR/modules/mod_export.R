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

mod_export_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    receipt <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$run, {
      shiny::req(rv$project)
      dir <- file.path(rv$session$out_dir, "export")
      if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
      name <- annotatR::at_session_status(rv$session)$name[rv$cursor]
      rows <- list()
      if ("mask_tiff" %in% input$formats) {
        p <- file.path(dir, paste0(name, ".tif"))
        annotatR::at_write_mask(annotatR::at_mask(rv$project, "labelled"), p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(format = "mask_tiff", path = p)
      }
      if ("geojson" %in% input$formats) {
        p <- file.path(dir, paste0(name, ".geojson"))
        annotatR::at_write_geojson(rv$project, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(format = "geojson", path = p)
      }
      if ("qupath" %in% input$formats) {
        p <- file.path(dir, paste0(name, "_qupath.geojson"))
        annotatR::at_write_qupath(rv$project, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(format = "qupath", path = p)
      }
      if ("csv" %in% input$formats) {
        p <- file.path(dir, paste0(name, "_rois.csv"))
        annotatR::at_write_rois_csv(rv$project, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(format = "csv", path = p)
      }
      receipt(if (length(rows)) do.call(rbind, rows) else NULL)
    })
    output$receipt <- shiny::renderTable(receipt())
    receipt
  })
}
