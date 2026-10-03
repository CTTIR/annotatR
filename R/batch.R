# Batch operations across a session's images: export, summaries, bulk edits, and
# validation. A single failed image never aborts a whole-session run.

# Materialise the project for image `i`, reusing a stored one when present.
.materialize_project <- function(session, i) {
  p <- session$projects[[i]]
  if (!is.null(p)) {
    p$image <- .reopen_image(p$image)
    return(p)
  }
  path <- session$manifest$project_path[i]
  if (!is.na(path) && nzchar(path)) {
    p <- at_load_project(path)
    if (!is.null(p$meta$entry_id) && !identical(p$meta$entry_id,session$manifest$entry_id[i])) stop("Project identity does not match manifest entry.")
    p$meta$entry_id <- session$manifest$entry_id[i]
    return(p)
  }
  img <- at_read_image(session$manifest$path[i])
  proj <- at_project(
    img,
    name = session$manifest$name[i],
    entry_id = session$manifest$entry_id[i]
  )
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
#' @return An invisible export-receipt [tibble::tibble] with columns `entry_id`,
#'   `image`, `format`, `path`, `bytes`, `n_rois`, `status`, and `message`. Also
#'   written to `_export_manifest.csv` alongside the exports. Additive columns
#'   `sidecar_path` and `sidecar_bytes` describe mask legends. Byte counts are
#'   doubles. Status is `"ok"` for a complete published bundle, `"error"` for a
#'   failed item, or `"skipped"` when an existing bundle is protected. Every
#'   image-format request has a row, even if loading the image fails. Receipt
#'   publication or annotation-summary failures warn and are also retained in
#'   `receipt_error` / `summary_error` attributes; the item receipt is returned.
#'
#' @details Derived filenames use safe portable components; display names stay
#'   in the receipt and annotation metadata. Case-folded collisions are given
#'   deterministic suffixes, including cross-format and sidecar collisions.
#'   The complete plan (including manifests) rejects descendant symlinks before
#'   writing outputs. Existing mask/legend bundles are skipped as a whole unless
#'   `overwrite=TRUE`. Files are staged and publication failures roll back prior
#'   files. Callers must serialize concurrent exports and avoid changing the
#'   destination filesystem during a run: preflight and multiple renames are
#'   not a race-free filesystem transaction. Receipt files are replaced each
#'   run, independently of the item overwrite policy.
#' @family batch
#' @seealso [at_write_masks()], [at_manifest()]
#' @export
#' @examples
#' sess <- at_example_session(2)
#' dir <- file.path(tempdir(), "annotatR-export")
#' at_export_all(sess, dir, formats = "geojson", scope = "all", progress = FALSE)
at_export_all <- function(session, dir,
                          formats = c("mask_tiff", "geojson", "qupath", "rds", "csv"),
                          scope = c("complete", "all", "current", "flagged"),
                          mask_type = c("labelled", "binary", "multiclass"),
                          level = 0L, overwrite = FALSE,
                          progress = TRUE, call = rlang::caller_env()) {
  .check_session(session, call = call)
  .check_string(dir, call = call)
  scope <- .check_choice(scope, c("complete", "all", "current", "flagged"), default = missing(scope), call = call)
  mask_type <- .check_choice(mask_type, c("labelled", "binary", "multiclass"), default = missing(mask_type), call = call)
  formats <- .export_formats(formats)
  .check_flag(overwrite,call=call); .check_flag(progress,call=call)
  indices <- .scope_indices(session, scope)
  receipt <- .export_session_items(session,indices,dir,formats,
    function(i) .materialize_project(session,i),overwrite=overwrite,
    level=level,mask_type=mask_type,progress=progress)
  summary <- tryCatch(at_manifest(session),error=identity)
  if(inherits(summary,"error")) {
    attr(receipt,"summary_error") <- conditionMessage(summary)
    warning("Could not generate export summary: ",conditionMessage(summary),call.=FALSE)
    summary <- NULL
  }
  receipt <- .export_receipt_files(receipt,dir,summary)
  n_err <- sum(receipt$status == "error")
  if(n_err>0L) cli::cli_warn("{n_err} exports failed; see the status column of the receipt.")
  invisible(receipt)
}

# Shared package/app planner: one receipt row for every image-format request.
.export_session_items <- function(session,indices,dir,formats,get_project,
                                  overwrite=FALSE,level=0L,mask_type="labelled",
                                  overlap="last",progress=FALSE,flat=FALSE,skip_empty=FALSE) {
  formats <- .export_formats(formats)
  subdirs <- c(mask_tiff="masks",geojson="geojson",qupath="qupath",rds="projects",csv="csv")
  exts <- c(mask_tiff=".tif",geojson=".geojson",qupath="_qupath.geojson",rds=".rds",csv="_rois.csv")
  jobs <- list()
  for(i in indices) for(fmt in formats) jobs[[length(jobs)+1L]] <- list(
    i=i,format=fmt,stem=session$manifest$export_stem[i],
    subdir=if(flat) NULL else subdirs[[fmt]],ext=exts[[fmt]],sidecar=fmt=="mask_tiff")
  jobs <- .export_plan(dir,jobs,reserved=c("_export_manifest.csv","_annotation_summary.csv"))
  rows <- list()
  export_one <- function(i,k,n) {
    project <- tryCatch(get_project(i),error=identity)
    count <- tryCatch(if(is.null(project) || inherits(project,"error")) NA_integer_ else nrow(at_rois(project)),error=identity)
    if(inherits(count,"error")) {project <- count;count <- NA_integer_}
    for(j in Filter(function(j) j$i==i,jobs)) {
      if(inherits(project,"error")) result <- list(status="error",message=conditionMessage(project),bytes=NA_real_,sidecar_bytes=NA_real_)
      else if(is.null(project) || (skip_empty && count==0L)) result <- list(status="skipped",message="No annotated project available.",bytes=NA_real_,sidecar_bytes=NA_real_)
      else result <- .export_outcome(j$paths,function(stage) .export_project_file(project,j$format,stage,level,mask_type,overlap),overwrite)
      rows[[length(rows)+1L]] <<- tibble::tibble(entry_id=session$manifest$entry_id[i],image=session$manifest$name[i],
        format=j$format,path=j$paths[1],bytes=result$bytes,n_rois=count,status=result$status,message=result$message,
        sidecar_path=if(length(j$paths)>1L) j$paths[2] else NA_character_,sidecar_bytes=result$sidecar_bytes)
    }
  }
  .batch_iterate(indices,export_one,progress,"Exporting")
  if(length(rows)) do.call(rbind,rows) else .export_receipt()
}

#' Session summary statistics
#'
#' @param session An [annot_session].
#' @param by Grouping: `"image"`, `"label"`, or `"layer"`.
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with the grouping key plus `n_rois`,
#'   `total_area_px`, `mean_area`, and `sd_area`. Image summaries also include
#'   `entry_id`, so repeated display names remain separate. A 0-row tibble when
#'   there are no ROIs.
#' @family batch
#' @export
at_summary_table <- function(session, by = c("image", "label", "layer"),
                             call = rlang::caller_env()) {
  .check_session(session, call = call)
  by <- .check_choice(by, c("image", "label", "layer"), default = missing(by), call = call)
  if (by == "image") {
    empty <- tibble::tibble(
      image = character(0), entry_id = character(0), n_rois = integer(0),
      total_area_px = double(0), mean_area = double(0), sd_area = double(0)
    )
  } else {
    empty <- tibble::tibble(
      key = character(0), n_rois = integer(0), total_area_px = double(0),
      mean_area = double(0), sd_area = double(0)
    )
    names(empty)[1] <- by
  }
  parts <- list()
  for (i in seq_len(nrow(session$manifest))) {
    proj <- session$projects[[i]]
    if (is.null(proj)) next
    rt <- sf::st_drop_geometry(at_rois(proj))
    if (nrow(rt) == 0L) next
    rt$image <- session$manifest$name[i]
    rt$entry_id <- session$manifest$entry_id[i]
    parts[[length(parts) + 1L]] <- rt
  }
  if (length(parts) == 0L) {
    return(empty)
  }
  all_rt <- do.call(rbind, parts)
  grp <- if (by == "image") {
    dplyr::group_by(all_rt, .data$image, .data$entry_id)
  } else {
    dplyr::group_by(all_rt, .data[[by]])
  }
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
  scope <- .check_choice(scope, c("all", "complete", "current", "flagged"), default = missing(scope), call = call)
  indices <- .scope_indices(session, scope)
  apply_one <- function(i, k, n) {
    proj <- .materialize_project(session, i)
    session$projects[[i]] <<- fn(proj, proj$image, i, ...)
    session$manifest$n_rois[i] <<- nrow(at_rois(session$projects[[i]]))
  }
  .batch_iterate(indices, apply_one, progress, "Applying")
  session
}

#' Check geometry across a whole session
#'
#' Run [at_check_geometry()] on every materialised project in the session and
#' stack the reports. Like `at_check_geometry()` (and unlike the assertion
#' [at_validate()]), this returns a report rather than throwing.
#'
#' @param session An [annot_session].
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with columns `image`, `roi_id`, `issue`, and
#'   `severity`. A 0-row tibble when all geometry is valid.
#' @family batch
#' @seealso [at_check_geometry()]
#' @export
at_batch_check_geometry <- function(session, call = rlang::caller_env()) {
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
