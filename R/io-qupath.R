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

.roi_to_qupath_feature <- function(r, layer_name, g, colour, level = r$level) {
  object_type <- r$attributes$qupath_object_type %||% if (r$source %in% c("mask", "derived")) "detection" else "annotation"
  list(
    type = "Feature",
    id = .qupath_uuid(r$id),
    geometry = .sfg_to_geojson(g),
    properties = list(
      objectType = object_type,
      classification = list(name = r$label, color = as.list(as.integer(grDevices::col2rgb(colour)))),
      metadata = list(annotatR_roi_id = r$id, annotatR_coordinate_schema = .coordinate_schema,
                      annotatR_coordinate_level = as.character(level)),
      isLocked = isTRUE(r$attributes$locked),
      layer = layer_name, level = level, source_level = r$level,
      coordinate_schema = .coordinate_schema
    )
  )
}

#' Write a project's ROIs as QuPath GeoJSON
#'
#' Uses current `objectType` and classification RGB arrays. Arbitrary internal
#' ROI IDs are mapped to deterministic UUID feature IDs and also recorded as
#' `properties.metadata.annotatR_roi_id`; existing UUIDs remain unchanged.
#' String metadata also preserves the coordinate schema and coordinate level.
#' QuPath 0.7.0 retains these entries through native import/export. Removing
#' that metadata loses the original non-UUID identity. Existing imported object
#' kinds are retained; mask/derived ROIs otherwise export as detections and
#' other sources as annotations. Geometry is unchanged apart from the requested
#' pyramid-level transform. Publication uses a staged replacement.
#'
#' @param project An [annot_project].
#' @param path Output file path.
#' @param layer Optional layer filter.
#' @param level Integer pyramid level for coordinates and the `level` property.
#'   Default `0`, as expected by QuPath; other levels are for consumers that
#'   explicitly support them. `source_level` records the stored ROI level.
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
  ids <- vapply(fc[["features"]],`[[`,character(1),"id")
  if(anyDuplicated(tolower(ids))) stop("Conflicting QuPath output UUIDs.")
  .export_bundle(path,function(stage) jsonlite::write_json(fc, stage[1], auto_unbox = TRUE, digits = NA, null = "null",
                       pretty = TRUE),overwrite)
  invisible(path)
}

#' Read ROIs from a QuPath GeoJSON file
#'
#' Accepts a native Feature array, FeatureCollection or single Feature. Current
#' `classification.color` RGB arrays and legacy `colorRGB` integers recover the
#' layer colour. Null classifications become `"unclassified"`. Current
#' `objectType` and legacy `object_type` support annotations and detections;
#' other kinds reject explicitly. Imported ROIs use source `"imported"` and keep
#' the native kind in `attributes$qupath_object_type` for subsequent exports.
#' Original IDs and coordinate declarations stored in annotatR string metadata
#' survive native QuPath import/export. Ordinary external IDs remain unchanged.
#' Contradictory duplicate fields or ID mappings reject; identical duplicate
#' metadata emitted by QuPath 0.7.0 is accepted.
#'
#' @param path Path to a QuPath GeoJSON file.
#' @param layer_name Layer name for the imported ROIs. Default `"qupath"`.
#' @param level Integer fallback level for features without level metadata.
#'   Default `0` (standard full-resolution QuPath coordinates).
#' @param coordinate_level Optional integer overriding every recorded `level`
#'   without scaling coordinates. Use only when the actual coordinate level is
#'   known, for example `0L` for legacy annotatR exports that wrote level-0
#'   coordinates beside a nonzero source level. `NULL` (default) uses the schema
#'   and `legacy_levels` policy. Coordinates are never automatically repaired.
#' @param legacy_levels How to interpret files without the corrected coordinate
#'   schema marker: `"error"` (default) rejects ambiguous nonzero recorded levels;
#'   `"recorded"` explicitly trusts those levels. Level-0 files remain unambiguous.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_layer].
#' @family io
#' @export
at_read_qupath <- function(path, layer_name = "qupath", level = 0L,
                           call = rlang::caller_env(), coordinate_level = NULL,
                           legacy_levels = c("error", "recorded")) {
  legacy_levels <- .check_choice(legacy_levels, c("error", "recorded"), default = missing(legacy_levels), call = call)
  if (!is.null(coordinate_level)) coordinate_level <- .check_count(coordinate_level, call = call)
  .check_file(path, call = call)
  .check_count(level, call=call)
  raw <- paste(readLines(path,warn=FALSE),collapse="\n")
  fc <- .qupath_object(jsonlite::fromJSON(raw, simplifyVector = FALSE))
  if(!is.list(fc)) stop("Malformed QuPath GeoJSON root.")
  features <- if (identical(fc[["type"]], "FeatureCollection")) {
    if (!is.list(fc[["features"]]) || !is.null(names(fc[["features"]]))) stop("Malformed QuPath FeatureCollection features.")
    fc[["features"]]
  } else if (identical(fc[["type"]], "Feature")) list(fc) else if (is.list(fc) && is.null(names(fc)) && startsWith(trimws(raw),"[")) fc else stop("Malformed QuPath GeoJSON root.")
  lyr <- at_layer(layer_name)
  colour_map <- character()
  for (ft in features) {
    if (!is.list(ft) || !identical(ft[["type"]],"Feature") || !is.list(ft[["geometry"]])) stop("Malformed QuPath GeoJSON Feature.")
    props <- ft[["properties"]] %||% list()
    if(!is.list(props) || (length(props) && is.null(names(props)))) stop("Malformed QuPath properties.")
    cls <- props[["classification"]]
    if(!is.null(cls) && (!is.list(cls) || is.null(names(cls)))) stop("Malformed QuPath classification.")
    label <- cls[["name"]] %||% "unclassified"
    .qupath_string(label, "classification name")
    colour <- .qupath_colour(cls)
    if(!is.null(colour)) {
      if(label %in% names(colour_map) && !identical(colour_map[[label]],colour)) stop("Conflicting QuPath classification colours for label: ",label)
      colour_map[[label]] <- colour
    }
    kind <- .qupath_consistent(list(props[["objectType"]],props[["object_type"]]),"object type") %||% "annotation"
    if(!is.character(kind) || length(kind)!=1L || !kind %in% c("annotation","detection")) stop("Unsupported QuPath object type; only annotation and detection objects are supported.")
    meta <- props[["metadata"]] %||% list()
    if(!is.list(meta) || (length(meta) && is.null(names(meta)))) stop("Malformed QuPath metadata mapping.")
    for(key in intersect(names(meta),c("annotatR_roi_id","annotatR_coordinate_schema","annotatR_coordinate_level"))) .qupath_string(meta[[key]],paste("metadata mapping",key))
    schema <- .qupath_consistent(list(props[["coordinate_schema"]],meta[["annotatR_coordinate_schema"]]),"coordinate schema")
    if(!is.null(schema)) .qupath_string(schema,"coordinate schema")
    recorded <- props[["level"]]
    if(!is.null(meta[["annotatR_coordinate_level"]])) {
      if(!grepl("^[0-9]+$",meta[["annotatR_coordinate_level"]])) stop("Malformed QuPath coordinate metadata mapping.")
      recorded <- .qupath_consistent(list(recorded,as.numeric(meta[["annotatR_coordinate_level"]])),"coordinate level")
    }
    if(!is.null(ft[["id"]])) .qupath_string(ft[["id"]],"feature ID")
    id <- meta[["annotatR_roi_id"]] %||% ft[["id"]] %||% .new_id("roi")
    .qupath_string(id,"ROI ID mapping")
    if(id %in% vapply(lyr$rois,`[[`,character(1),"id")) stop("Duplicate QuPath ROI ID mapping: ",id)
    if(!is.null(props[["isLocked"]]) && (!is.logical(props[["isLocked"]]) || length(props[["isLocked"]])!=1L || is.na(props[["isLocked"]]))) stop("Malformed QuPath isLocked field.")
    .qupath_geometry(ft[["geometry"]])
    g <- .geojson_to_sfg(ft[["geometry"]])
    roi <- at_roi_from_sf(
      sf::st_sfc(g, crs = sf::NA_crs_), label = label,
      level = .import_coordinate_level(recorded, level, schema,
                                       coordinate_level, legacy_levels, call),
      id = id, source = "imported"
    )
    roi$attributes$qupath_object_type <- kind
    if (isTRUE(props[["isLocked"]])) roi$attributes$locked <- TRUE
    lyr <- at_layer_add(lyr, roi)
  }
  # Apply recovered colours to the layer style.
  if (length(colour_map) > 0L) {
    lyr$style$colour <- .resolve_palette(lyr$labels, colour_map)
  }
  lyr
}

# Native QuPath requires UUID feature IDs, and preserves string metadata. The
# original ROI identity remains authoritative; ordinary external UUIDs stay intact.
.qupath_uuid <- function(id) {
  if(grepl("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$",id)) return(id)
  p <- tempfile(); on.exit(unlink(p)); writeBin(charToRaw(paste0("annotatR-roi:",enc2utf8(id))),p)
  h <- unname(tools::md5sum(p))
  paste(substr(h,1,8),substr(h,9,12),paste0("8",substr(h,14,16)),paste0("a",substr(h,18,20)),substr(h,21,32),sep="-")
}
.qupath_string <- function(x, field) {
  if(!is.character(x) || length(x)!=1L || is.na(x) || !nzchar(x)) stop("Malformed QuPath ",field,"; expected one nonempty string.")
  invisible(x)
}
.qupath_consistent <- function(values, field) {
  values <- Filter(Negate(is.null),values)
  if(!length(values)) return(NULL)
  equal <- function(x) {
    reference <- values[[1]]
    if(is.numeric(x) && is.numeric(reference)) identical(as.numeric(x),as.numeric(reference)) else identical(x,reference)
  }
  if(!all(vapply(values,equal,logical(1)))) stop("Conflicting QuPath ",field," declarations.")
  values[[1]]
}
# jsonlite exposes duplicate object names. Identical native metadata repetitions
# are accepted; contradictory duplicate values are never silently selected.
.qupath_object <- function(x) {
  if(!is.list(x)) return(x)
  x <- lapply(x,.qupath_object)
  if(!is.null(names(x))) {
    for(nm in unique(names(x))) {
      copies <- x[names(x)==nm]
      if(!all(vapply(copies,identical,logical(1),copies[[1]]))) stop("Conflicting QuPath duplicate field: ",nm)
    }
    x <- x[!duplicated(names(x))]
  }
  x
}
.qupath_colour <- function(cls) {
  if(is.null(cls)) return(NULL)
  current <- old <- NULL
  if(!is.null(cls[["color"]])) {
    rgb <- cls[["color"]]
    if(!is.list(rgb) || !is.null(names(rgb)) || length(rgb)!=3L || !all(vapply(rgb,function(v) is.numeric(v) && length(v)==1L && is.finite(v) && v==floor(v) && v>=0 && v<=255,logical(1)))) stop("Malformed QuPath classification color RGB array.")
    rgb <- unlist(rgb); current <- grDevices::rgb(rgb[1],rgb[2],rgb[3],maxColorValue=255)
  }
  if(!is.null(cls[["colorRGB"]])) {
    v <- cls[["colorRGB"]]
    if(!is.numeric(v) || length(v)!=1L || !is.finite(v) || v!=floor(v) || v< -2147483648 || v>4294967295) stop("Malformed QuPath classification colorRGB.")
    old <- .signed_int_to_hex(v)
  }
  .qupath_consistent(list(current,old),"classification colour")
}
.qupath_geometry <- function(g) {
  if(!is.character(g[["type"]]) || length(g[["type"]])!=1L) stop("Malformed QuPath GeoJSON geometry type.")
  depth <- switch(g[["type"]],Point=0L,MultiPoint=1L,LineString=1L,Polygon=2L,MultiPolygon=3L,stop("Unsupported QuPath GeoJSON geometry type."))
  coords <- function(x,n) {
    if(!is.list(x) || !is.null(names(x)) || !length(x)) stop("Malformed QuPath GeoJSON coordinates.")
    if(n==0L) {
      if(length(x)!=2L || !all(vapply(x,function(v) is.numeric(v) && length(v)==1L && is.finite(v),logical(1)))) stop("Malformed QuPath GeoJSON coordinate pair.")
    } else for(part in x) coords(part,n-1L)
  }
  coords(g[["coordinates"]],depth)
}
