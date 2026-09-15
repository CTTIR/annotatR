# The qupflowR handoff: a new, self-contained directory with neutral files
# (QuPath GeoJSON, GeoJSON, integer masks with legends, optional NPY/CSV/RDS),
# a manifest and a SHA-256 inventory, plus the local stage -> commit flow that
# applies a partner's changes to an annotatR project only after an explicit,
# revision-checked, idempotent commit.

.handoff_formats <- c("qupath_geojson", "geojson", "mask_tiff", "mask_npy", "csv", "rds", "manifest")

# ---- Inventory ---------------------------------------------------------------

# All regular files below `dir` (relative, forward slashes), including hidden
# files, excluding `integrity.json` at the root.
.list_payload_files <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE,
                      include.dirs = FALSE)
  files <- gsub("\\\\", "/", files)
  files[files != "integrity.json"]
}

.build_integrity <- function(dir) {
  files <- .list_payload_files(dir)
  files <- files[order(.utf8_sort_key(files), method = "radix")]
  list(
    format_version = .contract$integrity_format,
    files = lapply(files, function(f) {
      full <- file.path(dir, f)
      list(path = f, size_bytes = as.numeric(file.info(full)$size), sha256 = .sha256_file(full))
    })
  )
}

.handoff_digest <- function(integrity) .digest_json(integrity)

# ---- Export --------------------------------------------------------------------

# Write the neutral files for one project into `dir`; return file and mask
# records relative to `root`.
.export_project_files <- function(project, dir, root, formats, level, mask_type, entry_id) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  rel <- function(p) .relative_to(p, root)
  files <- list()
  masks <- list()
  add_file <- function(path, format, role) {
    files[[length(files) + 1L]] <<- list(path = rel(path), format = format, role = role,
                                         entry_id = entry_id)
  }
  lite <- project
  lite$image$handle <- NULL
  img_rec <- .image_record(project$image)
  .write_json_atomic(img_rec, file.path(dir, "image.json"))
  add_file(file.path(dir, "image.json"), "image_json", "image")
  if ("qupath_geojson" %in% formats) {
    p <- file.path(dir, "annotations_qupath.geojson")
    at_write_qupath(project, p, level = level, dialect = "qupath")
    add_file(p, "qupath_geojson", "annotations")
  }
  if ("geojson" %in% formats) {
    p <- file.path(dir, "annotations.geojson")
    at_write_geojson(project, p, level = level)
    add_file(p, "geojson", "annotations")
  }
  if (any(c("mask_tiff", "mask_npy") %in% formats) && length(project$layers) > 0L) {
    mdir <- file.path(dir, "masks")
    dir.create(mdir, showWarnings = FALSE)
    stems <- .unique_components(.safe_component(names(project$layers)))
    for (k in seq_along(project$layers)) {
      nm <- names(project$layers)[k]
      m <- at_mask(project, type = mask_type, layer = nm, level = level)
      attr(m, "background") <- 0L
      mid <- paste0(entry_id %||% "project", ":", nm)
      if ("mask_tiff" %in% formats) {
        maxv <- max(as.integer(as.matrix(m)), 0L)
        if (maxv > 65535L) {
          .at_abort(c("Layer {.val {nm}} has mask values up to {maxv}, beyond 16-bit TIFF.",
                      "i" = "Export with {.code formats = \"mask_npy\"} (int32)."),
                    class = "limit", code = "MASK_RANGE")
        }
        p <- file.path(mdir, paste0(stems[k], "_", mask_type, ".tif"))
        at_write_mask(m, p, format = "tiff", bits = if (maxv > 255L) 16L else 8L)
        add_file(p, "mask_tiff", "mask")
        add_file(paste0(p, ".legend.json"), "legend_json", "mask_legend")
        rec <- .mask_record(m, file = rel(p), mask_id = mid)
        rec$dtype <- if (maxv > 255L) "uint16" else "uint8"
        rec$layer <- nm
        masks[[length(masks) + 1L]] <- rec
      }
      if ("mask_npy" %in% formats) {
        p <- file.path(mdir, paste0(stems[k], "_", mask_type, ".npy"))
        at_write_npy(m, p, dtype = "int32")
        add_file(p, "mask_npy", "mask")
        add_file(paste0(p, ".legend.json"), "legend_json", "mask_legend")
        rec <- .mask_record(m, file = rel(p), mask_id = paste0(mid, ":npy"))
        rec$dtype <- "int32"
        rec$layer <- nm
        masks[[length(masks) + 1L]] <- rec
      }
    }
  }
  if ("csv" %in% formats) {
    p <- file.path(dir, "tables", "rois.csv")
    dir.create(dirname(p), showWarnings = FALSE)
    at_write_rois_csv(project, p)
    add_file(p, "csv", "roi_table")
  }
  if ("rds" %in% formats) {
    p <- file.path(dir, "objects", "project.rds")
    dir.create(dirname(p), showWarnings = FALSE)
    lite$image$source <- basename(lite$image$source)
    at_save_project(lite, p)
    add_file(p, "rds", "annotatr_internal")
  }
  if (at_is_spectral(project$image)) {
    p <- file.path(dir, "hsi_manifest.json")
    .write_json_atomic(.hsi_manifest(project$image, img_rec), p)
    add_file(p, "hsi_manifest", "hsi")
  }
  list(files = files, masks = masks)
}

.hsi_manifest <- function(img, img_rec = .image_record(img)) {
  list(
    schema = .contract$hsi,
    schema_version = .contract$version,
    document = "hsi_manifest",
    cube_id = img_rec$image_id,
    source_files = img_rec$source_files,
    tile_contract = "[y, x, band]",
    width = img_rec$width, height = img_rec$height, n_bands = img_rec$n_bands,
    n_levels = img_rec$n_levels, dtype = img_rec$dtype,
    bands = img_rec$bands,
    hsi = img_rec$hsi,
    plane = img_rec$plane,
    series_id = img_rec$series_id,
    pixel_size = img_rec$pixel_size, pixel_unit = img_rec$pixel_unit,
    calibration_digest = img_rec$calibration_digest,
    transform_digest = img_rec$transform_digest,
    read_accounting = at_read_stats(img)[c("tiles", "file_bytes", "decoded_bytes",
                                           "max_tile_bytes", "window_read")],
    note = "Native vendor cubes are referenced by digest and role, never embedded."
  )
}

#' Export annotations as a qupflowR handoff directory
#'
#' Write a new, self-contained handoff directory for a partner package such as
#' qupflowR. It contains only neutral, relative files: `image.json`,
#' `annotations_qupath.geojson` (QuPath 0.4+ dialect), optionally
#' `annotations.geojson`, one integer mask per layer under `masks/` with a
#' `.legend.json` sidecar, optional `tables/rois.csv`, an optional
#' annotatR-internal `objects/project.rds`, `hsi_manifest.json` for spectral
#' images, `manifest.json` ([at_interop_manifest()]) and `integrity.json`, the
#' SHA-256 inventory of every other file. The handoff digest is the SHA-256 of
#' the canonical `integrity.json`. Absolute paths are never used as identity.
#'
#' Files are written into a hidden sibling staging directory and moved into
#' place only when complete, so a failed export never leaves a directory that
#' looks valid. An existing destination is replaced only with
#' `overwrite = TRUE`, and only when it is itself a handoff directory.
#'
#' @param x An [annot_project] or [annot_session] (materialised entries are
#'   exported under `entries/entry-NNNN/`).
#' @param destination Path of the handoff directory to create.
#' @param formats Any of `"qupath_geojson"`, `"geojson"`, `"mask_tiff"`,
#'   `"mask_npy"`, `"csv"`, `"rds"`, `"manifest"`. `manifest.json` and
#'   `integrity.json` are always written.
#' @param overwrite Logical; replace an existing handoff directory.
#' @param level Integer pyramid level for coordinates and masks. Default `0`.
#' @param mask_type Mask type for mask files: `"labelled"` (default; one value
#'   per ROI, joinable by `roi_id` through the legend), `"multiclass"` or
#'   `"binary"`.
#' @param scope For sessions: `"all"` materialised entries (default),
#'   `"current"` or `"complete"`.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_handoff_receipt` (invisibly): a list with `destination`,
#'   `handoff_digest`, `files` (a tibble of `path`, `size_bytes`, `sha256`,
#'   `format`, `role`, `entry_id`), `manifest`, `skipped` entries and
#'   `overwritten`.
#' @family interop
#' @seealso [at_import_qupflowr()], [at_interop_manifest()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' dest <- file.path(tempdir(), "handoff-example")
#' rc <- at_export_qupflowr(at_example_project(), dest, overwrite = TRUE)
#' rc$handoff_digest
#' rc$files[, c("path", "format")]
at_export_qupflowr <- function(x, destination,
                               formats = c("qupath_geojson", "mask_tiff", "manifest"),
                               overwrite = FALSE, level = 0L,
                               mask_type = c("labelled", "multiclass", "binary"),
                               scope = c("all", "current", "complete"),
                               call = rlang::caller_env()) {
  if (!inherits(x, c("annot_project", "annot_session"))) {
    .at_abort("{.arg x} must be an {.cls annot_project} or {.cls annot_session}.", call = call)
  }
  .check_string(destination, call = call)
  .check_flag(overwrite, call = call)
  level <- .check_count(level, call = call)
  mask_type <- .check_choice(mask_type, c("labelled", "multiclass", "binary"), call = call)
  scope <- .check_choice(scope, c("all", "current", "complete"), call = call)
  if (!is.character(formats) || length(formats) == 0L || !all(formats %in% .handoff_formats)) {
    .at_abort("{.arg formats} must be drawn from {.val {(.handoff_formats)}}.", call = call)
  }
  dest <- normalizePath(destination, winslash = "/", mustWork = FALSE)
  existed <- file.exists(dest)
  if (existed) {
    if (!overwrite) {
      .at_abort(c("{.path {destination}} already exists.",
                  "i" = "Choose a new handoff directory or pass {.code overwrite = TRUE}."),
                class = "io", code = "DESTINATION_EXISTS", call = call)
    }
    if (!dir.exists(dest) || !file.exists(file.path(dest, "integrity.json"))) {
      .at_abort(c("{.path {destination}} is not an annotatR handoff directory.",
                  "x" = "Refusing to replace a directory or file without {.file integrity.json}."),
                class = "io", code = "DESTINATION_NOT_HANDOFF", call = call)
    }
  }
  parent <- dirname(dest)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  stage <- file.path(parent, paste0(".", basename(dest), ".partial-", .random_hex(6L)))
  dir.create(stage)
  ok <- FALSE
  on.exit(if (!ok) unlink(stage, recursive = TRUE), add = TRUE)

  files <- list()
  masks <- list()
  skipped <- character()
  if (inherits(x, "annot_project")) {
    res <- .export_project_files(x, stage, stage, formats, level, mask_type, NA_character_)
    files <- res$files
    masks <- res$masks
  } else {
    m <- x$manifest
    idx <- switch(scope, all = seq_len(nrow(m)), current = x$cursor,
                  complete = which(m$status == "complete"))
    for (i in idx) {
      eid <- sprintf("entry-%04d", i)
      p <- x$projects[[i]]
      if (is.null(p)) {
        skipped <- c(skipped, eid)
        next
      }
      res <- .export_project_files(p, file.path(stage, "entries", eid), stage, formats, level,
                                   mask_type, eid)
      files <- c(files, res$files)
      masks <- c(masks, res$masks)
    }
  }
  manifest <- unclass(at_interop_manifest(x, call = call))
  manifest$masks <- masks
  manifest$files <- files
  manifest$provenance$export <- list(formats = as.list(formats), level = level,
                                     mask_type = mask_type, scope = scope,
                                     skipped_entries = as.list(skipped))
  .schema_assert(.as_json_value(manifest), .contract$handoff, "manifest", what = "manifest",
                 call = call)
  .write_json_atomic(manifest, file.path(stage, "manifest.json"))
  integrity <- .build_integrity(stage)
  .write_json_atomic(integrity, file.path(stage, "integrity.json"))
  digest <- .handoff_digest(integrity)

  if (existed) {
    backup <- file.path(parent, paste0(".", basename(dest), ".previous-", .random_hex(6L)))
    if (!file.rename(dest, backup)) {
      .at_abort("Could not move the previous handoff aside.", class = "io", code = "WRITE_FAILED",
                call = call)
    }
    if (!file.rename(stage, dest)) {
      file.rename(backup, dest)
      .at_abort("Could not move the new handoff into place.", class = "io", code = "WRITE_FAILED",
                call = call)
    }
    unlink(backup, recursive = TRUE)
  } else if (!file.rename(stage, dest)) {
    .at_abort("Could not move the new handoff into place.", class = "io", code = "WRITE_FAILED",
              call = call)
  }
  ok <- TRUE
  fmt <- vapply(integrity$files, function(f) {
    hit <- Filter(function(r) identical(r$path, f$path), files)
    if (length(hit)) hit[[1]]$format else if (f$path == "manifest.json") "manifest" else "other"
  }, character(1))
  receipt <- structure(list(
    destination = dest,
    handoff_digest = digest,
    files = tibble::tibble(
      path = vapply(integrity$files, `[[`, character(1), "path"),
      size_bytes = vapply(integrity$files, function(f) as.numeric(f$size_bytes), numeric(1)),
      sha256 = vapply(integrity$files, `[[`, character(1), "sha256"),
      format = fmt
    ),
    manifest = manifest,
    skipped = skipped,
    overwritten = existed
  ), class = "at_handoff_receipt")
  invisible(receipt)
}

#' @export
print.at_handoff_receipt <- function(x, ...) {
  cat(cli::format_inline("{.cls at_handoff_receipt} {.path {x$destination}}"), "\n", sep = "")
  cat("  files: ", nrow(x$files), "  |  digest: ", x$handoff_digest, "\n", sep = "")
  if (length(x$skipped)) cat("  skipped entries: ", paste(x$skipped, collapse = ", "), "\n", sep = "")
  invisible(x)
}

# ---- Verification ---------------------------------------------------------------

.check_row <- function(check, status, detail = "") {
  tibble::tibble(check = check, status = status, detail = detail)
}

# Verify a handoff directory: inventory, hashes, extra/missing/duplicate files,
# symlinks, manifest schema and major version. Aborts on any integrity or
# schema failure; returns the parsed documents and a checks table.
.verify_handoff <- function(dir, call = rlang::caller_env()) {
  dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  checks <- list()
  fail <- function(msg, code, details = list()) {
    .at_abort(msg, code = code, details = details, call = call)
  }
  ipath <- file.path(dir, "integrity.json")
  if (!file.exists(ipath)) {
    fail("The handoff has no {.file integrity.json}.", "INTEGRITY_MISSING")
  }
  integrity <- .read_json_doc(ipath, max_bytes = .interop_limits()$handoff_max_json_bytes, call = call)
  .schema_assert(integrity, .contract$handoff, "integrity", what = "integrity", call = call)
  .check_major_version(integrity$format_version, 1L, "integrity", call = call)
  listed <- vapply(integrity$files, `[[`, character(1), "path")
  if (length(listed) > .interop_limits()$handoff_max_files) {
    .at_abort("The handoff lists more files than the limit.", class = "limit",
              code = "PAYLOAD_TOO_LARGE", call = call)
  }
  if (anyDuplicated(listed)) {
    fail("The inventory lists {.val {unique(listed[duplicated(listed)])}} more than once.",
         "INTEGRITY_DUPLICATE")
  }
  if (!identical(listed, listed[order(.utf8_sort_key(listed), method = "radix")])) {
    fail("The inventory is not sorted by UTF-8 path.", "INTEGRITY_INVALID")
  }
  bad <- listed[!vapply(listed, .is_clean_relative, logical(1))]
  if (length(bad)) {
    fail("The inventory contains paths outside the handoff.", "PATH_OUTSIDE_ROOT")
  }
  actual <- .list_payload_files(dir)
  links <- actual[.is_symlink(file.path(dir, actual))]
  if (length(links)) {
    fail("The handoff contains symbolic links: {.val {links}}.", "INTEGRITY_SYMLINK")
  }
  extra <- setdiff(actual, listed)
  missing <- setdiff(listed, actual)
  if (length(missing)) {
    fail("Files listed in the inventory are missing: {.val {missing}}.", "INTEGRITY_MISSING",
         list(missing = as.list(missing)))
  }
  if (length(extra)) {
    fail("Files not listed in the inventory are present: {.val {extra}}.", "INTEGRITY_EXTRA",
         list(extra = as.list(extra)))
  }
  for (f in integrity$files) {
    full <- file.path(dir, f$path)
    size <- file.info(full)$size
    if (!isTRUE(size == f$size_bytes)) {
      fail("{.file {f$path}} has {size} bytes; the inventory says {f$size_bytes}.",
           "INTEGRITY_MISMATCH", list(path = f$path))
    }
    if (!identical(.sha256_file(full), f$sha256)) {
      fail("{.file {f$path}} does not match its SHA-256 in the inventory.", "INTEGRITY_MISMATCH",
           list(path = f$path))
    }
  }
  checks[[length(checks) + 1L]] <- .check_row("integrity", "ok",
                                              sprintf("%d files verified", length(listed)))
  if (!"manifest.json" %in% listed) {
    fail("The handoff has no {.file manifest.json}.", "MANIFEST_MISSING")
  }
  manifest <- .read_json_doc(file.path(dir, "manifest.json"),
                             max_bytes = .interop_limits()$handoff_max_json_bytes, call = call)
  if (!identical(manifest$schema, .contract$handoff)) {
    .at_abort("{.file manifest.json} is not an {.val {(.contract$handoff)}} document.",
              class = "protocol", code = "PROTOCOL_MISMATCH", call = call)
  }
  .check_major_version(manifest$schema_version, 1L, "manifest", call = call)
  .schema_assert(manifest, .contract$handoff, "manifest", what = "manifest", call = call)
  checks[[length(checks) + 1L]] <- .check_row("manifest_schema", "ok", manifest$schema_version)
  list(dir = dir, integrity = integrity, manifest = manifest,
       digest = .handoff_digest(integrity), checks = do.call(rbind, checks))
}

# ---- Import ---------------------------------------------------------------------

.detect_import_format <- function(file) {
  if (dir.exists(file)) {
    return("handoff")
  }
  base <- tolower(basename(file))
  if (base %in% c("manifest.json", "integrity.json")) {
    return("handoff")
  }
  ext <- tolower(tools::file_ext(file))
  if (ext %in% c("geojson", "json")) {
    doc <- tryCatch(jsonlite::read_json(file, simplifyVector = FALSE), error = function(e) NULL)
    feats <- tryCatch(.qupath_features(doc), error = function(e) list())
    props <- if (length(feats)) feats[[1]]$properties else NULL
    if (!is.null(props$objectType) || !is.null(props$object_type) ||
        !is.null(props$classification)) {
      return("qupath_geojson")
    }
    return("geojson")
  }
  if (ext %in% c("tif", "tiff", "png")) return("mask")
  if (ext == "npy") return("npy")
  if (ext == "rds") return("rds")
  "unknown"
}

# Group a QuPath layer's ROIs into annotatR layers using the manifest (by ROI
# id) or the annotatR metadata written into the QuPath dialect.
.split_qupath_layers <- function(qlayer, manifest_layers = list(), manifest_rois = list()) {
  roi_layer <- stats::setNames(vapply(manifest_rois, function(r) r$layer, character(1)),
                               vapply(manifest_rois, function(r) r$roi_id, character(1)))
  out <- list()
  for (L in manifest_layers) {
    st <- at_style(visible = isTRUE(L$visible), locked = isTRUE(L$locked),
                   z = as.integer(L$z %||% 1L),
                   colour = if (length(L$colours)) unlist(L$colours) else NULL)
    out[[L$name]] <- at_layer(L$name, labels = unlist(L$labels) %||% character(), style = st)
  }
  for (r in qlayer$rois) {
    ln <- roi_layer[r$id]
    if (is.na(ln)) {
      ln <- r$attributes$qupath$metadata$annotatr_layer %||% qlayer$name
    }
    if (is.null(out[[ln]])) {
      out[[ln]] <- at_layer(ln)
    }
    out[[ln]]$rois <- c(out[[ln]]$rois, list(r))
    if (!r$label %in% out[[ln]]$labels) {
      out[[ln]]$labels <- c(out[[ln]]$labels, r$label)
      out[[ln]]$style$colour <- .resolve_palette(out[[ln]]$labels, out[[ln]]$style$colour)
    }
  }
  out
}

.read_mask_file <- function(dir, rec, call) {
  path <- file.path(dir, rec$file)
  ext <- tolower(tools::file_ext(path))
  m <- if (ext == "npy") .npy_read_matrix(path, call = call) else .read_mask_matrix(path, call)$m
  storage.mode(m) <- "integer"
  if (nrow(m) != rec$height || ncol(m) != rec$width) {
    .at_abort("Mask {.file {rec$file}} is {ncol(m)} x {nrow(m)} px; the manifest says {rec$width} x {rec$height}.",
              code = "MASK_DIMENSIONS", call = call)
  }
  legend_vals <- vapply(rec$legend, function(l) as.integer(l$value), integer(1))
  present <- setdiff(sort(unique(as.integer(m))), as.integer(rec$background))
  if (length(setdiff(present, legend_vals))) {
    .at_abort("Mask {.file {rec$file}} contains values {.val {setdiff(present, legend_vals)}} missing from its legend.",
              code = "LEGEND_INCOMPLETE", call = call)
  }
  lg <- tibble::tibble(
    value = legend_vals,
    label = vapply(rec$legend, function(l) as.character(l$label), character(1)),
    layer = vapply(rec$legend, function(l) as.character(l$layer %||% NA_character_), character(1)),
    roi_id = vapply(rec$legend, function(l) as.character(l$roi_id %||% NA_character_), character(1)),
    n_px = vapply(legend_vals, function(v) as.integer(sum(m == v)), integer(1)),
    colour = vapply(rec$legend, function(l) as.character(l$colour %||% "#5E2C8E"), character(1))
  )
  mk <- .new_annot_mask(m, lg, rec$level, c(rec$width, rec$height), rec$mask_type)
  attr(mk, "background") <- as.integer(rec$background)
  mk
}

#' Import a qupflowR handoff or neutral interchange file
#'
#' Read only the neutral contract, validate it, and return a namespaced
#' annotatR result together with a conversion report. For a handoff directory
#' the SHA-256 inventory (missing, extra, duplicate, resized, altered or
#' symlinked files), the manifest schema and major version, ROI id uniqueness
#' and the id join between manifest and GeoJSON, layers, planes, mask
#' dimensions, integer values and legend completeness are all checked; any
#' integrity or schema failure aborts with an `at_validation_error`. Nothing
#' is written, no analysis is started, and foreign objects are never returned as
#' if they were annotatR objects: imported ROIs carry `source = "imported"` and
#' partner fields under `attributes$qupflowr`. An RDS file is refused, because
#' deserialising it is not a neutral read.
#'
#' @param file A handoff directory (or its `manifest.json`/`integrity.json`), a
#'   QuPath GeoJSON, a GeoJSON, a mask TIFF/PNG with legend sidecar, or a
#'   `.npy` mask.
#' @param format `"auto"` (default), `"handoff"`, `"qupath_geojson"`,
#'   `"geojson"`, `"mask"` or `"npy"`.
#' @param expected_revision Optional `"sha256:..."` annotation revision the
#'   caller expects the handoff to carry; a different revision aborts with an
#'   `at_conflict_error` (`REVISION_CONFLICT`).
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_import_report`: a list with `status`, `format`,
#'   `source_name`, `handoff_digest`, `manifest`, `checks` (tibble of `check`,
#'   `status`, `detail`), `objects` (`layers`: named list of [annot_layer];
#'   `masks`: named list of `annot_mask`; `images`: image records), `conversion`
#'   (tibble with one row per ROI: `roi_id`, `layer`, `label`,
#'   `source_object_id`, `object_type`, `geometry_fidelity`, `geometry_match`,
#'   `notes`) and `annotation_revision` of the imported layers.
#' @family interop
#' @seealso [at_export_qupflowr()], [at_stage_qupflowr()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' dest <- file.path(tempdir(), "handoff-import-example")
#' at_export_qupflowr(at_example_project(), dest, overwrite = TRUE)
#' rep <- at_import_qupflowr(dest)
#' rep$checks
at_import_qupflowr <- function(file, format = c("auto", "handoff", "qupath_geojson", "geojson",
                                                "mask", "npy"),
                               expected_revision = NULL, call = rlang::caller_env()) {
  .check_string(file, call = call)
  if (!file.exists(file)) {
    .at_abort("{.path {file}} does not exist.", class = "io", code = "FILE_MISSING", call = call)
  }
  format <- .check_choice(format, c("auto", "handoff", "qupath_geojson", "geojson", "mask", "npy"),
                          call = call)
  if (!is.null(expected_revision)) .check_string(expected_revision, call = call)
  if (format == "auto") {
    format <- .detect_import_format(file)
  }
  if (format == "rds") {
    .at_abort(c("RDS files are not part of the neutral contract.",
                "i" = "Load a trusted annotatR project with {.fn at_load_project} instead."),
              code = "FORMAT_NOT_NEUTRAL", call = call)
  }
  if (format == "unknown") {
    .at_abort("Cannot determine the interchange format of {.path {basename(file)}}.",
              code = "FORMAT_UNRECOGNISED", call = call)
  }
  report <- switch(
    format,
    handoff = .import_handoff(if (dir.exists(file)) file else dirname(file), call),
    qupath_geojson = .import_single_geojson(file, qupath = TRUE, call),
    geojson = .import_single_geojson(file, qupath = FALSE, call),
    mask = .import_single_mask(file, npy = FALSE, call),
    npy = .import_single_mask(file, npy = TRUE, call)
  )
  report$format <- format
  if (!is.null(expected_revision)) {
    have <- report$manifest$annotations$annotation_revision %||% report$annotation_revision
    if (!identical(have, expected_revision)) {
      .at_abort(
        c("The handoff carries a different annotation revision than expected.",
          "x" = "Expected {.val {expected_revision}}, found {.val {have}}.",
          "i" = "Re-read the partner state and stage again."),
        class = "conflict", code = "REVISION_CONFLICT",
        details = list(expected = expected_revision, actual = have), call = call
      )
    }
    report$checks <- rbind(report$checks, .check_row("expected_revision", "ok", expected_revision))
  }
  report$status <- if (any(report$checks$status == "warn")) "valid_with_warnings" else "valid"
  structure(report, class = "at_import_report")
}

.conversion_rows <- function(layers, manifest_rois = list()) {
  by_id <- stats::setNames(manifest_rois, vapply(manifest_rois, function(r) r$roi_id, character(1)))
  rows <- list()
  for (L in layers) {
    for (r in L$rois) {
      rec <- by_id[[r$id]]
      match <- if (is.null(rec)) NA_character_ else if (identical(.geometry_sha256(r$geometry), rec$geometry_sha256)) "exact" else "changed"
      notes <- character()
      if (identical(r$attributes$qupath$roi_native, "ellipse")) notes <- c(notes, "ellipse polygonised by QuPath")
      if (identical(match, "changed")) notes <- c(notes, "geometry bytes differ from the manifest record")
      rows[[length(rows) + 1L]] <- tibble::tibble(
        roi_id = r$id, layer = L$name, label = r$label,
        source_object_id = r$attributes$qupath$object_id %||% NA_character_,
        object_type = r$attributes$qupath$object_type %||% NA_character_,
        geometry_fidelity = .geometry_fidelity(r),
        geometry_match = match,
        notes = paste(notes, collapse = "; ")
      )
    }
  }
  if (length(rows) == 0L) {
    return(tibble::tibble(roi_id = character(), layer = character(), label = character(),
                          source_object_id = character(), object_type = character(),
                          geometry_fidelity = character(), geometry_match = character(),
                          notes = character()))
  }
  do.call(rbind, rows)
}

.tag_imported <- function(layers, digest, manifest_rois = list()) {
  by_id <- stats::setNames(manifest_rois, vapply(manifest_rois, function(r) r$roi_id, character(1)))
  lapply(layers, function(L) {
    L$rois <- lapply(L$rois, function(r) {
      rec <- by_id[[r$id]]
      r$source <- "imported"
      r$attributes$qupflowr <- list(handoff_digest = digest,
                                    source_record = if (is.null(rec)) NULL else rec)
      if (!is.null(rec)) {
        r$attributes$review_status <- rec$review_status
        if (isTRUE(rec$locked)) r$attributes$locked <- TRUE
        if (!is.null(rec$plane)) {
          r$attributes$plane <- list(c = rec$plane$c %||% NA_integer_, z = rec$plane$z %||% 0L,
                                     t = rec$plane$t %||% 0L)
        }
      }
      r
    })
    L
  })
}

.import_handoff <- function(dir, call) {
  v <- .verify_handoff(dir, call = call)
  man <- v$manifest
  checks <- v$checks
  files <- man$files %||% list()
  entries <- unique(vapply(files, function(f) f$entry_id %||% NA_character_, character(1)))
  if (length(entries) == 0L) entries <- NA_character_
  layers_out <- list()
  masks_out <- list()
  conv <- list()
  m_rois <- man$annotations$rois %||% list()
  ids <- vapply(m_rois, function(r) r$roi_id, character(1))
  if (anyDuplicated(ids) && is.null(man$session)) {
    .at_abort("The manifest lists duplicate ROI ids {.val {unique(ids[duplicated(ids)])}}.",
              code = "DUPLICATE_ID", call = call)
  }
  for (eid in entries) {
    ef <- Filter(function(f) identical(f$entry_id %||% NA_character_, eid), files)
    ann <- Filter(function(f) f$format %in% c("qupath_geojson", "geojson"), ef)
    ann <- ann[order(vapply(ann, function(f) f$format != "qupath_geojson", logical(1)))]
    key <- if (is.na(eid)) "project" else eid
    proj_rec <- Filter(function(p) identical(p$entry_id %||% NA_character_, eid), man$projects %||% list())
    img_id <- if (length(man$images)) {
      idx <- if (is.na(eid)) 1L else which(vapply(man$session$queue %||% list(), function(q) q$entry_id, character(1)) == eid)
      q <- if (!is.na(eid) && length(idx)) man$session$queue[[idx]] else NULL
      q$image_id %||% man$images[[1]]$image_id
    } else NA_character_
    e_rois <- Filter(function(r) identical(r$image_id %||% NA_character_, img_id) || is.na(img_id), m_rois)
    if (length(ann)) {
      f <- ann[[1]]
      path <- file.path(v$dir, f$path)
      layers <- if (f$format == "qupath_geojson") {
        .split_qupath_layers(at_read_qupath(path, call = call), man$layers, e_rois)
      } else {
        at_read_geojson(path, call = call)
      }
      got <- unlist(lapply(layers, function(L) vapply(L$rois, `[[`, character(1), "id")))
      if (anyDuplicated(got)) {
        .at_abort("{.file {f$path}} contains duplicate ROI ids.", code = "DUPLICATE_ID", call = call)
      }
      want <- vapply(e_rois, function(r) r$roi_id, character(1))
      if (length(setdiff(want, got)) || length(setdiff(got, want))) {
        .at_abort(
          c("ROI ids in {.file {f$path}} do not match the manifest.",
            "x" = "Missing from the file: {.val {setdiff(want, got)}}.",
            "x" = "Not in the manifest: {.val {setdiff(got, want)}}."),
          code = "ID_JOIN_MISMATCH", call = call
        )
      }
      for (r in e_rois) {
        hit <- unlist(lapply(layers, function(L) Filter(function(x) identical(x$id, r$roi_id), L$rois)),
                      recursive = FALSE)
        if (length(hit) && !identical(hit[[1]]$label, r$label)) {
          .at_abort("ROI {.val {r$roi_id}} is labelled {.val {hit[[1]]$label}} but the manifest says {.val {r$label}}.",
                    code = "LABEL_MISMATCH", call = call)
        }
      }
      layers <- .tag_imported(layers, v$digest, e_rois)
      checks <- rbind(checks, .check_row(paste0("annotations:", key), "ok",
                                         sprintf("%d ROIs joined by id", length(got))))
      cv <- .conversion_rows(layers, e_rois)
      if (any(cv$geometry_match == "changed", na.rm = TRUE)) {
        checks <- rbind(checks, .check_row(paste0("geometry:", key), "warn",
                                           "some geometries differ from their manifest digests"))
      }
      conv[[length(conv) + 1L]] <- cv
      layers_out[[key]] <- layers
    }
    for (rec in Filter(function(m) !is.null(m$file) && !is.na(m$file), man$masks %||% list())) {
      in_entry <- if (is.na(eid)) !grepl("^entries/", rec$file) else startsWith(rec$file, paste0("entries/", eid, "/"))
      if (!in_entry) next
      masks_out[[rec$mask_id %||% rec$file]] <- .read_mask_file(v$dir, rec, call)
    }
  }
  if (length(masks_out)) {
    checks <- rbind(checks, .check_row("masks", "ok",
                                       sprintf("%d masks: dimensions, integers and legends verified", length(masks_out))))
  }
  flat_layers <- if (length(layers_out) == 1L && identical(names(layers_out), "project")) layers_out$project else layers_out
  list(
    source_name = basename(v$dir),
    handoff_digest = v$digest,
    manifest = man,
    checks = checks,
    objects = list(layers = flat_layers, masks = masks_out, images = man$images),
    conversion = if (length(conv)) do.call(rbind, conv) else .conversion_rows(list()),
    annotation_revision = if (length(layers_out) == 1L && identical(names(layers_out), "project")) {
      at_annotation_revision(structure(list(layers = layers_out$project), class = "annot_project"))
    } else NA_character_
  )
}

.import_single_geojson <- function(file, qupath, call) {
  layers <- if (qupath) {
    .split_qupath_layers(at_read_qupath(file, call = call))
  } else {
    at_read_geojson(file, call = call)
  }
  ids <- unlist(lapply(layers, function(L) vapply(L$rois, `[[`, character(1), "id")))
  checks <- .check_row("parse", "ok", sprintf("%d features", length(ids)))
  if (anyDuplicated(ids)) {
    .at_abort("{.file {basename(file)}} contains duplicate ROI ids.", code = "DUPLICATE_ID", call = call)
  }
  layers <- .tag_imported(layers, .sha256_file(file))
  list(
    source_name = basename(file), handoff_digest = NA_character_, manifest = NULL,
    checks = rbind(checks, .check_row("integrity", "warn", "single file: no inventory to verify")),
    objects = list(layers = layers, masks = list(), images = list()),
    conversion = .conversion_rows(layers),
    annotation_revision = at_annotation_revision(structure(list(layers = layers), class = "annot_project"))
  )
}

.import_single_mask <- function(file, npy, call) {
  mk <- if (npy) {
    at_read_npy(file, call = call)
  } else {
    side <- paste0(file, ".legend.json")
    m <- .read_mask_matrix(file, call)$m
    storage.mode(m) <- "integer"
    lg <- if (file.exists(side)) {
      j <- .read_json_doc(side, call = call)
      tibble::as_tibble(jsonlite::fromJSON(jsonlite::toJSON(j$legend, auto_unbox = TRUE)))
    } else {
      NULL
    }
    if (is.null(lg) || nrow(lg) == 0L) {
      vals <- sort(unique(as.integer(m[m != 0L])))
      lg <- tibble::tibble(value = vals, label = as.character(vals), layer = NA_character_,
                           roi_id = NA_character_, n_px = integer(length(vals)),
                           colour = rep("#5E2C8E", length(vals)))
    }
    .new_annot_mask(m, lg, 0L, c(ncol(m), nrow(m)), "labelled")
  }
  m <- as.matrix(mk)
  lg <- attr(mk, "legend")
  present <- setdiff(sort(unique(as.integer(m))), 0L)
  missing <- setdiff(present, as.integer(lg$value))
  checks <- .check_row("parse", "ok", sprintf("%d x %d px", ncol(m), nrow(m)))
  if (length(missing)) {
    .at_abort("Mask values {.val {missing}} are missing from the legend.", code = "LEGEND_INCOMPLETE",
              call = call)
  }
  list(
    source_name = basename(file), handoff_digest = NA_character_, manifest = NULL,
    checks = rbind(checks, .check_row("legend", "ok", "all values labelled")),
    objects = list(layers = list(), masks = list(mask = mk), images = list()),
    conversion = .conversion_rows(list()),
    annotation_revision = NA_character_
  )
}

#' @export
print.at_import_report <- function(x, ...) {
  cat(cli::format_inline("{.cls at_import_report} {x$format} {.file {x$source_name}} ({x$status})"), "\n", sep = "")
  n_rois <- nrow(x$conversion)
  cat("  layers: ", length(x$objects$layers), "  |  ROIs: ", n_rois,
      "  |  masks: ", length(x$objects$masks), "\n", sep = "")
  for (i in seq_len(nrow(x$checks))) {
    cat(sprintf("  [%s] %s %s\n", x$checks$status[i], x$checks$check[i], x$checks$detail[i]))
  }
  invisible(x)
}

# ---- Stage and commit ------------------------------------------------------------

.incoming_layers <- function(patch, call) {
  if (inherits(patch, "at_import_report")) {
    L <- patch$objects$layers
    if (length(L) && all(vapply(L, inherits, logical(1), "annot_layer"))) return(L)
    if (length(L) == 1L && is.list(L[[1]])) return(L[[1]])
    .at_abort("The import report holds several entries; stage one entry at a time.",
              code = "PATCH_AMBIGUOUS", call = call)
  }
  if (inherits(patch, "annot_layer")) {
    return(stats::setNames(list(patch), patch$name))
  }
  if (is.list(patch) && length(patch) && all(vapply(patch, inherits, logical(1), "annot_layer"))) {
    return(stats::setNames(patch, vapply(patch, `[[`, character(1), "name")))
  }
  if (.is_string(patch) && file.exists(patch)) {
    return(.incoming_layers(at_import_qupflowr(patch, call = call), call))
  }
  .at_abort("{.arg patch} must be an import report, a handoff path, or annotation layer(s).",
            call = call)
}

.find_roi <- function(project, id) {
  for (nm in names(project$layers)) {
    for (r in project$layers[[nm]]$rois) {
      if (identical(r$id, id)) return(list(roi = r, layer = nm))
    }
  }
  NULL
}

.roi_signature <- function(r, layer) {
  rec <- .roi_record(r, layer)
  .digest_json(rec[c("layer", "label", "level", "geometry_sha256", "locked", "plane")])
}

#' Stage partner changes against an annotatR project
#'
#' Compute, without applying, the changes a partner patch would make to an
#' annotatR project: ROIs are joined by id and classified as `create`,
#' `update`, `unchanged`, `delete` (only with `delete_missing = TRUE`) or
#' `conflict`. Reviewed or locked ROIs, and ROIs in locked layers, are never
#' changed automatically; such changes become conflicts. When
#' `expected_revision` is given and the project has moved on, staging aborts
#' with an `at_conflict_error` (`REVISION_CONFLICT`).
#'
#' @param x An [annot_project], or the path of a saved project `.rds` (then the
#'   commit re-reads and re-checks that file).
#' @param patch An import report from [at_import_qupflowr()], a handoff
#'   directory, or one or more [annot_layer] objects.
#' @param expected_revision Optional revision of `x` the partner based its patch
#'   on (see [at_annotation_revision()]).
#' @param delete_missing Logical; treat ROIs absent from the patch's layers as
#'   deletions. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_staged_patch`: a list with `patch_id`, `state = "staged"`,
#'   `created`, `base_revision`, `proposed_revision`, `operations` (tibble of
#'   `op`, `roi_id`, `layer`, `label`, `reason`), `summary` (counts by `op`),
#'   `base`, `proposed` (the would-be project), `target_path` and
#'   `patch_digest`.
#' @family interop
#' @seealso [at_commit_qupflowr()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' proj <- at_example_project()
#' partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
#'                                                          id = "partner-1"))
#' st <- at_stage_qupflowr(proj, partner, expected_revision = at_annotation_revision(proj))
#' st$summary
at_stage_qupflowr <- function(x, patch, expected_revision = NULL, delete_missing = FALSE,
                              call = rlang::caller_env()) {
  target_path <- NA_character_
  if (.is_string(x)) {
    .check_file(x, call = call)
    target_path <- normalizePath(x, winslash = "/")
    x <- at_load_project(x, call = call)
  }
  .check_project(x, call = call)
  .check_flag(delete_missing, call = call)
  base_revision <- at_annotation_revision(x)
  if (!is.null(expected_revision) && !identical(expected_revision, base_revision)) {
    .at_abort(
      c("The project changed since the partner read it.",
        "x" = "Expected revision {.val {expected_revision}}, current {.val {base_revision}}.",
        "i" = "Re-read the project state, rebuild the patch and stage again."),
      class = "conflict", code = "REVISION_CONFLICT",
      details = list(expected = expected_revision, actual = base_revision), call = call
    )
  }
  incoming <- .incoming_layers(patch, call)
  proposed <- x
  ops <- list()
  add_op <- function(op, id, layer, label, reason = "") {
    ops[[length(ops) + 1L]] <<- tibble::tibble(op = op, roi_id = id, layer = layer, label = label,
                                                reason = reason)
  }
  protected <- function(r, layer) {
    if (identical(r$attributes$review_status, "reviewed")) return("existing ROI is reviewed")
    if (isTRUE(r$attributes$locked)) return("existing ROI is locked")
    if (isTRUE(x$layers[[layer]]$style$locked)) return("existing layer is locked")
    ""
  }
  seen <- character()
  for (L in incoming) {
    if (is.null(proposed$layers[[L$name]])) {
      proposed <- at_add_layer(proposed, at_layer(L$name, labels = L$labels, style = L$style))
    }
    for (r in L$rois) {
      seen <- c(seen, r$id)
      hit <- .find_roi(x, r$id)
      if (is.null(hit)) {
        proposed <- at_add_roi(proposed, L$name, r)
        add_op("create", r$id, L$name, r$label)
      } else if (identical(.roi_signature(hit$roi, hit$layer), .roi_signature(r, L$name))) {
        add_op("unchanged", r$id, L$name, r$label)
      } else {
        why <- protected(hit$roi, hit$layer)
        if (nzchar(why)) {
          add_op("conflict", r$id, L$name, r$label, why)
        } else {
          proposed <- suppressWarnings(at_remove_roi(proposed, r$id))
          r$modified <- .now()
          proposed <- at_add_roi(proposed, L$name, r)
          add_op("update", r$id, L$name, r$label)
        }
      }
    }
  }
  if (delete_missing) {
    for (nm in intersect(names(incoming), names(x$layers))) {
      for (r in x$layers[[nm]]$rois) {
        if (r$id %in% seen) next
        why <- protected(r, nm)
        if (nzchar(why)) {
          add_op("conflict", r$id, nm, r$label, paste("delete refused:", why))
        } else {
          proposed <- at_remove_roi(proposed, r$id)
          add_op("delete", r$id, nm, r$label)
        }
      }
    }
  }
  ops_tbl <- if (length(ops)) do.call(rbind, ops) else tibble::tibble(
    op = character(), roi_id = character(), layer = character(), label = character(),
    reason = character()
  )
  summary <- as.list(table(factor(ops_tbl$op, levels = c("create", "update", "unchanged",
                                                         "delete", "conflict"))))
  summary <- lapply(summary, as.integer)
  proposed_revision <- at_annotation_revision(proposed)
  patch_digest <- .digest_json(list(
    base_revision = base_revision, proposed_revision = proposed_revision,
    operations = lapply(seq_len(nrow(ops_tbl)), function(i) as.list(ops_tbl[i, ]))
  ))
  structure(list(
    patch_id = .uuid(),
    state = "staged",
    created = .utc_stamp(),
    base_revision = base_revision,
    expected_revision = expected_revision %||% NA_character_,
    proposed_revision = proposed_revision,
    operations = ops_tbl,
    summary = summary,
    base = x,
    proposed = proposed,
    target_path = target_path,
    source = if (inherits(patch, "at_import_report")) patch$handoff_digest else NA_character_,
    patch_digest = patch_digest
  ), class = "at_staged_patch")
}

#' @export
print.at_staged_patch <- function(x, ...) {
  s <- x$summary
  cat(cli::format_inline("{.cls at_staged_patch} {x$patch_id} ({x$state})"), "\n", sep = "")
  cat(sprintf("  create %d | update %d | unchanged %d | delete %d | conflict %d\n",
              s$create, s$update, s$unchanged, s$delete, s$conflict))
  cat("  base ", x$base_revision, "\n  proposed ", x$proposed_revision, "\n", sep = "")
  invisible(x)
}

.commit_registry <- new.env(parent = emptyenv())

#' Commit a staged partner patch
#'
#' Apply an [at_stage_qupflowr()] patch. Conflicting operations are never
#' applied. The commit is idempotent: repeating it with the same
#' `idempotency_key` and the same patch returns the original receipt without
#' applying anything again, while the same key with a different patch aborts
#' with `IDEMPOTENCY_CONFLICT`. When the patch targets a saved project file (or
#' `destination` names one), the file is re-read and its revision re-checked
#' immediately before writing; an existing file is only replaced with
#' `overwrite = TRUE`. A `<file>.commit.json` receipt records the key across R
#' sessions.
#'
#' @param x An `at_staged_patch`.
#' @param idempotency_key Optional client key; defaults to one derived from the
#'   patch id.
#' @param destination Optional project `.rds` path to write the committed
#'   project to; defaults to the patch's `target_path` when staged from a file.
#' @param overwrite Logical; allow replacing an existing project file.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_commit_receipt`: a list with `state = "committed"`,
#'   `patch_id`, `idempotency_key`, `previous_revision`, `new_revision`,
#'   `applied` and `conflicts` (operation tibbles), `project`, `written` (path or
#'   `NA`), `committed_at` and `replayed`.
#' @family interop
#' @seealso [at_stage_qupflowr()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' proj <- at_example_project()
#' partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
#'                                                          id = "partner-1"))
#' rc <- at_commit_qupflowr(at_stage_qupflowr(proj, partner))
#' rc$new_revision
at_commit_qupflowr <- function(x, idempotency_key = NULL, destination = NULL, overwrite = FALSE,
                               call = rlang::caller_env()) {
  .check_class(x, "at_staged_patch", call = call)
  .check_flag(overwrite, call = call)
  key <- idempotency_key %||% paste0("patch-", x$patch_id)
  .check_string(key, call = call)
  if (!grepl("^[A-Za-z0-9._:-]{1,128}$", key)) {
    .at_abort("{.arg idempotency_key} must be 1-128 characters of letters, digits, '.', '_', ':' or '-'.",
              call = call)
  }
  prior <- .commit_registry[[key]]
  if (!is.null(prior)) {
    if (!identical(prior$patch_digest, x$patch_digest)) {
      .at_abort("The idempotency key {.val {key}} was already used for a different patch.",
                class = "conflict", code = "IDEMPOTENCY_CONFLICT", call = call)
    }
    out <- prior$receipt
    out$replayed <- TRUE
    return(out)
  }
  target <- destination %||% (if (is.na(x$target_path)) NULL else x$target_path)
  if (!is.null(target)) {
    .check_string(target, call = call)
    side <- paste0(target, ".commit.json")
    if (file.exists(side)) {
      rec <- tryCatch(.read_json_doc(side, call = call), error = function(e) NULL)
      if (identical(rec$idempotency_key, key)) {
        if (!identical(rec$patch_digest, x$patch_digest)) {
          .at_abort("The idempotency key {.val {key}} was already used for a different patch.",
                    class = "conflict", code = "IDEMPOTENCY_CONFLICT", call = call)
        }
        proj <- at_load_project(target, call = call)
        return(structure(list(
          state = "committed", patch_id = rec$patch_id, idempotency_key = key,
          previous_revision = rec$previous_revision, new_revision = rec$new_revision,
          applied = x$operations[x$operations$op %in% c("create", "update", "delete"), ],
          conflicts = x$operations[x$operations$op == "conflict", ],
          project = proj, written = normalizePath(target, winslash = "/"),
          committed_at = rec$committed_at, replayed = TRUE
        ), class = "at_commit_receipt"))
      }
    }
    if (file.exists(target)) {
      if (!overwrite) {
        .at_abort(c("{.path {target}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it after the revision check."),
                  class = "io", code = "DESTINATION_EXISTS", call = call)
      }
      current <- at_annotation_revision(at_load_project(target, call = call))
      if (!identical(current, x$base_revision)) {
        .at_abort(
          c("{.path {basename(target)}} changed after the patch was staged.",
            "x" = "Staged against {.val {x$base_revision}}, file now at {.val {current}}."),
          class = "conflict", code = "REVISION_CONFLICT",
          details = list(expected = x$base_revision, actual = current), call = call
        )
      }
    }
  }
  project <- .log_edit(x$proposed, "commit_qupflowr", x$patch_id)
  written <- NA_character_
  committed_at <- .utc_stamp()
  new_rev <- at_annotation_revision(project)
  if (!is.null(target)) {
    lite <- project
    lite$image$handle <- NULL
    tmp <- tempfile(pattern = ".annotatR-commit-", tmpdir = dirname(target), fileext = ".rds")
    at_save_project(lite, tmp, call = call)
    if (!file.rename(tmp, target)) {
      unlink(tmp)
      .at_abort("Could not replace {.path {basename(target)}}.", class = "io",
                code = "WRITE_FAILED", call = call)
    }
    written <- normalizePath(target, winslash = "/")
    .write_json_atomic(list(
      document = "annotatr_commit_receipt", idempotency_key = key, patch_id = x$patch_id,
      patch_digest = x$patch_digest, previous_revision = x$base_revision,
      new_revision = new_rev, committed_at = committed_at
    ), paste0(target, ".commit.json"))
  }
  receipt <- structure(list(
    state = "committed",
    patch_id = x$patch_id,
    idempotency_key = key,
    previous_revision = x$base_revision,
    new_revision = new_rev,
    applied = x$operations[x$operations$op %in% c("create", "update", "delete"), ],
    conflicts = x$operations[x$operations$op == "conflict", ],
    project = project,
    written = written,
    committed_at = committed_at,
    replayed = FALSE
  ), class = "at_commit_receipt")
  assign(key, list(patch_digest = x$patch_digest, receipt = receipt), envir = .commit_registry)
  receipt
}

#' @export
print.at_commit_receipt <- function(x, ...) {
  cat(cli::format_inline("{.cls at_commit_receipt} {x$patch_id} ({x$state}{if (isTRUE(x$replayed)) ', replayed' else ''})"),
      "\n", sep = "")
  cat("  applied ", nrow(x$applied), " | conflicts ", nrow(x$conflicts), "\n", sep = "")
  cat("  ", x$previous_revision, " -> ", x$new_revision, "\n", sep = "")
  invisible(x)
}
