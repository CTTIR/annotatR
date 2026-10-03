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
  annotatR::at_current(annotatR::at_goto(session, i))
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
  bslib::nav_panel("About", .page_about()),
  bslib::nav_panel("Workflow", .page_workflow()),
  bslib::nav_panel("Data", mod_data_ui("data")),
  bslib::nav_panel("Dashboard", mod_dashboard_ui("dashboard")),
  bslib::nav_panel("Annotate", .annotate_page),
  bslib::nav_panel("Summary", .summary_page),
  bslib::nav_panel("Export", bslib::card(bslib::card_header("Export"), mod_export_ui("export"))),
  bslib::nav_panel("References", .page_references()),
  bslib::nav_panel("Impressum", .page_impressum()),
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

  .state_init(rv, load_project = .materialise)

  shiny::observe({
    session$sendCustomMessage("annotatr-state", c(.state_stamp(rv), list(
      ready = isTRUE(rv$display_ready), error = rv$display_error)))
  })

  # Observe queue identity changes only; annotation/session writes must not
  # reload the canvas or restart a failed read/save.
  shiny::observeEvent(list(rv$cursor, rv$session_generation), {
    .state_load(rv)
  }, ignoreNULL = FALSE)

  shiny::observeEvent(input$key_next, {
    .state_navigate(rv, rv$cursor + 1L, .state_event(rv, input$key_next, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_prev, {
    .state_navigate(rv, rv$cursor - 1L, .state_event(rv, input$key_prev, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_tool, {
    event <- .state_event(rv, input$key_tool, keyboard = TRUE)
    if (!is.null(event)) rv$tool <- event$payload
  })
  shiny::observeEvent(input$key_label, {
    event <- .state_event(rv, input$key_label, keyboard = TRUE)
    shiny::req(event, rv$active_layer)
    labs <- rv$project$layers[[rv$active_layer]]$labels
    if (event$payload <= length(labs)) rv$active_label <- labs[event$payload]
  })
  shiny::observeEvent(input$key_flag, {
    .state_status(rv, "flagged", .state_event(rv, input$key_flag, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_undo, {
    .state_undo(rv, event = .state_event(rv, input$key_undo, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_redo, {
    .state_undo(rv, redo = TRUE, event = .state_event(rv, input$key_redo, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_paste_forward, {
    event <- .state_event(rv, input$key_paste_forward, keyboard = TRUE)
    shiny::req(event, rv$cursor > 1L)
    previous <- rv$session$projects[[rv$cursor - 1L]]
    shiny::req(previous)
    .state_mutate(rv, function(p) .copy_forward(previous, p), event)
  })
  shiny::observeEvent(input$key_next_pending, {
    .state_navigate(rv, .state_pending(rv), .state_event(rv, input$key_next_pending, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_export, {
    shiny::req(.state_event(rv, input$key_export, keyboard = TRUE))
    bslib::nav_select("nav", "Export", session = session)
  })
  shiny::observeEvent(input$key_commit_advance, {
    .state_save(rv, complete = TRUE, advance = TRUE,
                event = .state_event(rv, input$key_commit_advance, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_delete, {
    event <- .state_event(rv, input$key_delete, keyboard = TRUE)
    shiny::req(event, rv$project)
    rt <- annotatR::at_rois(rv$project)
    if (nrow(rt)) .state_mutate(rv, function(p) {
      annotatR::at_remove_roi(p, rt$roi_id[nrow(rt)])
    }, event)
  })
  shiny::observeEvent(input$key_save, {
    .state_save(rv, event = .state_event(rv, input$key_save, keyboard = TRUE))
  })
  shiny::observeEvent(input$key_help, {
    event <- .state_event(rv, input$key_help, keyboard = TRUE)
    if (!is.null(event)) rv$trigger_help <- event$payload
  })

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
