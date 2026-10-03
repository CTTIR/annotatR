# The mask ("Schablone") engine: the core deliverable. Rasterises ROI geometry
# to binary, labelled, or multi-class integer masks.
#
# PIXEL-COVERAGE CONTRACT (load-bearing; documented in at_mask() and tested
# against hand-computed cases):
#   * Pixel (i, j) covers the half-open square [j-1, j) x [i-1, i) in ROI
#     coordinate space, with (0, 0) at the top-left corner of the top-left pixel.
#     Its centre is (j - 0.5, i - 0.5).
#   * touches = FALSE (default): polygon centres use the symbolic sample
#     (x + epsilon, y + epsilon^2), epsilon -> 0+, to resolve boundary ties.
#     Points occupy their half-open containing cells.
#   * touches = TRUE: a pixel is included if the polygon touches it at all.
#   * ROI coordinates use the image convention (top-left origin, y increasing
#     downward); the rasteriser flips the y-axis to reconcile with GDAL's y-up
#     convention.

# ---- Per-ROI cover primitive -----------------------------------------------

# Centre polygon membership is evaluated symbolically at
# (x + epsilon, y + epsilon^2), epsilon -> 0+. No finite shift or tolerance is
# applied: narrow regions and non-tie centres retain their original meaning.
# Crossings at each centre y use edges active on [minY, maxY); sorted crossing
# pairs fill [left, right). Ring parity removes holes regardless of orientation.
# MultiPolygon components combine by union, rather than cancelling overlaps.
.cover_polygon <- function(geom, dims, origin = c(0, 0)) {
  width <- as.integer(dims[1])
  height <- as.integer(dims[2])
  out <- matrix(FALSE, height, width)
  polygons <- if (inherits(geom, "POLYGON")) list(unclass(geom)) else unclass(geom)
  for (rings in polygons) {
    if (!length(rings)) next
    starts <- do.call(rbind, lapply(rings, function(r) r[-nrow(r), 1:2, drop = FALSE]))
    ends <- do.call(rbind, lapply(rings, function(r) r[-1L, 1:2, drop = FALSE]))
    if (!nrow(starts)) next
    # Orient each edge upwards numerically for reproducible side comparisons
    # when ring winding is reversed; horizontal edges never cross a scanline.
    swap <- starts[, 2] > ends[, 2]
    low <- starts; high <- ends
    low[swap, ] <- ends[swap, , drop = FALSE]
    high[swap, ] <- starts[swap, , drop = FALSE]
    yr <- .centre_range(min(low[, 2]), max(high[, 2]), height, origin[2])
    if (yr[1] > yr[2]) next
    for (i in yr[1]:yr[2]) {
      y <- origin[2] + i - 0.5
      active <- low[, 2] <= y & y < high[, 2]
      if (!any(active)) next
      a <- low[active, , drop = FALSE]; b <- high[active, , drop = FALSE]
      # Locate the first centre at or to the right of each crossing using
      # cross products, never a rounded interpolated x. With edges directed
      # from low y to high y, a symbolic x+epsilon tie is always to the right.
      # Binary search keeps work logarithmic in image width for each edge.
      left <- rep.int(1, nrow(a)); right <- rep.int(width + 1, nrow(a))
      dx <- b[, 1] - a[, 1]; dy <- b[, 2] - a[, 2]
      while (any(left < right)) {
        pending <- which(left < right)
        mid <- floor((left[pending] + right[pending]) / 2)
        x <- origin[1] + mid - 0.5
        before <- (x - a[pending, 1]) * dy[pending] <
          (y - a[pending, 2]) * dx[pending]
        left[pending[before]] <- mid[before] + 1
        right[pending[!before]] <- mid[!before]
      }
      crossings <- sort(left)
      for (k in seq.int(1L, length(crossings), by = 2L)) {
        if (crossings[k] < crossings[k + 1L]) {
          out[i, crossings[k]:(crossings[k + 1L] - 1L)] <- TRUE
        }
      }
    }
  }
  out
}

# The selected engine retains its native line and all-touched rasterisation.
# All centre polygons and points share one membership path across engines.
# A private window origin evaluates the unchanged global geometry at global
# centres, so extraction does not alter fractional vertices before classifying.
.cover <- function(geom, dims, touches = FALSE, engine = "stars", origin = c(0, 0)) {
  if (!touches) {
    sc <- .cover_shortcircuit(geom, dims, origin)
    if (!is.null(sc)) return(sc)
    if (inherits(geom, "POLYGON") || inherits(geom, "MULTIPOLYGON")) {
      return(.cover_polygon(geom, dims, origin))
    }
    # Preserve the established GDAL line convention.
    eps <- 1e-7
    geom <- .apply_coords(geom, function(m) cbind(m[, 1] - origin[1] - eps,
                                                m[, 2] - origin[2] - eps))
  } else if (any(origin != 0)) {
    geom <- .apply_coords(geom, function(m) cbind(m[, 1] - origin[1], m[, 2] - origin[2]))
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
                               call = rlang::caller_env(), image = NULL) {
  if (inherits(x, "annot_project")) image <- x$image
  entries <- list()
  add_layer <- function(lyr) {
    z <- lyr$style$z %||% 1L
    cols <- lyr$style$colour
    for (r in lyr$rois) {
      if (!is.null(label) && !(r$label %in% label)) next
      g <- .transform_geom(r$geometry, r$level, level, image, call = call)
      colour <- if (!is.null(cols) && r$label %in% names(cols)) unname(cols[[r$label]]) else "#5E2C8E"
      entries[[length(entries) + 1L]] <<- list(
        roi_id = r$id, label = r$label, layer = lyr$name,
        z = as.integer(z), colour = colour, geom = g[[1]]
      )
    }
  }
  if (inherits(x, "annot_roi")) {
    g <- .transform_geom(x$geometry, x$level, level, image, call = call)
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
    # Integer-coordinate points occupy the cell beginning at that coordinate.
    point <- inherits(e$geom, "POINT") || inherits(e$geom, "MULTIPOINT")
    extent <- if (point) floor(co[, c("X", "Y"), drop = FALSE]) + 1 else co[, c("X", "Y"), drop = FALSE]
    xmax <- max(xmax, extent[, "X"], na.rm = TRUE)
    ymax <- max(ymax, extent[, "Y"], na.rm = TRUE)
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
#' pixel is included when its centre lies inside the polygon. Boundary ties use
#' the symbolic sample `(x + epsilon, y + epsilon^2)` as `epsilon` tends to zero
#' from above, without a finite coordinate shift. Equivalently, scanline edges
#' are active on `[minY, maxY)` and crossing pairs fill `[left, right)`.
#' Hole rings exclude pixels by parity regardless of winding; `MULTIPOLYGON`
#' components combine by union. Thin polygons containing no selected centres
#' have empty masks. This rule is shared by both engines and all overlap paths.
#'
#' `POINT` and `MULTIPOINT` geometries select their half-open containing cells:
#' `(5, 5)` selects row 6, column 6. Extraction uses the same membership and
#' bounds. With `touches = TRUE`, polygon coverage uses the selected engine's
#' all-touched rasterisation; lines and other geometry types also retain the
#' selected engine's rasterisation behavior. Engine equality is guaranteed for
#' centre-based polygons and points. ROI coordinates use the image convention
#' (top-left origin, y down).
#'
#' @param x An [annot_roi], [annot_layer], or [annot_project].
#' @param image Optional [annot_image] for standalone ROIs or layers. Required
#'   when changing coordinate levels; dimensions alone do not define a scale.
#'   Projects always use their own image. Without `dims`, the image supplies
#'   the full mask extent at `level`.
#' @param type `"binary"` (a logical matrix), `"labelled"` (one integer id per
#'   ROI), or `"multiclass"` (one id per label class).
#' @param layer Optional layer name(s) to restrict to (projects only).
#' @param label Optional label(s) to restrict to.
#' @param level Integer pyramid level at which to rasterise. Default `0`.
#' @param background Integer background value. Default `0`. Foreground codes
#'   must differ from background. Binary masks reject `1` (foreground), and
#'   normalize other accepted backgrounds to the stored logical `FALSE`/`0`.
#' @param touches Logical; see the coverage contract. Default `FALSE`.
#' @param dims Optional `c(width, height)`; taken from the image (projects) or
#'   the geometry bounding box otherwise, including containing cells for points.
#' @param values Optional named integer vector mapping labels to explicit class
#'   codes (e.g. `c(specular = 1L, blood = 2L, shadow = 4L)`), used only for
#'   `type = "multiclass"`. When `NULL` (default) codes follow first-seen label
#'   order. Supply power-of-two codes together with `overlap = "bitor"` to build
#'   a bitfield mask.
#' @param overlap How overlapping ROIs resolve: `"last"` (later z-order wins,
#'   the default), `"first"`, `"max"`, `"min"`, `"error"` (abort on any overlap),
#'   or `"bitor"` (bitwise-OR the overlapping values, for bitfield masks; use
#'   with power-of-two `values` and `background = 0`).
#' @param engine `"stars"` or `"terra"` (if installed). Centre-based polygons
#'   and points use shared membership; other coverage uses the selected engine.
#' @param call The calling environment, for error reporting.
#'
#' @return An `annot_mask`: a matrix (logical for `"binary"`, otherwise integer)
#'   with attributes `legend` (a tibble with columns `value`, `label`, `layer`,
#'   `roi_id`, `n_px`, `colour`), `level`, `dims`, `type`, and `created`. An
#'   all-background mask of the correct dimensions is returned when there are no
#'   ROIs. The `mask_metadata` attribute has schema version 1 and records
#'   encoding (`binary`, `instance`, `categorical`, or `bitfield`), background,
#'   overlap policy, grid (dimensions, level, origin, stride), source descriptor
#'   and entry provenance, and the complete label codebook. Supplied `values`
#'   retain mapped-but-absent classes with zero counts. Bitfields require unique
#'   positive single-bit codes and zero background; category `3` is exclusive
#'   unless bitfield encoding is explicitly declared.
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
                    touches = FALSE, dims = NULL, values = NULL,
                    overlap = c("last", "first", "max", "min", "error", "bitor"),
                    engine = c("stars", "terra"),
                    call = rlang::caller_env(), image = NULL) {
  type <- .check_choice(type, c("binary", "labelled", "multiclass"), default = missing(type), call = call)
  overlap <- .check_choice(overlap, c("last", "first", "max", "min", "error", "bitor"), default = missing(overlap), call = call)
  engine <- .check_choice(engine, c("stars", "terra"), default = missing(engine), call = call)
  level <- .check_count(level, call = call)
  background <- .check_count(background, min = 0L, call = call)
  .check_flag(touches, call = call)
  values <- .check_values_map(values, type, call = call)
  code_map <- values
  if (type == "binary") {
    if (background == 1L) cli::cli_abort("Binary foreground code collides with requested background.", call = call)
    background <- 0L
  }

  if (inherits(x, "annot_project")) image <- x$image
  if (!is.null(image)) {
    .check_image(image, call = call)
    image_dims <- at_dims(image, level, call = call)
    if (is.null(dims)) dims <- image_dims
  }
  entries <- .collect_mask_rois(x, layer = layer, label = label, level = level, call = call, image = image)
  d <- .resolve_mask_dims(x, level, dims, entries, call = call)
  width <- d[1]
  height <- d[2]

  # Assign each ROI a value according to the mask type.
  if (type == "multiclass") {
    if (!is.null(values)) {
      present <- unique(vapply(entries, `[[`, character(1), "label"))
      unmapped <- setdiff(present, names(values))
      if (length(unmapped) > 0L) {
        cli::cli_abort(
          c("{.arg values} does not map every label present.",
            "x" = "Unmapped label{?s}: {.val {unmapped}}."),
          call = call
        )
      }
      val_of <- function(e) values[[e$label]]
    } else {
      labels_all <- unique(vapply(entries, `[[`, character(1), "label"))
      val_of <- function(e) match(e$label, labels_all)
    }
  } else {
    val_of <- function(e) NA
  }
  values <- vapply(seq_along(entries), function(k) {
    switch(type, binary = 1L, labelled = k, multiclass = val_of(entries[[k]]))
  }, integer(1))

  codes <- code_map %||% unique(values)
  if (any(codes == background)) cli::cli_abort("Foreground codes collide with background.", call = call)
  if (overlap == "bitor" && (background != 0L || any(codes <= 0L) || any(bitwAnd(codes, codes - 1L) != 0L))) {
    cli::cli_abort("Bitfield codes must be positive single-bit powers of two with zero background.", call = call)
  }
  if (length(entries) == 0L) {
    out <- matrix(as.integer(background), nrow = height, ncol = width)
  } else if (overlap %in% c("last", "first") && length(entries) >= 2L) {
    # Batch all-touched rasterisation; centre coverage shares the per-ROI
    # membership primitive so adding another ROI cannot change its support.
    out <- .rasterize_batch(entries, values, c(width, height), background,
                            touches, reverse = (overlap == "first"), engine = engine)
  } else {
    out <- .rasterize_per_roi(entries, values, c(width, height), background,
                              touches, overlap, engine, call)
  }

  legend <- .build_legend(type, entries, values, out, background, overlap)
  if (!is.null(code_map)) {
    # Retain the caller's global mapping and order, including absent classes.
    absent <- setdiff(names(code_map), legend$label)
    for (lb in absent) legend <- rbind(legend, tibble::tibble(
      value = unname(code_map[[lb]]), label = lb, layer = NA_character_,
      roi_id = NA_character_, n_px = 0L, colour = "#5E2C8E"))
    legend <- legend[match(names(code_map), legend$label), , drop = FALSE]
  }

  if (type == "binary") {
    out <- out != background
  }
  .new_annot_mask(out, legend, level, c(width, height), type,
                  source = if (inherits(x, "annot_project")) x$meta$name %||% NA_character_ else NA_character_,
                  encoding = if (type == "binary") "binary" else if (overlap == "bitor") "bitfield" else if (type == "labelled") "instance" else "categorical",
                  background = background, overlap = overlap,
                  source_identity = .mask_source(image, if (inherits(x, "annot_project")) x else NULL))
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
      out[cover & (out == background)] <- value
      m2 <- cover & (out != background)
      out[m2] <- pmax(out[m2], value)
    } else if (overlap == "min") {
      out[cover & (out == background)] <- value
      m2 <- cover & (out != background)
      out[m2] <- pmin(out[m2], value)
    } else if (overlap == "bitor") {
      out[cover] <- bitwOr(out[cover], value)
    }
  }
  out
}

# Validate an optional label -> integer-code map (multiclass only).
.check_values_map <- function(values, type, call = rlang::caller_env()) {
  if (is.null(values)) {
    return(NULL)
  }
  if (type != "multiclass") {
    cli::cli_abort(
      c("{.arg values} is only supported for {.code type = \"multiclass\"}.",
        "x" = "You supplied {.arg values} with {.code type = \"{type}\"}."),
      call = call
    )
  }
  nm <- names(values)
  if (is.null(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) {
    cli::cli_abort(
      c("{.arg values} must be a named integer vector with unique, non-empty names.",
        "i" = "Names are labels; values are the integer codes to assign."),
      call = call
    )
  }
  values <- .mask_integers(values, "Label codes")
  if (anyDuplicated(values)) cli::cli_abort("Label codes must be unique; duplicate codes are ambiguous.", call = call)
  stats::setNames(as.integer(values), nm)
}

# Batched all-touched rasterisation, with shared per-ROI centre membership.
.rasterize_batch <- function(entries, values, dims, background, touches, reverse,
                             engine = "stars") {
  if (!touches) {
    return(.rasterize_per_roi(entries, values, dims, background, FALSE,
                              if (reverse) "first" else "last", engine))
  }
  width <- dims[1]
  height <- dims[2]
  geoms <- lapply(entries, `[[`, "geom")
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
# For the bitor policy, legend rows are the base (power-of-two) codes and pixel
# counts include every pixel with that bit set (composite pixels count for each
# of their bits).
.build_legend <- function(type, entries, values, out, background, overlap = "last") {
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
  # multiclass: one row per distinct base value. Under "bitor", a pixel counts
  # for every bit it carries, so counts use bitwAnd rather than equality.
  vals <- sort(unique(values))
  rows <- lapply(vals, function(v) {
    e <- entries[[which(values == v)[1]]]
    n <- if (overlap == "bitor") sum(bitwAnd(out, v) != 0L) else sum(out == v)
    tibble::tibble(
      value = as.integer(v), label = e$label, layer = e$layer,
      roi_id = NA_character_, n_px = as.integer(n), colour = e$colour
    )
  })
  do.call(rbind, rows)
}

# ---- annot_mask class ------------------------------------------------------

.new_annot_mask <- function(matrix, legend, level, dims, type, source = NA_character_,
                            encoding = NULL, background = 0L, overlap = "last",
                            source_identity = NULL, grid = NULL, metadata = NULL) {
  legend <- .mask_legend_normalize(legend)
  metadata <- metadata %||% .mask_default_metadata(matrix, legend, level, type,
    status = if (is.null(encoding)) "legacy-default" else "declared",
    encoding = encoding, background = background, overlap = overlap,
    source = source_identity, grid = grid)
  metadata <- .mask_validate_metadata(matrix, metadata, legend, dims, level)
  if (!is.logical(matrix)) storage.mode(matrix) <- "integer"
  structure(matrix, legend = .mask_recount(matrix, legend, metadata$encoding),
    level = as.integer(level), dims = as.integer(dims), mask_type = type,
    source_project = source, mask_metadata = metadata, created = .now(), class = "annot_mask")
}

#' @export
print.annot_mask <- function(x, ...) {
  info <- .mask_info(x)
  d <- info$metadata$grid$dims
  lg <- info$legend
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
  attr(unclass(x), "dim")
}

#' @export
as.matrix.annot_mask <- function(x, ...) {
  attributes(x) <- list(dim = dim(unclass(x)))
  unclass(x)
}

#' @export
summary.annot_mask <- function(object, ...) {
  .mask_info(object)$legend
}

#' Legend of a mask
#'
#' @param mask An `annot_mask`.
#' @param call The calling environment, for error reporting.
#' @return The mask's legend [tibble::tibble] (`value`, `label`, `layer`,
#'   `roi_id`, `n_px`, `colour`).
#' @family masks
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' at_mask_legend(at_mask(at_example_project(), "labelled"))
at_mask_legend <- function(mask, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  .mask_info(mask)$legend
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

#' Derive a training mask from layer masks
#'
#' Keep foreground state codes inside the requested anatomy class and outside
#' artefacts, using each mask's declared background and class membership. An
#' anatomy bitfield includes composite samples containing the requested bit.
#'
#' @param state An `annot_mask` of state (class) codes.
#' @param anatomy An `annot_mask` of anatomy codes, sharing `state`'s dimensions
#'   and level.
#' @param artefact Optional `annot_mask` (bitfield); pixels with any artefact bit
#'   set are dropped. `NULL` (default) applies no artefact exclusion.
#' @param keep_label The anatomy label whose region is kept (e.g. `"wound"`).
#' @param background Output background value. `NULL` (default) preserves the
#'   state mask's background. Must not collide with any state class code.
#' @param alignment `"legacy"` (default) validates declared source descriptors
#'   and grids; masks with only legacy metadata use a recorded legacy assumption.
#'   Modern masks with missing or conflicting provenance require `"assert"`,
#'   explicitly asserting registration without resampling. Dimensions must
#'   always agree. Entry IDs and runtime cache generations do not establish
#'   source compatibility. Combining the same object records `self-grid`.
#' @param call The calling environment, for error reporting.
#'
#' @return An `annot_mask` retaining state encoding and the full state codebook,
#'   with counts recomputed, zero counts for absent classes, and alignment
#'   provenance recorded in `mask_metadata$derivation`.
#' @family masks
#' @seealso [at_mask()], [at_mask_stack()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' proj <- at_example_project()
#' # A single-layer project derives trivially; the four-layer HSI workflow passes
#' # separate anatomy/state/artefact masks. See the masks vignette.
#' m <- at_mask(proj, "multiclass")
#' at_mask_derive(m, m, keep_label = at_mask_legend(m)$label[1])
at_mask_derive <- function(state, anatomy, artefact = NULL, keep_label = "wound",
                           background = NULL, call = rlang::caller_env(),
                           alignment = c("legacy", "assert")) {
  .check_class(state, "annot_mask", call = call)
  .check_class(anatomy, "annot_mask", call = call)
  if (!is.null(artefact)) .check_class(artefact, "annot_mask", call = call)
  alignment <- .check_choice(alignment, c("legacy", "assert"), default = missing(alignment), call = call)
  s <- .mask_info(state); a <- .mask_info(anatomy)
  # Combining the exact same object needs no external registration claim.
  provenance <- if (identical(state, anatomy)) "self-grid" else .mask_alignment(s, a, alignment)
  background <- background %||% s$metadata$background
  background <- .mask_integers(background, "Derived background")
  if (length(background) != 1L || any(s$legend$value == background)) cli::cli_abort("Invalid derived background or foreground/background collision.")
  vals <- a$legend$value[a$legend$label == keep_label]
  if (!length(vals)) cli::cli_abort("{.arg keep_label} {.val {keep_label}} is not a label of the anatomy mask.", call = call)
  keep <- Reduce(`|`, lapply(vals, function(v) .mask_membership(a$m, v, a$metadata$encoding))) & (s$m != s$metadata$background)
  if (!is.null(artefact)) {
    f <- .mask_info(artefact)
    artefact_alignment <- if (identical(state, artefact)) "self-grid" else .mask_alignment(s, f, alignment)
    keep <- keep & (f$m == f$metadata$background)
  }
  out <- s$m; out[!keep] <- background
  md <- s$metadata; md$background <- background
  md$derivation <- list(anatomy_alignment = provenance,
                        artefact_alignment = if (is.null(artefact)) NULL else artefact_alignment,
                        anatomy_source = a$metadata[["source"]],
                        artefact_source = if (is.null(artefact)) NULL else f$metadata[["source"]])
  .new_annot_mask(out, s$legend, md$grid$level, md$grid$dims,
                  attr(state, "mask_type"), source = attr(state, "source_project"), metadata = md)
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
  b & (m != .mask_info(mask)$metadata$background)
}

#' Downsampled preview of a mask
#'
#' Nearest-neighbour downsample only (interpolating a label mask would invent
#' labels that do not exist).
#'
#' @param mask An `annot_mask`.
#' @param max_dim Integer maximum dimension of the preview. Default `1024`.
#' @param call The calling environment, for error reporting.
#' @return A downsampled `annot_mask` with membership-aware counts recomputed.
#'   Metadata records the preview dimensions and sampling stride, its parent
#'   grid, and the original source provenance. No full-resolution counts are
#'   copied onto the sampled matrix.
#' @family masks
#' @export
at_mask_preview <- function(mask, max_dim = 1024L, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  max_dim <- .check_count(max_dim, min = 1L, call = call)
  info <- .mask_info(mask)
  m <- info$m
  nr <- nrow(m)
  nc <- ncol(m)
  fac <- max(1L, ceiling(max(nr, nc) / max_dim))
  if (fac == 1L) {
    return(mask)
  }
  ys <- seq(1L, nr, by = fac)
  xs <- seq(1L, nc, by = fac)
  small <- m[ys, xs, drop = FALSE]
  md <- info$metadata
  md$preview <- list(parent_grid = md$grid, sampling = "nearest-neighbour")
  md$grid$dims <- as.integer(c(ncol(small), nrow(small)))
  md$grid$stride <- md$grid$stride * fac
  .new_annot_mask(small, info$legend, md$grid$level, md$grid$dims,
                  attr(mask, "mask_type"), source = attr(mask, "source_project"), metadata = md)
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
#'   (`centroid_x`, `centroid_y`). Every bitfield membership contributes to its
#'   class count, including composite samples; categorical counts are exclusive.
#'   Mapped-but-absent classes have zero counts. A 0-row tibble is returned only
#'   when the codebook is empty.
#' @family masks
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' at_mask_stats(at_mask(at_example_project(), "labelled"))
at_mask_stats <- function(mask, pixel_size = NULL, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  info <- .mask_info(mask)
  m <- info$m
  lg <- info$legend
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
    idx <- which(.mask_membership(m, v, info$metadata$encoding), arr.ind = TRUE)
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
  lg <- .mask_display(x)
  # Only foreground pixels are drawn (background is left blank). geom_tile (not
  # geom_raster) is used so sparse foreground data raises no warnings.
  df <- expand.grid(y = seq_len(nrow(m)), x = seq_len(ncol(m)))
  df$value <- as.vector(m)
  df <- df[df$value != lg$background, , drop = FALSE]
  df$label <- if (nrow(df) > 0L && length(lg$value) > 0L) lg$label[match(df$value, lg$value)] else character(0)
  pal <- NULL
  if (length(lg$value) > 0L) {
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
