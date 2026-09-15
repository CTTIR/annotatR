# Partner manifest: a sanitised, versioned description of annotatR objects for
# the qupflowR contract. It records identities, dimensions, planes, coordinate
# convention, band/wavelength metadata, digests and provenance. Local absolute
# paths never appear: files are identified by basename, role and SHA-256.

# ---- Annotation records and revision ----------------------------------------

.iso_time <- function(t) {
  if (is.null(t) || length(t) != 1L || is.na(t)) {
    return(NA_character_)
  }
  format(as.POSIXct(t), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

.geometry_fidelity <- function(r) {
  if (identical(r$attributes$qupath$geometry_fidelity, "approximated") ||
      isTRUE(r$attributes$shape %in% c("circle", "ellipse"))) {
    return("approximated")
  }
  "exact"
}

.roi_plane <- function(r) {
  p <- r$attributes$plane
  if (!is.list(p)) {
    return(list(c = NA_integer_, z = 0L, t = 0L))
  }
  list(c = as.integer(p$c %||% NA_integer_), z = as.integer(p$z %||% 0L),
       t = as.integer(p$t %||% 0L))
}

.geometry_sha256 <- function(geom) {
  .sha256_bytes(sf::st_as_binary(geom, EWKB = FALSE, endian = "little")[[1]])
}

# Stable record of one ROI. Timestamps and authors are excluded from the
# revision digest (they are not annotation content) but kept in the manifest.
.roi_record <- function(r, layer_name, image_id = NA_character_) {
  bb <- as.numeric(sf::st_bbox(r$geometry))
  attrs <- r$attributes[setdiff(names(r$attributes), c("qupath", "qupflowr", "plane",
                                                       "locked", "review_status", "shape"))]
  list(
    roi_id = as.character(r$id),
    image_id = image_id,
    layer = layer_name,
    label = r$label,
    level = as.integer(r$level),
    geom_type = as.character(sf::st_geometry_type(r$geometry)),
    geometry_sha256 = .geometry_sha256(r$geometry),
    bbox = list(xmin = bb[1], ymin = bb[2], xmax = bb[3], ymax = bb[4]),
    source = r$source,
    locked = isTRUE(r$attributes$locked),
    review_status = r$attributes$review_status %||% "unreviewed",
    geometry_fidelity = .geometry_fidelity(r),
    native_roi = if (identical(.geometry_fidelity(r), "approximated")) "approximated" else "unknown",
    hierarchy = "unknown",
    plane = .roi_plane(r),
    qupath_object_type = r$attributes$qupath$object_type %||% NA_character_,
    qupath_object_id = r$attributes$qupath$object_id %||% NA_character_,
    attributes_sha256 = if (length(attrs)) .digest_json(.json_safe(attrs)) else NA_character_,
    created = .iso_time(r$created),
    modified = .iso_time(r$modified)
  )
}

# Coerce arbitrary attribute values to JSON-safe lists (drops functions and
# environments, turns non-finite numbers into strings).
.json_safe <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.function(x) || is.environment(x)) {
    return(NULL)
  }
  if (inherits(x, "POSIXt")) {
    return(.iso_time(x))
  }
  if (is.data.frame(x)) {
    return(lapply(as.list(x), .json_safe))
  }
  if (is.list(x)) {
    out <- lapply(x, .json_safe)
    if (!is.null(names(x))) names(out) <- names(x)
    return(out)
  }
  if (is.numeric(x)) {
    if (any(!is.finite(x) & !is.na(x))) {
      return(as.list(ifelse(is.nan(x), "NaN", ifelse(is.infinite(x),
                                                     ifelse(x > 0, "Infinity", "-Infinity"),
                                                     as.character(x)))))
    }
    return(if (length(x) == 1L) x else as.list(x))
  }
  if (is.atomic(x)) {
    return(if (length(x) == 1L) x else as.list(x))
  }
  NULL
}

.layer_record <- function(L) {
  cols <- L$style$colour
  list(
    name = L$name,
    labels = as.list(L$labels),
    colours = if (length(cols)) as.list(stats::setNames(unname(cols), names(cols))) else .json_object(),
    z = as.integer(L$style$z %||% 1L),
    visible = isTRUE(L$style$visible),
    locked = isTRUE(L$style$locked),
    n_rois = length(L$rois)
  )
}

.revision_core <- function(project) {
  layers <- lapply(project$layers, function(L) {
    rec <- .layer_record(L)
    rec$n_rois <- NULL
    rec$rois <- lapply(L$rois, function(r) {
      x <- .roi_record(r, L$name)
      x[c("roi_id", "layer", "label", "level", "geom_type", "geometry_sha256", "source",
          "locked", "review_status", "plane", "attributes_sha256")]
    })
    rec
  })
  unname(layers)
}

#' Annotation revision token
#'
#' A content revision for annotations: the SHA-256 of the canonical record of
#' every layer (name, labels, colours, z-order, visibility, lock) and ROI (id,
#' layer, label, level, geometry WKB, source, lock, review status, plane and
#' attributes). It changes whenever annotation content changes and is
#' independent of timestamps, authors, file paths and pixel data. Partners pass
#' it back as `expected_revision` to detect stale patches.
#'
#' @param x An [annot_project], [annot_layer], or [annot_session] (combining
#'   every materialised project and the queue statuses).
#' @param call The calling environment, for error reporting.
#'
#' @return A single string `"sha256:<64 hex>"`.
#' @family interop
#' @export
#' @examples
#' proj <- at_example_project()
#' at_annotation_revision(proj)
at_annotation_revision <- function(x, call = rlang::caller_env()) {
  core <- if (inherits(x, "annot_project")) {
    .revision_core(x)
  } else if (inherits(x, "annot_layer")) {
    .revision_core(list(layers = list(x)))
  } else if (inherits(x, "annot_session")) {
    list(
      statuses = as.list(x$manifest$status),
      projects = lapply(x$projects, function(p) if (is.null(p)) NULL else .revision_core(p))
    )
  } else {
    .at_abort("{.arg x} must be an {.cls annot_project}, {.cls annot_layer} or {.cls annot_session}.",
              call = call)
  }
  paste0("sha256:", .digest_json(core))
}

# ---- Image records ------------------------------------------------------------

# Files that make up an image source, identified by role and basename.
.source_files <- function(img, hash = TRUE) {
  paths <- if (img$backend %in% c("envi", "tivita") && grepl("\\.hdr$", img$source, ignore.case = TRUE)) {
    p <- .envi_paths(img$source)
    c(header = p$hdr, data = p$dat)
  } else {
    c(image = img$source)
  }
  paths <- paths[!is.na(paths)]
  lapply(names(paths), function(role) {
    f <- paths[[role]]
    exists <- file.exists(f) && !dir.exists(f)
    list(
      role = role,
      name = basename(f),
      size_bytes = if (exists) as.numeric(file.info(f)$size) else NA_real_,
      sha256 = if (exists && hash) .sha256_file(f) else NA_character_,
      hash_status = if (!exists) "missing" else if (hash) "ok" else "skipped"
    )
  })
}

.image_id <- function(img, files) {
  hashes <- vapply(files, function(f) f$sha256 %||% NA_character_, character(1))
  basis <- if (length(hashes) && !anyNA(hashes)) {
    list(files = as.list(hashes))
  } else {
    list(identity = .image_identity_digest(img))
  }
  paste0("sha256:", substr(.digest_json(basis), 1L, 16L))
}

.image_record <- function(img, hash = TRUE) {
  files <- .source_files(img, hash = hash)
  hm <- at_hsi_meta(img)
  bands <- at_bands(img)
  list(
    image_id = .image_id(img, files),
    role = "source",
    source_name = basename(img$source),
    source_files = files,
    backend = img$backend,
    format = hm$format,
    image_kind = hm$image_kind,
    width = hm$width,
    height = hm$height,
    n_levels = hm$n_levels,
    level_dims = lapply(img$level_dims, function(d) list(width = d[1], height = d[2])),
    n_bands = hm$n_bands,
    dtype = hm$dtype,
    series_id = as.integer(hm$series_id),
    plane = hm$plane,
    pixel_size = as.list(hm$pixel_size),
    pixel_unit = hm$pixel_unit,
    bands = lapply(seq_len(nrow(bands)), function(i) {
      list(index = bands$index[i], name = bands$name[i], wavelength = bands$wavelength[i],
           fwhm = bands$fwhm[i], unit = bands$unit[i],
           wavelength_status = bands$wavelength_status[i])
    }),
    hsi = list(
      vendor = hm$vendor, instrument = hm$instrument, acquisition_id = hm$acquisition_id,
      value_unit = hm$value_unit, scale_factor = hm$scale_factor, offset = hm$offset,
      nodata = hm$nodata, valid_range = as.list(hm$valid_range), interleave = hm$interleave,
      byte_order = hm$byte_order, header_bytes = hm$header_bytes, axis_order = hm$axis_order,
      origin = hm$origin, y_direction = hm$y_direction, wavelength_unit = hm$wavelength_unit,
      profile = hm$profile, window_read = hm$window_read, pan_sharpened = hm$pan_sharpened,
      calibration_status = hm$calibration$status %||% "missing"
    ),
    calibration_digest = hm$calibration_digest,
    transform_digest = hm$transform_digest
  )
}

# ---- Mask records ---------------------------------------------------------------

.mask_dtype <- function(m) {
  v <- as.matrix(m)
  if (is.logical(v)) {
    return("bool")
  }
  rng <- suppressWarnings(range(v, na.rm = TRUE))
  if (!all(is.finite(rng))) return("uint8")
  if (rng[1] >= 0 && rng[2] <= 255) return("uint8")
  if (rng[1] >= 0 && rng[2] <= 65535) return("uint16")
  "int32"
}

.mask_record <- function(mask, file = NA_character_, mask_id = NA_character_) {
  lg <- attr(mask, "legend")
  legend <- if (is.null(lg) || nrow(lg) == 0L) list() else lapply(seq_len(nrow(lg)), function(i) {
    list(value = as.integer(lg$value[i]), label = as.character(lg$label[i]),
         layer = as.character(lg$layer[i] %||% NA_character_),
         roi_id = as.character(lg$roi_id[i] %||% NA_character_),
         n_px = as.integer(lg$n_px[i]), colour = as.character(lg$colour[i] %||% NA_character_))
  })
  d <- attr(mask, "dims")
  list(
    mask_id = mask_id,
    file = file,
    mask_type = attr(mask, "mask_type") %||% "labelled",
    dtype = .mask_dtype(mask),
    background = as.integer(attr(mask, "background") %||% 0L),
    width = as.integer(d[1]),
    height = as.integer(d[2]),
    level = as.integer(attr(mask, "level") %||% 0L),
    legend = legend,
    legend_sha256 = .digest_json(legend),
    overlap = attr(mask, "overlap") %||% NA_character_,
    coverage_rule = "pixel centre inside geometry; half-open [lower, upper) ties",
    pixel_convention = "row 1 is the top image row; pixel (i, j) covers [j-1, j) x [i-1, i)",
    source_project = attr(mask, "source_project") %||% NA_character_
  )
}

# ---- Manifest ---------------------------------------------------------------------

.manifest_base <- function(object_kind) {
  caps <- at_interop_capabilities()
  list(
    schema = .contract$handoff,
    schema_version = .contract$version,
    document = "manifest",
    consumer = .contract$consumer,
    object_kind = object_kind,
    annotatr_version = .pkg_version(),
    r_version = as.character(getRversion()),
    source_revision = .source_revision(),
    capability_digest = caps$digest,
    created = .utc_stamp(),
    coordinate_convention = .coordinate_convention()
  )
}

.project_manifest_parts <- function(project, hash = TRUE, entry_id = NA_character_) {
  img_rec <- .image_record(project$image, hash = hash)
  iid <- img_rec$image_id
  rois <- unlist(lapply(project$layers, function(L) {
    lapply(L$rois, .roi_record, layer_name = L$name, image_id = iid)
  }), recursive = FALSE)
  list(
    image = img_rec,
    layers = unname(lapply(project$layers, .layer_record)),
    annotations = list(
      count = length(rois),
      annotation_revision = at_annotation_revision(project),
      rois = unname(rois)
    ),
    project = list(
      name = project$meta$name %||% NA_character_,
      entry_id = entry_id,
      created = .iso_time(project$provenance$created),
      modified = .iso_time(project$provenance$modified),
      created_with = project$provenance$annotatR_version %||% NA_character_,
      edit_count = length(project$provenance$edit_log)
    )
  )
}

#' Build a partner interop manifest
#'
#' Describe annotatR objects for a partner such as qupflowR without exposing
#' local paths: images are identified by content hash (`image_id`) and file
#' basename; annotations by string ROI ids and an [at_annotation_revision()];
#' masks by type, integer dtype, background, dimensions, level and legend. The
#' coordinate convention, band/wavelength table, HSI value semantics, plane,
#' calibration and transform digests are recorded explicitly. QuPath hierarchy
#' and native ROI shapes, which annotatR does not model, are reported as
#' `"unknown"` or `"approximated"`, never invented.
#'
#' @param x An [annot_project], [annot_session], [annot_image], [annot_layer],
#'   [annot_roi] or `annot_mask`.
#' @param destination Optional path: an existing directory (the manifest is
#'   written as `manifest.json` inside it) or a `.json` file path. An existing
#'   file is never overwritten.
#' @param hash_sources Logical; hash image source files (needed for a
#'   content-derived `image_id`). Default `TRUE`.
#' @param call The calling environment, for error reporting.
#'
#' @return The manifest (a list of class `at_interop_manifest`); invisibly when
#'   `destination` is given.
#' @family interop
#' @seealso [at_export_qupflowr()], [at_interop_capabilities()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_interop_manifest(at_example_project())
#' m$annotations$annotation_revision
#' m$images[[1]]$image_id
at_interop_manifest <- function(x, destination = NULL, hash_sources = TRUE,
                                call = rlang::caller_env()) {
  .check_flag(hash_sources, call = call)
  if (inherits(x, "annot_project")) {
    parts <- .project_manifest_parts(x, hash = hash_sources)
    out <- c(.manifest_base("project"), list(
      images = list(parts$image), layers = parts$layers, annotations = parts$annotations,
      masks = list(), projects = list(parts$project), session = NULL
    ))
  } else if (inherits(x, "annot_session")) {
    m <- x$manifest
    entries <- lapply(seq_len(nrow(m)), function(i) {
      p <- x$projects[[i]]
      rec <- list(entry_id = sprintf("entry-%04d", i), queue_index = i, name = m$name[i],
                  status = m$status[i], n_rois = as.integer(m$n_rois[i]),
                  materialised = !is.null(p), image_id = NA_character_,
                  annotation_revision = NA_character_)
      if (!is.null(p)) {
        rec$image_id <- .image_record(p$image, hash = hash_sources)$image_id
        rec$annotation_revision <- at_annotation_revision(p)
        rec$n_rois <- nrow(at_rois(p))
      } else if (file.exists(m$path[i])) {
        f <- list(list(sha256 = if (hash_sources) .sha256_file(m$path[i]) else NA_character_))
        rec$image_id <- if (hash_sources) {
          paste0("sha256:", substr(.digest_json(list(files = list(f[[1]]$sha256))), 1L, 16L))
        } else NA_character_
      }
      rec
    })
    projects <- lapply(seq_len(nrow(m)), function(i) {
      p <- x$projects[[i]]
      if (is.null(p)) NULL else .project_manifest_parts(p, hash = hash_sources,
                                                        entry_id = sprintf("entry-%04d", i))
    })
    kept <- Filter(Negate(is.null), projects)
    out <- c(.manifest_base("session"), list(
      images = lapply(kept, `[[`, "image"),
      layers = if (length(kept)) kept[[1]]$layers else list(),
      annotations = list(
        count = sum(vapply(kept, function(p) as.integer(p$annotations$count), integer(1))),
        annotation_revision = at_annotation_revision(x),
        rois = unlist(lapply(kept, function(p) p$annotations$rois), recursive = FALSE) %||% list()
      ),
      masks = list(),
      projects = lapply(kept, `[[`, "project"),
      session = list(queue = entries, cursor = as.integer(x$cursor),
                     entry_identity = "queue_index", labels = as.list(x$labels),
                     autosave = isTRUE(x$autosave))
    ))
  } else if (inherits(x, "annot_image")) {
    out <- c(.manifest_base("image"), list(
      images = list(.image_record(x, hash = hash_sources)), layers = list(),
      annotations = list(count = 0L, annotation_revision = NA_character_, rois = list()),
      masks = list(), projects = list(), session = NULL
    ))
  } else if (inherits(x, "annot_layer") || inherits(x, "annot_roi")) {
    L <- if (inherits(x, "annot_roi")) new_annot_layer("roi", rois = list(x), labels = x$label) else x
    rois <- lapply(L$rois, .roi_record, layer_name = L$name)
    out <- c(.manifest_base(if (inherits(x, "annot_roi")) "roi" else "layer"), list(
      images = list(), layers = list(.layer_record(L)),
      annotations = list(count = length(rois), annotation_revision = at_annotation_revision(L),
                         rois = rois),
      masks = list(), projects = list(), session = NULL
    ))
  } else if (inherits(x, "annot_mask")) {
    out <- c(.manifest_base("mask"), list(
      images = list(), layers = list(),
      annotations = list(count = 0L, annotation_revision = NA_character_, rois = list()),
      masks = list(.mask_record(x, mask_id = "mask-0001")), projects = list(), session = NULL
    ))
  } else {
    .at_abort("{.arg x} must be an annotatR project, session, image, layer, ROI or mask.",
              call = call)
  }
  out$provenance <- list(
    generator = paste0("annotatR ", .pkg_version()),
    local_paths = "excluded"
  )
  out$extensions <- .json_object()
  out <- structure(out, class = "at_interop_manifest")
  .schema_assert(.as_json_value(unclass(out)), .contract$handoff, "manifest",
                 what = "manifest", call = call)
  if (is.null(destination)) {
    return(out)
  }
  .check_string(destination, call = call)
  target <- if (dir.exists(destination)) file.path(destination, "manifest.json") else destination
  if (!grepl("\\.json$", target, ignore.case = TRUE)) {
    .at_abort("{.arg destination} must be an existing directory or a {.file .json} path.",
              class = "io", code = "DESTINATION_INVALID", call = call)
  }
  if (file.exists(target)) {
    .at_abort(c("{.path {target}} already exists.", "i" = "Choose a new destination."),
              class = "io", code = "DESTINATION_EXISTS", call = call)
  }
  .write_json_atomic(unclass(out), target)
  invisible(out)
}

#' @export
print.at_interop_manifest <- function(x, ...) {
  cat(cli::format_inline("{.cls at_interop_manifest} {x$schema} {x$schema_version} ({x$object_kind})"),
      "\n", sep = "")
  cat("  images: ", length(x$images), "  |  layers: ", length(x$layers),
      "  |  ROIs: ", x$annotations$count, "  |  masks: ", length(x$masks), "\n", sep = "")
  cat("  annotation revision: ", x$annotations$annotation_revision %||% "NA", "\n", sep = "")
  invisible(x)
}
