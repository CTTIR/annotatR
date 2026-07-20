# Project and session serialisation as full-fidelity RDS, with a version stamp
# and a migration hook so future versions can upgrade older files.

# Compare a stored annotatR version against the installed one, warn if the file
# is from a newer version, and run the (currently trivial) migration chain.
.migrate_object <- function(obj, stored_version, call = rlang::caller_env()) {
  inst <- .pkg_version()
  if (!is.null(stored_version) && !is.na(stored_version) &&
      utils::compareVersion(as.character(stored_version), inst) > 0) {
    cli::cli_warn(c(
      "This file was written by a newer annotatR ({stored_version} > {inst}).",
      "i" = "Some fields may not load correctly; upgrade annotatR to be safe."
    ))
  }
  # Future migrations keyed on stored_version go here. None needed for 0.0.1.
  obj
}

#' Save a project
#'
#' @param project An [annot_project].
#' @param path Output `.rds` path.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#' @return The path, invisibly.
#' @family io
#' @seealso [at_load_project()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' p <- withr::local_tempfile(fileext = ".rds")
#' at_save_project(at_example_project(), p)
at_save_project <- function(project, path, overwrite = FALSE,
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  project$provenance$saved_with <- .pkg_version()
  saveRDS(project, path)
  invisible(path)
}

#' Load a project
#'
#' @param path Path to a saved project `.rds`.
#' @param call The calling environment, for error reporting.
#' @return The [annot_project]. Warns if the file was written by a newer
#'   annotatR.
#' @family io
#' @export
at_load_project <- function(path, call = rlang::caller_env()) {
  .check_file(path, call = call)
  obj <- readRDS(path)
  .check_project(obj, arg = "path", call = call)
  ver <- obj$provenance$saved_with %||% obj$provenance$annotatR_version
  .migrate_object(obj, ver, call = call)
}

#' Save a session
#'
#' @param session An [annot_session].
#' @param path Optional output path; defaults to `_session.rds` in `out_dir`.
#' @param overwrite Logical; overwrite an existing file. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return The session, invisibly.
#' @family io
#' @seealso [at_load_session()], [at_session_save()]
#' @export
at_save_session <- function(session, path = NULL, overwrite = TRUE,
                            call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$meta$annotatR_version <- .pkg_version()
  if (!is.null(path) && file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  at_session_save(session, path = path, call = call)
}

#' Load a session
#'
#' @param path Path to a saved session `.rds`.
#' @param call The calling environment, for error reporting.
#' @return The [annot_session]. Warns if written by a newer annotatR.
#' @family io
#' @export
at_load_session <- function(path, call = rlang::caller_env()) {
  obj <- at_session_load(path, call = call)
  .migrate_object(obj, obj$meta$annotatR_version, call = call)
}
