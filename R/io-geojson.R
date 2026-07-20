# GeoJSON import/export. Geometry conversion is done by hand (rather than via a
# GeoJSON driver) for exact round-trip fidelity and full control over the
# property schema. These converters are shared with the QuPath dialect.

# ---- sfg <-> GeoJSON geometry ----------------------------------------------

.ring_to_coords <- function(m) {
  lapply(seq_len(nrow(m)), function(i) as.numeric(m[i, 1:2]))
}

# Convert a single sfg to a GeoJSON geometry list (type + coordinates).
.sfg_to_geojson <- function(g) {
  type <- as.character(sf::st_geometry_type(sf::st_sfc(g)))
  switch(
    type,
    "POINT"        = list(type = "Point", coordinates = as.numeric(g)),
    "MULTIPOINT"   = list(type = "MultiPoint", coordinates = .ring_to_coords(unclass(g))),
    "LINESTRING"   = list(type = "LineString", coordinates = .ring_to_coords(unclass(g))),
    "POLYGON"      = list(type = "Polygon", coordinates = lapply(g, .ring_to_coords)),
    "MULTIPOLYGON" = list(type = "MultiPolygon",
                          coordinates = lapply(g, function(p) lapply(p, .ring_to_coords))),
    cli::cli_abort("Cannot convert geometry type {.val {type}} to GeoJSON.")
  )
}

.coords_to_matrix <- function(ring) {
  do.call(rbind, lapply(ring, function(p) as.numeric(unlist(p))))
}

# Convert a parsed GeoJSON geometry (from jsonlite, simplifyVector = FALSE) to sfg.
.geojson_to_sfg <- function(geom) {
  type <- geom$type
  co <- geom$coordinates
  switch(
    type,
    "Point"        = sf::st_point(as.numeric(unlist(co))),
    "MultiPoint"   = sf::st_multipoint(.coords_to_matrix(co)),
    "LineString"   = sf::st_linestring(.coords_to_matrix(co)),
    "Polygon"      = sf::st_polygon(lapply(co, .coords_to_matrix)),
    "MultiPolygon" = sf::st_multipolygon(lapply(co, function(p) lapply(p, .coords_to_matrix))),
    cli::cli_abort("Cannot convert GeoJSON geometry type {.val {type}}.")
  )
}

# Apply a y-flip to an sfg given the image height.
.flip_sfg_y <- function(g, height) {
  .apply_coords(g, function(m) cbind(m[, 1], height - m[, 2]))
}

# ---- Write ------------------------------------------------------------------

#' Write a project's ROIs to GeoJSON
#'
#' @param project An [annot_project].
#' @param path Output file path.
#' @param layer Optional layer filter.
#' @param level Integer pyramid level for the coordinates. Default `0`.
#' @param flip_y Logical; invert the y-axis (for GIS-oriented consumers). Default
#'   `FALSE` (image orientation preserved). The consequence is documented in the
#'   interop vignette.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return The output path, invisibly.
#' @family io
#' @seealso [at_read_geojson()], [at_write_qupath()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' p <- withr::local_tempfile(fileext = ".geojson")
#' at_write_geojson(at_example_project(), p)
at_write_geojson <- function(project, path, layer = NULL, level = 0L,
                             flip_y = FALSE, overwrite = FALSE,
                             call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  .check_flag(flip_y, call = call)
  .check_flag(overwrite, call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  height <- at_dims(project$image, level)[2]
  fc <- .project_to_features(project, layer, level, flip_y, height,
                             qupath = FALSE)
  jsonlite::write_json(fc, path, auto_unbox = TRUE, digits = NA, null = "null",
                       pretty = TRUE)
  invisible(path)
}

# Build a FeatureCollection list from a project.
.project_to_features <- function(project, layer, level, flip_y, height, qupath) {
  Ls <- project$layers
  if (!is.null(layer)) Ls <- Ls[intersect(layer, names(Ls))]
  features <- list()
  for (nm in names(Ls)) {
    lyr <- Ls[[nm]]
    cols <- lyr$style$colour
    for (r in lyr$rois) {
      g <- .geom_to_level(.to_level0(r$geometry, r$level, project$image), level, project$image)[[1]]
      if (flip_y) g <- .flip_sfg_y(g, height)
      colour <- if (!is.null(cols) && r$label %in% names(cols)) unname(cols[[r$label]]) else "#5E2C8E"
      feat <- if (qupath) {
        .roi_to_qupath_feature(r, nm, g, colour)
      } else {
        .roi_to_feature(r, nm, g)
      }
      features[[length(features) + 1L]] <- feat
    }
  }
  list(type = "FeatureCollection", features = features)
}

.roi_to_feature <- function(r, layer_name, g) {
  list(
    type = "Feature",
    id = r$id,
    geometry = .sfg_to_geojson(g),
    properties = list(
      roi_id = r$id, layer = layer_name, label = r$label,
      level = r$level, author = r$author,
      created = format(r$created, "%Y-%m-%dT%H:%M:%S%z"),
      modified = format(r$modified, "%Y-%m-%dT%H:%M:%S%z"),
      source = r$source, annotatR_version = .pkg_version(),
      attributes = r$attributes
    )
  )
}

# ---- Read -------------------------------------------------------------------

#' Read ROIs from a GeoJSON file
#'
#' @param path Path to a GeoJSON file.
#' @param layer_name Layer name for the imported ROIs; taken from the features'
#'   `layer` property when `NULL`.
#' @param level Integer level to record when a feature has no `level` property.
#' @param flip_y Logical; invert the y-axis on read. Default `FALSE`.
#' @param height Image height in pixels, required when `flip_y = TRUE`.
#' @param call The calling environment, for error reporting.
#'
#' @return A named list of [annot_layer] objects (one per distinct `layer`
#'   property), or a single [annot_layer] when `layer_name` is supplied.
#' @family io
#' @export
at_read_geojson <- function(path, layer_name = NULL, level = 0L, flip_y = FALSE,
                            height = NULL, call = rlang::caller_env()) {
  .check_file(path, call = call)
  if (flip_y && is.null(height)) {
    cli::cli_abort("{.arg height} is required when {.code flip_y = TRUE}.", call = call)
  }
  fc <- jsonlite::read_json(path, simplifyVector = FALSE)
  features <- fc$features %||% list()
  layers <- list()
  for (ft in features) {
    props <- ft$properties %||% list()
    g <- .geojson_to_sfg(ft$geometry)
    if (flip_y) g <- .flip_sfg_y(g, height)
    ln <- layer_name %||% (props$layer %||% "imported")
    lb <- props$label %||% "unlabelled"
    lvl <- props$level %||% level
    roi <- at_roi_from_sf(
      sf::st_sfc(g, crs = sf::NA_crs_), label = as.character(lb), level = as.integer(lvl),
      id = props$roi_id %||% ft$id %||% .new_id("roi"),
      source = props$source %||% "imported",
      author = props$author %||% .default_author()
    )
    if (!is.null(props$attributes)) roi$attributes <- props$attributes
    if (is.null(layers[[ln]])) layers[[ln]] <- at_layer(ln)
    layers[[ln]] <- at_layer_add(layers[[ln]], roi)
  }
  if (!is.null(layer_name)) {
    return(layers[[layer_name]] %||% at_layer(layer_name))
  }
  layers
}
