# Extraction of image/spectral values under ROIs. Extraction is tile-wise: for
# each ROI only the tiles covering its bounding box are read, so a full
# whole-slide image is never materialised.

.extract_stats <- list(
  mean   = function(v) mean(v),
  median = function(v) stats::median(v),
  sd     = function(v) stats::sd(v),
  min    = function(v) min(v),
  max    = function(v) max(v),
  sum    = function(v) sum(v),
  n      = function(v) length(v)
)

.empty_extract_tbl <- function() {
  tibble::tibble(
    roi_id = character(0), layer = character(0), label = character(0),
    band = integer(0), band_name = character(0), wavelength = double(0),
    stat = character(0), value = double(0), n_px = integer(0)
  )
}

# Pixel range (1-based, inclusive) covering a geometry's bbox, clamped to dims.
.bbox_range <- function(geom, dims) {
  bb <- sf::st_bbox(geom)
  x1 <- max(1L, as.integer(floor(bb["xmin"])) + 1L)
  x2 <- min(as.integer(dims[1]), as.integer(ceiling(bb["xmax"])))
  y1 <- max(1L, as.integer(floor(bb["ymin"])) + 1L)
  y2 <- min(as.integer(dims[2]), as.integer(ceiling(bb["ymax"])))
  list(x = c(x1, x2), y = c(y1, y2), ok = x1 <= x2 && y1 <= y2)
}

# For one ROI at `level`, return the covered pixel values as a list of numeric
# vectors, one per requested band, read tile-wise.
.roi_pixel_values <- function(geom, img, level, bands) {
  dims <- at_dims(img, level)
  rng <- .bbox_range(geom, dims)
  if (!rng$ok) {
    return(NULL)
  }
  tile <- at_tile(img, level = level, xrange = rng$x, yrange = rng$y, bands = bands)
  # Shift geometry to tile-local coordinates and rasterise a cover.
  local <- .apply_coords(geom, function(m) cbind(m[, 1] - (rng$x[1] - 1), m[, 2] - (rng$y[1] - 1)))
  w <- rng$x[2] - rng$x[1] + 1L
  h <- rng$y[2] - rng$y[1] + 1L
  cover <- .cover(local, c(w, h), touches = FALSE)
  nb <- dim(tile)[3]
  vals <- lapply(seq_len(nb), function(b) tile[, , b][cover])
  list(values = vals, n_px = sum(cover),
       bands = if (is.null(bands)) seq_len(nb) else bands)
}

#' Extract summary statistics under ROIs
#'
#' Compute per-band summary statistics of image values inside each ROI. Works
#' tile-wise and never materialises the whole image.
#'
#' @param project An [annot_project].
#' @param img An [annot_image]; defaults to the project's image.
#' @param stat One or more of `"mean"`, `"median"`, `"sd"`, `"min"`, `"max"`,
#'   `"sum"`, `"n"`, or `"all"` (every statistic).
#' @param layer,label Optional filters.
#' @param level Integer pyramid level. Default `0`.
#' @param bands Optional band indices; all bands by default.
#' @param call The calling environment, for error reporting.
#'
#' @return A long [tibble::tibble] with columns `roi_id`, `layer`, `label`,
#'   `band` (integer), `band_name`, `wavelength` (`NA` when not spectral),
#'   `stat`, `value`, and `n_px`. A 0-row tibble with these columns when nothing
#'   matches.
#' @family extraction
#' @seealso [at_extract_spectrum()], [at_extract_pixels()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' proj <- at_example_project()
#' at_extract(proj, stat = "mean")
at_extract <- function(project, img = NULL, stat = "mean", layer = NULL,
                       label = NULL, level = 0L, bands = NULL,
                       call = rlang::caller_env()) {
  .check_project(project, call = call)
  if (is.null(img)) img <- project$image
  .check_image(img, call = call)
  level <- .check_count(level, call = call)
  stats_req <- if (identical(stat, "all") || "all" %in% stat) {
    c("mean", "median", "sd", "min", "max", "sum", "n")
  } else {
    vapply(stat, function(s) .check_choice(s, names(.extract_stats), call = call), character(1))
  }
  band_tbl <- at_bands(img)
  entries <- .collect_mask_rois(project, layer = layer, label = label, level = level, call = call)
  if (length(entries) == 0L) {
    return(.empty_extract_tbl())
  }
  rows <- list()
  for (e in entries) {
    pv <- .roi_pixel_values(e$geom, img, level, bands)
    if (is.null(pv) || pv$n_px == 0L) next
    for (bi in seq_along(pv$bands)) {
      b <- pv$bands[bi]
      v <- pv$values[[bi]]
      for (s in stats_req) {
        rows[[length(rows) + 1L]] <- tibble::tibble(
          roi_id = e$roi_id, layer = e$layer, label = e$label,
          band = as.integer(b), band_name = band_tbl$name[b],
          wavelength = band_tbl$wavelength[b], stat = s,
          value = as.double(.extract_stats[[s]](v)), n_px = as.integer(pv$n_px)
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(.empty_extract_tbl())
  }
  do.call(rbind, rows)
}

#' Extract mean/median spectra for a spectral cube
#'
#' @inheritParams at_extract
#' @param stat `"mean"` (default) or `"median"`.
#' @return The long tibble of [at_extract()], restricted to spectral bands and
#'   sorted by wavelength.
#' @family extraction
#' @export
at_extract_spectrum <- function(project, img = NULL, stat = "mean", layer = NULL,
                                label = NULL, level = 0L,
                                call = rlang::caller_env()) {
  .check_project(project, call = call)
  if (is.null(img)) img <- project$image
  if (!at_is_spectral(img)) {
    cli::cli_abort(
      c("{.fn at_extract_spectrum} requires a spectral image.",
        "i" = "This image has no wavelengths; use {.fn at_extract}."),
      call = call
    )
  }
  stat <- .check_choice(stat, c("mean", "median"), call = call)
  out <- at_extract(project, img, stat = stat, layer = layer, label = label, level = level, call = call)
  out[order(out$roi_id, out$wavelength), , drop = FALSE]
}

#' Extract per-pixel values under ROIs
#'
#' @inheritParams at_extract
#' @param layer Optional layer filter.
#' @param max_px Maximum number of pixels to extract before aborting. Default
#'   `1e6`.
#' @return A long [tibble::tibble] with columns `roi_id`, `layer`, `label`, `x`,
#'   `y`, `band`, and `value`. A 0-row tibble with these columns when nothing
#'   matches.
#' @family extraction
#' @export
at_extract_pixels <- function(project, img = NULL, layer = NULL, level = 0L,
                              bands = NULL, max_px = 1e6,
                              call = rlang::caller_env()) {
  .check_project(project, call = call)
  if (is.null(img)) img <- project$image
  .check_image(img, call = call)
  level <- .check_count(level, call = call)
  .check_number(max_px, min = 1, call = call)
  empty <- tibble::tibble(
    roi_id = character(0), layer = character(0), label = character(0),
    x = double(0), y = double(0), band = integer(0), value = double(0)
  )
  entries <- .collect_mask_rois(project, layer = layer, level = level, call = call)
  if (length(entries) == 0L) {
    return(empty)
  }
  dims <- at_dims(img, level)
  # Guard against extracting an enormous region.
  total <- 0
  for (e in entries) {
    rng <- .bbox_range(e$geom, dims)
    if (rng$ok) {
      total <- total + (rng$x[2] - rng$x[1] + 1) * (rng$y[2] - rng$y[1] + 1)
    }
  }
  if (total > max_px) {
    cli::cli_abort(
      c("Per-pixel extraction would touch about {round(total)} pixels, over {.arg max_px} = {max_px}.",
        "i" = "Subsample, restrict with {.arg layer}, or use {.fn at_extract}."),
      call = call
    )
  }
  rows <- list()
  for (e in entries) {
    rng <- .bbox_range(e$geom, dims)
    if (!rng$ok) next
    tile <- at_tile(img, level = level, xrange = rng$x, yrange = rng$y, bands = bands)
    local <- .apply_coords(e$geom, function(m) cbind(m[, 1] - (rng$x[1] - 1), m[, 2] - (rng$y[1] - 1)))
    w <- rng$x[2] - rng$x[1] + 1L
    h <- rng$y[2] - rng$y[1] + 1L
    cover <- .cover(local, c(w, h), touches = FALSE)
    idx <- which(cover, arr.ind = TRUE)
    if (nrow(idx) == 0L) next
    px_x <- rng$x[1] + idx[, 2] - 1L
    px_y <- rng$y[1] + idx[, 1] - 1L
    nb <- dim(tile)[3]
    band_ids <- if (is.null(bands)) seq_len(nb) else bands
    for (bi in seq_len(nb)) {
      vals <- tile[, , bi][cover]
      rows[[length(rows) + 1L]] <- tibble::tibble(
        roi_id = e$roi_id, layer = e$layer, label = e$label,
        x = as.double(px_x), y = as.double(px_y),
        band = as.integer(band_ids[bi]), value = as.double(vals)
      )
    }
  }
  if (length(rows) == 0L) {
    return(empty)
  }
  do.call(rbind, rows)
}
