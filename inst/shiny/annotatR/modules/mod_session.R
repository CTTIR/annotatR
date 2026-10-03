# Session module: save/resume, autosave status, mark complete/flag.

mod_session_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    .at_action(ns("save"), "💾 Save"),
    .at_action(ns("complete"), "✓ Complete"),
    .at_action(ns("flag"), "⚑ Flag"),
    shiny::span(class = "at-saved", shiny::textOutput(ns("saved"), inline = TRUE))
  )
}

.lite_project <- function(p) {
  if (is.null(p)) NULL else annotatR:::.prepare_project(p)
}

mod_session_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    rv$save_callback <- function(candidate, cursor) {
      annotatR:::.save_checkpoint(candidate, cursor)
    }
    save_now <- function() .state_save(rv)
    shiny::observeEvent(input$save, {
      .state_save(rv, event = .state_event(rv, input$save))
    })
    shiny::observeEvent(rv$trigger_save, {
      .state_save(rv, event = .state_event(rv, rv$trigger_save))
    }, ignoreInit = TRUE)
    shiny::observeEvent(input$complete, {
      .state_save(rv, complete = TRUE, event = .state_event(rv, input$complete))
    })
    shiny::observeEvent(input$flag, {
      .state_status(rv, "flagged", .state_event(rv, input$flag))
    })
    # Mutations synchronously invoke autosave through the shared state helper.
    # No project/session observer retries a failed write without a new action.
    output$saved <- shiny::renderText({
      switch(rv$saved %||% "saved",
             saved = "✓ saved", saving = "⟳ saving…", unsaved = "⚠ unsaved", unavailable = "image unavailable")
    })
    list(save_now = save_now)
  })
}
