# annotatR batch-annotation application.
# Launched via annotatR::at_annotate(); every call is namespace-qualified, with
# no package attaching.

for (f in list.files("modules", pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = FALSE)
}

# Materialise the project for image `i`, reusing a stored one when present.
.materialise <- function(session, i) {
  p <- session$projects[[i]]
  if (!is.null(p)) {
    return(p)
  }
  img <- annotatR::at_read_image(session$manifest$path[i])
  proj <- annotatR::at_project(img, meta = list(name = session$manifest$name[i]))
  for (L in session$layer_spec) proj <- annotatR::at_add_layer(proj, L)
  if (length(proj$layers) == 0L) {
    proj <- annotatR::at_add_layer(proj, annotatR::at_layer("annotations",
                                                            labels = session$labels))
  }
  proj
}

ui <- bslib::page_navbar(
  title = "annotatR",
  theme = bslib::bs_theme(version = 5, primary = .app_accent),
  header = shiny::tagList(
    shinyjs::useShinyjs(),
    shiny::includeCSS("www/custom.css"),
    shiny::tags$script(src = "keys.js")
  ),
  bslib::nav_panel(
    "Annotate",
    bslib::layout_columns(
      col_widths = c(3, 6, 3),
      bslib::card(bslib::card_header("Queue"), mod_queue_ui("queue")),
      bslib::card(
        bslib::card_header(mod_session_ui("session")),
        mod_canvas_ui("canvas")
      ),
      bslib::card(
        mod_layers_ui("layers"),
        mod_mask_ui("mask"),
        mod_spectrum_ui("spectrum"),
        mod_roitable_ui("roitable"),
        mod_export_ui("export"),
        mod_help_ui("help")
      )
    )
  )
)

server <- function(input, output, session) {
  sess0 <- .app_session()
  rv <- shiny::reactiveValues(
    session = sess0, cursor = sess0$cursor, project = NULL, tool = "pan",
    active_layer = NULL, active_label = NULL, mask_type = "labelled",
    overlap = "last", undo = list(), redo = list(), saved = "saved",
    paste_forward = NULL
  )

  # Route global keyboard shortcuts (from www/keys.js) to state and actions.
  shiny::observeEvent(input$key_next, {
    rv$session <- annotatR::at_next(rv$session); rv$cursor <- rv$session$cursor
  })
  shiny::observeEvent(input$key_prev, {
    rv$session <- annotatR::at_prev(rv$session); rv$cursor <- rv$session$cursor
  })
  shiny::observeEvent(input$key_tool, rv$tool <- input$key_tool)
  shiny::observeEvent(input$key_label, {
    shiny::req(rv$project, rv$active_layer)
    labs <- rv$project$layers[[rv$active_layer]]$labels
    if (input$key_label <= length(labs)) rv$active_label <- labs[input$key_label]
  })
  shiny::observeEvent(input$key_flag, {
    rv$session <- annotatR::at_set_status(rv$session, rv$cursor, "flagged")
  })
  shiny::observeEvent(input$key_undo, {
    if (length(rv$undo) > 0L) {
      rv$redo <- c(rv$redo, list(rv$project))
      rv$project <- rv$undo[[length(rv$undo)]]
      rv$undo <- rv$undo[-length(rv$undo)]
    }
  })
  shiny::observeEvent(input$key_redo, {
    if (length(rv$redo) > 0L) {
      rv$undo <- c(rv$undo, list(rv$project))
      rv$project <- rv$redo[[length(rv$redo)]]
      rv$redo <- rv$redo[-length(rv$redo)]
    }
  })
  shiny::observeEvent(input$key_paste_forward, rv$paste_forward <- input$key_paste_forward)

  shiny::observeEvent(rv$cursor, {
    proj <- tryCatch(.materialise(rv$session, rv$cursor), error = function(e) e)
    if (inherits(proj, "error")) {
      rv$session <- annotatR::at_set_status(rv$session, rv$cursor, "skipped")
      rv$project <- NULL
      shiny::showNotification(paste("Skipped image:", conditionMessage(proj)),
                              type = "error")
      return()
    }
    rv$project <- proj
    rv$active_layer <- names(proj$layers)[1]
    rv$active_label <- proj$layers[[1]]$labels[1]
    rv$saved <- "saved"
  }, ignoreNULL = FALSE)

  mod_queue_server("queue", rv)
  mod_canvas_server("canvas", rv)
  mod_layers_server("layers", rv)
  mod_mask_server("mask", rv)
  mod_spectrum_server("spectrum", rv)
  mod_roitable_server("roitable", rv)
  mod_export_server("export", rv)
  mod_session_server("session", rv)
  mod_help_server("help", rv)
}

shiny::shinyApp(ui, server)
