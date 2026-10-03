# Data module: choose the images/cubes to annotate. Shows the current queue and
# lets the user point at a folder to (re)load a queue, reusing the session's
# label vocabulary and layer template.

.data_exts <- "\\.(dat|hdr|tif|tiff|png|jpe?g|qptiff|cu3|cu3s)$"

mod_data_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Data source"),
    bslib::layout_columns(
      col_widths = c(9, 3),
      shiny::textInput(ns("dir"), "Image folder", placeholder = "/path/to/a/folder of images or cubes"),
      .at_action(ns("load"), "Load folder", class = "btn-primary", fields = list(dir = ns("dir")))
    ),
    shiny::div(class = "at-progress", shiny::textOutput(ns("msg"), inline = TRUE)),
    .at_action(ns("restore"), "Restore previous queue"),
    shiny::textOutput(ns("recovery")),
    shiny::h5("Current queue"),
    shiny::tableOutput(ns("table"))
  )
}

mod_data_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    msg <- shiny::reactiveVal("")

    shiny::observeEvent(input$load, {
      event <- .state_event(rv, input$load, fields = c("dir"))
      shiny::req(event)
      d <- event$payload$dir
      shiny::req(is.character(d), length(d) == 1L)
      if (!nzchar(d) || !dir.exists(d)) {
        msg("Folder not found."); return()
      }
      files <- list.files(d, pattern = .data_exts, recursive = TRUE,
                          full.names = TRUE, ignore.case = TRUE)
      # Prefer TIVITA cubes when present; otherwise take what matched.
      cubes <- files[grepl("_SpecCube\\.dat$", files, ignore.case = TRUE)]
      if (length(cubes)) files <- cubes
      if (!length(files)) { msg("No supported images found in that folder."); return()
      }
      new_sess <- tryCatch(
        annotatR::at_session(files, labels = rv$session$labels,
                             layers = rv$session$layer_spec,
                             out_dir = file.path(rv$session$out_dir, annotatR:::.new_identity_id("session")),
                             autosave = rv$session$autosave),
        error = function(e) e)
      if (inherits(new_sess, "error")) { msg(paste("Load failed:", conditionMessage(new_sess))); return() }
      if (.state_replace(rv, new_sess, event)) {
        msg(sprintf("Loaded %d image(s). Previous queue retained; use Restore previous queue to recover its annotations.", nrow(new_sess$manifest)))
      }
    })

    shiny::observeEvent(input$restore, {
      if (.state_restore_queue(rv, .state_event(rv, input$restore))) msg("Previous queue restored with its annotations and save state.")
    })
    output$recovery <- shiny::renderText({
      if (!is.null(rv$recovery_queue)) "Previous queue and any unsaved annotations are retained in this session. Restore them before closing the app."
      else "No previous queue is retained."
    })
    output$msg <- shiny::renderText(msg())

    output$table <- shiny::renderTable({
      shiny::req(rv$session)
      rv$cursor
      m <- annotatR::at_session_status(rv$session)
      data.frame(idx = m$idx, name = m$name, status = m$status,
                 n_rois = m$n_rois, path = m$path)
    })
  })
}
