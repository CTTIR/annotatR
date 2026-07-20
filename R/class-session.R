# The annot_session class: a resumable batch-annotation session over a queue of
# images, with a manifest, a cursor, per-image projects (materialised lazily),
# and shared label/layer templates.

# Allowed manifest status values.
.session_statuses <- c("pending", "in_progress", "complete", "flagged", "skipped")

new_annot_session <- function(manifest,
                              projects,
                              cursor = 1L,
                              labels = character(),
                              layer_spec = list(),
                              out_dir = tempdir(),
                              autosave = TRUE,
                              meta = list()) {
  structure(
    list(
      manifest   = manifest,
      projects   = projects,
      cursor     = as.integer(cursor),
      labels     = as.character(labels),
      layer_spec = layer_spec,
      out_dir    = as.character(out_dir),
      autosave   = isTRUE(autosave),
      meta       = meta
    ),
    class = "annot_session"
  )
}

.check_session <- function(x, arg = rlang::caller_arg(x), call = rlang::caller_env()) {
  .check_class(x, "annot_session", arg = arg, call = call)
}

# Coerce a `layers` template argument to a list of annot_layer.
.normalize_layer_spec <- function(layers, call = rlang::caller_env()) {
  if (is.null(layers)) {
    return(list())
  }
  if (inherits(layers, "annot_layer")) {
    return(list(layers))
  }
  if (is.list(layers) && all(vapply(layers, inherits, logical(1), "annot_layer"))) {
    return(layers)
  }
  cli::cli_abort(
    c(
      "{.arg layers} must be `NULL`, an {.cls annot_layer}, or a list of them.",
      "x" = "You supplied {.cls {class(layers)[1]}}."
    ),
    call = call
  )
}

#' Create a batch annotation session
#'
#' @param paths Character vector of image file paths forming the queue.
#' @param labels Character vector of the global label vocabulary.
#' @param layers An [annot_layer], a list of them, or `NULL`. Applied as a
#'   template to every image visited.
#' @param out_dir Directory for autosave and exports. Defaults to a session
#'   temporary directory.
#' @param autosave Logical; whether to autosave on annotation commits. Default
#'   `TRUE`.
#' @param ... Additional named session metadata.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_session] with a manifest over `paths`, all statuses
#'   `"pending"`, the cursor at the first image, and projects not yet
#'   materialised.
#' @family sessions
#' @seealso [at_next()], [at_current()], [at_resume()]
#' @export
#' @examples
#' # Build a session over the bundled example image copied several times:
#' # sess <- at_example_session(3)
at_session <- function(paths, labels = character(), layers = NULL,
                       out_dir = tempdir(), autosave = TRUE, ...,
                       call = rlang::caller_env()) {
  if (!is.character(paths) || length(paths) == 0L) {
    cli::cli_abort(
      c(
        "{.arg paths} must be a non-empty character vector of image paths.",
        "x" = "You supplied {.cls {class(paths)[1]}} of length {length(paths)}."
      ),
      call = call
    )
  }
  missing <- !file.exists(paths)
  if (any(missing)) {
    cli::cli_abort(
      c(
        "Every path in {.arg paths} must exist.",
        "x" = "Missing: {.path {paths[missing]}}."
      ),
      call = call
    )
  }
  .check_flag(autosave, call = call)
  n <- length(paths)
  manifest <- tibble::tibble(
    idx          = seq_len(n),
    path         = as.character(paths),
    name         = tools::file_path_sans_ext(basename(paths)),
    status       = rep("pending", n),
    project_path = rep(NA_character_, n),
    n_rois       = rep(0L, n),
    modified     = as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC")
  )
  new_annot_session(
    manifest   = manifest,
    projects   = vector("list", n),
    cursor     = 1L,
    labels     = as.character(labels),
    layer_spec = .normalize_layer_spec(layers, call = call),
    out_dir    = out_dir,
    autosave   = autosave,
    meta       = list(...)
  )
}

# ---- Navigation ------------------------------------------------------------

#' Advance to the next image
#' @param session An [annot_session].
#' @param call The calling environment, for error reporting.
#' @return A new [annot_session] with the cursor advanced (clamped at the end).
#' @family sessions
#' @export
at_next <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$cursor <- min(session$cursor + 1L, nrow(session$manifest))
  session
}

#' Step back to the previous image
#' @inheritParams at_next
#' @return A new [annot_session] with the cursor decremented (clamped at 1).
#' @family sessions
#' @export
at_prev <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$cursor <- max(session$cursor - 1L, 1L)
  session
}

#' Jump to a specific image
#' @inheritParams at_next
#' @param i Integer image index (1-based) within the queue.
#' @return A new [annot_session] with the cursor at `i`.
#' @family sessions
#' @export
at_goto <- function(session, i, call = rlang::caller_env()) {
  .check_session(session, call = call)
  i <- .check_count(i, min = 1L, call = call)
  n <- nrow(session$manifest)
  if (i > n) {
    cli::cli_abort(
      c("{.arg i} is out of range.", "x" = "The queue has {n} image{?s}; got {i}."),
      call = call
    )
  }
  session$cursor <- i
  session
}

#' The current project
#'
#' Return the project for the image at the cursor, materialising it from the
#' image (and applying the session's layer template) if it has not been visited.
#'
#' @inheritParams at_next
#' @return An [annot_project].
#' @family sessions
#' @export
at_current <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  i <- session$cursor
  proj <- session$projects[[i]]
  if (!is.null(proj)) {
    return(proj)
  }
  img <- at_read_image(session$manifest$path[i])
  proj <- at_project(img)
  for (L in session$layer_spec) {
    proj <- at_add_layer(proj, L)
  }
  proj
}

# ---- Status and manifest ---------------------------------------------------

#' Set the status of a queued image
#' @inheritParams at_goto
#' @param status One of `"pending"`, `"in_progress"`, `"complete"`,
#'   `"flagged"`, `"skipped"`.
#' @return A new [annot_session] with the status updated.
#' @family sessions
#' @export
at_set_status <- function(session, i, status, call = rlang::caller_env()) {
  .check_session(session, call = call)
  i <- .check_count(i, min = 1L, call = call)
  status <- .check_choice(status, .session_statuses, call = call)
  n <- nrow(session$manifest)
  if (i > n) {
    cli::cli_abort(
      c("{.arg i} is out of range.", "x" = "The queue has {n} image{?s}; got {i}."),
      call = call
    )
  }
  session$manifest$status[i] <- status
  session
}

#' The session manifest
#' @inheritParams at_next
#' @return The manifest [tibble::tibble] with columns `idx`, `path`, `name`,
#'   `status`, `project_path`, `n_rois`, and `modified`.
#' @family sessions
#' @export
at_session_status <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$manifest
}

#' Session progress manifest with per-label counts
#'
#' @inheritParams at_next
#' @return A [tibble::tibble] with `idx`, `name`, `path`, `status`, `n_layers`,
#'   `n_rois`, and one integer column per label in the session vocabulary giving
#'   its ROI count per image.
#' @family sessions
#' @export
at_manifest <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  m <- session$manifest
  labels <- session$labels
  counts <- lapply(seq_len(nrow(m)), function(i) {
    proj <- session$projects[[i]]
    if (is.null(proj)) {
      out <- rep(0L, length(labels))
    } else {
      rt <- at_rois(proj)
      out <- vapply(labels, function(lb) sum(rt$label == lb), integer(1))
    }
    names(out) <- labels
    out
  })
  n_layers <- vapply(seq_len(nrow(m)), function(i) {
    proj <- session$projects[[i]]
    if (is.null(proj)) 0L else length(proj$layers)
  }, integer(1))
  base <- tibble::tibble(
    idx      = m$idx,
    name     = m$name,
    path     = m$path,
    status   = m$status,
    n_layers = n_layers,
    n_rois   = m$n_rois
  )
  if (length(labels) > 0L) {
    count_mat <- do.call(rbind, counts)
    count_tbl <- tibble::as_tibble(as.data.frame(count_mat))
    base <- dplyr::bind_cols(base, count_tbl)
  }
  base
}

# ---- Persistence -----------------------------------------------------------

#' Save a session
#' @inheritParams at_next
#' @param path Optional output path. Defaults to `_session.rds` in the session's
#'   `out_dir`.
#' @return The session, invisibly.
#' @family sessions
#' @export
at_session_save <- function(session, path = NULL, call = rlang::caller_env()) {
  .check_session(session, call = call)
  if (is.null(path)) {
    if (!dir.exists(session$out_dir)) {
      dir.create(session$out_dir, recursive = TRUE)
    }
    path <- file.path(session$out_dir, "_session.rds")
  }
  .check_string(path, call = call)
  saveRDS(session, path)
  invisible(session)
}

#' Load a session
#' @param path Path to a saved `_session.rds` file.
#' @param call The calling environment, for error reporting.
#' @return The restored [annot_session].
#' @family sessions
#' @export
at_session_load <- function(path, call = rlang::caller_env()) {
  .check_file(path, call = call)
  obj <- readRDS(path)
  .check_session(obj, arg = "path", call = call)
  obj
}

#' Resume a saved session
#'
#' A more discoverable alias for [at_session_load()].
#'
#' @inheritParams at_session_load
#' @return The restored [annot_session].
#' @family sessions
#' @export
at_resume <- function(path, call = rlang::caller_env()) {
  at_session_load(path, call = call)
}

# ---- S3 methods ------------------------------------------------------------

#' @export
format.annot_session <- function(x, ...) {
  m <- x$manifest
  done <- sum(m$status == "complete")
  c(
    cli::format_inline("{.cls annot_session}"),
    cli::format_inline("images: {nrow(m)}  |  complete: {done}  |  cursor: {x$cursor}"),
    cli::format_inline("out_dir: {.path {x$out_dir}}  |  autosave: {x$autosave}")
  )
}

#' @export
print.annot_session <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
