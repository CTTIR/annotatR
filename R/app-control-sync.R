# Two-way synchronisation between an attached app and its control hub. The hub
# is the source of truth: controller commands change the hub and the app
# follows it through a revision poll; user edits in the app are pushed into the
# hub with origin "app" so controllers see them as events. Internal.

# Push app-side changes (navigation, annotation edits) into the hub.
.hub_push_from_app <- function(hub, rv_session, cursor, project, app_id) {
  if (!identical(hub$status, "running")) {
    return(invisible(FALSE))
  }
  changed <- FALSE
  origin <- list(kind = "app", request_id = app_id)
  if (!identical(as.integer(cursor), as.integer(hub$session$cursor))) {
    hub$session$projects[[hub$session$cursor]] <- .hub_project(hub)
    hub$session <- at_goto(hub$session, cursor)
    hub$selection <- character()
    hub$staged <- NULL
    .hub_bump(hub, "image.changed", list(queue_index = as.integer(cursor)), origin)
    changed <- TRUE
  }
  if (!is.null(project)) {
    current <- hub$session$projects[[cursor]]
    if (is.null(current) || !identical(at_annotation_revision(current), at_annotation_revision(project))) {
      hub$session$projects[[cursor]] <- project
      hub$session$manifest$n_rois[cursor] <- nrow(at_rois(project))
      if (!identical(hub$annotation_status, "staged")) hub$annotation_status <- "unsaved"
      .hub_bump(hub, "annotations.edited",
                list(queue_index = as.integer(cursor), annotation_revision = at_annotation_revision(project)),
                origin)
      changed <- TRUE
    }
  }
  if (!identical(rv_session$manifest$status, hub$session$manifest$status)) {
    hub$session$manifest$status <- rv_session$manifest$status
    changed <- TRUE
  }
  invisible(changed)
}

.control_app_attach <- function(hub, rv, session) {
  app_id <- paste0("app-", session$token %||% .uuid())
  assign(app_id, list(connected_at = .utc_stamp()), envir = hub$apps)
  .hub_event(hub, "app.connected", list(app_id = app_id))
  synced <- hub$revision
  session$onSessionEnded(function() {
    if (exists(app_id, envir = hub$apps, inherits = FALSE)) rm(list = app_id, envir = hub$apps)
    .hub_event(hub, "app.disconnected", list(app_id = app_id))
  })
  poll <- shiny::reactivePoll(250, session, checkFunc = function() hub$revision,
                              valueFunc = function() hub$revision)
  # Hub -> app.
  shiny::observeEvent(poll(), {
    rev <- poll()
    if (identical(rev, synced)) return()
    synced <<- rev
    if (identical(hub$last_origin, "app")) return()
    rv$session <- hub$session
    if (!identical(as.integer(rv$cursor), as.integer(hub$session$cursor))) {
      rv$cursor <- hub$session$cursor
    }
    proj <- hub$session$projects[[hub$session$cursor]]
    if (!is.null(proj) && (is.null(rv$project) ||
                           !identical(at_annotation_revision(proj), at_annotation_revision(rv$project)))) {
      rv$project <- proj
      rv$saved <- "saved"
    }
    rv$staged <- hub$staged
    if (identical(hub$annotation_status, "committed")) {
      rv$last_commit <- hub$last_commit
      rv$last_action <- "commit"
    }
    rv$selection <- as.character(hub$selection)
    bg <- hub$view$band_group
    rv$view <- if (is.null(bg)) NULL else list(operation = bg$operation, bands = as.integer(unlist(bg$bands)),
                                               params = bg$params)
    if (!identical(rv$tool, hub$view$tool)) rv$tool <- hub$view$tool
    rv$overlay_on <- isTRUE(hub$view$overlay$show)
    rv$overlay_alpha <- hub$view$overlay$alpha %||% 0.5
    if (!is.null(hub$view$overlay$mask_type)) rv$mask_type <- hub$view$overlay$mask_type
    if (!is.null(hub$view$bounds)) rv$fit_bounds <- as.numeric(unlist(hub$view$bounds))
  }, ignoreInit = TRUE)
  # App -> hub.
  shiny::observeEvent(list(rv$cursor, rv$project, rv$session), {
    if (.hub_push_from_app(hub, rv$session, rv$cursor, rv$project, app_id)) {
      synced <<- hub$revision
    }
  }, ignoreInit = TRUE)
  invisible(app_id)
}

mod_control_status_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("status"))
}

mod_control_status_server <- function(id, rv, hub = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    output$status <- shiny::renderUI({
      if (is.null(hub)) return(NULL)
      shiny::invalidateLater(1000)
      shiny::div(
        class = "at-progress at-control", role = "status",
        sprintf("control: %s | revision %d | %s", hub$status, hub$revision,
                if (isTRUE(hub$read_only)) "read-only" else "annotate")
      )
    })
  })
}
