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

# Drop the bulky in-memory pixel cache before serialising: the image is
# re-materialised from its source path on resume, so persisting the (up to
# hundreds of MB) cube array on every autosave would freeze the UI for nothing.
.lite_project <- function(p) {
  if (!is.null(p) && !is.null(p$image)) p$image$handle <- NULL
  p
}

mod_session_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    # Persist the current project and session (annotations only; no pixel data).
    save_now <- function() {
      rv$saved <- "saving"
      pdir <- file.path(rv$session$out_dir, "projects")
      if (!dir.exists(pdir)) dir.create(pdir, recursive = TRUE)
      if (!is.null(rv$project)) {
        rv$session$projects[[rv$cursor]] <- rv$project
        name <- annotatR::at_session_status(rv$session)$name[rv$cursor]
        rv$session$manifest$n_rois[rv$cursor] <- nrow(annotatR::at_rois(rv$project))
        annotatR::at_save_project(.lite_project(rv$project),
                                  file.path(pdir, paste0(name, ".rds")),
                                  overwrite = TRUE)
      }
      sess <- rv$session
      sess$projects <- lapply(sess$projects, .lite_project)
      annotatR::at_save_session(sess)
      rv$saved <- "saved"
    }
    shiny::observeEvent(input$save, save_now())
    # 's' key / commit-advance route through here (they own no save of their own).
    shiny::observeEvent(rv$trigger_save, save_now(), ignoreInit = TRUE)
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
