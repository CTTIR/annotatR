# ROI table module: a sortable/filterable table with delete.

mod_roitable_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("ROIs"),
    shiny::tableOutput(ns("table")),
    shiny::textInput(ns("del_id"), "ROI ID to delete", placeholder = "roi_id to delete"),
    .at_action(ns("delete"), "Delete ROI", fields = list(del_id = ns("del_id")))
  )
}

mod_roitable_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
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
      event <- .state_event(rv, input$delete, fields = c("del_id"))
      shiny::req(event, rv$project, is.character(event$payload$del_id),
                 length(event$payload$del_id) == 1L, nzchar(event$payload$del_id))
      .state_mutate(rv, function(p) annotatR::at_remove_roi(p, event$payload$del_id),
                    event)
    })
  })
}
