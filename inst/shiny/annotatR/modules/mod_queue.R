# Queue module: image list with status, navigation, and progress.

.status_glyph <- function(status) {
  c(pending = "○", in_progress = "◐", complete = "✓",
    flagged = "⚑", skipped = "⊘")[status]
}

mod_queue_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-queue-controls",
      shiny::selectInput(ns("filter"), NULL,
                         choices = c("all", "pending", "in_progress", "complete", "flagged", "skipped"),
                         selected = "all"),
      shiny::actionButton(ns("prev"), "◀"),
      shiny::actionButton(ns("nxt"), "▶"),
      shiny::actionButton(ns("next_pending"), "Next pending")
    ),
    shiny::tableOutput(ns("list")),
    shiny::div(class = "at-progress", shiny::textOutput(ns("progress")))
  )
}

mod_queue_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observeEvent(input$nxt, {
      rv$session <- annotatR::at_next(rv$session)
      rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$prev, {
      rv$session <- annotatR::at_prev(rv$session)
      rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$next_pending, {
      m <- annotatR::at_session_status(rv$session)
      pending <- which(m$status == "pending")
      nxt <- pending[pending > rv$cursor]
      target <- if (length(nxt)) nxt[1] else if (length(pending)) pending[1] else rv$cursor
      rv$session <- annotatR::at_goto(rv$session, target)
      rv$cursor <- target
    })
    output$list <- shiny::renderTable({
      m <- annotatR::at_session_status(rv$session)
      if (input$filter != "all") m <- m[m$status == input$filter, , drop = FALSE]
      data.frame(idx = m$idx, name = m$name,
                 status = .status_glyph(m$status), n = m$n_rois)
    })
    output$progress <- shiny::renderText({
      m <- annotatR::at_session_status(rv$session)
      sprintf("%d / %d complete", sum(m$status == "complete"), nrow(m))
    })
  })
}
