# Batch operations across a session's images: export, summaries, bulk edits, and
# validation. A single failed image never aborts a whole-session run.

# Materialise the project for image `i`, reusing a stored one when present.
.materialize_project <- function(session, i) {
  p <- session$projects[[i]]
  if (!is.null(p)) {
    return(p)
  }
  img <- at_read_image(session$manifest$path[i])
  proj <- at_project(img, name = session$manifest$name[i])
  for (L in session$layer_spec) proj <- at_add_layer(proj, L)
  if (length(proj$layers) == 0L) {
    proj <- at_add_layer(proj, at_layer("annotations", labels = session$labels))
  }
  proj
}

# Which image indices a scope selects.
.scope_indices <- function(session, scope) {
  m <- session$manifest
  switch(
    scope,
    all      = seq_len(nrow(m)),
    complete = which(m$status == "complete"),
    current  = session$cursor,
    flagged  = which(m$status == "flagged")
  )
}

# Run `fun(i, k, n)` over indices with console/Shiny progress.
.batch_iterate <- function(indices, fun, progress, label) {
  n <- length(indices)
  in_shiny <- requireNamespace("shiny", quietly = TRUE) && shiny::isRunning()
  if (progress && in_shiny) {
    shiny::withProgress(message = label, value = 0, {
      for (k in seq_along(indices)) {
        fun(indices[k], k, n)
        shiny::incProgress(1 / n)
      }
    })
  } else if (progress && n > 1L) {
    cli::cli_progress_bar(label, total = n, .envir = parent.frame())
    for (k in seq_along(indices)) {
      fun(indices[k], k, n)
      cli::cli_progress_update(.envir = parent.frame())
    }
    cli::cli_progress_done(.envir = parent.frame())
  } else {
    for (k in seq_along(indices)) fun(indices[k], k, n)
  }
  invisible(NULL)
}

#' Export a whole session
#'
#' Export every selected image's annotations in the requested formats, isolating
#' per-image failures so one bad image never aborts the run.
#'
#' @param session An [annot_session].
#' @param dir Output directory (created if needed).
#' @param formats Any of `"mask_tiff"`, `"geojson"`, `"qupath"`, `"rds"`,
#'   `"csv"`.
#' @param scope `"complete"` (default), `"all"`, `"current"`, or `"flagged"`.
#' @param mask_type Mask type for `"mask_tiff"`.
#' @param level Integer pyramid level. Default `0`.
#' @param overwrite Logical; overwrite existing files. Default `FALSE`.
#' @param progress Logical; show a progress bar. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#'
#' @return An invisible export-receipt [tibble::tibble] with columns `image`,
#'   `format`, `path`, `bytes`, `n_rois`, `status`, and `message`. Also written
#'   to `_export_manifest.csv` alongside the exports.
#' @family batch
#' @seealso [at_write_masks()], [at_manifest()]
#' @export
at_export_all <- function(session, dir,
                          formats = c("mask_tiff", "geojson", "qupath", "rds", "csv"),
                          scope = c("complete", "all", "current", "flagged"),
                          mask_type = c("labelled", "binary", "multiclass"),
                          level = 0L, overwrite = FALSE,
                          progress = TRUE, call = rlang::caller_env()) {
  .check_session(session, call = call)
  .check_string(dir, call = call)
  scope <- .check_choice(scope, c("complete", "all", "current", "flagged"), call = call)
  mask_type <- .check_choice(mask_type, c("labelled", "binary", "multiclass"), call = call)
  formats <- intersect(formats, c("mask_tiff", "geojson", "qupath", "rds", "csv"))
  subdirs <- c(mask_tiff = "masks", geojson = "geojson", qupath = "qupath",
               rds = "projects", csv = "csv")
  for (d in c(dir, file.path(dir, unique(subdirs[formats])))) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }
  indices <- .scope_indices(session, scope)
  rows <- list()
  add_row <- function(image, format, path, bytes, n_rois, status, message) {
    rows[[length(rows) + 1L]] <<- tibble::tibble(
      image = image, format = format, path = path, bytes = as.integer(bytes),
      n_rois = as.integer(n_rois), status = status, message = message
    )
  }
  export_one <- function(i, k, n) {
    name <- session$manifest$name[i]
    proj <- tryCatch(.materialize_project(session, i), error = function(e) e)
    if (inherits(proj, "error")) {
      add_row(name, NA_character_, NA_character_, NA_integer_, NA_integer_,
              "error", conditionMessage(proj))
      return()
    }
    n_rois <- nrow(at_rois(proj))
    do_fmt <- function(fmt, path, writer) {
      res <- tryCatch({
        writer(path)
        list(bytes = file.info(path)$size, status = "ok", message = "")
      }, error = function(e) list(bytes = NA, status = "error", message = conditionMessage(e)))
      add_row(name, fmt, path, res$bytes, n_rois, res$status, res$message)
    }
    if ("mask_tiff" %in% formats) {
      p <- file.path(dir, "masks", paste0(name, ".tif"))
      do_fmt("mask_tiff", p, function(pp) {
        at_write_mask(at_mask(proj, type = mask_type, level = level), pp, overwrite = overwrite)
      })
    }
    if ("geojson" %in% formats) {
      p <- file.path(dir, "geojson", paste0(name, ".geojson"))
      do_fmt("geojson", p, function(pp) at_write_geojson(proj, pp, level = level, overwrite = overwrite))
    }
    if ("qupath" %in% formats) {
      p <- file.path(dir, "qupath", paste0(name, "_qupath.geojson"))
      do_fmt("qupath", p, function(pp) at_write_qupath(proj, pp, level = level, overwrite = overwrite))
    }
    if ("rds" %in% formats) {
      p <- file.path(dir, "projects", paste0(name, ".rds"))
      do_fmt("rds", p, function(pp) at_save_project(proj, pp, overwrite = overwrite))
    }
    if ("csv" %in% formats) {
      p <- file.path(dir, "csv", paste0(name, "_rois.csv"))
      do_fmt("csv", p, function(pp) at_write_rois_csv(proj, pp, overwrite = overwrite))
    }
  }
  .batch_iterate(indices, export_one, progress, "Exporting")
  receipt <- if (length(rows)) do.call(rbind, rows) else tibble::tibble(
    image = character(0), format = character(0), path = character(0),
    bytes = integer(0), n_rois = integer(0), status = character(0), message = character(0)
  )
  utils::write.csv(receipt, file.path(dir, "_export_manifest.csv"), row.names = FALSE)
  utils::write.csv(at_manifest(session), file.path(dir, "_annotation_summary.csv"),
                   row.names = FALSE)
  n_err <- sum(receipt$status == "error")
  if (n_err > 0L) {
    cli::cli_warn("{n_err} export{?s} failed; see the {.field status} column of the receipt.")
  }
  invisible(receipt)
}

#' Session summary statistics
#'
#' @param session An [annot_session].
#' @param by Grouping: `"image"`, `"label"`, or `"layer"`.
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with the grouping key plus `n_rois`,
#'   `total_area_px`, `mean_area`, and `sd_area`. A 0-row tibble when there are
#'   no ROIs.
#' @family batch
#' @export
at_summary_table <- function(session, by = c("image", "label", "layer"),
                             call = rlang::caller_env()) {
  .check_session(session, call = call)
  by <- .check_choice(by, c("image", "label", "layer"), call = call)
  empty <- tibble::tibble(
    key = character(0), n_rois = integer(0), total_area_px = double(0),
    mean_area = double(0), sd_area = double(0)
  )
  names(empty)[1] <- by
  parts <- list()
  for (i in seq_len(nrow(session$manifest))) {
    proj <- session$projects[[i]]
    if (is.null(proj)) next
    rt <- sf::st_drop_geometry(at_rois(proj))
    if (nrow(rt) == 0L) next
    rt$image <- session$manifest$name[i]
    parts[[length(parts) + 1L]] <- rt
  }
  if (length(parts) == 0L) {
    return(empty)
  }
  all_rt <- do.call(rbind, parts)
  grp <- dplyr::group_by(all_rt, .data[[by]])
  out <- dplyr::summarise(
    grp,
    n_rois = dplyr::n(),
    total_area_px = sum(.data$area_px, na.rm = TRUE),
    mean_area = mean(.data$area_px, na.rm = TRUE),
    sd_area = stats::sd(.data$area_px, na.rm = TRUE),
    .groups = "drop"
  )
  tibble::as_tibble(out)
}

#' Apply a function to every project in a session
#'
#' @param session An [annot_session].
#' @param fn A function `fn(project, image, idx)` returning an [annot_project].
#' @param ... Passed to `fn`.
#' @param scope `"all"` (default), `"complete"`, `"current"`, or `"flagged"`.
#' @param progress Logical; show a progress bar. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return The [annot_session] with modified projects.
#' @family batch
#' @export
at_batch_apply <- function(session, fn, ..., scope = "all", progress = TRUE,
                           call = rlang::caller_env()) {
  .check_session(session, call = call)
  if (!is.function(fn)) {
    cli::cli_abort("{.arg fn} must be a function.", call = call)
  }
  scope <- .check_choice(scope, c("all", "complete", "current", "flagged"), call = call)
  indices <- .scope_indices(session, scope)
  apply_one <- function(i, k, n) {
    proj <- .materialize_project(session, i)
    session$projects[[i]] <<- fn(proj, proj$image, i, ...)
    session$manifest$n_rois[i] <<- nrow(at_rois(session$projects[[i]]))
  }
  .batch_iterate(indices, apply_one, progress, "Applying")
  session
}

#' Validate geometry across a whole session
#'
#' @param session An [annot_session].
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with columns `image`, `roi_id`, `issue`, and
#'   `severity`. A 0-row tibble when all geometry is valid.
#' @family batch
#' @seealso [at_check_geometry()]
#' @export
at_batch_validate <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  empty <- tibble::tibble(image = character(0), roi_id = character(0),
                          issue = character(0), severity = character(0))
  parts <- list()
  for (i in seq_len(nrow(session$manifest))) {
    proj <- session$projects[[i]]
    if (is.null(proj)) next
    ch <- at_check_geometry(proj)
    if (nrow(ch) > 0L) {
      ch$image <- session$manifest$name[i]
      parts[[length(parts) + 1L]] <- ch[, c("image", "roi_id", "issue", "severity")]
    }
  }
  if (length(parts) == 0L) {
    return(empty)
  }
  do.call(rbind, parts)
}
