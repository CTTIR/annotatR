# annotatR batch-annotation application.
# Launched via annotatR::at_annotate(); every call is namespace-qualified, with
# no package attaching.

# Load shared setup (.app_session(), .app_accent, .app_theme) and the module
# files. Sourced explicitly so the app builds identically however it is
# launched, rather than relying on the host auto-sourcing global.R.
source("global.R", local = FALSE)
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
  proj <- annotatR::at_project(img, name = session$manifest$name[i])
  for (L in session$layer_spec) proj <- annotatR::at_add_layer(proj, L)
  if (length(proj$layers) == 0L) {
    proj <- annotatR::at_add_layer(proj, annotatR::at_layer("annotations",
                                                            labels = session$labels))
  }
  proj
}

# ---- The annotation page: a clean three-column workspace ------------------
# Queue (left) | canvas + tools (middle) | layers & labels (right). Everything
# analytical lives on the other pages so this view stays uncluttered.
.annotate_page <- bslib::layout_columns(
  col_widths = c(3, 6, 3),
  bslib::card(
    class = "at-queue",
    bslib::card_header("Queue"),
    mod_queue_ui("queue")
  ),
  bslib::card(
    bslib::card_header(class = "at-canvas-header", mod_session_ui("session")),
    mod_canvas_ui("canvas")
  ),
  bslib::card(
    bslib::card_header("Layers & labels"),
    mod_layers_ui("layers"),
    shiny::hr(),
    mod_help_ui("help")
  )
)

.summary_page <- bslib::layout_columns(
  col_widths = c(6, 6),
  bslib::card(bslib::card_header("Mask"), mod_mask_ui("mask")),
  bslib::card(bslib::card_header("Spectra & ROIs"),
              mod_spectrum_ui("spectrum"), shiny::hr(), mod_roitable_ui("roitable"))
)

ui <- bslib::page_navbar(
  id = "nav",
  window_title = "annotatR",
  theme = .app_theme(),
  fillable = FALSE,
  selected = "Annotate",
  title = shiny::span(
    class = "at-brand",
    shiny::img(src = "logo.svg", class = "at-logo", alt = "annotatR"),
    shiny::span("annotatR", class = "at-brandname")
  ),
  header = shiny::tagList(
    shinyjs::useShinyjs(),
    shiny::tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
    shiny::tags$script(src = "keys.js")
  ),
  bslib::nav_panel("Data", mod_data_ui("data")),
  bslib::nav_panel("Dashboard", mod_dashboard_ui("dashboard")),
  bslib::nav_panel("Annotate", .annotate_page),
  bslib::nav_panel("Summary", .summary_page),
  bslib::nav_panel("Export", bslib::card(bslib::card_header("Export"), mod_export_ui("export"))),
  bslib::nav_spacer(),
  bslib::nav_item(bslib::input_dark_mode(id = "dark_mode"))
)

server <- function(input, output, session) {
  sess0 <- .app_session()
  rv <- shiny::reactiveValues(
    session = sess0, cursor = sess0$cursor, project = NULL, tool = "pan",
    active_layer = NULL, active_label = NULL, mask_type = "labelled",
    overlap = "last", undo = list(), redo = list(), saved = "saved",
    paste_forward = NULL, trigger_save = NULL, trigger_help = NULL
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
  # N: jump to the next pending image (mirrors the queue's Next-pending button).
  shiny::observeEvent(input$key_next_pending, {
    m <- annotatR::at_session_status(rv$session)
    pending <- which(m$status == "pending")
    nxt <- pending[pending > rv$cursor]
    target <- if (length(nxt)) nxt[1] else if (length(pending)) pending[1] else rv$cursor
    rv$session <- annotatR::at_goto(rv$session, target)
    rv$cursor <- target
  })
  # Ctrl+E: jump to the Export page.
  shiny::observeEvent(input$key_export,
                      bslib::nav_select("nav", "Export", session = session))
  # Shift+Enter: mark the current image complete, persist, and advance.
  shiny::observeEvent(input$key_commit_advance, {
    rv$session <- annotatR::at_set_status(rv$session, rv$cursor, "complete")
    rv$trigger_save <- input$key_commit_advance
    rv$session <- annotatR::at_next(rv$session)
    rv$cursor <- rv$session$cursor
  })
  # d: delete the most recently added ROI on the current image (undoable).
  shiny::observeEvent(input$key_delete, {
    shiny::req(rv$project)
    rt <- annotatR::at_rois(rv$project)
    if (nrow(rt) > 0L) {
      rv$undo <- c(rv$undo, list(rv$project))
      rv$redo <- list()
      rv$project <- annotatR::at_remove_roi(rv$project, rt$roi_id[nrow(rt)])
      rv$saved <- "unsaved"
    }
  })
  # s / ? : hand off to the modules that own saving and the help modal.
  shiny::observeEvent(input$key_save, rv$trigger_save <- input$key_save)
  shiny::observeEvent(input$key_help, rv$trigger_help <- input$key_help)

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

  mod_data_server("data", rv)
  mod_dashboard_server("dashboard", rv)
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
