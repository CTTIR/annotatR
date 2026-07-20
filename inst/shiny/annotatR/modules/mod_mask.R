# Mask module: live mask preview, type/overlap toggles, and one-click export.

mod_mask_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Mask preview"),
    shiny::radioButtons(ns("type"), NULL,
                        choices = c("binary", "labelled", "multiclass"),
                        selected = "labelled", inline = TRUE),
    shiny::selectInput(ns("overlap"), "Overlap",
                       choices = c("last", "first", "max", "min", "error")),
    shiny::plotOutput(ns("preview"), height = "200px"),
    shiny::uiOutput(ns("overlap_warn")),
    shiny::tableOutput(ns("stats")),
    shiny::actionButton(ns("export"), "Export this mask")
  )
}

# Build the current mask (debounce is applied at the app level).
.current_mask <- function(rv) {
  shiny::req(rv$project)
  annotatR::at_mask(rv$project, type = rv$mask_type %||% "labelled",
                    overlap = rv$overlap %||% "last")
}

mod_mask_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observeEvent(input$type, rv$mask_type <- input$type)
    shiny::observeEvent(input$overlap, rv$overlap <- input$overlap)
    output$preview <- shiny::renderPlot({
      m <- .current_mask(rv)
      annotatR::at_plot_mask(annotatR::at_mask_preview(m, max_dim = 400L))
    })
    output$stats <- shiny::renderTable({
      m <- .current_mask(rv)
      st <- annotatR::at_mask_stats(m)
      st[, c("label", "n_px", "frac_total")]
    })
    output$overlap_warn <- shiny::renderUI({
      shiny::req(rv$project)
      ov <- annotatR::at_rois_overlap(rv$project$layers[[rv$active_layer %||% names(rv$project$layers)[1]]])
      if (nrow(ov) > 0L) {
        shiny::span(class = "at-warn", "⚠ overlapping ROIs")
      }
    })
    shiny::observeEvent(input$export, {
      shiny::req(rv$project)
      dir <- file.path(rv$session$out_dir, "masks")
      if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
      name <- annotatR::at_session_status(rv$session)$name[rv$cursor]
      annotatR::at_write_mask(.current_mask(rv),
                              file.path(dir, paste0(name, ".tif")), overwrite = TRUE)
    })
  })
}
