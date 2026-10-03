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
                         selected = "all", selectize = FALSE),
      .at_action(ns("prev"), "◀"),
      .at_action(ns("nxt"), "▶"),
      .at_action(ns("next_pending"), "Next pending")
    ),
    shiny::tableOutput(ns("list")),
    shiny::div(class = "at-progress", shiny::textOutput(ns("progress")))
  )
}

mod_queue_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    shiny::observeEvent(input$nxt, {
      .state_navigate(rv, rv$cursor + 1L, .state_event(rv, input$nxt))
    })
    shiny::observeEvent(input$prev, {
      .state_navigate(rv, rv$cursor - 1L, .state_event(rv, input$prev))
    })
    shiny::observeEvent(input$next_pending, {
      .state_navigate(rv, .state_pending(rv), .state_event(rv, input$next_pending))
    })
    output$list <- shiny::renderTable({
      m <- annotatR::at_session_status(rv$session)
      n <- m$n_rois
      # Live count for the image being edited (manifest counts only update on save).
      if (!is.null(rv$project) && rv$cursor >= 1L && rv$cursor <= length(n)) {
        n[rv$cursor] <- nrow(annotatR::at_rois(rv$project))
      }
      keep <- if (!is.null(input$filter) && input$filter != "all") m$status == input$filter else rep(TRUE, nrow(m))
      data.frame(idx = m$idx[keep], name = m$name[keep],
                 status = .status_glyph(m$status[keep]), n = n[keep])
    })
    output$progress <- shiny::renderText({
      m <- annotatR::at_session_status(rv$session)
      sprintf("%d / %d complete", sum(m$status == "complete"), nrow(m))
    })
    # Keep the queue status current even while another page is in front, so ROI
    # counts and statuses are up to date the moment you return to Annotate.
    shiny::outputOptions(output, "list", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "progress", suspendWhenHidden = FALSE)
  })
}
