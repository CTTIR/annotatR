# The batch-annotation app launcher.

.annotate_pkgs <- c("shiny", "bslib", "htmlwidgets", "shinyjs")

# Normalise the launcher's `x` argument to an annot_session.
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
        cli::cli_abort("No supported image files found in the directory.", call = call)
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

#' Launch the batch annotation application
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
#' @param ... Reserved for future use.
#' @param call The calling environment, for error reporting.
#'
#' @return Invisible `NULL`. Launches a Shiny application; called for side
#'   effects.
#' @family shiny
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
  missing_pkgs <- .annotate_pkgs[!vapply(.annotate_pkgs, requireNamespace,
                                         logical(1), quietly = TRUE)]
  if (length(missing_pkgs) > 0L) {
    cli::cli_abort(
      c("{.fn at_annotate} requires packages not currently installed.",
        "x" = "Missing: {.pkg {missing_pkgs}}.",
        "i" = "Install with {.code install.packages(c({paste0('\"', missing_pkgs, '\"', collapse = ', ')}))}."),
      call = call
    )
  }
  session <- .to_session(x, labels, layers, out_dir, call = call)
  if (!dir.exists(session$out_dir)) {
    dir.create(session$out_dir, recursive = TRUE)
  }
  old <- options(annotatR.session = session)
  on.exit(options(old), add = TRUE)
  app_dir <- system.file("shiny", "annotatR", package = "annotatR")
  shiny::runApp(app_dir, launch.browser = launch.browser, port = port)
  invisible(NULL)
}
