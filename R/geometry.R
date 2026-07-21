# Geometry operations on ROIs: exact level transforms, set operations, spatial
# predicates, and validity checking / repair. Thin, well-documented wrappers
# over `sf` that preserve the annot_roi class and metadata.

# ---- Coordinate transforms -------------------------------------------------

#' Transform an ROI between pyramid levels using real image dimensions
#'
#' Unlike [at_roi_rescale()] (which assumes a power-of-two pyramid), this uses
#' the actual level dimensions of an [annot_image], so it is exact for pyramids
#' with any downsampling ratio.
#'
#' @param roi An [annot_roi].
#' @param from_level,to_level Integer source and target pyramid levels.
#' @param img The [annot_image] whose pyramid defines the level dimensions.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_roi] with coordinates at `to_level`. Exactly invertible.
#' @family geometry
#' @seealso [at_roi_rescale()]
#' @export
#' @examplesIf requireNamespace("tiff", quietly = TRUE)
#' img <- at_example_image("multiplex")
#' r <- at_roi_rect(0, 0, 100, 100, label = "a")
#' at_transform(r, from_level = 0, to_level = 2, img = img)
at_transform <- function(roi, from_level, to_level, img, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  .check_image(img, call = call)
  from_level <- .check_count(from_level, call = call)
  to_level <- .check_count(to_level, call = call)
  maxl <- img$n_levels - 1L
  if (from_level > maxl || to_level > maxl) {
    cli::cli_abort(
      c("Levels must be within the image pyramid.",
        "x" = "Levels {.val {c(from_level, to_level)}} requested; max is {maxl}."),
      call = call
    )
  }
  df <- img$level_dims[[from_level + 1L]]
  dt <- img$level_dims[[to_level + 1L]]
  fx <- dt[1] / df[1]
  fy <- dt[2] / df[2]
  out <- lapply(roi$geometry, .apply_coords,
                fun = function(m) cbind(m[, 1] * fx, m[, 2] * fy))
  g <- sf::st_sfc(out, crs = sf::NA_crs_)
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = to_level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

#' Flip an ROI's y-axis
#'
#' Convert between image orientation (top-left origin, y down) and GIS
#' orientation (bottom-left origin, y up). Self-inverse.
#'
#' @param roi An [annot_roi].
#' @param height Numeric image height in pixels at the ROI's reference level.
#' @param call The calling environment, for error reporting.
#' @return An [annot_roi] with the y-axis flipped.
#' @family geometry
#' @export
#' @examples
#' at_flip_y(at_roi_rect(0, 0, 10, 5, label = "a"), height = 100)
at_flip_y <- function(roi, height, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  .check_number(height, call = call)
  g <- .flip_y(roi$geometry, height)
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = roi$level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

#' Snap ROI vertices to a grid
#'
#' @param roi An [annot_roi].
#' @param grid Positive numeric grid spacing in pixels. Default `1`.
#' @param call The calling environment, for error reporting.
#' @return An [annot_roi] with vertices rounded to the nearest grid multiple.
#' @family geometry
#' @export
#' @examples
#' at_snap(at_roi_point(3.4, 5.6, label = "a"), grid = 1)
at_snap <- function(roi, grid = 1, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  .check_number(grid, min = .Machine$double.eps, call = call)
  out <- lapply(roi$geometry, .apply_coords, fun = function(m) round(m / grid) * grid)
  g <- sf::st_sfc(out, crs = sf::NA_crs_)
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = roi$level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

#' Clip an ROI to image bounds
#'
#' @param roi An [annot_roi].
#' @param dims Integer `c(width, height)` bounds in pixels.
#' @param call The calling environment, for error reporting.
#' @return An [annot_roi] clipped to `[0, width] x [0, height]`. Warns if the
#'   clip empties the geometry.
#' @family geometry
#' @export
#' @examples
#' at_clamp(at_roi_rect(-5, -5, 20, 20, label = "a"), dims = c(10, 10))
at_clamp <- function(roi, dims, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  if (!is.numeric(dims) || length(dims) != 2L) {
    cli::cli_abort("{.arg dims} must be a length-2 numeric vector.", call = call)
  }
  rect <- sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(0, 0), c(dims[1], 0), c(dims[1], dims[2]), c(0, dims[2]), c(0, 0)
    ))),
    crs = sf::NA_crs_
  )
  g <- suppressWarnings(sf::st_intersection(roi$geometry, rect))
  if (length(g) == 0L || all(sf::st_is_empty(g))) {
    cli::cli_warn("Clipping {.val {roi$id}} to bounds produced an empty geometry.")
    g <- sf::st_sfc(sf::st_polygon(), crs = sf::NA_crs_)
  }
  new_annot_roi(
    geometry = g, id = roi$id, label = roi$label, level = roi$level,
    attributes = roi$attributes, created = roi$created, modified = .now(),
    author = roi$author, source = roi$source
  )
}

# ---- Set operations --------------------------------------------------------

# Collect ROIs from `...` (each an annot_roi) or a single annot_layer.
.collect_rois <- function(args, call = rlang::caller_env()) {
  if (length(args) == 1L && inherits(args[[1]], "annot_layer")) {
    return(args[[1]]$rois)
  }
  ok <- vapply(args, inherits, logical(1), "annot_roi")
  if (!all(ok)) {
    cli::cli_abort(
      "Arguments must all be {.cls annot_roi} objects, or a single {.cls annot_layer}.",
      call = call
    )
  }
  args
}

# Build a derived annot_roi from a result geometry, inheriting a template's
# label, level, and author.
.roi_from_geom <- function(g, template, source = "derived") {
  new_annot_roi(
    geometry = .finalize_geometry(g), id = .new_id("roi"),
    label = template$label, level = template$level,
    attributes = template$attributes, author = template$author, source = source
  )
}

#' Set operations on ROIs
#'
#' Combine ROIs geometrically. Each accepts several [annot_roi] via `...`, or a
#' single [annot_layer]. Multi-part results are returned as one ROI with
#' `MULTIPOLYGON` geometry (the return type is always a single [annot_roi]).
#'
#' @param ... Two or more [annot_roi], or a single [annot_layer].
#' @param call The calling environment, for error reporting.
#' @return A single [annot_roi] with `source = "derived"`.
#' @name at_roi_setops
#' @family geometry
#' @examples
#' a <- at_roi_rect(0, 0, 6, 6, label = "x")
#' b <- at_roi_rect(4, 4, 10, 10, label = "x")
#' at_roi_area(at_roi_intersect(a, b))
NULL

#' @rdname at_roi_setops
#' @export
at_roi_union <- function(..., call = rlang::caller_env()) {
  rois <- .collect_rois(list(...), call = call)
  if (length(rois) == 0L) {
    cli::cli_abort("{.fn at_roi_union} needs at least one ROI.", call = call)
  }
  geoms <- do.call(c, lapply(rois, `[[`, "geometry"))
  .roi_from_geom(sf::st_union(geoms), rois[[1]])
}

#' @rdname at_roi_setops
#' @export
at_roi_intersect <- function(..., call = rlang::caller_env()) {
  rois <- .collect_rois(list(...), call = call)
  if (length(rois) == 0L) {
    cli::cli_abort("{.fn at_roi_intersect} needs at least one ROI.", call = call)
  }
  g <- rois[[1]]$geometry
  for (r in rois[-1]) {
    g <- suppressWarnings(sf::st_intersection(g, r$geometry))
  }
  .roi_from_geom(g, rois[[1]])
}

#' @rdname at_roi_setops
#' @export
at_roi_difference <- function(..., call = rlang::caller_env()) {
  rois <- .collect_rois(list(...), call = call)
  if (length(rois) < 2L) {
    cli::cli_abort("{.fn at_roi_difference} needs at least two ROIs.", call = call)
  }
  rest <- do.call(c, lapply(rois[-1], `[[`, "geometry"))
  g <- suppressWarnings(sf::st_difference(rois[[1]]$geometry, sf::st_union(rest)))
  .roi_from_geom(g, rois[[1]])
}

#' @rdname at_roi_setops
#' @export
at_roi_symdiff <- function(..., call = rlang::caller_env()) {
  rois <- .collect_rois(list(...), call = call)
  if (length(rois) < 2L) {
    cli::cli_abort("{.fn at_roi_symdiff} needs at least two ROIs.", call = call)
  }
  g <- rois[[1]]$geometry
  for (r in rois[-1]) {
    g <- suppressWarnings(sf::st_sym_difference(g, r$geometry))
  }
  .roi_from_geom(g, rois[[1]])
}

#' Ring (annulus) along an ROI margin
#'
#' Build a band straddling an ROI's boundary -- the natural shape for a
#' "penumbra" region along an injury or wound margin. The ring extends `outer`
#' units outside the boundary and `inner` units inside it, formed as the set
#' difference of the outward and inward buffers.
#'
#' @param roi An [annot_roi].
#' @param outer Non-negative outward width (dilation) of the ring.
#' @param inner Non-negative inward width (erosion) of the ring. Default `0`, a
#'   purely external band.
#' @param label Label for the derived ring ROI. Default the source ROI's label.
#' @param call The calling environment, for error reporting.
#' @return A derived [annot_roi] (an annulus) with `source = "derived"`.
#' @family geometry
#' @seealso [at_roi_buffer()], [at_roi_difference()]
#' @export
#' @examples
#' inj <- at_roi_rect(10, 10, 20, 20, label = "injury")
#' at_roi_ring(inj, outer = 3, label = "penumbra")
at_roi_ring <- function(roi, outer, inner = 0, label = roi$label,
                        call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  .check_number(outer, min = 0, call = call)
  .check_number(inner, min = 0, call = call)
  outer_roi <- at_roi_buffer(roi, outer)
  inner_roi <- at_roi_buffer(roi, -inner)
  ring <- at_roi_difference(outer_roi, inner_roi, call = call)
  ring$label <- as.character(label)
  ring$source <- "derived"
  ring
}

# ---- Predicates ------------------------------------------------------------

#' Test whether points fall inside an ROI
#'
#' @param roi An [annot_roi].
#' @param x,y Numeric coordinate vectors of equal length.
#' @param call The calling environment, for error reporting.
#' @return A logical vector of length `length(x)`.
#' @family geometry
#' @export
#' @examples
#' at_roi_contains(at_roi_rect(0, 0, 10, 10, label = "a"), c(5, 20), c(5, 20))
at_roi_contains <- function(roi, x, y, call = rlang::caller_env()) {
  .check_roi(roi, call = call)
  if (length(x) != length(y)) {
    cli::cli_abort("{.arg x} and {.arg y} must have the same length.", call = call)
  }
  if (length(x) == 0L) {
    return(logical(0))
  }
  pts <- sf::st_sfc(lapply(seq_along(x), function(i) sf::st_point(c(x[i], y[i]))),
                    crs = sf::NA_crs_)
  lengths(suppressMessages(sf::st_intersects(pts, roi$geometry))) > 0L
}

#' Test whether two ROIs intersect
#'
#' @param roi1,roi2 [annot_roi] objects.
#' @param call The calling environment, for error reporting.
#' @return A logical scalar.
#' @family geometry
#' @export
at_roi_overlaps <- function(roi1, roi2, call = rlang::caller_env()) {
  .check_roi(roi1, arg = "roi1", call = call)
  .check_roi(roi2, arg = "roi2", call = call)
  g1 <- .to_level0(roi1$geometry, roi1$level)
  g2 <- .to_level0(roi2$geometry, roi2$level)
  length(suppressMessages(sf::st_intersects(g1, g2)[[1]])) > 0L
}

#' Distance between two ROIs
#'
#' @param roi1,roi2 [annot_roi] objects.
#' @param call The calling environment, for error reporting.
#' @return A numeric scalar distance in level-0 pixels.
#' @family geometry
#' @export
at_roi_distance <- function(roi1, roi2, call = rlang::caller_env()) {
  .check_roi(roi1, arg = "roi1", call = call)
  .check_roi(roi2, arg = "roi2", call = call)
  g1 <- .to_level0(roi1$geometry, roi1$level)
  g2 <- .to_level0(roi2$geometry, roi2$level)
  as.numeric(sf::st_distance(g1, g2)[1, 1])
}

#' Pairwise ROI overlaps within a layer
#'
#' @param layer An [annot_layer].
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with columns `id_a`, `id_b` (character),
#'   `overlap_px` (double, level-0 pixels), and `jaccard` (double). A 0-row
#'   tibble with these columns when no ROIs overlap.
#' @family geometry
#' @export
at_rois_overlap <- function(layer, call = rlang::caller_env()) {
  .check_layer(layer, call = call)
  empty <- tibble::tibble(
    id_a = character(0), id_b = character(0),
    overlap_px = double(0), jaccard = double(0)
  )
  rois <- layer$rois
  n <- length(rois)
  if (n < 2L) {
    return(empty)
  }
  geoms <- lapply(rois, function(r) .to_level0(r$geometry, r$level))
  rows <- list()
  for (i in seq_len(n - 1L)) {
    for (j in (i + 1L):n) {
      inter <- suppressWarnings(sf::st_intersection(geoms[[i]], geoms[[j]]))
      a <- if (length(inter) == 0L) 0 else sum(as.numeric(sf::st_area(inter)))
      if (a > 0) {
        uni <- sum(as.numeric(sf::st_area(suppressWarnings(sf::st_union(geoms[[i]], geoms[[j]])))))
        rows[[length(rows) + 1L]] <- tibble::tibble(
          id_a = rois[[i]]$id, id_b = rois[[j]]$id,
          overlap_px = a, jaccard = a / uni
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(empty)
  }
  do.call(rbind, rows)
}

# ---- Validity checking and repair ------------------------------------------

# Signed area of a coordinate ring (shoelace).
.ring_signed_area <- function(ring) {
  n <- nrow(ring)
  if (n < 3L) {
    return(0)
  }
  x <- ring[, 1]
  y <- ring[, 2]
  j <- c(seq_len(n)[-1], 1L)
  sum(x * y[j] - x[j] * y) / 2
}

# Detect issues on a single (possibly raw/broken) geometry.
.geometry_issues <- function(g, dims = NULL) {
  issues <- character()
  fixable <- logical()
  severity <- character()
  add <- function(issue, sev, fix) {
    issues[[length(issues) + 1L]] <<- issue
    severity[[length(severity) + 1L]] <<- sev
    fixable[[length(fixable) + 1L]] <<- fix
  }
  co <- tryCatch(sf::st_coordinates(g), error = function(e) NULL)
  xy <- if (is.null(co)) NULL else co[, c("X", "Y"), drop = FALSE]
  areal <- as.character(sf::st_geometry_type(g)) %in% c("POLYGON", "MULTIPOLYGON")
  if (!is.null(xy) && anyNA(xy)) {
    add("na_coordinates", "error", FALSE)
  }
  reason <- tryCatch(sf::st_is_valid(g, reason = TRUE), error = function(e) "unknown")
  if (!identical(reason, "Valid Geometry") && !is.na(reason)) {
    if (grepl("self.?intersection", reason, ignore.case = TRUE)) {
      add("self_intersection", "error", TRUE)
    } else {
      add("invalid_geometry", "error", TRUE)
    }
  }
  if (areal && !is.null(xy) && !anyNA(xy)) {
    ar <- tryCatch(as.numeric(sf::st_area(g)), error = function(e) NA_real_)
    if (isTRUE(ar == 0)) {
      add("zero_area", "error", FALSE)
    }
    ndist <- nrow(unique(round(xy, 9)))
    if (ndist < 3L) {
      add("degenerate", "error", FALSE)
    }
    # Holes should wind opposite to the exterior ring (RFC 7946 convention).
    if (as.character(sf::st_geometry_type(g)) == "POLYGON") {
      poly <- g[[1]] # sfg POLYGON: a list of ring coordinate matrices
      if (length(poly) > 1L) {
        s <- vapply(poly, .ring_signed_area, numeric(1))
        if (any(sign(s[-1]) == sign(s[1]) & s[-1] != 0)) {
          add("ring_orientation", "warning", TRUE)
        }
      }
    }
  }
  if (!is.null(xy) && nrow(xy) >= 2L) {
    d <- rowSums(abs(diff(xy)))
    if (length(d) >= 2L && any(d[-length(d)] == 0, na.rm = TRUE)) {
      add("duplicate_vertices", "warning", TRUE)
    }
  }
  if (!is.null(dims) && !is.null(xy)) {
    oob <- any(xy[, 1] < 0 | xy[, 1] > dims[1] | xy[, 2] < 0 | xy[, 2] > dims[2], na.rm = TRUE)
    if (isTRUE(oob)) {
      add("out_of_bounds", "warning", TRUE)
    }
  }
  list(issue = issues, severity = severity, fixable = fixable)
}

#' Check the geometry of every ROI in a project
#'
#' @param project An [annot_project].
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with columns `roi_id` (character), `issue`
#'   (character), `severity` (character, `"error"`/`"warning"`), and `fixable`
#'   (logical). Detected issues: self-intersection, invalid geometry, zero area,
#'   degenerate rings, out-of-bounds vertices, duplicate consecutive vertices,
#'   ring orientation, and `NA` coordinates. A 0-row tibble when all geometry is
#'   valid.
#' @family geometry
#' @seealso [at_fix_geometry()], [at_validate()]
#' @export
#' @examples
#' at_check_geometry(at_example_project())
at_check_geometry <- function(project, call = rlang::caller_env()) {
  .check_project(project, call = call)
  empty <- tibble::tibble(
    roi_id = character(0), issue = character(0),
    severity = character(0), fixable = logical(0)
  )
  rows <- list()
  for (nm in names(project$layers)) {
    for (r in project$layers[[nm]]$rois) {
      dims <- tryCatch(project$image$level_dims[[r$level + 1L]], error = function(e) NULL)
      res <- .geometry_issues(r$geometry, dims)
      if (length(res$issue) > 0L) {
        rows[[length(rows) + 1L]] <- tibble::tibble(
          roi_id = r$id, issue = res$issue,
          severity = res$severity, fixable = res$fixable
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(empty)
  }
  do.call(rbind, rows)
}

#' Repair the geometry of a project
#'
#' Apply `sf::st_make_valid()` to invalid ROIs (which also drops duplicate
#' consecutive vertices) and clamp out-of-bounds vertices into the image bounds,
#' reporting what changed.
#'
#' @param project An [annot_project].
#' @param verbose Logical; whether to report repairs. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return The [annot_project] with repaired geometry. Repairs are reported via
#'   [cli::cli_inform()] when `verbose` is `TRUE`. Issues that cannot be repaired
#'   (zero area, degenerate, `NA` coordinates) are left in place and reported.
#' @family geometry
#' @seealso [at_check_geometry()]
#' @export
at_fix_geometry <- function(project, verbose = TRUE, call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_flag(verbose, call = call)
  n_fixed <- 0L
  n_unfixable <- 0L
  for (nm in names(project$layers)) {
    rois <- project$layers[[nm]]$rois
    for (k in seq_along(rois)) {
      g <- rois[[k]]$geometry
      dims <- tryCatch(project$image$level_dims[[rois[[k]]$level + 1L]],
                       error = function(e) NULL)
      res <- .geometry_issues(g, dims)
      if (length(res$issue) == 0L) {
        next
      }
      if (any(!res$fixable)) {
        n_unfixable <- n_unfixable + 1L
      }
      if (any(res$fixable)) {
        fixed <- g
        # Clamp out-of-bounds vertices into the image bounds (as at_clamp does);
        # st_make_valid does not treat out-of-bounds as an invalidity.
        if ("out_of_bounds" %in% res$issue && !is.null(dims)) {
          fixed <- tryCatch(
            sf::st_sfc(lapply(fixed, .apply_coords, fun = function(m) cbind(
              pmin(pmax(m[, 1], 0), dims[1]),
              pmin(pmax(m[, 2], 0), dims[2])
            )), crs = sf::st_crs(fixed)),
            error = function(e) fixed
          )
        }
        fixed <- tryCatch(sf::st_make_valid(fixed), error = function(e) fixed)
        suppressWarnings(sf::st_crs(fixed) <- sf::NA_crs_)
        if (!isTRUE(all.equal(sf::st_coordinates(fixed), sf::st_coordinates(g)))) {
          n_fixed <- n_fixed + 1L
        }
        rois[[k]]$geometry <- fixed
        rois[[k]]$modified <- .now()
      }
    }
    project$layers[[nm]]$rois <- rois
  }
  if (verbose) {
    cli::cli_inform(c(
      "v" = "Repaired {n_fixed} ROI{?s}.",
      if (n_unfixable > 0L) c("!" = "{n_unfixable} ROI{?s} had issues that cannot be auto-repaired (zero area, degenerate, or NA coordinates).")
    ))
  }
  .log_edit(project, "fix_geometry", sprintf("fixed=%d unfixable=%d", n_fixed, n_unfixable))
}
