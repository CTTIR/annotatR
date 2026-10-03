# Extraction of image/spectral values under ROIs. Each ROI reads one tile
# covering its clipped bounding box. An image-sized ROI can therefore allocate
# an image-sized tile; extraction is not streamed within that bounding box.

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
    unit = character(0), stat = character(0), value = double(0),
    n_px = integer(0), n_valid = integer(0), n_invalid = integer(0)
  )
}

# Metadata travels with empty and populated summaries; the raster backend is
# display-converted and cannot certify original high-bit-depth intensities.
.extract_metadata <- function(out, img, level, nonfinite) {
  attr(out, "analysis") <- list(
    nonfinite = nonfinite, count_unit = "selected pixels per ROI and band",
    level = level, bands = at_bands(img), backend = img$backend,
    source = img[["source_descriptor"]],
    sample_contract = if (img$backend == "raster") "display-converted-0-255" else
      img[["meta"]][["reader_contract"]][["samples"]] %||%
        if (img$backend == "envi") "raw-scalar-v1" else "backend-defined",
    limitations = c("Overlapping ROIs count shared pixels separately.",
      "One bounding-box tile per ROI; no within-ROI streaming.",
      if (img$backend == "raster") "Raster values use display conversion; original high-bit-depth intensities are not preserved."))
  out
}

# Extraction bounds use the same centre intervals as polygon masks. Points
# (and conservatively other non-areal geometry) need their containing cells,
# including an integer-coordinate maximum that belongs to the next cell.
.bbox_range <- function(geom, dims) {
  bb <- sf::st_bbox(geom)
  if (any(!is.finite(bb))) return(list(x = c(1L, 0L), y = c(1L, 0L), ok = FALSE))
  type <- as.character(sf::st_geometry_type(sf::st_sfc(geom)))
  if (type %in% c("POLYGON", "MULTIPOLYGON")) {
    x <- .centre_range(bb["xmin"], bb["xmax"], dims[1])
    y <- .centre_range(bb["ymin"], bb["ymax"], dims[2])
  } else {
    # Native line rasterisation can include the cell before an integer lower
    # endpoint. Keep one conservative border cell without changing membership.
    point <- type %in% c("POINT", "MULTIPOINT")
    cell_range <- function(lower, upper, size) {
      as.integer(c(max(1, min(size + 1, floor(lower) + as.integer(point))),
                   max(0, min(size, floor(upper) + 1))))
    }
    x <- cell_range(bb["xmin"], bb["xmax"], dims[1])
    y <- cell_range(bb["ymin"], bb["ymax"], dims[2])
  }
  list(x = x, y = y, ok = x[1] <= x[2] && y[1] <= y[2])
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
  # Classify unchanged geometry at global centres within the tile window.
  w <- rng$x[2] - rng$x[1] + 1L
  h <- rng$y[2] - rng$y[1] + 1L
  cover <- .cover(geom, c(w, h), touches = FALSE,
                  origin = c(rng$x[1] - 1, rng$y[1] - 1))
  nb <- dim(tile)[3]
  vals <- lapply(seq_len(nb), function(b) tile[, , b][cover])
  list(values = vals, n_px = sum(cover),
       bands = if (is.null(bands)) seq_len(nb) else bands)
}

# Alternate images assert registration on the same full-resolution grid. Their
# overview grids may differ, so bridge through project level zero when needed.
.collect_extract_rois <- function(project, img, layer = NULL, label = NULL,
                                  level = 0L, call = rlang::caller_env()) {
  base <- at_dims(project$image, 0L, call = call)
  target_base <- at_dims(img, 0L, call = call)
  if (!identical(as.numeric(base), as.numeric(target_base))) {
    cli::cli_abort(
      c("Extraction images must share the same level-0 grid extent.",
        "i" = "Different extents require explicit spatial alignment before extraction."),
      call = call)
  }
  target <- at_dims(img, level, call = call)
  if (level < project$image$n_levels &&
      identical(as.numeric(at_dims(project$image, level)), as.numeric(target))) {
    # Preserve identity/same-grid arithmetic and the reviewed membership inputs.
    return(.collect_mask_rois(project, layer, label, level, call = call))
  }
  entries <- .collect_mask_rois(project, layer, label, 0L, call = call)
  lapply(entries, function(e) {
    e$geom <- .geom_to_level(sf::st_sfc(e$geom, crs = sf::NA_crs_), level, img)[[1]]
    e
  })
}

#' Extract summary statistics under ROIs
#'
#' Compute per-band summary statistics of image values inside each ROI. Reads
#' one tile covering each ROI's clipped bounding box; an image-sized bounding
#' box can allocate an image-sized tile. Polygon centre membership
#' and point containing cells follow the pixel-coverage contract in [at_mask()].
#' For example, point `(5, 5)` selects matrix row 6, column 6.
#'
#' @param project An [annot_project].
#' @param img An [annot_image]; defaults to the project's image. Supplying an
#'   alternate image asserts spatial registration on the same level-0 pixel
#'   grid. Its level-0 extent must match; differing pyramid dimensions are
#'   handled using the alternate image's actual level dimensions.
#' @param stat One or more of `"mean"`, `"median"`, `"sd"`, `"min"`, `"max"`,
#'   `"sum"`, `"n"`, or `"all"` (every statistic).
#' @param layer,label Optional filters.
#' @param level Integer pyramid level. Default `0`.
#' @param bands Optional band indices; all bands by default.
#' @param nonfinite Policy for NA, NaN and infinite samples: `"propagate"`
#'   (default) returns NA statistics for any affected ROI/band; `"omit"` uses
#'   finite samples only; `"error"` aborts on selected nonfinite samples.
#'   `n` always counts selected pixels. A wholly invalid selection has NA
#'   statistics under omit (including sum); singleton sample SD is NA.
#' @param call The calling environment, for error reporting.
#'
#' @return A long [tibble::tibble] with columns `roi_id`, `layer`, `label`,
#'   `band` (integer), `band_name`, `wavelength` (`NA` when not spectral),
#'   `unit` (declared wavelength unit, NA if unknown), `stat`, `value`, `n_px`
#'   (selected support), `n_valid` (finite samples), and `n_invalid`.
#'   Empty selections produce zero rows. Band order follows requested indices;
#'   wavelength values and units are preserved, without implicit conversion.
#'   The `analysis` attribute records policy, level, source, bands and limitations.
#'   Values come directly from tiles, independently of display contrast. The
#'   raster backend itself uses display conversion and cannot preserve original
#'   high-bit-depth samples; raw TIFF/OME/ENVI readers have separate contracts.
#' @family extraction
#' @seealso [at_extract_spectrum()], [at_extract_pixels()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' proj <- at_example_project()
#' at_extract(proj, stat = "mean")
at_extract <- function(project, img = NULL, stat = "mean", layer = NULL,
                       label = NULL, level = 0L, bands = NULL,
                       call = rlang::caller_env(), nonfinite = c("propagate", "omit", "error")) {
  nonfinite <- .check_choice(nonfinite, c("propagate", "omit", "error"), default = missing(nonfinite), call = call)
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
  entries <- .collect_extract_rois(project, img, layer = layer, label = label, level = level, call = call)
  if (length(entries) == 0L) {
    return(.extract_metadata(.empty_extract_tbl(), img, level, nonfinite))
  }
  rows <- list()
  for (e in entries) {
    pv <- .roi_pixel_values(e$geom, img, level, bands)
    if (is.null(pv) || pv$n_px == 0L) next
    for (bi in seq_along(pv$bands)) {
      b <- pv$bands[bi]
      v <- pv$values[[bi]]
      valid <- is.finite(v)
      n_valid <- sum(valid)
      n_invalid <- length(v) - n_valid
      if (nonfinite == "error" && n_invalid > 0L)
        cli::cli_abort("Selected nonfinite samples in ROI {.val {e$roi_id}}, band {b}.", call = call)
      samples <- if (nonfinite == "omit") v[valid] else v
      for (s in stats_req) {
        value <- if (s == "n") pv$n_px else if (!length(samples) ||
          (nonfinite == "propagate" && n_invalid > 0L)) NA_real_ else .extract_stats[[s]](samples)
        rows[[length(rows) + 1L]] <- tibble::tibble(
          roi_id = e$roi_id, layer = e$layer, label = e$label,
          band = as.integer(b), band_name = band_tbl$name[b],
          wavelength = band_tbl$wavelength[b], unit = band_tbl$unit[b], stat = s,
          value = as.double(value), n_px = as.integer(pv$n_px),
          n_valid = as.integer(n_valid), n_invalid = as.integer(n_invalid)
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(.extract_metadata(.empty_extract_tbl(), img, level, nonfinite))
  }
  .extract_metadata(do.call(rbind, rows), img, level, nonfinite)
}

#' Extract mean/median spectra for a spectral cube
#'
#' @inheritParams at_extract
#' @param stat `"mean"` (default) or `"median"`.
#' @return The long tibble of [at_extract()], restricted to spectral bands and
#'   sorted by ROI, declared unit, wavelength, then band index. Values are not
#'   converted between units; equal wavelengths retain band order.
#' @family extraction
#' @export
#' @examples
#' cube <- at_example_image("cube")
#' proj <- at_project(cube, at_layer_add(at_layer("roi"),
#'                                       at_roi_circle(16, 16, 5, label = "roi")))
#' at_extract_spectrum(proj)
at_extract_spectrum <- function(project, img = NULL, stat = "mean", layer = NULL,
                                label = NULL, level = 0L,
                                call = rlang::caller_env(), nonfinite = c("propagate", "omit", "error")) {
  nonfinite <- .check_choice(nonfinite, c("propagate", "omit", "error"), default = missing(nonfinite), call = call)
  .check_project(project, call = call)
  if (is.null(img)) img <- project$image
  if (!at_is_spectral(img)) {
    cli::cli_abort(
      c("{.fn at_extract_spectrum} requires a spectral image.",
        "i" = "This image has no wavelengths; use {.fn at_extract}."),
      call = call
    )
  }
  stat <- .check_choice(stat, c("mean", "median"), default = missing(stat), call = call)
  out <- at_extract(project, img, stat = stat, layer = layer, label = label, level = level, call = call, nonfinite = nonfinite)
  out[order(out$roi_id, out$unit, out$wavelength, out$band), , drop = FALSE]
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
  entries <- .collect_extract_rois(project, img, layer = layer, level = level, call = call)
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
    w <- rng$x[2] - rng$x[1] + 1L
    h <- rng$y[2] - rng$y[1] + 1L
    cover <- .cover(e$geom, c(w, h), touches = FALSE,
                    origin = c(rng$x[1] - 1, rng$y[1] - 1))
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
