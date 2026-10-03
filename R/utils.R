# Internal utilities shared across annotatR. None of these are exported.

# ---- Identifiers -----------------------------------------------------------

# Monotonic per-session counter used to mint identifiers. An environment is
# used deliberately (rather than `<<-`) to hold mutable state at package level.
.id_state <- new.env(parent = emptyenv())
.id_state$n <- 0L

# Reset the identifier counter. Exposed only for reproducible tests; not
# exported.
.reset_id_counter <- function() {
  .id_state$n <- 0L
  invisible(NULL)
}

# Mint a new identifier with the given prefix, e.g. "roi_000000001".
#
# Uses a monotonic counter rather than the random-number generator, so it never
# disturbs the caller's RNG stream and is fully deterministic within a session.
# Uniqueness within a project is additionally guaranteed on insertion, where a
# colliding identifier (e.g. from a loaded project) is re-minted.
.new_id <- function(prefix = "roi") {
  .id_state$n <- .id_state$n + 1L
  sprintf("%s_%09d", prefix, .id_state$n)
}

# Runtime and queue identities have a process-specific namespace and their own
# counters so independent R processes cannot repeat persisted IDs, and creating
# sessions or reading images cannot change the established ROI identifier
# sequence. Like .new_id(), this generator never touches R's random-number
# generator.
.identity_state <- new.env(parent = emptyenv())

.initialize_identity_state <- function() {
  rm(list = ls(envir = .identity_state, all.names = TRUE),
     envir = .identity_state)
  .identity_state$namespace <- gsub(
    "[^A-Za-z0-9._-]", "_", basename(tempfile(pattern = "at_"))
  )
  invisible(NULL)
}

.new_identity_id <- function(kind) {
  if (is.null(.identity_state$namespace)) {
    .initialize_identity_state()
  }
  n <- .identity_state[[kind]] %||% 0L
  n <- n + 1L
  .identity_state[[kind]] <- n
  sprintf("%s_%s_%09d", kind, .identity_state$namespace, n)
}

# A deterministic representation of a serializable object. Reader options are
# fingerprinted once at image-open time, rather than expanded into every tile
# cache key.
.identity_fingerprint <- function(x) {
  raw <- serialize(x, NULL, version = 2L)
  paste(sprintf("%02x", as.integer(raw)), collapse = "")
}

# ---- Time and version ------------------------------------------------------

# Current time as a length-1 POSIXct. Wrapped so the point of truth is single.
.now <- function() Sys.time()

# Installed annotatR version as a character scalar.
.pkg_version <- function() as.character(utils::packageVersion("annotatR"))

# Default author for new annotations: the `annotatR.author` option if set,
# otherwise the current system user, otherwise "unknown".
.default_author <- function() {
  opt <- getOption("annotatR.author", default = NULL)
  if (.is_string(opt)) {
    return(opt)
  }
  user <- tryCatch(Sys.info()[["user"]], error = function(e) NA_character_)
  if (.is_string(user) && nzchar(user)) user else "unknown"
}

# ---- The ROI query contract ------------------------------------------------

# The single source of truth for the tibble returned by `at_rois()` and every
# other function that yields an ROI table. Returns a 0-row tibble with exactly
# the contracted columns and column types. See `at_rois()` for the documented
# contract.
.empty_roi_tbl <- function() {
  tibble::tibble(
    roi_id     = character(0),
    layer      = character(0),
    label      = character(0),
    geom_type  = character(0),
    level      = integer(0),
    source_level = integer(0),
    area_px    = double(0),
    centroid_x = double(0),
    centroid_y = double(0),
    n_vertices = integer(0),
    created    = .empty_posixct(),
    modified   = .empty_posixct(),
    author     = character(0),
    source     = character(0),
    geometry   = sf::st_sfc(crs = sf::NA_crs_)
  )
}

# A length-0 POSIXct with a stable class, for building empty tibbles.
.empty_posixct <- function() {
  as.POSIXct(numeric(0), origin = "1970-01-01", tz = "UTC")
}

# ---- Level transforms for the query contract -------------------------------

# One transform boundary: coordinates are scaled independently on each axis.
# Identity operations need no image; a change of level always requires metadata.
.transform_geom <- function(geom, from_level, to_level, image = NULL,
                            call = rlang::caller_env()) {
  from_level <- .check_count(from_level, call = call)
  to_level <- .check_count(to_level, call = call)
  if (!is.null(image)) {
    .check_image(image, call = call)
    df <- at_dims(image, from_level, call = call)
    dt <- at_dims(image, to_level, call = call)
    valid_dims <- function(d) is.numeric(d) && length(d) == 2L &&
      all(is.finite(d)) && all(d > 0)
    if (!valid_dims(df) || !valid_dims(dt)) {
      cli::cli_abort("Image pyramid levels require finite positive dimensions.", call = call)
    }
  }
  if (from_level == to_level) return(geom)
  if (is.null(image)) {
    cli::cli_abort(
      c("Changing coordinate levels requires image pyramid dimensions.",
        "i" = "Supply an image, or explicitly use at_roi_rescale() for a power-of-two pyramid."),
      call = call)
  }
  scale <- dt / df
  out <- lapply(geom, .apply_coords,
                fun = function(m) cbind(m[, 1] * scale[1], m[, 2] * scale[2]))
  sf::st_sfc(out, crs = sf::st_crs(geom))
}

.to_level0 <- function(geom, level, image = NULL) {
  .transform_geom(geom, level, 0L, image)
}

.geom_to_level <- function(geom, level, image = NULL) {
  .transform_geom(geom, 0L, level, image)
}

# Schema marker distinguishes corrected interchange from ambiguous old exports.
.coordinate_schema <- "annotatR-pixel-level-v1"

.import_coordinate_level <- function(recorded = NULL, fallback = 0L, schema = NULL,
                                     coordinate_level = NULL, legacy_levels = "error",
                                     call = rlang::caller_env()) {
  if (!is.null(recorded)) recorded <- .check_count(recorded, call = call)
  fallback <- .check_count(fallback, call = call)
  if (!is.null(coordinate_level)) return(coordinate_level)
  if (!is.null(recorded) && recorded != 0L &&
      !identical(schema, .coordinate_schema) && legacy_levels != "recorded") {
    cli::cli_abort(
      c("Ambiguous legacy coordinate level: nonzero level without a coordinate schema.",
        "i" = "Set coordinate_level to the known coordinate level (0L for old normalized exports), or legacy_levels = 'recorded' to explicitly trust recorded levels."),
      call = call)
  }
  recorded %||% fallback
}

# Build the ROI query-contract tibble from a list of annot_roi and a matching
# vector of layer names. Coordinates, area, and centroid are expressed at level
# 0; `level` is 0 and `source_level` records the stored reference level. Returns the
# canonical 0-row tibble when `rois` is empty.
.rois_to_tbl <- function(rois, layers, image = NULL) {
  if (length(rois) == 0L) {
    return(.empty_roi_tbl())
  }
  n <- length(rois)
  geoms <- lapply(rois, function(r) .to_level0(r$geometry, r$level, image))
  geometry <- do.call(c, geoms)
  gtype <- vapply(
    geoms, function(g) as.character(sf::st_geometry_type(g)), character(1)
  )
  areal <- gtype %in% c("POLYGON", "MULTIPOLYGON")
  area <- vapply(
    seq_len(n),
    function(i) if (areal[i]) as.numeric(sf::st_area(geoms[[i]])) else NA_real_,
    numeric(1)
  )
  cen <- t(vapply(
    geoms,
    function(g) {
      co <- sf::st_coordinates(suppressWarnings(sf::st_centroid(g)))
      c(co[1, "X"], co[1, "Y"])
    },
    numeric(2)
  ))
  nv <- vapply(geoms, function(g) nrow(sf::st_coordinates(g)), integer(1))
  tibble::tibble(
    roi_id     = vapply(rois, `[[`, character(1), "id"),
    layer      = as.character(layers),
    label      = vapply(rois, `[[`, character(1), "label"),
    geom_type  = gtype,
    level      = rep.int(0L, n),
    source_level = vapply(rois, function(r) as.integer(r$level), integer(1)),
    area_px    = area,
    centroid_x = cen[, 1],
    centroid_y = cen[, 2],
    n_vertices = nv,
    created    = do.call(c, lapply(rois, `[[`, "created")),
    modified   = do.call(c, lapply(rois, `[[`, "modified")),
    author     = vapply(rois, `[[`, character(1), "author"),
    source     = vapply(rois, `[[`, character(1), "source"),
    geometry   = geometry
  )
}

# ---- Colour palette --------------------------------------------------------

# The Okabe-Ito colourblind-safe qualitative palette (8 colours), used as the
# default for ROI/label styling. Order is the canonical Okabe-Ito order,
# beginning with a neutral grey.
.okabe_ito <- function() {
  c(
    "#999999", "#E69F00", "#56B4E9", "#009E73",
    "#F0E442", "#0072B2", "#D55E00", "#CC79A7"
  )
}

# Resolve a stable label -> colour mapping. `colour` may be NULL (cycle the
# Okabe-Ito palette over the labels), a single colour (recycled), or a named or
# unnamed character vector of colours. The returned vector is always named by
# `labels` so the mapping is stable across sessions.
.resolve_palette <- function(labels, colour = NULL) {
  labels <- unique(as.character(labels))
  n <- length(labels)
  if (n == 0L) {
    out <- character(0)
    names(out) <- character(0)
    return(out)
  }
  pal <- .okabe_ito()
  if (is.null(colour)) {
    out <- pal[((seq_len(n) - 1L) %% length(pal)) + 1L]
    names(out) <- labels
    return(out)
  }
  nms <- names(colour)
  colour <- as.character(colour)
  names(colour) <- nms
  if (!is.null(names(colour))) {
    out <- rep(pal[1], n)
    names(out) <- labels
    common <- intersect(labels, names(colour))
    out[common] <- colour[common]
    # Fill any labels not named in `colour` by cycling the palette.
    missing <- setdiff(labels, names(colour))
    if (length(missing)) {
      idx <- match(missing, labels)
      out[missing] <- pal[((idx - 1L) %% length(pal)) + 1L]
    }
    return(out)
  }
  out <- rep(colour, length.out = n)
  names(out) <- labels
  out
}

# ---- Geometry orientation --------------------------------------------------

# Flip the y-axis of an sfc between image orientation (top-left origin, y down)
# and GIS orientation (bottom-left origin, y up), given the image height in
# pixels. Self-inverse. Internal; used at the boundaries with GIS-oriented
# tooling. `height` is the extent along y at the geometry's reference level.
.flip_y <- function(geom, height) {
  stopifnot(inherits(geom, "sfc"))
  flip <- function(m) {
    m[, 2] <- height - m[, 2]
    m
  }
  out <- lapply(geom, .apply_coords, fun = flip)
  sf::st_sfc(out, crs = sf::st_crs(geom))
}

# Apply a coordinate-matrix transform `fun` to every ring/part of a single
# sfg geometry, preserving its type. Handles POINT, MULTIPOINT, LINESTRING,
# POLYGON, MULTILINESTRING, and MULTIPOLYGON.
.apply_coords <- function(g, fun) {
  type <- as.character(sf::st_geometry_type(sf::st_sfc(g)))
  switch(
    type,
    "POINT"           = sf::st_point(fun(matrix(unclass(g), nrow = 1))),
    "MULTIPOINT"      = sf::st_multipoint(fun(unclass(g))),
    "LINESTRING"      = sf::st_linestring(fun(unclass(g))),
    "MULTILINESTRING" = sf::st_multilinestring(lapply(g, fun)),
    "POLYGON"         = sf::st_polygon(lapply(g, fun)),
    "MULTIPOLYGON"    = sf::st_multipolygon(lapply(g, function(p) lapply(p, fun))),
    cli::cli_abort("Unsupported geometry type {.val {type}} in {.fn .apply_coords}.")
  )
}

# ---- Small helpers ---------------------------------------------------------

# Vector-safe test for a single non-missing string.
.is_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x)

# Coerce to integer, erroring on loss. Internal convenience.
.as_count <- function(x) {
  xi <- suppressWarnings(as.integer(round(x)))
  xi
}
