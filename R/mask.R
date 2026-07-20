# The mask ("Schablone") engine: the core deliverable. Rasterises ROI geometry
# to binary, labelled, or multi-class integer masks.
#
# PIXEL-COVERAGE CONTRACT (load-bearing; documented in at_mask() and tested
# against hand-computed cases):
#   * Pixel (i, j) covers the half-open square [j-1, j) x [i-1, i) in ROI
#     coordinate space, with (0, 0) at the top-left corner of the top-left pixel.
#     Its centre is (j - 0.5, i - 0.5).
#   * touches = FALSE (default): a pixel is included when its CENTRE lies inside
#     the polygon (GDAL ALL_TOUCHED=FALSE).
#   * touches = TRUE: a pixel is included if the polygon touches it at all.
#   * ROI coordinates use the image convention (top-left origin, y increasing
#     downward); the rasteriser flips the y-axis to reconcile with GDAL's y-up
#     convention.

# ---- Per-ROI cover primitive -----------------------------------------------

# Rasterise a single geometry to a logical [height, width] cover matrix in image
# orientation. `engine` selects the reference (stars) or accelerated (terra)
# implementation; the two are verified bit-identical in tests.
#
# For centre-based coverage (touches = FALSE) the geometry is shifted by a
# sub-pixel epsilon so that no pixel centre ever lands exactly on a polygon edge.
# This makes the boundary-tie rule deterministic and axis-symmetric: a centre on
# the lower edge falls strictly inside (included) and one on the upper edge falls
# strictly outside (excluded), i.e. the half-open `[lower, upper)` convention.
# The shift is far below pixel scale, so no non-tie pixel is affected and the
# stars and terra paths remain bit-identical.
.cover <- function(geom, dims, touches = FALSE, engine = "stars") {
  if (!touches) {
    # Fast, exact path for axis-aligned rectangles and points (bit-identical to
    # the general rasteriser); avoids stars/terra entirely.
    sc <- .cover_shortcircuit(geom, dims)
    if (!is.null(sc)) {
      return(sc)
    }
    eps <- 1e-7
    geom <- .apply_coords(geom, function(m) cbind(m[, 1] - eps, m[, 2] - eps))
  }
  if (engine == "terra" && requireNamespace("terra", quietly = TRUE)) {
    return(.cover_terra(geom, dims, touches))
  }
  .cover_stars(geom, dims, touches)
}

.cover_stars <- function(geom, dims, touches) {
  width <- dims[1]
  height <- dims[2]
  sfobj <- sf::st_sf(v = 1L, geometry = sf::st_sfc(geom, crs = sf::NA_crs_))
  bb <- sf::st_bbox(c(xmin = 0, ymin = 0, xmax = width, ymax = height))
  templ <- stars::st_as_stars(bb, nx = as.integer(width), ny = as.integer(height),
                              values = 0L)
  opt <- if (touches) "ALL_TOUCHED=TRUE" else "ALL_TOUCHED=FALSE"
  r <- suppressWarnings(stars::st_rasterize(sfobj, template = templ, options = opt))
  m <- r[[1]]
  m[is.na(m)] <- 0L
  cover <- t(m)[height:1, , drop = FALSE] != 0L
  matrix(cover, nrow = height, ncol = width)
}

.cover_terra <- function(geom, dims, touches) {
  width <- dims[1]
  height <- dims[2]
  v <- terra::vect(sf::st_sfc(geom, crs = sf::NA_crs_))
  r <- terra::rast(xmin = 0, xmax = width, ymin = 0, ymax = height,
                   resolution = 1, vals = 0)
  rr <- terra::rasterize(v, r, field = 1, background = 0, touches = touches)
  m <- terra::as.matrix(rr, wide = TRUE) # [row, col], row 1 = ymax (top)
  m[is.na(m)] <- 0
  # terra row 1 = ymax; image row 1 = y small -> flip rows.
  cover <- m[height:1, , drop = FALSE] != 0
  matrix(cover, nrow = height, ncol = width)
}

# ---- Collect ROIs for masking ----------------------------------------------

# Return a list describing the ROIs to rasterise, ordered by draw order
# (ascending z, then insertion), with geometry transformed to `level`.
.collect_mask_rois <- function(x, layer = NULL, label = NULL, level = 0L,
                               call = rlang::caller_env()) {
  image <- if (inherits(x, "annot_project")) x$image else NULL
  entries <- list()
  add_layer <- function(lyr) {
    z <- lyr$style$z %||% 1L
    cols <- lyr$style$colour
    for (r in lyr$rois) {
      if (!is.null(label) && !(r$label %in% label)) next
      g0 <- .to_level0(r$geometry, r$level, image)
      g <- .geom_to_level(g0, level, image)
      colour <- if (!is.null(cols) && r$label %in% names(cols)) unname(cols[[r$label]]) else "#5E2C8E"
      entries[[length(entries) + 1L]] <<- list(
        roi_id = r$id, label = r$label, layer = lyr$name,
        z = as.integer(z), colour = colour, geom = g[[1]]
      )
    }
  }
  if (inherits(x, "annot_roi")) {
    g0 <- .to_level0(x$geometry, x$level, NULL)
    g <- .geom_to_level(g0, level, NULL)
    entries[[1]] <- list(roi_id = x$id, label = x$label, layer = NA_character_,
                         z = 1L, colour = "#5E2C8E", geom = g[[1]])
  } else if (inherits(x, "annot_layer")) {
    add_layer(x)
  } else if (inherits(x, "annot_project")) {
    lyrs <- x$layers
    if (!is.null(layer)) lyrs <- lyrs[intersect(layer, names(lyrs))]
    for (lyr in lyrs) add_layer(lyr)
  } else {
    cli::cli_abort(
      "{.arg x} must be an {.cls annot_roi}, {.cls annot_layer}, or {.cls annot_project}.",
      call = call
    )
  }
  # Stable order by ascending z (higher z drawn later, on top).
  if (length(entries) > 1L) {
    ord <- order(vapply(entries, `[[`, integer(1), "z"), seq_along(entries))
    entries <- entries[ord]
  }
  entries
}

# Determine mask dimensions c(width, height) at a level.
.resolve_mask_dims <- function(x, level, dims, entries, call = rlang::caller_env()) {
  if (!is.null(dims)) {
    if (!is.numeric(dims) || length(dims) != 2L) {
      cli::cli_abort("{.arg dims} must be a length-2 numeric vector.", call = call)
    }
    return(as.integer(ceiling(dims)))
  }
  if (inherits(x, "annot_project")) {
    return(at_dims(x$image, level))
  }
  # Fall back to the geometry bounding box.
  if (length(entries) == 0L) {
    return(c(1L, 1L))
  }
  xmax <- 0
  ymax <- 0
  for (e in entries) {
    co <- sf::st_coordinates(sf::st_sfc(e$geom))
    xmax <- max(xmax, co[, "X"], na.rm = TRUE)
    ymax <- max(ymax, co[, "Y"], na.rm = TRUE)
  }
  as.integer(c(ceiling(xmax), ceiling(ymax)))
}

# ---- The mask constructor --------------------------------------------------

#' Rasterise ROIs to a mask ("Schablone")
#'
#' Produce a binary, labelled, or multi-class integer mask from annotations.
#' This is the package's core output artifact.
#'
#' @details
#' **Pixel-coverage contract.** Pixel `(i, j)` covers the half-open square
#' `[j-1, j) x [i-1, i)` with `(0, 0)` at the top-left corner of the top-left
#' pixel; its centre is `(j - 0.5, i - 0.5)`. With `touches = FALSE` (default) a
#' pixel is included when its centre lies inside the polygon; with
#' `touches = TRUE` a pixel is included if the polygon touches it at all. ROI
#' coordinates use the image convention (top-left origin, y down).
#'
#' @param x An [annot_roi], [annot_layer], or [annot_project].
#' @param type `"binary"` (a logical matrix), `"labelled"` (one integer id per
#'   ROI), or `"multiclass"` (one id per label class).
#' @param layer Optional layer name(s) to restrict to (projects only).
#' @param label Optional label(s) to restrict to.
#' @param level Integer pyramid level at which to rasterise. Default `0`.
#' @param background Integer background value. Default `0`.
#' @param touches Logical; see the coverage contract. Default `FALSE`.
#' @param dims Optional `c(width, height)`; taken from the image (projects) or
#'   the geometry bounding box otherwise.
#' @param overlap How overlapping ROIs resolve: `"last"` (later z-order wins,
#'   the default), `"first"`, `"max"`, `"min"`, or `"error"` (abort on any
#'   overlap).
#' @param engine `"stars"` (reference) or `"terra"` (accelerated, if installed);
#'   the two produce identical masks.
#' @param call The calling environment, for error reporting.
#'
#' @return An `annot_mask`: a matrix (logical for `"binary"`, otherwise integer)
#'   with attributes `legend` (a tibble with columns `value`, `label`, `layer`,
#'   `roi_id`, `n_px`, `colour`), `level`, `dims`, `type`, and `created`. An
#'   all-background mask of the correct dimensions is returned when there are no
#'   ROIs.
#' @family masks
#' @seealso [at_write_mask()], [at_read_mask()], [at_mask_stats()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' proj <- at_example_project()
#' m <- at_mask(proj, type = "multiclass")
#' table(as.integer(m))
at_mask <- function(x,
                    type = c("binary", "labelled", "multiclass"),
                    layer = NULL, label = NULL, level = 0L, background = 0L,
                    touches = FALSE, dims = NULL,
                    overlap = c("last", "first", "max", "min", "error"),
                    engine = c("stars", "terra"),
                    call = rlang::caller_env()) {
  type <- .check_choice(type, c("binary", "labelled", "multiclass"), call = call)
  overlap <- .check_choice(overlap, c("last", "first", "max", "min", "error"), call = call)
  engine <- .check_choice(engine, c("stars", "terra"), call = call)
  level <- .check_count(level, call = call)
  background <- .check_count(background, min = 0L, call = call)
  .check_flag(touches, call = call)

  entries <- .collect_mask_rois(x, layer = layer, label = label, level = level, call = call)
  d <- .resolve_mask_dims(x, level, dims, entries, call = call)
  width <- d[1]
  height <- d[2]

  # Assign each ROI a value according to the mask type.
  if (type == "multiclass") {
    labels_all <- unique(vapply(entries, `[[`, character(1), "label"))
    val_of <- function(e) match(e$label, labels_all)
  } else {
    val_of <- function(e) NA
  }
  values <- vapply(seq_along(entries), function(k) {
    switch(type, binary = 1L, labelled = k, multiclass = val_of(entries[[k]]))
  }, integer(1))

  if (length(entries) == 0L) {
    out <- matrix(as.integer(background), nrow = height, ncol = width)
  } else if (overlap %in% c("last", "first") && length(entries) >= 2L) {
    # Fast path: burn every ROI in one rasterisation (painter's order gives the
    # "last" policy; reversing the order gives "first"). Bit-identical to the
    # per-ROI combine but far cheaper for many ROIs.
    out <- .rasterize_batch(entries, values, c(width, height), background,
                            touches, reverse = (overlap == "first"), engine = engine)
  } else {
    out <- .rasterize_per_roi(entries, values, c(width, height), background,
                              touches, overlap, engine, call)
  }

  legend <- .build_legend(type, entries, values, out, background)

  if (type == "binary") {
    out <- out != background
  }
  .new_annot_mask(out, legend, level, c(width, height), type,
                  source = if (inherits(x, "annot_project")) x$meta$name %||% NA_character_ else NA_character_)
}

# Per-ROI rasterise-and-combine (short-circuits + all five overlap policies).
.rasterize_per_roi <- function(entries, values, dims, background, touches,
                               overlap, engine, call = rlang::caller_env()) {
  width <- dims[1]
  height <- dims[2]
  out <- matrix(as.integer(background), nrow = height, ncol = width)
  for (k in seq_along(entries)) {
    cover <- .cover(entries[[k]]$geom, c(width, height), touches = touches, engine = engine)
    value <- values[k]
    if (overlap == "error") {
      if (any(cover & out != background)) {
        cli::cli_abort(
          c("Overlapping ROIs detected with {.code overlap = \"error\"}.",
            "i" = "Use a different overlap policy or fix the annotations."),
          call = call
        )
      }
      out[cover] <- value
    } else if (overlap == "last") {
      out[cover] <- value
    } else if (overlap == "first") {
      out[cover & (out == background)] <- value
    } else if (overlap == "max") {
      out[cover] <- pmax(out[cover], value)
    } else if (overlap == "min") {
      out[cover & (out == background)] <- value
      m2 <- cover & (out != background)
      out[m2] <- pmin(out[m2], value)
    }
  }
  out
}

# Batched rasterisation: burn all ROIs in one st_rasterize/terra call.
.rasterize_batch <- function(entries, values, dims, background, touches, reverse,
                             engine = "stars") {
  width <- dims[1]
  height <- dims[2]
  geoms <- lapply(entries, `[[`, "geom")
  if (!touches) {
    eps <- 1e-7
    geoms <- lapply(geoms, function(g) .apply_coords(g, function(m) cbind(m[, 1] - eps, m[, 2] - eps)))
  }
  ord <- if (reverse) rev(seq_along(geoms)) else seq_along(geoms)
  sfc <- sf::st_sfc(geoms[ord], crs = sf::NA_crs_)
  sfobj <- sf::st_sf(value = as.integer(values[ord]), geometry = sfc)
  opt <- if (touches) "ALL_TOUCHED=TRUE" else "ALL_TOUCHED=FALSE"
  if (engine == "terra" && requireNamespace("terra", quietly = TRUE)) {
    v <- terra::vect(sfobj)
    r <- terra::rast(xmin = 0, xmax = width, ymin = 0, ymax = height, resolution = 1)
    rr <- terra::rasterize(v, r, field = "value", background = background, touches = touches)
    m <- terra::as.matrix(rr, wide = TRUE)
    m[is.na(m)] <- as.integer(background)
    return(matrix(as.integer(m[height:1, , drop = FALSE]), nrow = height, ncol = width))
  }
  bb <- sf::st_bbox(c(xmin = 0, ymin = 0, xmax = width, ymax = height))
  templ <- stars::st_as_stars(bb, nx = as.integer(width), ny = as.integer(height),
                              values = as.integer(background))
  r <- suppressWarnings(stars::st_rasterize(sfobj, template = templ, options = opt))
  m <- r[[1]]
  m[is.na(m)] <- as.integer(background)
  matrix(as.integer(t(m)[height:1, , drop = FALSE]), nrow = height, ncol = width)
}

# Build the legend tibble from the entries, their values, and the final mask.
.build_legend <- function(type, entries, values, out, background) {
  empty <- tibble::tibble(
    value = integer(0), label = character(0), layer = character(0),
    roi_id = character(0), n_px = integer(0), colour = character(0)
  )
  if (length(entries) == 0L) {
    return(empty)
  }
  if (type == "binary") {
    return(tibble::tibble(
      value = 1L, label = "foreground", layer = NA_character_,
      roi_id = NA_character_, n_px = as.integer(sum(out != background)),
      colour = "#5E2C8E"
    ))
  }
  if (type == "labelled") {
    rows <- lapply(seq_along(entries), function(k) {
      e <- entries[[k]]
      tibble::tibble(
        value = as.integer(values[k]), label = e$label, layer = e$layer,
        roi_id = e$roi_id, n_px = as.integer(sum(out == values[k])),
        colour = e$colour
      )
    })
    return(do.call(rbind, rows))
  }
  # multiclass: one row per distinct value.
  vals <- sort(unique(values))
  rows <- lapply(vals, function(v) {
    e <- entries[[which(values == v)[1]]]
    tibble::tibble(
      value = as.integer(v), label = e$label, layer = e$layer,
      roi_id = NA_character_, n_px = as.integer(sum(out == v)), colour = e$colour
    )
  })
  do.call(rbind, rows)
}

# ---- annot_mask class ------------------------------------------------------

.new_annot_mask <- function(matrix, legend, level, dims, type, source = NA_character_) {
  structure(
    matrix,
    legend = legend,
    level = as.integer(level),
    dims = as.integer(dims),
    mask_type = type,
    source_project = source,
    created = .now(),
    class = "annot_mask"
  )
}

#' @export
print.annot_mask <- function(x, ...) {
  d <- attr(x, "dims")
  lg <- attr(x, "legend")
  cat(cli::format_inline(
    "{.cls annot_mask} {attr(x, 'mask_type')}  |  {d[1]} x {d[2]} px  |  level {attr(x, 'level')}"
  ), "\n", sep = "")
  cat(cli::format_inline("values: {nrow(lg)}"), "\n", sep = "")
  if (nrow(lg) > 0L) {
    print(utils::head(lg, 10L))
  }
  invisible(x)
}

#' @export
dim.annot_mask <- function(x) {
  attr(x, "dims")[c(2, 1)] # [height, width] to match the matrix
}

#' @export
as.matrix.annot_mask <- function(x, ...) {
  attributes(x) <- list(dim = dim(unclass(x)))
  unclass(x)
}

#' @export
summary.annot_mask <- function(object, ...) {
  attr(object, "legend")
}

#' Legend of a mask
#'
#' @param mask An `annot_mask`.
#' @param call The calling environment, for error reporting.
#' @return The mask's legend [tibble::tibble] (`value`, `label`, `layer`,
#'   `roi_id`, `n_px`, `colour`).
#' @family masks
#' @export
at_mask_legend <- function(mask, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  attr(mask, "legend")
}

# ---- Additional mask operations --------------------------------------------

#' Stack per-layer masks into a 3D array
#'
#' @param project An [annot_project].
#' @param layers Optional layer name(s) to include; all by default.
#' @param level Integer pyramid level. Default `0`.
#' @param call The calling environment, for error reporting.
#' @return A 3D integer array `[y, x, layer]`, one multi-class plane per layer;
#'   the third dimension is named by layer.
#' @family masks
#' @export
at_mask_stack <- function(project, layers = NULL, level = 0L,
                          call = rlang::caller_env()) {
  .check_project(project, call = call)
  nms <- names(project$layers)
  if (!is.null(layers)) {
    nms <- intersect(layers, nms)
  }
  d <- at_dims(project$image, level)
  if (length(nms) == 0L) {
    return(array(0L, dim = c(d[2], d[1], 0L)))
  }
  planes <- lapply(nms, function(nm) {
    as.matrix(at_mask(project, type = "multiclass", layer = nm, level = level))
  })
  arr <- array(0L, dim = c(d[2], d[1], length(nms)),
               dimnames = list(NULL, NULL, nms))
  for (k in seq_along(planes)) arr[, , k] <- planes[[k]]
  arr
}

#' Object boundaries of a mask
#'
#' @param mask An `annot_mask`.
#' @param width Integer boundary thickness in pixels. Default `1`.
#' @param call The calling environment, for error reporting.
#' @return A logical matrix marking boundary pixels (where a 4-neighbour has a
#'   different value).
#' @family masks
#' @export
at_mask_boundary <- function(mask, width = 1L, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  width <- .check_count(width, min = 1L, call = call)
  m <- as.matrix(mask)
  storage.mode(m) <- "double"
  nr <- nrow(m)
  nc <- ncol(m)
  b <- matrix(FALSE, nr, nc)
  b[-nr, ] <- b[-nr, ] | (m[-nr, ] != m[-1, ])
  b[-1, ]  <- b[-1, ]  | (m[-1, ] != m[-nr, ])
  b[, -nc] <- b[, -nc] | (m[, -nc] != m[, -1])
  b[, -1]  <- b[, -1]  | (m[, -1] != m[, -nc])
  if (width > 1L) {
    for (w in seq_len(width - 1L)) {
      bb <- b
      bb[-nr, ] <- bb[-nr, ] | b[-1, ]
      bb[-1, ]  <- bb[-1, ]  | b[-nr, ]
      bb[, -nc] <- bb[, -nc] | b[, -1]
      bb[, -1]  <- bb[, -1]  | b[, -nc]
      b <- bb
    }
  }
  # Keep only foreground (object) boundary pixels, not adjacent background.
  b & (m != 0)
}

#' Downsampled preview of a mask
#'
#' Nearest-neighbour downsample only (interpolating a label mask would invent
#' labels that do not exist).
#'
#' @param x An `annot_mask`.
#' @param max_dim Integer maximum dimension of the preview. Default `1024`.
#' @param call The calling environment, for error reporting.
#' @return A downsampled `annot_mask` with the legend pixel counts recomputed.
#' @family masks
#' @export
at_mask_preview <- function(x, max_dim = 1024L, call = rlang::caller_env()) {
  .check_class(x, "annot_mask", call = call)
  max_dim <- .check_count(max_dim, min = 1L, call = call)
  m <- as.matrix(x)
  nr <- nrow(m)
  nc <- ncol(m)
  fac <- max(1L, ceiling(max(nr, nc) / max_dim))
  if (fac == 1L) {
    return(x)
  }
  ys <- seq(1L, nr, by = fac)
  xs <- seq(1L, nc, by = fac)
  small <- m[ys, xs, drop = FALSE]
  lg <- attr(x, "legend")
  if (nrow(lg) > 0L) {
    lg$n_px <- vapply(lg$value, function(v) as.integer(sum(small == v)), integer(1))
  }
  .new_annot_mask(
    small, lg, attr(x, "level"),
    c(ncol(small), nrow(small)), attr(x, "mask_type"),
    source = attr(x, "source_project")
  )
}

#' Per-value statistics of a mask
#'
#' @param mask An `annot_mask`.
#' @param pixel_size Optional numeric `c(x, y)` physical pixel size for physical
#'   area. When `NULL`, `area_physical` is `NA`.
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with one row per mask value: `value`, `label`,
#'   `n_px`, `area_px`, `area_physical`, `frac_total`, bounding box
#'   (`bbox_xmin`, `bbox_ymin`, `bbox_xmax`, `bbox_ymax`), and centroid
#'   (`centroid_x`, `centroid_y`). A 0-row tibble when the mask is empty.
#' @family masks
#' @export
at_mask_stats <- function(mask, pixel_size = NULL, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  m <- as.matrix(mask)
  lg <- attr(mask, "legend")
  total <- length(m)
  cols <- c("value", "label", "n_px", "area_px", "area_physical", "frac_total",
            "bbox_xmin", "bbox_ymin", "bbox_xmax", "bbox_ymax",
            "centroid_x", "centroid_y")
  empty <- tibble::tibble(
    value = integer(0), label = character(0), n_px = integer(0),
    area_px = double(0), area_physical = double(0), frac_total = double(0),
    bbox_xmin = double(0), bbox_ymin = double(0), bbox_xmax = double(0),
    bbox_ymax = double(0), centroid_x = double(0), centroid_y = double(0)
  )
  if (nrow(lg) == 0L) {
    return(empty)
  }
  psf <- if (is.null(pixel_size)) NA_real_ else prod(pixel_size)
  rows <- lapply(seq_len(nrow(lg)), function(k) {
    v <- lg$value[k]
    idx <- which(m == v, arr.ind = TRUE)
    n <- nrow(idx)
    if (n == 0L) {
      return(tibble::tibble(
        value = as.integer(v), label = lg$label[k], n_px = 0L, area_px = 0,
        area_physical = if (is.na(psf)) NA_real_ else 0,
        frac_total = 0, bbox_xmin = NA_real_, bbox_ymin = NA_real_,
        bbox_xmax = NA_real_, bbox_ymax = NA_real_,
        centroid_x = NA_real_, centroid_y = NA_real_
      ))
    }
    xs <- idx[, 2] - 0.5
    ys <- idx[, 1] - 0.5
    tibble::tibble(
      value = as.integer(v), label = lg$label[k], n_px = as.integer(n),
      area_px = as.double(n),
      area_physical = if (is.na(psf)) NA_real_ else n * psf,
      frac_total = n / total,
      bbox_xmin = min(xs) - 0.5, bbox_ymin = min(ys) - 0.5,
      bbox_xmax = max(xs) + 0.5, bbox_ymax = max(ys) + 0.5,
      centroid_x = mean(xs), centroid_y = mean(ys)
    )
  })
  do.call(rbind, rows)
}

#' Plot a mask
#'
#' @param x An `annot_mask`.
#' @param legend Logical; show the fill legend. Default `TRUE`.
#' @param ... Ignored.
#' @return A [ggplot2::ggplot] object (discrete fill from the legend colours,
#'   image orientation). Not drawn; print it to render.
#' @keywords internal
#' @export
plot.annot_mask <- function(x, legend = TRUE, ...) {
  m <- as.matrix(x)
  lg <- attr(x, "legend")
  # Only foreground pixels are drawn (background is left blank). geom_tile (not
  # geom_raster) is used so sparse foreground data raises no warnings.
  df <- expand.grid(y = seq_len(nrow(m)), x = seq_len(ncol(m)))
  df$value <- as.vector(m)
  df <- df[df$value != 0, , drop = FALSE]
  df$label <- if (nrow(df) > 0L && nrow(lg) > 0L) lg$label[match(df$value, lg$value)] else character(0)
  pal <- NULL
  if (nrow(lg) > 0L) {
    pal <- lg$colour
    names(pal) <- lg$label
  }
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$x, y = .data$y, fill = .data$label)) +
    ggplot2::geom_tile() +
    ggplot2::scale_y_reverse() +
    ggplot2::coord_fixed() +
    ggplot2::labs(title = "Mask", x = "x (px)", y = "y (px)", fill = "label") +
    ggplot2::theme_minimal()
  if (!is.null(pal)) {
    p <- p + ggplot2::scale_fill_manual(values = pal)
  }
  if (!legend) {
    p <- p + ggplot2::theme(legend.position = "none")
  }
  p
}
