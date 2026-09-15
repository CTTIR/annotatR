# The app builder: at_app() returns a shiny.appobj built entirely from package
# code and explicit arguments, so it can be embedded, tested with
# shiny::testServer() or run by at_annotate(). No global option is used as an
# integration channel.
#
# Cross-module state lives in one reactiveValues object `rv`:
#   session, cursor, project      queue, current index, current image project
#   tool, active_layer, active_label, mask_type, overlap
#   undo, redo                    project history of the current image
#   saved                         "saved" | "saving" | "unsaved"
#   read_only                     edits disabled
#   view                          band view list(operation, bands, params) or NULL
#   probe, selection, viewport    last probed pixel, selected ROI ids, view bounds
#   overlay_on, overlay_alpha     mask overlay on the canvas
#   staged, last_commit           staged partner patch and last commit receipt
#   last_action, generation       last transition name, queue replacement counter
#   fit_bounds                    bounds requested by a controller
#   paste_forward, trigger_save, trigger_help   keyboard event relays

.annotate_pkgs <- c("shiny", "bslib", "htmlwidgets", "shinyjs")

.check_app_pkgs <- function(call = rlang::caller_env()) {
  missing_pkgs <- .annotate_pkgs[!vapply(.annotate_pkgs, requireNamespace, logical(1),
                                         quietly = TRUE)]
  if (length(missing_pkgs) > 0L) {
    .at_abort(
      c("The annotation app requires packages not currently installed.",
        "x" = "Missing: {.pkg {missing_pkgs}}.",
        "i" = "Install with {.code install.packages(c({paste0('\"', missing_pkgs, '\"', collapse = ', ')}))}."),
      class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call
    )
  }
  invisible(TRUE)
}

# Normalise what to annotate into an annot_session.
.to_session <- function(x, labels, layers, out_dir, call = rlang::caller_env()) {
  od <- out_dir %||% tempdir()
  if (inherits(x, "annot_session")) {
    return(x)
  }
  if (is.null(x)) {
    return(at_example_session(3, call = call))
  }
  if (inherits(x, "annot_project")) {
    s <- at_session(x$image$source, labels = labels, layers = layers, out_dir = od, call = call)
    s$projects[[1]] <- x
    return(s)
  }
  if (inherits(x, "annot_image")) {
    return(at_session(x$source, labels = labels, layers = layers, out_dir = od, call = call))
  }
  if (is.character(x)) {
    if (length(x) == 1L && dir.exists(x)) {
      x <- list.files(x, pattern = "\\.(png|jpe?g|tiff?|qptiff|cu3|cu3s|hdr|dat)$",
                      full.names = TRUE, ignore.case = TRUE)
      if (length(x) == 0L) {
        cli::cli_abort("No supported images found in the directory.", call = call)
      }
    }
    return(at_session(x, labels = labels, layers = layers, out_dir = od, call = call))
  }
  cli::cli_abort(
    c("{.arg x} must be a session, project, image, file paths, a directory, or NULL.",
      "x" = "You supplied {.cls {class(x)[1]}}."),
    call = call
  )
}

# Suite accent colour (Hugo Coder blue; the gold is used for ROI handles).
.app_accent <- "#1f6feb"

# Bootstrap 5 theme with local/system fonts only (no CDN).
.app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    primary = .app_accent,
    base_font = bslib::font_collection(
      "Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"),
    code_font = bslib::font_collection(
      "JetBrains Mono", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"),
    heading_font = bslib::font_collection(
      "JetBrains Mono", "Inter", "system-ui")
  )
}

.app_www <- function() system.file("shiny", "annotatR", "www", package = "annotatR")

.app_ui <- function() {
  shiny::addResourcePath("annotatR-www", .app_www())
  annotate_page <- bslib::layout_columns(
    col_widths = c(3, 6, 3),
    bslib::card(
      class = "at-queue",
      bslib::card_header("Queue"),
      mod_queue_ui("queue")
    ),
    bslib::card(
      bslib::card_header(class = "at-canvas-header", mod_session_ui("session")),
      mod_staging_ui("staging"),
      mod_canvas_ui("canvas")
    ),
    bslib::card(
      bslib::card_header("Layers & labels"),
      mod_layers_ui("layers"),
      shiny::hr(),
      mod_view_ui("view"),
      shiny::hr(),
      mod_control_status_ui("control"),
      mod_help_ui("help")
    )
  )
  summary_page <- bslib::layout_columns(
    col_widths = c(6, 6),
    bslib::card(bslib::card_header("Mask"), mod_mask_ui("mask")),
    bslib::card(bslib::card_header("Spectra & ROIs"),
                mod_spectrum_ui("spectrum"), shiny::hr(), mod_region_ui("region"),
                shiny::hr(), mod_roitable_ui("roitable"))
  )
  bslib::page_navbar(
    id = "nav",
    window_title = "annotatR",
    theme = .app_theme(),
    fillable = FALSE,
    selected = "Annotate",
    title = shiny::span(
      class = "at-brand",
      shiny::img(src = "annotatR-www/logo.svg", class = "at-logo", alt = "annotatR"),
      shiny::span("annotatR", class = "at-brandname")
    ),
    header = shiny::tagList(
      shinyjs::useShinyjs(),
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "annotatR-www/custom.css"),
      shiny::tags$script(src = "annotatR-www/keys.js")
    ),
    bslib::nav_panel("About", .page_about()),
    bslib::nav_panel("Workflow", .page_workflow()),
    bslib::nav_panel("Data", mod_data_ui("data")),
    bslib::nav_panel("Dashboard", mod_dashboard_ui("dashboard")),
    bslib::nav_panel("Annotate", annotate_page),
    bslib::nav_panel("Summary", summary_page),
    bslib::nav_panel("Export", bslib::card(bslib::card_header("Export"), mod_export_ui("export"))),
    bslib::nav_panel("References", .page_references()),
    bslib::nav_panel("Impressum", .page_impressum()),
    bslib::nav_spacer(),
    bslib::nav_item(bslib::input_dark_mode(id = "dark_mode"))
  )
}

# The initial reactive state for a session.
.app_state <- function(sess, read_only = FALSE, view = NULL) {
  shiny::reactiveValues(
    session = sess, cursor = sess$cursor, project = NULL, tool = "pan",
    active_layer = NULL, active_label = NULL, mask_type = "labelled",
    overlap = "last", undo = list(), redo = list(), saved = "saved",
    read_only = isTRUE(read_only), view = view, probe = NULL, selection = character(),
    viewport = NULL, overlay_on = FALSE, overlay_alpha = 0.5, staged = NULL,
    last_commit = NULL, last_action = NULL, generation = 0L, fit_bounds = NULL,
    paste_forward = NULL, trigger_save = NULL, trigger_help = NULL
  )
}

# Server factory: closes over the explicit session, options and control hub.
.app_server <- function(sess, read_only = FALSE, view = NULL, hub = NULL) {
  force(sess)
  force(read_only)
  force(view)
  force(hub)
  function(input, output, session) {
    s0 <- if (!is.null(hub)) hub$session else sess
    rv <- .app_state(s0, read_only = read_only || isTRUE(hub$read_only), view = view)

    shiny::observeEvent(input$key_next, {
      rv$session <- at_next(rv$session); rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$key_prev, {
      rv$session <- at_prev(rv$session); rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$key_tool, {
      if (isTRUE(rv$read_only) && !input$key_tool %in% .read_only_tools) return()
      rv$tool <- input$key_tool
    })
    shiny::observeEvent(input$key_label, {
      shiny::req(rv$project, rv$active_layer)
      labs <- rv$project$layers[[rv$active_layer]]$labels
      if (input$key_label <= length(labs)) rv$active_label <- labs[input$key_label]
    })
    shiny::observeEvent(input$key_flag, {
      rv$session <- at_set_status(rv$session, rv$cursor, "flagged")
    })
    shiny::observeEvent(input$key_undo, {
      if (length(rv$undo) > 0L && !isTRUE(rv$read_only)) {
        rv$redo <- c(rv$redo, list(rv$project))
        rv$project <- rv$undo[[length(rv$undo)]]
        rv$undo <- rv$undo[-length(rv$undo)]
        rv$saved <- "unsaved"
      }
    })
    shiny::observeEvent(input$key_redo, {
      if (length(rv$redo) > 0L && !isTRUE(rv$read_only)) {
        rv$undo <- c(rv$undo, list(rv$project))
        rv$project <- rv$redo[[length(rv$redo)]]
        rv$redo <- rv$redo[-length(rv$redo)]
        rv$saved <- "unsaved"
      }
    })
    shiny::observeEvent(input$key_paste_forward, rv$paste_forward <- input$key_paste_forward)
    shiny::observeEvent(input$key_next_pending, {
      m <- at_session_status(rv$session)
      pending <- which(m$status == "pending")
      nxt <- pending[pending > rv$cursor]
      target <- if (length(nxt)) nxt[1] else if (length(pending)) pending[1] else rv$cursor
      rv$session <- at_goto(rv$session, target)
      rv$cursor <- target
    })
    shiny::observeEvent(input$key_export,
                        bslib::nav_select("nav", "Export", session = session))
    # Shift+Enter: store the current project in its own queue slot, mark it
    # complete, persist, then advance.
    shiny::observeEvent(input$key_commit_advance, {
      if (!is.null(rv$project)) {
        rv$session$projects[[rv$cursor]] <- rv$project
      }
      rv$session <- at_set_status(rv$session, rv$cursor, "complete")
      rv$trigger_save <- input$key_commit_advance
      rv$session <- at_next(rv$session)
      rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$key_delete, {
      shiny::req(rv$project)
      rt <- at_rois(rv$project)
      if (nrow(rt) > 0L) {
        .app_edit(rv, at_remove_roi(rv$project, rt$roi_id[nrow(rt)]), "delete")
      }
    })
    shiny::observeEvent(input$key_save, rv$trigger_save <- input$key_save)
    shiny::observeEvent(input$key_help, rv$trigger_help <- input$key_help)

    # Materialise the project of the entry under the cursor. The previous
    # entry's live project is kept in the session before switching, so
    # navigation never discards edits (independent of autosave).
    last_cursor <- NULL
    shiny::observeEvent(list(rv$cursor, rv$generation), {
      if (!is.null(last_cursor) && !is.null(rv$project) &&
          last_cursor <= length(rv$session$projects) &&
          identical(shiny::isolate(rv$generation), attr(last_cursor, "generation"))) {
        rv$session$projects[[last_cursor]] <- shiny::isolate(rv$project)
      }
      proj <- tryCatch(.materialize_project(rv$session, rv$cursor), error = function(e) e)
      last_cursor <<- structure(rv$cursor, generation = shiny::isolate(rv$generation))
      if (inherits(proj, "error")) {
        rv$session <- at_set_status(rv$session, rv$cursor, "skipped")
        rv$project <- NULL
        shiny::showNotification(paste("Skipped image:", conditionMessage(proj)), type = "error")
        return()
      }
      rv$project <- proj
      rv$undo <- list()
      rv$redo <- list()
      rv$staged <- NULL
      rv$selection <- character()
      rv$active_layer <- names(proj$layers)[1]
      rv$active_label <- proj$layers[[1]]$labels[1]
      rv$saved <- "saved"
    }, ignoreNULL = FALSE)

    mod_data_server("data", rv)
    mod_dashboard_server("dashboard", rv)
    mod_queue_server("queue", rv)
    mod_canvas_server("canvas", rv)
    mod_layers_server("layers", rv)
    mod_view_server("view", rv)
    mod_mask_server("mask", rv)
    mod_spectrum_server("spectrum", rv)
    mod_region_server("region", rv)
    mod_roitable_server("roitable", rv)
    mod_export_server("export", rv)
    mod_session_server("session", rv)
    mod_staging_server("staging", rv)
    mod_help_server("help", rv)
    mod_control_status_server("control", rv, hub)
    if (!is.null(hub)) {
      .control_app_attach(hub, rv, session)
    }
    # Values read by shinytest2 browser tests (only exposed in test mode).
    shiny::exportTestValues(
      cursor = rv$cursor,
      n_rois = if (is.null(rv$project)) NA_integer_ else nrow(at_rois(rv$project)),
      annotation_status = .annotation_status(rv),
      view_operation = rv$view$operation %||% "natural",
      overlay_on = isTRUE(rv$overlay_on),
      probe = rv$probe,
      staged = !is.null(rv$staged),
      tool = rv$tool,
      saved = rv$saved
    )
    invisible(rv)
  }
}

#' Build the annotation app as a Shiny app object
#'
#' Construct the batch annotation application from explicit inputs, without
#' launching a browser or touching global options. The result can be run with
#' [shiny::runApp()], embedded in another Shiny application, or exercised in
#' tests; [at_annotate()] is a launcher around it.
#'
#' @param input What to annotate: an [annot_project], [annot_image], a
#'   character vector of image paths, a directory of images, or `NULL`.
#' @param session An [annot_session] to resume. Supply `input` or `session`,
#'   not both; with neither, the bundled example session is used.
#' @param control `"off"` (default; no control service) or an
#'   `at_control_handle` from [at_control_start()] whose session the app then
#'   displays and synchronises with.
#' @param labels,layers,out_dir Passed to [at_session()] when `input` is not a
#'   session.
#' @param read_only Logical; disable all annotation edits (view and inspect
#'   only).
#' @param view Optional initial band view, e.g.
#'   `list(operation = "rgb", bands = c(30, 20, 10))`.
#' @param ... Reserved; must be empty.
#' @param call The calling environment, for error reporting.
#'
#' @return A `shiny.appobj`.
#' @family shiny
#' @seealso [at_annotate()], [at_control_start()]
#' @export
#' @examplesIf requireNamespace("shiny", quietly = TRUE) && requireNamespace("bslib", quietly = TRUE) && requireNamespace("shinyjs", quietly = TRUE) && requireNamespace("htmlwidgets", quietly = TRUE)
#' app <- at_app(session = at_example_session(2))
#' class(app)
#' \dontrun{
#' shiny::runApp(app)
#' }
at_app <- function(input = NULL, session = NULL, control = "off", labels = character(),
                   layers = NULL, out_dir = NULL, read_only = FALSE, view = NULL, ...,
                   call = rlang::caller_env()) {
  rlang::check_dots_empty(call = call)
  .check_app_pkgs(call = call)
  .check_flag(read_only, call = call)
  hub <- NULL
  if (inherits(control, "at_control_handle")) {
    hub <- .control_hub(control, call = call)
    if (!is.null(input) || !is.null(session)) {
      .at_abort("With a control handle the session comes from the control service; omit {.arg input} and {.arg session}.",
                call = call)
    }
    sess <- hub$session
  } else {
    if (!identical(control, "off")) {
      .at_abort("{.arg control} must be {.val off} or a handle from {.fn at_control_start}.",
                call = call)
    }
    if (!is.null(input) && !is.null(session)) {
      .at_abort("Supply {.arg input} or {.arg session}, not both.", call = call)
    }
    if (!is.null(session)) {
      .check_class(session, "annot_session", call = call)
      sess <- session
    } else {
      sess <- .to_session(input, labels, layers, out_dir, call = call)
    }
  }
  if (!dir.exists(sess$out_dir)) {
    dir.create(sess$out_dir, recursive = TRUE)
  }
  if (!is.null(view) && !is.list(view)) {
    .at_abort("{.arg view} must be a list with {.field operation}, {.field bands} and {.field params}.",
              call = call)
  }
  shiny::shinyApp(
    ui = function(req) .app_ui(),
    server = .app_server(sess, read_only = read_only, view = view, hub = hub),
    onStart = function() shiny::addResourcePath("annotatR-www", .app_www())
  )
}

#' Launch the batch annotation application
#'
#' A launcher around [at_app()]: it builds the app object from explicit
#' arguments and runs it. Nothing is exchanged through global options.
#'
#' @param x What to annotate: an [annot_session], [annot_project], [annot_image],
#'   a character vector of image paths, a directory of images, or `NULL` (opens
#'   the bundled example session).
#' @param labels Character vector of the global label vocabulary.
#' @param layers An [annot_layer], a list of them, or `NULL`. Applied as a
#'   template to every image.
#' @param out_dir Directory for autosave and exports.
#' @param launch.browser Passed to [shiny::runApp()].
#' @param port Passed to [shiny::runApp()].
#' @param ... Passed to [at_app()] (`control`, `read_only`, `view`).
#' @param call The calling environment, for error reporting.
#'
#' @return Invisible `NULL`. Launches a Shiny application; called for side
#'   effects.
#' @family shiny
#' @seealso [at_app()]
#' @export
#' @examples
#' \donttest{
#' if (interactive()) {
#'   at_annotate(at_example_session(5))
#' }
#' }
at_annotate <- function(x = NULL, labels = character(), layers = NULL,
                        out_dir = NULL, launch.browser = TRUE, port = NULL, ...,
                        call = rlang::caller_env()) {
  .check_app_pkgs(call = call)
  dots <- list(...)
  if (inherits(dots$control, "at_control_handle")) {
    app <- at_app(control = dots$control, read_only = isTRUE(dots$read_only),
                  view = dots$view, call = call)
  } else {
    session <- .to_session(x, labels, layers, out_dir, call = call)
    app <- at_app(session = session, read_only = isTRUE(dots$read_only), view = dots$view,
                  call = call)
  }
  shiny::runApp(app, launch.browser = launch.browser, port = port)
  invisible(NULL)
}
