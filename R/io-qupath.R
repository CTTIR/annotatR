# QuPath GeoJSON dialect. QuPath encodes a classification's colour as a signed
# 32-bit integer packed as 0xFFRRGGBB (the 0xFF alpha makes most colours
# negative), so the hex <-> int conversion is done with modular arithmetic to
# avoid integer overflow.

# Hex colour -> QuPath signed 32-bit colorRGB.
.hex_to_signed_int <- function(hex) {
  c3 <- grDevices::col2rgb(hex)
  unsigned <- 255 * 16777216 + c3[1] * 65536 + c3[2] * 256 + c3[3]
  as.integer(if (unsigned >= 2147483648) unsigned - 4294967296 else unsigned)
}

# QuPath signed 32-bit colorRGB -> hex colour.
.signed_int_to_hex <- function(val) {
  unsigned <- if (val < 0) as.numeric(val) + 4294967296 else as.numeric(val)
  b <- unsigned %% 256
  g <- (unsigned %/% 256) %% 256
  r <- (unsigned %/% 65536) %% 256
  grDevices::rgb(r, g, b, maxColorValue = 255)
}

.roi_to_qupath_feature <- function(r, layer_name, g, colour) {
  object_type <- if (r$source %in% c("mask", "derived")) "detection" else "annotation"
  list(
    type = "Feature",
    id = r$id,
    geometry = .sfg_to_geojson(g),
    properties = list(
      object_type = object_type,
      classification = list(name = r$label, colorRGB = .hex_to_signed_int(colour)),
      isLocked = isTRUE(r$attributes$locked),
      layer = layer_name
    )
  )
}

#' Write a project's ROIs as QuPath GeoJSON
#'
#' @param project An [annot_project].
#' @param path Output file path.
#' @param layer Optional layer filter.
#' @param level Integer pyramid level. Default `0`.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return The output path, invisibly.
#' @family io
#' @seealso [at_read_qupath()], [at_write_geojson()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' p <- withr::local_tempfile(fileext = ".geojson")
#' at_write_qupath(at_example_project(), p)
at_write_qupath <- function(project, path, layer = NULL, level = 0L,
                            overwrite = FALSE, call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  .check_flag(overwrite, call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  height <- at_dims(project$image, level)[2]
  fc <- .project_to_features(project, layer, level, flip_y = FALSE, height = height,
                             qupath = TRUE)
  jsonlite::write_json(fc, path, auto_unbox = TRUE, digits = NA, null = "null",
                       pretty = TRUE)
  invisible(path)
}

#' Read ROIs from a QuPath GeoJSON file
#'
#' Maps `classification.name` to the ROI label, `colorRGB` to the layer style
#' colour, and `object_type` to the ROI source. Features with a `null`
#' classification are imported as `"unclassified"`.
#'
#' @param path Path to a QuPath GeoJSON file.
#' @param layer_name Layer name for the imported ROIs. Default `"qupath"`.
#' @param level Integer level to record on the ROIs. Default `0`.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_layer].
#' @family io
#' @export
at_read_qupath <- function(path, layer_name = "qupath", level = 0L,
                           call = rlang::caller_env()) {
  .check_file(path, call = call)
  fc <- jsonlite::read_json(path, simplifyVector = FALSE)
  features <- fc$features %||% list()
  lyr <- at_layer(layer_name)
  colour_map <- character()
  for (ft in features) {
    props <- ft$properties %||% list()
    cls <- props$classification
    label <- if (is.null(cls) || is.null(cls$name)) "unclassified" else as.character(cls$name)
    if (!is.null(cls) && !is.null(cls$colorRGB)) {
      colour_map[[label]] <- .signed_int_to_hex(as.integer(cls$colorRGB))
    }
    src <- if (identical(props$object_type, "detection")) "imported" else "imported"
    g <- .geojson_to_sfg(ft$geometry)
    roi <- at_roi_from_sf(
      sf::st_sfc(g, crs = sf::NA_crs_), label = label, level = as.integer(level),
      id = ft$id %||% .new_id("roi"), source = "imported"
    )
    if (isTRUE(props$isLocked)) roi$attributes$locked <- TRUE
    lyr <- at_layer_add(lyr, roi)
  }
  # Apply recovered colours to the layer style.
  if (length(colour_map) > 0L) {
    lyr$style$colour <- .resolve_palette(lyr$labels, colour_map)
  }
  lyr
}
