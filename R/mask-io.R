# Mask input/output. The primary format is integer TIFF with a self-describing
# sidecar JSON legend, which is what makes a mask consumable downstream.

# ---- Writing ---------------------------------------------------------------

#' Write a mask to disk
#'
#' @param mask An `annot_mask`.
#' @param path Output file path.
#' @param format `"tiff"` (default), `"png"` (8-bit only), or `"rds"`
#'   (full-fidelity `annot_mask`).
#' @param bits Integer bit depth for TIFF: `16` (default) or `8`.
#' @param legend Logical; also write a `<path>.legend.json` sidecar describing
#'   the mask. Default `TRUE`.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return The output path, invisibly.
#' @family masks
#' @seealso [at_read_mask()]
#' @export
at_write_mask <- function(mask, path, format = c("tiff", "png", "rds"),
                          bits = c(16L, 8L), legend = TRUE, overwrite = FALSE,
                          call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  .check_string(path, call = call)
  format <- .check_choice(format, c("tiff", "png", "rds"), call = call)
  bits <- .check_choice(bits, c(16L, 8L), call = call)
  .check_flag(legend, call = call)
  .check_flag(overwrite, call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(
      c("{.path {path}} already exists.",
        "i" = "Pass {.code overwrite = TRUE} to replace it."),
      call = call
    )
  }
  m <- as.matrix(mask)
  storage.mode(m) <- "integer"
  maxv <- max(m, 0L)
  if (format == "rds") {
    saveRDS(mask, path)
  } else if (format == "png") {
    if (maxv > 255L) {
      cli::cli_abort(
        c("PNG masks are 8-bit but this mask has values up to {maxv}.",
          "i" = "Use {.code format = \"tiff\"}."),
        call = call
      )
    }
    .write_mask_raster(m, path, bits = 8L, format = "png", call = call)
  } else {
    if (maxv > 2^bits - 1L) {
      cli::cli_abort(
        c("Mask values up to {maxv} exceed the {bits}-bit range.",
          "i" = "Use {.code bits = 16} or wider."),
        call = call
      )
    }
    .write_mask_raster(m, path, bits = bits, format = "tiff", call = call)
  }
  if (legend && format != "rds") {
    .write_legend_json(mask, paste0(path, ".legend.json"))
  }
  invisible(path)
}

.write_mask_raster <- function(m, path, bits, format, call) {
  if (requireNamespace("tiff", quietly = TRUE) && format == "tiff") {
    tiff::writeTIFF(m / (2^bits - 1), path, bits.per.sample = as.integer(bits))
    return(invisible(path))
  }
  if (requireNamespace("magick", quietly = TRUE)) {
    arr <- array(m / (2^bits - 1), dim = c(dim(m), 1L))
    img <- magick::image_read(arr)
    magick::image_write(img, path, format = format)
    return(invisible(path))
  }
  if (requireNamespace("stars", quietly = TRUE) && format == "tiff") {
    st <- stars::st_as_stars(list(v = m))
    stars::write_stars(st, path)
    return(invisible(path))
  }
  cli::cli_abort(c(
    "Writing a {format} mask requires package {.pkg tiff} or {.pkg magick}.",
    "i" = "Install one, or use {.code format = \"rds\"}."
  ), call = call)
}

.write_legend_json <- function(mask, path) {
  payload <- list(
    annotatR_version = .pkg_version(),
    created = format(attr(mask, "created"), "%Y-%m-%dT%H:%M:%S%z"),
    mask_type = attr(mask, "mask_type"),
    level = attr(mask, "level"),
    dims = attr(mask, "dims"),
    source_project = attr(mask, "source_project"),
    legend = attr(mask, "legend")
  )
  jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = TRUE, na = "null")
  invisible(path)
}

# ---- Reading / polygonising ------------------------------------------------

# Read a mask file to an integer matrix in image orientation.
.read_mask_matrix <- function(path, call) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") {
    obj <- readRDS(path)
    return(list(m = as.matrix(obj), mask = obj))
  }
  if (requireNamespace("tiff", quietly = TRUE) && ext %in% c("tif", "tiff")) {
    raw <- suppressWarnings(tiff::readTIFF(path, as.is = TRUE))
    if (length(dim(raw)) == 3L) raw <- raw[, , 1]
    return(list(m = matrix(as.integer(round(raw)), nrow = nrow(raw)), mask = NULL))
  }
  if (requireNamespace("magick", quietly = TRUE)) {
    img <- magick::image_read(path)
    dat <- magick::image_data(img, channels = "gray")
    m <- t(matrix(as.integer(dat[1, , ]), nrow = dim(dat)[2]))
    return(list(m = m, mask = NULL))
  }
  cli::cli_abort("Reading {.path {path}} requires package {.pkg tiff} or {.pkg magick}.",
                 call = call)
}

#' Read a mask into editable ROIs
#'
#' Polygonise an existing mask file (e.g. Cellpose, StarDist, or QuPath output,
#' or a prior annotatR export) into an editable [annot_layer]. A sidecar
#' `<path>.legend.json` is used to recover labels when present.
#'
#' @param path Path to a mask file (TIFF, PNG, or RDS).
#' @param level Integer pyramid level to record on the ROIs. Default `0`.
#' @param connectivity `8` (default) or `4` pixel connectivity.
#' @param simplify Non-negative simplification tolerance for the polygons.
#' @param min_area Minimum polygon area in pixels to keep. Default `0`.
#' @param legend Optional legend tibble (`value`, `label`) overriding the
#'   sidecar / pixel-value labelling.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_layer] with one ROI per connected region.
#' @family masks
#' @seealso [at_write_mask()], [at_mask()]
#' @export
at_read_mask <- function(path, level = 0L, connectivity = c(8L, 4L),
                         simplify = 0, min_area = 0, legend = NULL,
                         call = rlang::caller_env()) {
  .check_file(path, call = call)
  level <- .check_count(level, call = call)
  connectivity <- .check_choice(connectivity, c(8L, 4L), call = call)
  .check_number(simplify, min = 0, call = call)
  .check_number(min_area, min = 0, call = call)
  rd <- .read_mask_matrix(path, call = call)
  m <- rd$m
  height <- nrow(m)
  width <- ncol(m)
  # Recover a value -> label map.
  side <- paste0(path, ".legend.json")
  lg <- legend
  if (is.null(lg) && file.exists(side)) {
    lg <- tryCatch({
      j <- jsonlite::read_json(side, simplifyVector = TRUE)
      tibble::as_tibble(j$legend)
    }, error = function(e) NULL)
  }
  # Build a stars object matching the rasterisation grid and polygonise.
  stars_mat <- t(m[height:1, , drop = FALSE])
  bb <- sf::st_bbox(c(xmin = 0, ymin = 0, xmax = width, ymax = height))
  st <- stars::st_as_stars(bb, nx = as.integer(width), ny = as.integer(height),
                           values = 0L)
  st[[1]][] <- stars_mat
  sfp <- suppressWarnings(sf::st_as_sf(st, as_points = FALSE, merge = TRUE))
  names(sfp)[1] <- "value"
  sfp <- sfp[sfp$value != 0, , drop = FALSE]
  lyr <- at_layer(tools::file_path_sans_ext(basename(path)))
  if (nrow(sfp) == 0L) {
    return(lyr)
  }
  for (i in seq_len(nrow(sfp))) {
    v <- sfp$value[i]
    g <- sf::st_geometry(sfp)[i]
    # Rasterisation interprets image coordinates directly as the raster's
    # coordinate space (only the output matrix is flipped), so polygonisation is
    # its exact inverse and needs no y-flip.
    if (simplify > 0) {
      g <- sf::st_simplify(g, dTolerance = simplify, preserveTopology = TRUE)
    }
    if (min_area > 0 && as.numeric(sf::st_area(g)) < min_area) {
      next
    }
    label <- if (!is.null(lg) && v %in% lg$value) {
      as.character(lg$label[match(v, lg$value)])
    } else {
      as.character(v)
    }
    roi <- at_roi_from_sf(g, label = label, level = level, source = "mask")
    lyr <- at_layer_add(lyr, roi)
  }
  lyr
}

#' Batch-write the masks of a project
#'
#' @param project An [annot_project].
#' @param dir Output directory (created if needed).
#' @param per One of `"layer"`, `"roi"`, `"class"`, or `"project"`; controls how
#'   masks are split into files.
#' @param type Mask type passed to [at_mask()].
#' @param level Integer pyramid level. Default `0`.
#' @param overwrite Logical; overwrite existing files. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return An invisible export-receipt [tibble::tibble] with columns `path`,
#'   `type`, `n_px`, and `bytes`.
#' @family masks
#' @export
at_write_masks <- function(project, dir, per = c("layer", "roi", "class", "project"),
                           type = "labelled", level = 0L, overwrite = FALSE,
                           call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(dir, call = call)
  per <- .check_choice(per, c("layer", "roi", "class", "project"), call = call)
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }
  base <- project$meta$name %||% "project"
  jobs <- switch(
    per,
    project = list(list(name = base, mask = at_mask(project, type = type, level = level))),
    layer = lapply(names(project$layers), function(nm) {
      list(name = paste0(base, "_", nm),
           mask = at_mask(project, type = type, layer = nm, level = level))
    }),
    class = {
      labs <- unique(at_rois(project)$label)
      lapply(labs, function(lb) {
        list(name = paste0(base, "_", lb),
             mask = at_mask(project, type = type, label = lb, level = level))
      })
    },
    roi = {
      d <- at_dims(project$image, level)
      entries <- list()
      for (nm in names(project$layers)) {
        for (r in project$layers[[nm]]$rois) {
          entries[[length(entries) + 1L]] <- list(
            name = paste0(base, "_", r$id),
            mask = at_mask(r, type = type, level = level, dims = d)
          )
        }
      }
      entries
    }
  )
  rows <- lapply(jobs, function(j) {
    p <- file.path(dir, paste0(j$name, ".tif"))
    at_write_mask(j$mask, p, format = "tiff", overwrite = overwrite)
    tibble::tibble(
      path = p, type = type,
      n_px = as.integer(sum(as.matrix(j$mask) != 0)),
      bytes = as.integer(file.info(p)$size)
    )
  })
  invisible(do.call(rbind, rows))
}
