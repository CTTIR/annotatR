# Flat CSV export of ROIs with a WKT geometry column, for spreadsheet users and
# pipelines that want ROI metadata without parsing GeoJSON.

#' Write a project's ROIs to CSV
#'
#' One row per ROI with a WKT `geometry` column.
#'
#' @param project An [annot_project].
#' @param path Output `.csv` path.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#' @return The path, invisibly.
#' @family io
#' @seealso [at_read_rois_csv()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' p <- withr::local_tempfile(fileext = ".csv")
#' at_write_rois_csv(at_example_project(), p)
at_write_rois_csv <- function(project, path, overwrite = FALSE,
                              call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  rt <- at_rois(project)
  df <- data.frame(
    roi_id = rt$roi_id, layer = rt$layer, label = rt$label,
    level = rt$level, area_px = rt$area_px, author = rt$author,
    source = rt$source,
    created = format(rt$created, "%Y-%m-%dT%H:%M:%S%z"),
    modified = format(rt$modified, "%Y-%m-%dT%H:%M:%S%z"),
    geometry = if (nrow(rt) > 0L) sf::st_as_text(rt$geometry) else character(0),
    stringsAsFactors = FALSE
  )
  utils::write.csv(df, path, row.names = FALSE)
  invisible(path)
}

#' Read ROIs from a CSV with WKT geometry
#'
#' @param path Path to a CSV with at least `label` and `geometry` (WKT) columns.
#'   Other columns (`level`, `author`, `source`, ...) are used when present.
#' @param layer_name Layer name for the imported ROIs. Default `"csv"`.
#' @param call The calling environment, for error reporting.
#' @return An [annot_layer].
#' @family io
#' @export
at_read_rois_csv <- function(path, layer_name = "csv", call = rlang::caller_env()) {
  .check_file(path, call = call)
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!all(c("label", "geometry") %in% names(df))) {
    cli::cli_abort(
      c("The CSV must have {.field label} and {.field geometry} (WKT) columns.",
        "x" = "Found: {.val {names(df)}}."),
      call = call
    )
  }
  lyr <- at_layer(layer_name)
  if (nrow(df) == 0L) {
    return(lyr)
  }
  geoms <- sf::st_as_sfc(df$geometry, crs = sf::NA_crs_)
  for (i in seq_len(nrow(df))) {
    roi <- at_roi_from_sf(
      geoms[i], label = as.character(df$label[i]),
      level = if ("level" %in% names(df)) as.integer(df$level[i]) else 0L,
      id = if ("roi_id" %in% names(df)) as.character(df$roi_id[i]) else .new_id("roi"),
      source = if ("source" %in% names(df)) as.character(df$source[i]) else "imported",
      author = if ("author" %in% names(df)) as.character(df$author[i]) else .default_author()
    )
    lyr <- at_layer_add(lyr, roi)
  }
  lyr
}
