# ROI table module: a sortable/filterable table with delete.

mod_roitable_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("ROIs"),
    shiny::tableOutput(ns("table")),
    shiny::textInput(ns("del_id"), NULL, placeholder = "roi_id to delete"),
    shiny::actionButton(ns("delete"), "Delete ROI")
  )
}

mod_roitable_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$table <- shiny::renderTable({
      shiny::req(rv$project)
      rt <- annotatR::at_rois(rv$project)
      if (nrow(rt) == 0L) {
        return(data.frame(roi_id = character(0), layer = character(0),
                          label = character(0), area_px = double(0)))
      }
      data.frame(roi_id = rt$roi_id, layer = rt$layer, label = rt$label,
                 area_px = round(rt$area_px, 1))
    })
    shiny::observeEvent(input$delete, {
      shiny::req(rv$project, nzchar(input$del_id))
      rv$undo <- c(rv$undo, list(rv$project))
      rv$project <- annotatR::at_remove_roi(rv$project, input$del_id)
      rv$saved <- "unsaved"
    })
  })
}
