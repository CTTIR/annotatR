# Shared app state. Entry identity and revision are checked before every
# transition. History stores annotation layers only, never image data.

.state_revision <- function(project) {
  rev <- project$meta$annotation_revision %||% 0
  if (!is.numeric(rev) || length(rev) != 1L || is.na(rev) ||
      !is.finite(rev) || rev < 0 || rev != floor(rev)) {
    stop("Invalid stored annotation revision.")
  }
  as.numeric(rev)
}

.state_init <- function(rv, load_project = NULL) {
  shiny::isolate({
    if (!isTRUE(rv$state_initialized)) {
      rv$history <- list()
      rv$dirty <- list()
      rv$history_limit <- 50L
      rv$session_generation <- 0
      rv$loaded_generation <- -1
      rv$entry_id <- NULL
      rv$revision <- 0
      rv$undo <- list(); rv$redo <- list()
      rv$save_error <- NULL
      rv$state_initialized <- TRUE
      if (!is.null(rv$project)) .state_adopt(rv, rv$project)
    }
    if (!is.null(load_project)) rv$load_project <- load_project
  })
  invisible(rv)
}

.state_adopt <- function(rv, project) {
  id <- rv$session$manifest$entry_id[rv$cursor]
  if (!is.null(project$meta$entry_id) && !identical(project$meta$entry_id, id)) {
    stop("Project identity does not match the selected queue entry.")
  }
  rev <- .state_revision(project)
  project$meta$entry_id <- id
  project$meta$annotation_revision <- rev
  rv$entry_id <- id; rv$revision <- rev
  rv$project <- project
  rv$loaded_generation <- rv$session_generation
  history <- rv$history[[id]] %||% list(undo = list(), redo = list())
  rv$undo <- history$undo; rv$redo <- history$redo
  rv$active_layer <- names(project$layers)[1]
  rv$active_label <- if (length(project$layers)) project$layers[[1]]$labels[1] else NULL
  rv$saved <- if (isTRUE(rv$dirty[[id]])) "unsaved" else "saved"
  invisible(TRUE)
}

.state_stamp <- function(rv) list(entry_id = rv$entry_id, revision = rv$revision)

.state_matches <- function(rv, event, require_project = TRUE) {
  (!require_project || !is.null(rv$project)) && !is.null(event) &&
    is.character(event$entry_id) && length(event$entry_id) == 1L &&
    identical(event$entry_id, rv$entry_id) &&
    identical(rv$entry_id, rv$session$manifest$entry_id[rv$cursor]) &&
    is.numeric(event$revision) && length(event$revision) == 1L &&
    is.finite(event$revision) && event$revision >= 0 &&
    event$revision == floor(event$revision) && isTRUE(event$revision == rv$revision)
}

# All browser actions carry the originating entry, revision and value snapshot.
# Trusted server transitions call .state_stamp() explicitly (or use the default).
.state_event <- function(rv, value, widget = FALSE, keyboard = FALSE, fields = NULL) {
  if (!is.list(value) || !all(c("entry_id", "revision", "payload") %in% names(value)) ||
      anyDuplicated(names(value))) return(NULL)
  if (!.state_matches(rv, value, require_project = FALSE)) return(NULL)
  if (!is.null(fields) && (!is.list(value$payload) ||
      !all(vapply(fields, function(field) {
        x <- value$payload[[field]]
        is.character(x) && length(x) == 1L && !is.na(x)
      }, logical(1))))) return(NULL)
  value
}

.at_action <- function(inputId, label, ..., fields = NULL) {
  button <- shiny::actionButton(inputId, label, ...)
  htmltools::tagAppendAttributes(button, `data-at-action` = "true",
    `data-at-fields` = if (!is.null(fields)) jsonlite::toJSON(fields, auto_unbox = TRUE) else "{}")
}

# Protection is an app mutation rule, shared by every ingress and history path.
.state_protected <- function(before, after) {
  for (nm in names(before$layers)) {
    old <- before$layers[[nm]]; new <- after$layers[[nm]]
    if (isTRUE(old$style$locked) && !identical(old, new)) return(TRUE)
    for (roi in old$rois) if (isTRUE(roi$attributes$locked)) {
      matches <- Filter(function(r) identical(r$id, roi$id), new$rois)
      if (length(matches) != 1L || !identical(matches[[1]], roi)) return(TRUE)
    }
  }
  FALSE
}

.state_snapshot <- function(rv) {
  if (!.state_matches(rv, .state_stamp(rv))) return(invisible(FALSE))
  sess <- rv$session
  sess$projects[[rv$cursor]] <- rv$project
  sess$manifest$n_rois[rv$cursor] <- nrow(annotatR::at_rois(rv$project))
  rv$session <- sess
  invisible(TRUE)
}

.state_history <- function(rv, undo, redo) {
  undo <- tail(undo, rv$history_limit)
  redo <- tail(redo, rv$history_limit)
  rv$history[[rv$entry_id]] <- list(undo = undo, redo = redo)
  rv$undo <- undo; rv$redo <- redo
}

.state_selection <- function(rv) {
  layers <- names(rv$project$layers)
  if (!length(layers)) {
    rv$active_layer <- NULL; rv$active_label <- NULL
    return(invisible(NULL))
  }
  if (!isTRUE(rv$active_layer %in% layers)) rv$active_layer <- layers[1]
  labels <- rv$project$layers[[rv$active_layer]]$labels
  if (!isTRUE(rv$active_label %in% labels)) {
    rv$active_label <- if (length(labels)) labels[1] else NULL
  }
  invisible(NULL)
}

.state_changed <- function(rv, project) {
  rv$revision <- rv$revision + 1
  project$meta$entry_id <- rv$entry_id
  project$meta$annotation_revision <- rv$revision
  rv$project <- project
  .state_selection(rv)
  rv$dirty[[rv$entry_id]] <- TRUE
  rv$saved <- "unsaved"
  .state_snapshot(rv)
  if (isTRUE(rv$session$autosave) && is.function(rv$save_callback)) .state_save(rv)
  invisible(TRUE)
}

.state_mutate <- function(rv, mutate, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event) || identical(rv$display_ready, FALSE)) return(invisible(FALSE))
  project <- mutate(rv$project)
  if (.state_protected(rv$project, project) || identical(project$layers, rv$project$layers)) return(invisible(FALSE))
  .state_history(rv, c(rv$undo, list(list(layers = rv$project$layers))), list())
  .state_changed(rv, project)
}

.state_undo <- function(rv, redo = FALSE, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event)) return(invisible(FALSE))
  stack <- if (redo) rv$redo else rv$undo
  if (!length(stack)) return(invisible(FALSE))
  snapshot <- stack[[length(stack)]]
  candidate <- rv$project; candidate$layers <- snapshot$layers
  if (identical(rv$display_ready, FALSE) || .state_protected(rv$project, candidate)) return(invisible(FALSE))
  current <- list(layers = rv$project$layers)
  if (redo) .state_history(rv, c(rv$undo, list(current)), head(stack, -1L))
  else .state_history(rv, head(stack, -1L), c(rv$redo, list(current)))
  project <- rv$project
  project$layers <- snapshot$layers
  .state_changed(rv, project)
}

.state_load <- function(rv) {
  id <- rv$session$manifest$entry_id[rv$cursor]
  if (identical(rv$entry_id, id) &&
      identical(rv$loaded_generation, rv$session_generation)) return(invisible(TRUE))
  rv$entry_id <- id; rv$project <- NULL; rv$revision <- 0
  rv$display_ready <- FALSE; rv$display_error <- "Loading current image…"
  rv$saved <- "unavailable"
  # A failed load is still an attempted load for this cursor/generation. Only
  # a new navigation/replacement retries it, not the following observer flush.
  rv$loaded_generation <- rv$session_generation
  rv$undo <- list(); rv$redo <- list()
  # Standalone module tests may supply only state, without an image loader.
  if (!is.function(rv$load_project)) return(invisible(FALSE))
  result <- tryCatch({
    .state_adopt(rv, rv$load_project(rv$session, rv$cursor))
  }, error = function(e) e)
  if (inherits(result, "error")) {
    rv$display_error <- paste("Could not load image:", conditionMessage(result))
    rv$session <- annotatR::at_set_status(rv$session, rv$cursor, "skipped")
    shiny::showNotification(paste("Could not load image:", conditionMessage(result)), type = "error")
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

.state_navigate <- function(rv, target, event = .state_stamp(rv)) {
  # A failed image load has no live project; navigation must remain usable.
  if (!.state_matches(rv, event, require_project = FALSE)) return(invisible(FALSE))
  target <- max(1L, min(as.integer(target), nrow(rv$session$manifest)))
  .state_snapshot(rv)
  rv$session <- annotatR::at_goto(rv$session, target)
  rv$cursor <- target
  .state_load(rv)
  invisible(TRUE)
}

.state_pending <- function(rv) {
  pending <- which(rv$session$manifest$status == "pending")
  next_entries <- pending[pending > rv$cursor]
  if (length(next_entries)) next_entries[1] else if (length(pending)) pending[1] else rv$cursor
}

.state_replace <- function(rv, sess, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event, require_project = FALSE)) return(invisible(FALSE))
  .state_snapshot(rv)
  # Keep the complete in-memory queue (including dirty projects and history)
  # until it is explicitly restored or replaced after all edits are saved.
  if (!is.null(rv$recovery_queue) && any(vapply(rv$dirty, isTRUE, logical(1)))) {
    shiny::showNotification("Restore the previous queue or save this queue before loading another folder.", type = "warning")
    return(invisible(FALSE))
  }
  if (is.null(rv$recovery_queue)) rv$recovery_queue <- list(session = rv$session,
    cursor = rv$cursor, history = rv$history, dirty = rv$dirty, project = rv$project,
    active_layer = rv$active_layer, active_label = rv$active_label)
  sess$autosave <- rv$session$autosave
  rv$session <- sess; rv$cursor <- sess$cursor
  rv$history <- list(); rv$dirty <- list()
  rv$session_generation <- rv$session_generation + 1
  .state_load(rv)
  invisible(TRUE)
}

.state_restore_queue <- function(rv, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event, require_project = FALSE) || is.null(rv$recovery_queue)) return(invisible(FALSE))
  if (any(vapply(rv$dirty, isTRUE, logical(1)))) {
    shiny::showNotification("Save the current queue's edits before restoring the previous queue.", type = "warning")
    return(invisible(FALSE))
  }
  old <- rv$recovery_queue
  rv$recovery_queue <- NULL; rv$session <- old$session; rv$cursor <- old$cursor
  rv$history <- old$history; rv$dirty <- old$dirty
  rv$session_generation <- rv$session_generation + 1
  if (!is.null(old$project)) {
    .state_adopt(rv, old$project)
    rv$active_layer <- old$active_layer; rv$active_label <- old$active_label
    rv$display_ready <- FALSE; rv$display_error <- "Loading restored image…"
  } else .state_load(rv)
  invisible(TRUE)
}

# Callback receives a candidate session and the original cursor. It must
# synchronously persist and return that session, or throw/return FALSE.
# T03 replaces its disk implementation without changing this transaction API.
.state_save <- function(rv, complete = FALSE, advance = FALSE,
                        event = .state_stamp(rv)) {
  if (!.state_matches(rv, event)) return(invisible(FALSE))
  .state_snapshot(rv)
  candidate <- rv$session
  cursor <- rv$cursor
  if (complete) candidate <- annotatR::at_set_status(candidate, cursor, "complete")
  rv$saved <- "saving"
  result <- tryCatch({
    if (!is.function(rv$save_callback)) stop("No save handler is available.")
    saved <- rv$save_callback(candidate, cursor)
    if (!inherits(saved, "annot_session")) stop("The save handler did not confirm persistence.")
    saved
  }, error = function(e) e)
  if (inherits(result, "error")) {
    rv$dirty[[rv$entry_id]] <- TRUE
    rv$saved <- "unsaved"
    rv$save_error <- paste("Save failed:", conditionMessage(result),
                           "Check the output folder and retry Save before advancing.")
    shiny::showNotification(rv$save_error, type = "error", duration = NULL)
    return(invisible(FALSE))
  }
  rv$session <- result
  rv$dirty[[rv$entry_id]] <- FALSE
  rv$saved <- "saved"; rv$save_error <- NULL
  if (advance) .state_navigate(rv, cursor + 1L, event)
  invisible(TRUE)
}

.state_status <- function(rv, status, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event)) return(invisible(FALSE))
  rv$session <- annotatR::at_set_status(rv$session, rv$cursor, status)
  rv$dirty[[rv$entry_id]] <- TRUE; rv$saved <- "unsaved"
  if (isTRUE(rv$session$autosave) && is.function(rv$save_callback)) .state_save(rv)
  invisible(TRUE)
}
