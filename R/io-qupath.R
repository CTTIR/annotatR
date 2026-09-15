# QuPath GeoJSON dialect.
#
# QuPath 0.4+ (verified against a real QuPath 0.7.0 export, see
# tests/testthat/fixtures/qupath-0.7.0) writes `properties.objectType`,
# `classification = {name | names, color = [r, g, b]}`, `isLocked` only when
# locked, the object UUID as the feature `id`, a non-default image plane as
# `geometry.plane`, ellipses as polygons flagged `geometry.isEllipse`, cell
# nuclei as a feature-level `nucleusGeometry`, and `measurements` as a flat
# object whose non-finite values are strings such as "NaN". QuPath silently
# replaces feature ids that are not UUIDs, so the QuPath dialect writes a
# deterministic UUID per ROI and keeps annotatR's own id in
# `properties.metadata`.
#
# The legacy annotatR 0.1 dialect (`object_type`, signed 32-bit `colorRGB`) is
# still readable and can still be written with `dialect = "legacy"`. QuPath's
# colorRGB packs 0xFFRRGGBB into a signed int, so the hex <-> int conversion
# uses modular arithmetic to avoid integer overflow.

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

.uuid_pattern <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

# Deterministic UUID (version 8, RFC 9562 "custom") derived from an annotatR
# ROI id, so repeated exports of the same ROI give QuPath the same object id.
# An id that already is a UUID is kept unchanged.
.roi_uuid <- function(id) {
  if (grepl(.uuid_pattern, id)) {
    return(tolower(id))
  }
  h <- substr(.sha256_bytes(paste0("annotatR:roi:", id)), 1L, 32L)
  chars <- strsplit(h, "")[[1]]
  chars[13] <- "8"
  chars[17] <- c("8", "9", "a", "b")[(strtoi(chars[17], 16L) %% 4L) + 1L]
  h <- paste(chars, collapse = "")
  paste(substr(h, 1, 8), substr(h, 9, 12), substr(h, 13, 16), substr(h, 17, 20),
        substr(h, 21, 32), sep = "-")
}

.roi_to_qupath_feature <- function(r, layer_name, g, colour, dialect = "qupath") {
  object_type <- r$attributes$qupath$object_type %||%
    (if (r$source %in% c("mask", "derived")) "detection" else "annotation")
  if (identical(dialect, "legacy")) {
    return(list(
      type = "Feature",
      id = r$id,
      geometry = .sfg_to_geojson(g),
      properties = list(
        object_type = object_type,
        classification = list(name = r$label, colorRGB = .hex_to_signed_int(colour)),
        isLocked = isTRUE(r$attributes$locked),
        layer = layer_name
      )
    ))
  }
  geometry <- .sfg_to_geojson(g)
  plane <- r$attributes$plane
  if (is.list(plane) && (isTRUE(plane$z > 0) || isTRUE(plane$t > 0) ||
                         (!is.null(plane$c) && !is.na(plane$c) && plane$c >= 0))) {
    geometry$plane <- list(c = if (is.null(plane$c) || is.na(plane$c)) -1L else as.integer(plane$c),
                           z = as.integer(plane$z %||% 0L), t = as.integer(plane$t %||% 0L))
  }
  rgb <- as.integer(grDevices::col2rgb(colour)[, 1])
  classification <- if (grepl(": ", r$label, fixed = TRUE)) {
    list(names = as.list(strsplit(r$label, ": ", fixed = TRUE)[[1]]), color = as.list(rgb))
  } else {
    list(name = r$label, color = as.list(rgb))
  }
  props <- list(objectType = object_type)
  if (.is_string(r$attributes$qupath$name)) {
    props$name <- r$attributes$qupath$name
  }
  if (!identical(r$label, "unclassified")) {
    props$classification <- classification
  }
  if (isTRUE(r$attributes$locked)) {
    props$isLocked <- TRUE
  }
  props$metadata <- list(
    annotatr_roi_id = r$id,
    annotatr_layer = layer_name,
    annotatr_source = r$source,
    annotatr_level = as.character(r$level)
  )
  feat <- list(type = "Feature", id = .roi_uuid(r$id), geometry = geometry, properties = props)
  if (!is.null(r$attributes$qupath$nucleus_geometry)) {
    feat$nucleusGeometry <- r$attributes$qupath$nucleus_geometry
  }
  feat
}

#' Write a project's ROIs as QuPath GeoJSON
#'
#' The default `dialect = "qupath"` writes what QuPath 0.4 and later read
#' natively (verified with QuPath 0.7.0): `objectType`, `classification` with
#' an `[r, g, b]` colour, `isLocked` for locked ROIs, a deterministic UUID per
#' ROI as the feature id (QuPath replaces non-UUID ids), and annotatR's own ROI
#' id, layer, source and level in `properties.metadata`. `dialect = "legacy"`
#' writes the annotatR 0.1 form (`object_type`, signed `colorRGB`), which QuPath
#' still reads with a deprecation warning.
#'
#' QuPath keeps one colour per classification name, so identical labels with
#' different layer colours collapse to the first colour QuPath sees.
#'
#' @param project An [annot_project].
#' @param path Output file path.
#' @param layer Optional layer filter.
#' @param level Integer pyramid level. Default `0`.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param dialect `"qupath"` (default) or `"legacy"`.
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
                            overwrite = FALSE, dialect = c("qupath", "legacy"),
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  .check_flag(overwrite, call = call)
  dialect <- .check_choice(dialect, c("qupath", "legacy"), call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  height <- at_dims(project$image, level)[2]
  fc <- .project_to_features(project, layer, level, flip_y = FALSE, height = height,
                             qupath = TRUE, dialect = dialect)
  jsonlite::write_json(fc, path, auto_unbox = TRUE, digits = I(17), null = "null",
                       pretty = TRUE)
  invisible(path)
}

# Features of a QuPath GeoJSON document: a FeatureCollection, a bare array of
# features (QuPath's export without options) or a single Feature.
.qupath_features <- function(doc) {
  if (is.list(doc) && identical(doc$type, "FeatureCollection")) {
    return(doc$features %||% list())
  }
  if (is.list(doc) && identical(doc$type, "Feature")) {
    return(list(doc))
  }
  if (is.list(doc) && is.null(names(doc))) {
    return(doc)
  }
  .at_abort("The document is not GeoJSON features.", code = "INVALID_GEOJSON")
}

# Label from a QuPath classification (single or derived name list).
.qupath_label <- function(cls) {
  if (is.null(cls)) {
    return("unclassified")
  }
  if (!is.null(cls[["name"]])) {
    return(as.character(cls[["name"]]))
  }
  if (!is.null(cls[["names"]]) && length(cls[["names"]]) > 0L) {
    return(paste(vapply(cls[["names"]], as.character, character(1)), collapse = ": "))
  }
  "unclassified"
}

.qupath_colour <- function(cls) {
  if (is.null(cls)) {
    return(NULL)
  }
  if (!is.null(cls[["color"]]) && length(cls[["color"]]) >= 3L) {
    v <- as.numeric(unlist(cls[["color"]]))[1:3]
    return(grDevices::rgb(v[1], v[2], v[3], maxColorValue = 255))
  }
  if (!is.null(cls[["colorRGB"]])) {
    return(.signed_int_to_hex(as.integer(cls[["colorRGB"]])))
  }
  NULL
}

# QuPath measurements -> tibble with explicit value states. QuPath writes
# non-finite values as strings ("NaN", "Infinity", "-Infinity").
.qupath_measurements <- function(ms) {
  if (is.null(ms) || length(ms) == 0L) {
    return(NULL)
  }
  vals <- lapply(ms, function(v) if (is.null(v)) NA else v)
  state <- vapply(vals, function(v) {
    if (is.character(v)) {
      switch(v, "NaN" = "nan", "Infinity" = "pos_inf", "-Infinity" = "neg_inf", "text")
    } else if (is.numeric(v) && length(v) == 1L && !is.na(v)) {
      "finite"
    } else {
      "missing"
    }
  }, character(1))
  value <- vapply(seq_along(vals), function(i) {
    switch(state[i], finite = as.numeric(vals[[i]]), nan = NaN, pos_inf = Inf,
           neg_inf = -Inf, NA_real_)
  }, numeric(1))
  tibble::tibble(name = names(ms), value = value, value_state = unname(state))
}

#' Read ROIs from a QuPath GeoJSON file
#'
#' Reads QuPath 0.4+ exports (a FeatureCollection or a bare feature array) and
#' the legacy annotatR 0.1 dialect. `classification.name` (or the joined
#' `names` of a derived class, e.g. `"Tumor: Positive"`) becomes the ROI label,
#' the classification colour the layer style colour, and features without a
#' classification are labelled `"unclassified"`. Everything else QuPath carries
#' is kept, never invented, under each ROI's `attributes$qupath`: the object
#' id and type, name, measurements (with explicit `value_state`), the image
#' plane (zero-based `c`, `z`, `t`; `c = NA` for all channels), metadata, a
#' nucleus geometry, and `roi_native = "ellipse"` with
#' `geometry_fidelity = "approximated"` for polygonised ellipses. An annotatR id
#' stored in `metadata.annotatr_roi_id` is restored as the ROI id.
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
  doc <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) {
      .at_abort("{.path {basename(path)}} is not valid JSON.", code = "INVALID_JSON", call = call)
    }
  )
  features <- .qupath_features(doc)
  lyr <- at_layer(layer_name)
  colour_map <- character()
  for (ft in features) {
    props <- ft$properties %||% list()
    cls <- props$classification
    label <- .qupath_label(cls)
    col <- .qupath_colour(cls)
    if (!is.null(col) && !label %in% names(colour_map)) {
      colour_map[[label]] <- col
    }
    geom <- ft$geometry
    if (is.null(geom) || is.null(geom$type)) {
      .at_abort("A feature has no geometry.", code = "INVALID_GEOJSON", call = call)
    }
    g <- .geojson_to_sfg(geom)
    meta <- props$metadata
    rid <- meta$annotatr_roi_id %||% ft$id %||% .new_id("roi")
    roi <- at_roi_from_sf(
      sf::st_sfc(g, crs = sf::NA_crs_), label = label, level = as.integer(level),
      id = as.character(rid), source = "imported"
    )
    qp <- list(
      object_id = if (is.null(ft$id)) NA_character_ else as.character(ft$id),
      object_type = props$objectType %||% props$object_type %||% "annotation",
      dialect = if (!is.null(props$objectType)) "qupath" else "legacy"
    )
    if (!is.null(props[["name"]])) qp$name <- as.character(props[["name"]])
    if (isTRUE(geom$isEllipse)) {
      qp$roi_native <- "ellipse"
      qp$geometry_fidelity <- "approximated"
    }
    if (!is.null(ft$nucleusGeometry)) qp$nucleus_geometry <- ft$nucleusGeometry
    if (!is.null(props$measurements)) qp$measurements <- .qupath_measurements(props$measurements)
    if (!is.null(meta)) qp$metadata <- meta
    roi$attributes$qupath <- qp
    if (!is.null(geom$plane)) {
      pc <- geom$plane$c %||% -1L
      roi$attributes$plane <- list(
        c = if (is.null(pc) || pc < 0) NA_integer_ else as.integer(pc),
        z = as.integer(geom$plane$z %||% 0L), t = as.integer(geom$plane$t %||% 0L)
      )
    }
    if (isTRUE(props$isLocked)) roi$attributes$locked <- TRUE
    lyr <- at_layer_add(lyr, roi)
  }
  # Apply recovered colours to the layer style.
  if (length(colour_map) > 0L) {
    lyr$style$colour <- .resolve_palette(lyr$labels, colour_map)
  }
  lyr
}
