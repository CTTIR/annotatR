# Mask input/output. The primary format is integer TIFF with a self-describing
# sidecar JSON legend, which is what makes a mask consumable downstream.

# ---- Writing ---------------------------------------------------------------

#' Write a mask to disk
#'
#' @param mask An `annot_mask`.
#' @param path Output file path.
#' @param format `"tiff"` (default), `"png"` (8-bit only), or `"rds"`
#'   (full-fidelity `annot_mask`).
#' @param bits Single finite whole-number bit depth for TIFF: `16` (default)
#'   or `8`, including `16L`/`8L`. Explicit vectors are rejected.
#' @param legend Logical; also write a `<path>.legend.json` sidecar describing
#'   the mask. Default `TRUE`.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @details TIFF exports preserve unsigned 8/16-bit codes; PNG exports are
#'   unsigned 8-bit only, regardless of `bits`. Samples must be finite integers
#'   in the selected unsigned range; invalid samples reject before writing.
#'   TIFF writing requires `tiff` or a capable `magick` build. PNG writing
#'   requires `magick` with exact grayscale support. Missing exact conversion
#'   capability produces an error rather than a quantized output. The caller's
#'   explicit path is respected. Mask and legend are staged before either is
#'   replaced; a preexisting sidecar also requires `overwrite=TRUE`. Publication
#'   failure rolls back prior files. Concurrent writers must be serialized.
#'
#' @return The output path, invisibly.
#' @family masks
#' @seealso [at_read_mask()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "labelled")
#' f <- tempfile(fileext = ".tif")
#' at_write_mask(m, f)
at_write_mask <- function(mask, path, format = c("tiff", "png", "rds"),
                          bits = c(16L, 8L), legend = TRUE, overwrite = FALSE,
                          call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  .check_string(path, call = call)
  format <- .check_choice(format, c("tiff", "png", "rds"), default = missing(format), call = call)
  bits <- .check_choice(bits, c(16L, 8L), default = missing(bits), call = call)
  .check_flag(legend, call = call)
  .check_flag(overwrite, call = call)
  paths <- c(path, if(legend && format != "rds") paste0(path,".legend.json"))
  .export_bundle(paths, function(stage) {
  path <- stage[1]
  m <- .mask_info(mask)$m
  maxv <- max(m, 0L)
  if (format != "rds" && any(m < 0)) cli::cli_abort("TIFF/PNG masks require unsigned samples in range starting at zero.", call = call)
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
          "i" = "Use {.code bits = 16} for values up to 65535, or {.code format = \"rds\"} for wider codes."),
        call = call
      )
    }
    .write_mask_raster(m, path, bits = bits, format = "tiff", call = call)
  }
  if (legend && format != "rds") {
    .write_legend_json(mask, stage[2])
  }
  }, overwrite=overwrite)
  invisible(path)
}

.write_mask_raster <- function(m, path, bits, format, call) {
  bits <- .check_choice(bits, c(16L, 8L), call = call)
  format <- .check_choice(format, c("tiff", "png"), call = call)
  values <- .mask_integers(m, "Raster mask samples")
  if (length(dim(m)) != 2L || any(dim(m) < 1L) || any(values < 0 | values > 2^bits - 1)) {
    cli::cli_abort("Raster mask samples must be a nonempty matrix in the unsigned {bits}-bit range.", call = call)
  }
  if (requireNamespace("tiff", quietly = TRUE) && format == "tiff") {
    tiff::writeTIFF(m / (2^bits - 1), path, bits.per.sample = as.integer(bits))
    return(invisible(path))
  }
  if (requireNamespace("magick", quietly = TRUE)) {
    .mask_magick_require(bits, call)
    img <- magick::image_read(.mask_pgm_encode(m, bits))
    # Pin both depth and colour type: PNG otherwise optimizes binary masks to
    # one bit, and an unconstrained TIFF may inherit the build's quantum depth.
    defines <- if (format == "png") c("png:bit-depth" = as.character(bits), "png:color-type" = "0") else NULL
    magick::image_write(img, path, format = format, depth = bits,
                        compression = "none", defines = defines)
    return(invisible(path))
  }
  cli::cli_abort(c(
    "Writing an exact {format} mask requires package {.pkg tiff} (TIFF) or {.pkg magick}.",
    "i" = "Install a capable writer, or use {.code format = \"rds\"}."
  ), call = call)
}

.write_legend_json <- function(mask, path, storage = NULL) {
  info <- .mask_info(mask)
  if (!is.null(info[["metadata"]][["source"]][["descriptor"]])) {
    info[["metadata"]][["source"]][["descriptor"]][["options"]] <- .mask_options_encode(info[["metadata"]][["source"]][["descriptor"]][["options"]])
    info[["metadata"]][["source"]][["descriptor"]][["options_encoding"]] <- "typed-json-v2"
  }
  payload <- list(
    mask_metadata = info[["metadata"]],
    storage = storage,
    annotatR_version = .pkg_version(),
    created = format(attr(mask, "created"), "%Y-%m-%dT%H:%M:%S%z"),
    mask_type = attr(mask, "mask_type"),
    level = attr(mask, "level"),
    dims = attr(mask, "dims"),
    source_project = attr(mask, "source_project"),
    legend = info$legend
  )
  jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null", digits = 17)
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
  if (ext == "npy") {
    return(list(m = .npy_read_matrix(path, call = call), mask = NULL))
  }
  if (ext %in% c("tif", "tiff")) {
    planes <- .tiff_raw_read(path)
    if (length(planes)!=1L || length(dim(planes[[1]])) != 2L) cli::cli_abort("Only a single 2-D TIFF mask plane is supported.", call = call)
    raw <- planes[[1]]
    values <- .mask_integers(raw, "TIFF mask samples")
    return(list(m = matrix(values, nrow = nrow(raw)), mask = NULL))
  }
  if (ext == "png") {
    header <- .mask_png_header(path, call)
    .mask_magick_require(header$bits, call)
    img <- magick::image_read(path)
    if (length(img) != 1L) cli::cli_abort("Only one grayscale PNG mask plane is supported.", call = call)
    m <- .mask_pgm_decode(magick::image_write(img, format = "pgm", depth = header$bits), header$bits)
    if (!identical(dim(m), c(header$height, header$width))) cli::cli_abort("PNG decoder returned inconsistent dimensions.", call = call)
    return(list(m = m, mask = NULL))
  }
  cli::cli_abort("Unsupported mask format; use TIFF, 8/16-bit grayscale PNG, RDS or NPY.", call = call)
}

#' Read a mask into editable ROIs
#'
#' Polygonise an existing mask file (e.g. Cellpose, StarDist, or QuPath output,
#' or a prior annotatR export) into an editable [annot_layer]. Explicit metadata
#' and legend/level arguments take precedence over embedded RDS metadata, then
#' the `<path>.legend.json` sidecar. Bitfields polygonise each class membership.
#' Legacy masks default to exclusive values and zero background, recorded as
#' `legacy-default`; incomplete legacy bitfield legends require an explicit
#' encoding override. Malformed/future metadata and inconsistent dimensions
#' fail rather than silently discarding labels. Sampled previews or translated
#' grids cannot be polygonised as editable ROIs; import the original-resolution
#' mask with unit stride and zero origin.
#'
#' @param path Path to a mask file (TIFF, PNG, RDS, or NPY). NPY sidecar storage
#'   orientation is recovered automatically for polygonisation. PNG input must
#'   be unsigned 8/16-bit grayscale without palette, colour, alpha channels or
#'   `tRNS` transparency;
#'   original class codes are preserved. TIFF requires the raw `tiff` reader;
#'   PNG requires a `magick` build with exact grayscale capability.
#' @param level Integer pyramid level to record on the ROIs. `NULL` (default)
#'   uses the RDS mask or legend sidecar level, falling back to 0 for an
#'   external mask without level metadata. An explicit level overrides metadata.
#' @param connectivity Single finite whole number `8` (default) or `4`,
#'   including `8L`/`4L`. Eight-connectivity joins corner-touching pixels into
#'   one ROI; four-connectivity requires shared edges. Explicit vectors reject.
#' @param simplify Non-negative simplification tolerance for the polygons.
#' @param min_area Minimum polygon area in pixels to keep. Default `0`.
#' @param legend Optional legend tibble (`value`, `label`) overriding the
#'   embedded / sidecar / pixel-value labelling.
#' @param metadata Optional named list overriding semantic `mask_metadata`
#'   fields, such as `encoding`, `background`, or `source`. Nested grid fields
#'   merge with recovered metadata. Explicit `level` and `legend` take precedence
#'   over this list. Overrides do not resample pixels. Stored versioned metadata
#'   must be structurally valid before overrides are applied.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_layer] with one ROI per connected region. Recovered semantic
#'   metadata is retained in `layer$meta$mask_metadata`, including empty layers.
#' @family masks
#' @seealso [at_write_mask()], [at_mask()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "labelled")
#' f <- tempfile(fileext = ".tif")
#' at_write_mask(m, f)
#' at_read_mask(f)
at_read_mask <- function(path, level = NULL, connectivity = c(8L, 4L),
                         simplify = 0, min_area = 0, legend = NULL,
                         call = rlang::caller_env(), metadata = NULL) {
  .check_file(path, call = call)
  connectivity <- .check_choice(connectivity, c(8L, 4L), default = missing(connectivity), call = call)
  .check_number(simplify, min = 0, call = call)
  .check_number(min_area, min = 0, call = call)
  rd <- .read_mask_matrix(path, call = call)
  # Embedded metadata is authoritative; an unrelated sidecar cannot corrupt it.
  sidecar <- if (!is.null(attr(rd$mask, "mask_metadata"))) NULL else .mask_read_sidecar(path)
  if (!is.null(sidecar[["storage"]])) {
    .mask_validate_storage(rd$m, sidecar[["storage"]])
    if (identical(sidecar[["storage"]][["axes"]], "xy")) rd$m <- t(rd$m)
  }
  recovered <- .mask_recover(rd$m, rd$mask, sidecar, level, legend, metadata)
  info <- .mask_info(recovered)
  if (any(info[["metadata"]]$grid$stride != 1) || any(info[["metadata"]]$grid$origin != 0)) {
    cli::cli_abort("Cannot polygonise a sampled or translated mask grid; import the original-resolution mask.", call = call)
  }
  m <- info$m; lg <- info$legend; level <- info[["metadata"]]$grid$level
  height <- nrow(m); width <- ncol(m)
  lyr <- at_layer(tools::file_path_sans_ext(basename(path)))
  lyr$meta$mask_metadata <- info[["metadata"]]
  # Polygonise class membership individually: composite bit samples belong to
  # each contributing class, while category 3 remains its own exclusive class.
  for (k in seq_len(nrow(lg))) {
    member <- .mask_membership(m, lg$value[k], info[["metadata"]]$encoding)
    if (!any(member)) next
    stars_mat <- t(member[height:1, , drop = FALSE])
    bb <- sf::st_bbox(c(xmin = 0, ymin = 0, xmax = width, ymax = height))
    st <- stars::st_as_stars(bb, nx = as.integer(width), ny = as.integer(height), values = 0L)
    st[[1]][] <- stars_mat
    # Membership is exactly 0/1. The floating polygonizer honours connect8
    # even on GDAL builds whose integer polygonizer ignores this option.
    sfp <- suppressWarnings(sf::st_as_sf(st, as_points = FALSE, merge = TRUE,
                                          connect8 = (connectivity == 8L), use_integer = FALSE))
    sfp <- sfp[sfp[[1]] != 0, , drop = FALSE]
    for (i in seq_len(nrow(sfp))) {
      g <- sf::st_geometry(sfp)[i]
      # Eight-connected pixel regions may have point-touching polygon rings.
      # Represent those generated rings as valid multipart geometry before
      # creating an ROI; this preserves the exact raster membership.
      if (connectivity == 8L) g <- sf::st_make_valid(g)
      if (simplify > 0) g <- sf::st_simplify(g, dTolerance = simplify, preserveTopology = TRUE)
      if (min_area > 0 && as.numeric(sf::st_area(g)) < min_area) next
      roi <- at_roi_from_sf(g, label = lg$label[k], level = level, source = "mask")
      lyr <- at_layer_add(lyr, roi)
    }
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
#'   `type`, `n_px`, `bytes`, `name`, `status`, `message`, `sidecar_path`, and
#'   `sidecar_bytes`. Counts and bytes use double precision. Display names are
#'   retained in `name`; filenames use safe components with unique suffixes.
#'   Each item is `"ok"`, `"error"`, or `"skipped"`; one failure does not abort
#'   later items. A TIFF and its legend form one staged output bundle.
#'
#' @details Output plans reject symlinked descendants and aliases before writing.
#'   Callers must serialize concurrent writes and keep destination paths stable;
#'   preflight plus staged renames is not a race-free filesystem transaction.
#' @family masks
#' @export
at_write_masks <- function(project, dir, per = c("layer", "roi", "class", "project"),
                           type = c("labelled", "binary", "multiclass"),
                           level = 0L, overwrite = FALSE,
                           call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(dir, call = call)
  per <- .check_choice(per, c("layer", "roi", "class", "project"), default = missing(per), call = call)
  type <- .check_choice(type, c("labelled", "binary", "multiclass"), default = missing(type), call = call)
  .check_flag(overwrite, call=call)
  base <- project$meta$name %||% "project"
  jobs <- list()
  add <- function(name, make) {
    jobs[[length(jobs)+1L]] <<- list(name=name,stem=name,ext=".tif",sidecar=TRUE,make=make)
  }
  if(per=="project") add(base,function() at_mask(project,type=type,level=level))
  if(per=="layer") for(nm in names(project$layers)) local({
    layer <- nm; add(paste0(base,"_",layer),function() at_mask(project,type=type,layer=layer,level=level))
  })
  if(per=="class") for(lb in unique(at_rois(project)$label)) local({
    label <- lb; add(paste0(base,"_",label),function() at_mask(project,type=type,label=label,level=level))
  })
  if(per=="roi") for(L in project$layers) for(r in L$rois) local({
    roi <- r; add(paste0(base,"_",roi$id),function() at_mask(roi,type=type,level=level,dims=at_dims(project$image,level),image=project$image))
  })
  jobs <- .export_plan(dir,jobs)
  rows <- lapply(jobs,function(j) {
    n_px <- NA_real_
    result <- .export_outcome(j$paths,function(stage) {
      mask <- j$make()
      n_px <<- as.double(sum(as.matrix(mask)!=0))
      at_write_mask(mask,stage[1],format="tiff",legend=FALSE)
      .write_legend_json(mask,stage[2])
    },overwrite)
    tibble::tibble(path=j$paths[1],type=type,n_px=n_px,bytes=result$bytes,
      name=j$name,status=result$status,message=result$message,
      sidecar_path=j$paths[2],sidecar_bytes=result$sidecar_bytes)
  })
  receipt <- if(length(rows)) do.call(rbind,rows) else tibble::tibble(
    path=character(),type=character(),n_px=double(),bytes=double(),name=character(),
    status=character(),message=character(),sidecar_path=character(),sidecar_bytes=double())
  invisible(receipt)
}
