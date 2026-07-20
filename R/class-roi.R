# The annot_roi class: a single region of interest. Geometry is an `sf` simple
# feature stored in image pixel coordinates at a declared pyramid level.
#
# COORDINATE CONVENTION (important, and documented loudly for users): geometry
# is stored in a null-CRS `sfc` with the image raster convention — origin at the
# top-left corner, x increasing rightward, y increasing DOWNWARD. This is the
# opposite of the GIS convention (y up). Use `at_flip_y()` at the boundary with
# GIS-oriented tooling.

# ---- Internal constructor --------------------------------------------------

new_annot_roi <- function(geometry,
                          id,
                          label,
                          level,
                          attributes = list(),
                          created = .now(),
                          modified = .now(),
                          author = .default_author(),
                          source = "manual") {
  structure(
    list(
      geometry   = geometry,
      id         = as.character(id),
      label      = as.character(label),
      level      = as.integer(level),
      attributes = attributes,
      created    = created,
      modified   = modified,
      author     = as.character(author),
      source     = as.character(source)
    ),
    class = "annot_roi"
  )
}

# Coerce/validate an incoming geometry to a length-1, null-CRS sfc, repairing
# invalid geometries with a warning.
.finalize_geometry <- function(g, arg = "geometry", call = rlang::caller_env()) {
  if (inherits(g, "sf")) {
    g <- sf::st_geometry(g)
  }
  if (inherits(g, "sfg")) {
    g <- sf::st_sfc(g)
  }
  if (!inherits(g, "sfc")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be an {.pkg sf} geometry ({.cls sfc}, {.cls sfg}, or {.cls sf}).",
        "x" = "You supplied {.cls {class(g)[1]}}."
      ),
      call = call
    )
  }
  suppressWarnings(sf::st_crs(g) <- sf::NA_crs_)
  if (length(g) > 1L) {
    g <- sf::st_sfc(sf::st_combine(g)[[1]], crs = sf::NA_crs_)
  }
  valid <- sf::st_is_valid(g)
  if (!isTRUE(valid)) {
    g <- sf::st_make_valid(g)
    suppressWarnings(sf::st_crs(g) <- sf::NA_crs_)
    cli::cli_warn(
      c(
        "Repaired an invalid geometry in {.arg {arg}}.",
        "i" = "Applied {.fn sf::st_make_valid}; check the result if precise vertices matter."
      )
    )
  }
  g
}

# Assemble an annot_roi from a finalised geometry plus the shared `...` handling.
.build_roi <- function(geometry, label, level, dots, call = rlang::caller_env()) {
  .check_string(label, call = call)
  level <- .check_count(level, call = call)
  g <- .finalize_geometry(geometry, call = call)
  author <- dots$author %||% .default_author()
  source <- dots$source %||% "manual"
  id     <- dots$id %||% .new_id("roi")
  attrs  <- dots[setdiff(names(dots), c("author", "source", "id"))]
  if (is.null(names(dots))) attrs <- list()
  new_annot_roi(
    geometry = g, id = id, label = label, level = level,
    attributes = attrs, author = author, source = source
  )
}

# Close a coordinate ring if it is not already closed.
.close_ring <- function(m) {
  if (!isTRUE(all.equal(m[1, ], m[nrow(m), ]))) {
    m <- rbind(m, m[1, , drop = FALSE])
  }
  m
}

# ---- Exported constructors -------------------------------------------------

#' Create a point ROI
#'
#' @param x,y Numeric coordinates of the point, in image pixels.
#' @param label Single string class label.
#' @param level Integer pyramid level the coordinates refer to. Default `0`.
#' @param ... Additional named attributes stored on the ROI. The reserved names
#'   `author`, `source`, and `id` set those fields; all others become
#'   user attributes.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_roi] with `POINT` geometry.
#' @family rois
#' @seealso [at_roi_rect()], [at_roi_polygon()]
#' @export
#' @examples
#' r <- at_roi_point(10, 20, label = "cell")
#' at_roi_centroid(r)
at_roi_point <- function(x, y, label, level = 0L, ..., call = rlang::caller_env()) {
  .check_number(x, call = call)
  .check_number(y, call = call)
  g <- sf::st_sfc(sf::st_point(c(x, y)), crs = sf::NA_crs_)
  .build_roi(g, label, level, list(...), call = call)
}

#' Create a rectangular ROI
#'
#' @param xmin,ymin,xmax,ymax Numeric bounds in image pixels. `xmax`/`ymax` must
#'   exceed `xmin`/`ymin`.
#' @inheritParams at_roi_point
#'
#' @return An [annot_roi] with `POLYGON` geometry (an axis-aligned rectangle).
#' @family rois
#' @export
#' @examples
#' r <- at_roi_rect(0, 0, 10, 5, label = "tissue")
#' at_roi_bbox(r)
at_roi_rect <- function(xmin, ymin, xmax, ymax, label, level = 0L, ...,
                        call = rlang::caller_env()) {
  .check_number(xmin, call = call)
  .check_number(ymin, call = call)
  .check_number(xmax, call = call)
  .check_number(ymax, call = call)
  if (xmax <= xmin || ymax <= ymin) {
    cli::cli_abort(
      c(
        "Rectangle bounds must satisfy {.arg xmax} > {.arg xmin} and {.arg ymax} > {.arg ymin}.",
        "x" = "Got x [{xmin}, {xmax}], y [{ymin}, {ymax}]."
      ),
      call = call
    )
  }
  ring <- rbind(
    c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
  )
  g <- sf::st_sfc(sf::st_polygon(list(ring)), crs = sf::NA_crs_)
  .build_roi(g, label, level, list(...), call = call)
}

#' Create a circular ROI
#'
#' The circle is approximated by a regular polygon of `n_seg` segments.
#'
#' @param x,y Numeric centre coordinates in image pixels.
#' @param r Positive numeric radius in pixels.
#' @param n_seg Integer number of polygon segments approximating the circle.
#' @inheritParams at_roi_point
#'
#' @return An [annot_roi] with `POLYGON` geometry.
#' @family rois
#' @export
#' @examples
#' r <- at_roi_circle(50, 50, r = 10, label = "nucleus")
at_roi_circle <- function(x, y, r, label, level = 0L, n_seg = 64L, ...,
                          call = rlang::caller_env()) {
  .check_number(x, call = call)
  .check_number(y, call = call)
  .check_number(r, min = .Machine$double.eps, call = call)
  n_seg <- .check_count(n_seg, min = 3L, call = call)
  ang <- seq(0, 2 * pi, length.out = n_seg + 1L)
  ring <- cbind(x + r * cos(ang), y + r * sin(ang))
  ring[nrow(ring), ] <- ring[1, ]
  g <- sf::st_sfc(sf::st_polygon(list(ring)), crs = sf::NA_crs_)
  .build_roi(g, label, level, list(...), call = call)
}

#' Create an elliptical ROI
#'
#' @param x,y Numeric centre coordinates in image pixels.
#' @param rx,ry Positive numeric semi-axis lengths in pixels.
#' @param rotation Rotation of the major axis in degrees, clockwise in image
#'   orientation. Default `0`.
#' @param n_seg Integer number of polygon segments approximating the ellipse.
#' @inheritParams at_roi_point
#'
#' @return An [annot_roi] with `POLYGON` geometry.
#' @family rois
#' @export
#' @examples
#' r <- at_roi_ellipse(50, 50, rx = 20, ry = 10, rotation = 30, label = "cell")
at_roi_ellipse <- function(x, y, rx, ry, rotation = 0, label, level = 0L,
                           n_seg = 64L, ..., call = rlang::caller_env()) {
  .check_number(x, call = call)
  .check_number(y, call = call)
  .check_number(rx, min = .Machine$double.eps, call = call)
  .check_number(ry, min = .Machine$double.eps, call = call)
  .check_number(rotation, call = call)
  n_seg <- .check_count(n_seg, min = 3L, call = call)
  ang <- seq(0, 2 * pi, length.out = n_seg + 1L)
  dx <- rx * cos(ang)
  dy <- ry * sin(ang)
  th <- rotation * pi / 180
  rxs <- x + dx * cos(th) - dy * sin(th)
  rys <- y + dx * sin(th) + dy * cos(th)
  ring <- cbind(rxs, rys)
  ring[nrow(ring), ] <- ring[1, ]
  g <- sf::st_sfc(sf::st_polygon(list(ring)), crs = sf::NA_crs_)
  .build_roi(g, label, level, list(...), call = call)
}

#' Create a polygon ROI
#'
#' @param coords Either a two-column numeric matrix of exterior-ring vertices,
#'   or a list of such matrices where the first is the exterior ring and any
#'   others are holes. Rings are closed automatically.
#' @param hole Optional list of two-column matrices giving additional holes,
#'   combined with any holes supplied via `coords`.
#' @inheritParams at_roi_point
#'
#' @return An [annot_roi] with `POLYGON` geometry.
#' @family rois
#' @export
#' @examples
#' sq <- matrix(c(0, 0, 10, 0, 10, 10, 0, 10), ncol = 2, byrow = TRUE)
#' r <- at_roi_polygon(sq, label = "region")
at_roi_polygon <- function(coords, label, level = 0L, hole = NULL, ...,
                           call = rlang::caller_env()) {
  rings <- if (is.matrix(coords)) list(coords) else coords
  if (!is.list(rings) || !all(vapply(rings, is.matrix, logical(1)))) {
    cli::cli_abort(
      c(
        "{.arg coords} must be a numeric matrix or a list of numeric matrices.",
        "x" = "You supplied {.cls {class(coords)[1]}}."
      ),
      call = call
    )
  }
  if (!is.null(hole)) {
    hole <- if (is.matrix(hole)) list(hole) else hole
    rings <- c(rings, hole)
  }
  rings <- lapply(rings, function(m) .close_ring(as.matrix(m)))
  g <- sf::st_sfc(sf::st_polygon(rings), crs = sf::NA_crs_)
  .build_roi(g, label, level, list(...), call = call)
}

#' Create a freehand ROI
#'
#' A freehand trace is stored as a closed polygon, optionally simplified.
#'
#' @param coords Two-column numeric matrix of vertices in drawing order.
#' @param simplify Non-negative Douglas-Peucker tolerance (`dTolerance`) applied
#'   to the closed polygon. `0` (default) keeps every vertex.
#' @inheritParams at_roi_point
#'
#' @return An [annot_roi] with `POLYGON` geometry.
#' @family rois
#' @export
#' @examples
#' pts <- cbind(c(0, 5, 10, 5), c(0, 2, 0, -2))
#' r <- at_roi_freehand(pts, label = "trace")
at_roi_freehand <- function(coords, label, level = 0L, simplify = 0, ...,
                            call = rlang::caller_env()) {
  if (!is.matrix(coords) || ncol(coords) != 2L || nrow(coords) < 3L) {
    cli::cli_abort(
      c(
        "{.arg coords} must be a two-column matrix with at least 3 rows.",
        "x" = "You supplied {.cls {class(coords)[1]}} with dim {.val {dim(coords)}}."
      ),
      call = call
    )
  }
  .check_number(simplify, min = 0, call = call)
  ring <- .close_ring(coords)
  g <- sf::st_sfc(sf::st_polygon(list(ring)), crs = sf::NA_crs_)
  if (simplify > 0) {
    g <- sf::st_simplify(g, dTolerance = simplify, preserveTopology = TRUE)
  }
  .build_roi(g, label, level, list(...), call = call)
}

#' Create an ROI from an existing sf geometry
#'
#' @param geometry An `sf`, `sfc`, or `sfg` geometry in image pixel coordinates.
#' @inheritParams at_roi_point
#'
#' @return An [annot_roi] wrapping the supplied geometry.
#' @family rois
#' @export
#' @examples
#' g <- sf::st_point(c(3, 4))
#' r <- at_roi_from_sf(g, label = "imported", source = "imported")
at_roi_from_sf <- function(geometry, label, level = 0L, ...,
                           call = rlang::caller_env()) {
  .build_roi(geometry, label, level, list(...), call = call)
}

# ---- Rescaling and transforms ----------------------------------------------

# Rescale an sfc between pyramid levels assuming a power-of-two pyramid.
# Level transforms against a real (possibly non-power-of-two) pyramid use
# at_transform() with the annot_image dimensions.
.rescale_geom <- function(geom, from_level, to_level) {
  if (from_level == to_level) {
    return(geom)
  }
  factor <- 2^(from_level - to_level)
  out <- lapply(geom, .apply_coords, fun = function(m) m * factor)
  sf::st_sfc(out, crs = sf::st_crs(geom))
}

#' Rescale an ROI between pyramid levels
#'
#' Transform an ROI's coordinates from one pyramid level to another, assuming a
#' power-of-two pyramid. For an exact transform against a real image pyramid
#' (which need not be power-of-two), use `at_transform()` with the
#' [annot_image].
#'
#' @param roi An [annot_roi].
#' @param from_level,to_level Integer source and target pyramid levels.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_roi] with coordinates at `to_level` and its `level` field
#'   set to `to_level`. The transform is exactly invertible.
#' @family geometry
#' @seealso `at_transform()`
#' @export
#' @examples
#' r <- at_roi_rect(0, 0, 100, 100, label = "a")
#' r2 <- at_roi_rescale(r, from_level = 0, to_level = 2)
#' identical(
#'   sf::st_coordinates(sf::st_geometry(r)),
#'   sf::st_coordinates(sf::st_geometry(at_roi_rescale(r2, 2, 0)))
#' )
at_roi_rescale <- function(roi, from_level, to_level, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  from_level <- .check_count(from_level, call = call)
  to_level <- .check_count(to_level, call = call)
  g <- .rescale_geom(roi$geometry, from_level, to_level)
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = to_level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

# ---- Measurements ----------------------------------------------------------

# TRUE for areal geometry types (polygonal).
.is_areal <- function(g) {
  as.character(sf::st_geometry_type(g)) %in% c("POLYGON", "MULTIPOLYGON")
}

#' ROI area
#'
#' @param roi An [annot_roi].
#' @param level Integer pyramid level at which to express the area. Default `0`.
#' @param units Either `"px"` (pixels squared, the default) or `"physical"`.
#'   Physical units require a `pixel_size` attribute on the ROI.
#' @param call The calling environment, for error reporting.
#'
#' @return A numeric scalar area, or `NA_real_` for non-areal geometry (points,
#'   lines).
#' @family rois
#' @export
#' @examples
#' at_roi_area(at_roi_rect(0, 0, 10, 5, label = "a"))
at_roi_area <- function(roi, level = 0L, units = c("px", "physical"),
                        call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  level <- .check_count(level, call = call)
  units <- .check_choice(units, c("px", "physical"), call = call)
  if (!.is_areal(roi$geometry)) {
    return(NA_real_)
  }
  g <- .rescale_geom(roi$geometry, roi$level, level)
  a <- as.numeric(sf::st_area(g))
  if (units == "physical") {
    ps <- roi$attributes$pixel_size
    if (is.null(ps)) {
      cli::cli_abort(
        c(
          "Physical area requires a {.field pixel_size} attribute on the ROI.",
          "i" = "Attach it via the {.arg ...} of a constructor, or use pixel units."
        ),
        call = call
      )
    }
    a <- a * prod(ps)
  }
  a
}

#' ROI centroid
#'
#' @param roi An [annot_roi].
#' @param call The calling environment, for error reporting.
#' @return A numeric vector `c(x, y)` in the ROI's stored coordinates (at its
#'   own `level`).
#' @family rois
#' @export
#' @examples
#' at_roi_centroid(at_roi_rect(0, 0, 10, 10, label = "a"))
at_roi_centroid <- function(roi, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  co <- sf::st_coordinates(sf::st_centroid(roi$geometry))
  as.numeric(co[1, c("X", "Y")])
}

#' ROI bounding box
#'
#' @param roi An [annot_roi].
#' @param call The calling environment, for error reporting.
#' @return A numeric vector `c(xmin, ymin, xmax, ymax)` in the ROI's stored
#'   coordinates.
#' @family rois
#' @export
#' @examples
#' at_roi_bbox(at_roi_circle(50, 50, 10, label = "a"))
at_roi_bbox <- function(roi, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  bb <- sf::st_bbox(roi$geometry)
  as.numeric(bb[c("xmin", "ymin", "xmax", "ymax")])
}

#' Buffer an ROI
#'
#' @param roi An [annot_roi].
#' @param dist Numeric buffer distance in pixels (may be negative to erode).
#' @param call The calling environment, for error reporting.
#' @return An [annot_roi] with the buffered geometry.
#' @family rois
#' @export
#' @examples
#' at_roi_buffer(at_roi_point(10, 10, label = "a"), dist = 5)
at_roi_buffer <- function(roi, dist, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  .check_number(dist, call = call)
  g <- sf::st_buffer(roi$geometry, dist = dist)
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = roi$level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

#' Simplify an ROI
#'
#' @param roi An [annot_roi].
#' @param tolerance Non-negative Douglas-Peucker tolerance (`dTolerance`).
#' @param call The calling environment, for error reporting.
#' @return An [annot_roi] with simplified geometry.
#' @family rois
#' @export
#' @examples
#' at_roi_simplify(at_roi_circle(50, 50, 10, n_seg = 128, label = "a"), 1)
at_roi_simplify <- function(roi, tolerance, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  .check_number(tolerance, min = 0, call = call)
  g <- sf::st_simplify(roi$geometry, dTolerance = tolerance, preserveTopology = TRUE)
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = roi$level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

# ---- S3 methods ------------------------------------------------------------

#' @export
format.annot_roi <- function(x, ...) {
  gtype <- as.character(sf::st_geometry_type(x$geometry))
  bb <- as.numeric(sf::st_bbox(x$geometry))
  c(
    cli::format_inline("{.cls annot_roi} {.field {x$label}} ({gtype})"),
    cli::format_inline("id: {.val {x$id}}  |  level: {x$level}  |  source: {x$source}"),
    cli::format_inline(
      "bbox: [{round(bb[1],1)}, {round(bb[2],1)}] - [{round(bb[3],1)}, {round(bb[4],1)}]"
    )
  )
}

#' @export
print.annot_roi <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

#' Plot an ROI
#'
#' @param x An [annot_roi].
#' @param ... Ignored.
#' @return A [ggplot2::ggplot] object. The plot is not drawn; print it to render.
#' @keywords internal
#' @export
plot.annot_roi <- function(x, ...) {
  sfobj <- sf::st_sf(label = x$label, geometry = x$geometry)
  ggplot2::ggplot(sfobj) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data$label), alpha = 0.4) +
    ggplot2::scale_y_reverse() +
    ggplot2::coord_sf(default_crs = NULL) +
    ggplot2::labs(title = paste0("ROI: ", x$label), x = "x (px)", y = "y (px)") +
    ggplot2::theme_minimal()
}

#' @exportS3Method sf::st_geometry
st_geometry.annot_roi <- function(obj, ...) {
  obj$geometry
}

#' @exportS3Method sf::st_as_sf
st_as_sf.annot_roi <- function(x, ...) {
  sf::st_sf(
    roi_id = x$id,
    label = x$label,
    level = x$level,
    author = x$author,
    source = x$source,
    geometry = x$geometry
  )
}
