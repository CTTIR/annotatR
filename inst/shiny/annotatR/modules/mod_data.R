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
      shiny::textInput(ns("dir"), NULL, placeholder = "/path/to/a/folder of images or cubes"),
      shiny::actionButton(ns("load"), "Load folder", class = "btn-primary")
    ),
    shiny::div(class = "at-progress", shiny::textOutput(ns("msg"), inline = TRUE)),
    shiny::h5("Current queue"),
    shiny::tableOutput(ns("table"))
  )
}

mod_data_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    msg <- shiny::reactiveVal("")

    shiny::observeEvent(input$load, {
      d <- input$dir
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
                             out_dir = rv$session$out_dir),
        error = function(e) e)
      if (inherits(new_sess, "error")) { msg(paste("Load failed:", conditionMessage(new_sess))); return() }
      rv$session <- new_sess
      rv$cursor <- 1L
      msg(sprintf("Loaded %d image(s).", nrow(new_sess$manifest)))
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
