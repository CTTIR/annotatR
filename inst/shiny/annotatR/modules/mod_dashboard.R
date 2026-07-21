# Dashboard module: a progress overview of the whole session — metric tiles,
# a status breakdown, and per-image ROI counts.

.metric_tile <- function(value, label) {
  shiny::div(class = "at-tile",
             shiny::div(class = "at-tile-val", value),
             shiny::div(class = "at-tile-lab", label))
}

mod_dashboard_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Progress"),
    shiny::uiOutput(ns("tiles")),
    shiny::br(),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(bslib::card_header("ROIs per image"),
                  shiny::plotOutput(ns("plot"), height = "300px")),
      bslib::card(bslib::card_header("Queue status"),
                  shiny::tableOutput(ns("status")))
    )
  )
}

mod_dashboard_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    status <- shiny::reactive({
      shiny::req(rv$session)
      rv$cursor            # refresh when navigation/edits happen
      rv$saved
      annotatR::at_session_status(rv$session)
    })

    output$tiles <- shiny::renderUI({
      m <- status()
      shiny::div(
        class = "at-tiles",
        .metric_tile(nrow(m), "images"),
        .metric_tile(sum(m$status == "complete"), "complete"),
        .metric_tile(sum(m$status == "pending"), "pending"),
        .metric_tile(sum(m$status == "flagged"), "flagged"),
        .metric_tile(sum(m$n_rois), "ROIs total")
      )
    })

    output$status <- shiny::renderTable({
      m <- status()
      agg <- as.data.frame(table(factor(m$status,
        levels = c("pending", "in_progress", "complete", "flagged", "skipped"))))
      names(agg) <- c("status", "images")
      agg[agg$images > 0, , drop = FALSE]
    })

    output$plot <- shiny::renderPlot({
      m <- status()
      df <- data.frame(image = factor(m$name, levels = m$name),
                       n = m$n_rois, status = m$status)
      ggplot2::ggplot(df, ggplot2::aes(x = .data$image, y = .data$n, fill = .data$status)) +
        ggplot2::geom_col() +
        ggplot2::scale_fill_manual(values = c(
          pending = "#7f93a8", in_progress = "#e3a008", complete = "#1f6feb",
          flagged = "#d55e00", skipped = "#495867"), drop = FALSE) +
        ggplot2::labs(x = NULL, y = "ROIs", fill = NULL) +
        ggplot2::coord_flip() +
        ggplot2::theme_minimal(base_size = 12)
    })
  })
}
