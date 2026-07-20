# Session module: save/resume, autosave status, mark complete/flag.

mod_session_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::actionButton(ns("save"), "💾 Save"),
    shiny::actionButton(ns("complete"), "✓ Complete"),
    shiny::actionButton(ns("flag"), "⚑ Flag"),
    shiny::span(class = "at-saved", shiny::textOutput(ns("saved"), inline = TRUE))
  )
}

mod_session_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    # Persist the current project and session.
    save_now <- function() {
      rv$saved <- "saving"
      pdir <- file.path(rv$session$out_dir, "projects")
      if (!dir.exists(pdir)) dir.create(pdir, recursive = TRUE)
      if (!is.null(rv$project)) {
        rv$session$projects[[rv$cursor]] <- rv$project
        name <- annotatR::at_session_status(rv$session)$name[rv$cursor]
        rv$session$manifest$n_rois[rv$cursor] <- nrow(annotatR::at_rois(rv$project))
        annotatR::at_save_project(rv$project, file.path(pdir, paste0(name, ".rds")),
                                  overwrite = TRUE)
      }
      annotatR::at_save_session(rv$session)
      rv$saved <- "saved"
    }
    shiny::observeEvent(input$save, save_now())
    shiny::observeEvent(input$complete, {
      rv$session <- annotatR::at_set_status(rv$session, rv$cursor, "complete")
      save_now()
    })
    shiny::observeEvent(input$flag, {
      rv$session <- annotatR::at_set_status(rv$session, rv$cursor, "flagged")
    })
    # Autosave on any ROI change (session-context <<- allowed here).
    shiny::observeEvent(rv$project, {
      if (isTRUE(rv$session$autosave) && identical(rv$saved, "unsaved")) {
        save_now()
      }
    }, ignoreInit = TRUE)
    output$saved <- shiny::renderText({
      switch(rv$saved %||% "saved",
             saved = "✓ saved", saving = "⟳ saving…",
             unsaved = "⚠ unsaved")
    })
    list(save_now = save_now)
  })
}
