# DNN training datasets: grouped, leakage-free splits of fixed-size tiles with
# integer masks, complete legends, band/transform provenance and an integrity
# inventory; independent dataset checks; and staged import of model
# predictions. Training itself is an external, optional workflow.

.training_mask_types <- c("labelled", "instance", "binary")

# Write a numeric [y, x, band] array as a float32 NumPy array of shape
# (height, width, bands) (Fortran order stores the R array verbatim).
.npy_write_array3 <- function(arr, path) {
  d <- dim(arr)
  if (length(d) == 2L) d <- c(d, 1L)
  dict <- sprintf("{'descr': '<f4', 'fortran_order': True, 'shape': (%d, %d, %d), }",
                  d[1], d[2], d[3])
  preamble <- length(.NPY_MAGIC) + 2L + 2L
  pad <- (64L - ((preamble + nchar(dict) + 1L) %% 64L)) %% 64L
  dict <- paste0(dict, strrep(" ", pad), "\n")
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.raw(c(.NPY_MAGIC, 1, 0)), con)
  writeBin(as.integer(nchar(dict)), con, size = 2L, endian = "little")
  writeBin(charToRaw(dict), con)
  writeBin(as.double(arr), con, size = 4L, endian = "little")
  invisible(path)
}

# Deterministic grouped split: rank groups by SHA-256 of "seed:group" and cut by
# cumulative fractions. Independent of the R random-number generator.
.assign_splits <- function(groups, fractions, seed) {
  groups <- unique(as.character(groups))
  keys <- vapply(groups, function(g) .sha256_bytes(paste0(seed, ":", g)), character(1))
  ord <- groups[order(keys, method = "radix")]
  n <- length(ord)
  fr <- fractions / sum(fractions)
  cuts <- round(cumsum(fr) * n)
  cuts[length(cuts)] <- n
  split <- character(n)
  start <- 1L
  for (k in seq_along(fr)) {
    end <- cuts[k]
    if (end >= start) split[start:end] <- names(fr)[k]
    start <- end + 1L
  }
  stats::setNames(split, ord)
}

.training_entries <- function(x, call) {
  if (inherits(x, "annot_project")) {
    return(list(list(entry_id = "entry-0001", name = x$meta$name %||% basename(x$image$source),
                     project = x)))
  }
  if (!inherits(x, "annot_session")) {
    .at_abort("{.arg x} must be an {.cls annot_project} or {.cls annot_session}.", call = call)
  }
  out <- list()
  for (i in seq_len(nrow(x$manifest))) {
    p <- x$projects[[i]]
    if (is.null(p)) next
    out[[length(out) + 1L]] <- list(entry_id = sprintf("entry-%04d", i), name = x$manifest$name[i],
                                    project = p)
  }
  if (!length(out)) {
    .at_abort("The session has no materialised projects to export.", call = call)
  }
  out
}

#' Export a DNN training dataset
#'
#' Tile annotated images into a portable training dataset with integer masks,
#' deterministic grouped splits and a complete provenance manifest. Splits are
#' assigned per group (by default per image, or by `subject_id`/`sample_id`
#' from `groups`), so tiles of one group never occur in two splits. Masks are
#' written as integer TIFF (or NPY) with background `0`; class codes are shared
#' across the dataset and instance ids are only produced for
#' `mask_type = "instance"`. Tiles that do not fit the image are excluded as
#' partial; empty and ambiguous (overlapping labels) tiles are counted and
#' handled by policy. Image bytes are excluded unless `include_images = TRUE`.
#'
#' `mask_type` uses training terminology: `"labelled"` is a semantic class-code
#' mask (annotatR `"multiclass"`), `"instance"` has one id per ROI (annotatR
#' `"labelled"`), `"binary"` marks foreground. The mapping is recorded in the
#' manifest.
#'
#' @param x An [annot_session] (materialised entries) or [annot_project].
#' @param destination New dataset directory.
#' @param split Optional explicit assignment: a named list
#'   (`train`, `validation`, `test`) of group ids. `NULL` assigns groups by
#'   `fractions` and `seed`.
#' @param tile_size Tile edge length in pixels at `level`.
#' @param overlap Tile overlap in pixels (`0 <= overlap < tile_size`).
#' @param level Pyramid level.
#' @param mask_type `"labelled"`, `"instance"` or `"binary"`.
#' @param bands Band indices recorded (and written with `include_images`).
#' @param include_images Logical; also write float32 NPY image tiles.
#' @param seed Split seed (recorded).
#' @param group_by Group column used for splitting: `"image_id"` (default),
#'   `"sample_id"` or `"subject_id"`.
#' @param groups Optional data frame with `entry_id` (or `name`) plus
#'   `subject_id` and/or `sample_id` columns (character).
#' @param fractions Named split fractions.
#' @param label_map Optional named integer class codes (`label = code`, codes
#'   `>= 1`); defaults to first-seen label order.
#' @param empty_tiles `"keep"` (default) or `"exclude"` tiles without
#'   foreground.
#' @param mask_format `"tiff"` (default) or `"npy"`.
#' @param normalization Optional list describing value normalisation applied
#'   downstream (recorded, not applied).
#' @param overwrite Logical; replace an existing dataset directory.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_training_export` list: `destination`, `dataset_digest`,
#'   `manifest`, `files` and `checks` (from [at_training_check()]).
#' @family training
#' @seealso [at_training_check()], [at_training_import()]
#' @export
#' @examplesIf requireNamespace("tiff", quietly = TRUE)
#' sess <- at_example_session(3)
#' for (i in 1:3) sess$projects[[i]] <- at_example_project()
#' ds <- at_training_export(sess, file.path(tempdir(), "train-example"), tile_size = 128,
#'                          overwrite = TRUE)
#' ds$manifest$counts$tiles
at_training_export <- function(x, destination, split = NULL, tile_size = 256L, overlap = 0L,
                               level = 0L, mask_type = c("labelled", "instance", "binary"),
                               bands = NULL, include_images = FALSE, seed = 1L,
                               group_by = c("image_id", "sample_id", "subject_id"), groups = NULL,
                               fractions = c(train = 0.7, validation = 0.15, test = 0.15),
                               label_map = NULL, empty_tiles = c("keep", "exclude"),
                               mask_format = c("tiff", "npy"), normalization = NULL,
                               overwrite = FALSE, call = rlang::caller_env()) {
  .check_string(destination, call = call)
  tile_size <- .check_count(tile_size, min = 8L, call = call)
  overlap <- .check_count(overlap, call = call)
  if (overlap >= tile_size) {
    .at_abort("{.arg overlap} must be smaller than {.arg tile_size}.", call = call)
  }
  level <- .check_count(level, call = call)
  mask_type <- .check_choice(mask_type, .training_mask_types, call = call)
  group_by <- .check_choice(group_by, c("image_id", "sample_id", "subject_id"), call = call)
  empty_tiles <- .check_choice(empty_tiles, c("keep", "exclude"), call = call)
  mask_format <- .check_choice(mask_format, c("tiff", "npy"), call = call)
  seed <- .check_count(seed, call = call)
  .check_flag(include_images, call = call)
  .check_flag(overwrite, call = call)
  if (!is.numeric(fractions) || is.null(names(fractions)) || any(fractions < 0) || sum(fractions) <= 0) {
    .at_abort("{.arg fractions} must be non-negative named numbers.", call = call)
  }
  entries <- .training_entries(x, call)

  # Group ids per entry.
  ginfo <- lapply(entries, function(e) {
    img_id <- .image_id(e$project$image, .source_files(e$project$image))
    row <- NULL
    if (!is.null(groups)) {
      groups <- as.data.frame(groups, stringsAsFactors = FALSE)
      key <- if ("entry_id" %in% names(groups)) groups$entry_id == e$entry_id else groups$name == e$name
      row <- groups[which(key)[1], , drop = FALSE]
    }
    get <- function(col) {
      v <- if (!is.null(row) && col %in% names(row)) as.character(row[[col]]) else NA_character_
      if (length(v) == 0L) NA_character_ else v
    }
    list(image_id = img_id, subject_id = get("subject_id"), sample_id = get("sample_id"))
  })
  group_ids <- vapply(ginfo, function(g) {
    v <- g[[group_by]]
    if (is.na(v)) {
      .at_abort("Group column {.field {group_by}} is missing for an entry; supply {.arg groups}.",
                code = "GROUP_MISSING", call = call)
    }
    v
  }, character(1))
  split_of <- if (is.null(split)) {
    .assign_splits(group_ids, fractions, seed)
  } else {
    s <- unlist(lapply(names(split), function(nm) stats::setNames(rep(nm, length(split[[nm]])),
                                                                   as.character(split[[nm]]))))
    if (anyDuplicated(names(s))) {
      .at_abort("A group appears in more than one split.", code = "SPLIT_LEAKAGE", call = call)
    }
    missing <- setdiff(unique(group_ids), names(s))
    if (length(missing)) {
      .at_abort("Groups {.val {missing}} are not assigned to a split.", code = "SPLIT_INCOMPLETE",
                call = call)
    }
    s
  }

  # Global class codes.
  all_labels <- unique(unlist(lapply(entries, function(e) at_rois(e$project)$label)))
  if (is.null(label_map)) {
    label_map <- stats::setNames(seq_along(all_labels), all_labels)
  } else {
    label_map <- .check_values_map(label_map, "multiclass", call = call)
    if (any(label_map < 1L)) {
      .at_abort("{.arg label_map} codes must be >= 1 (0 is background).", call = call)
    }
    unmapped <- setdiff(all_labels, names(label_map))
    if (length(unmapped)) {
      .at_abort("{.arg label_map} does not map labels {.val {unmapped}}.", code = "LEGEND_INCOMPLETE",
                call = call)
    }
  }

  dest <- normalizePath(destination, winslash = "/", mustWork = FALSE)
  if (file.exists(dest)) {
    if (!overwrite || !file.exists(file.path(dest, "training-manifest.json"))) {
      .at_abort("{.path {destination}} already exists.", class = "io", code = "DESTINATION_EXISTS",
                call = call)
    }
  }
  stage <- file.path(dirname(dest), paste0(".", basename(dest), ".partial-", .random_hex(6L)))
  dir.create(stage, recursive = TRUE)
  ok <- FALSE
  on.exit(if (!ok) unlink(stage, recursive = TRUE), add = TRUE)

  tiles <- list()
  images <- list()
  class_px <- list()
  step <- tile_size - overlap
  for (k in seq_along(entries)) {
    e <- entries[[k]]
    proj <- e$project
    img <- proj$image
    d <- at_dims(img, level)
    sp <- split_of[[group_ids[k]]]
    full <- switch(
      mask_type,
      labelled = at_mask(proj, type = "multiclass", level = level, values = label_map[unique(at_rois(proj)$label)]),
      instance = at_mask(proj, type = "labelled", level = level),
      binary = at_mask(proj, type = "binary", level = level)
    )
    m <- as.matrix(full)
    storage.mode(m) <- "integer"
    covers <- matrix(0L, d[2], d[1])
    for (en in .collect_mask_rois(proj, level = level)) {
      covers <- covers + .cover(en$geom, d)
    }
    inst_legend <- if (mask_type == "instance") {
      lg <- attr(full, "legend")
      lapply(seq_len(nrow(lg)), function(i) list(instance_id = lg$value[i], roi_id = lg$roi_id[i],
                                                 label = lg$label[i], class_code = unname(label_map[lg$label[i]]),
                                                 layer = lg$layer[i]))
    } else list()
    rstatus <- vapply(unlist(lapply(proj$layers, `[[`, "rois"), recursive = FALSE),
                      function(r) r$attributes$review_status %||% "unreviewed", character(1))
    images[[k]] <- list(
      entry_id = e$entry_id, name = e$name, image_id = ginfo[[k]]$image_id,
      group_id = group_ids[k], subject_id = ginfo[[k]]$subject_id, sample_id = ginfo[[k]]$sample_id,
      split = sp, source_name = basename(img$source), backend = img$backend,
      width = d[1], height = d[2], level = level,
      annotation_revision = at_annotation_revision(proj),
      layers = as.list(names(proj$layers)), n_rois = nrow(at_rois(proj)),
      review_status_counts = as.list(table(factor(rstatus, levels = c("unreviewed", "reviewed", "rejected", "staged")))),
      calibration_digest = at_hsi_meta(img)$calibration_digest,
      transform_digest = .transform_digest(img),
      instance_legend = inst_legend
    )
    ys <- seq(0L, d[2] - 1L, by = step)
    xs <- seq(0L, d[1] - 1L, by = step)
    for (y0 in ys) {
      for (x0 in xs) {
        tid <- sprintf("%s_l%d_x%06d_y%06d", e$entry_id, level, x0, y0)
        partial <- x0 + tile_size > d[1] || y0 + tile_size > d[2]
        rec <- list(tile_id = tid, entry_id = e$entry_id, split = sp, x = x0, y = y0,
                    width = tile_size, height = tile_size, level = level,
                    mask_file = NA_character_, image_file = NA_character_,
                    foreground_px = 0L, ambiguous_px = 0L, classes = list(),
                    status = "included", reason = NA_character_)
        if (partial) {
          rec$status <- "excluded"
          rec$reason <- "partial_tile"
          tiles[[length(tiles) + 1L]] <- rec
          next
        }
        rows <- (y0 + 1L):(y0 + tile_size)
        cols <- (x0 + 1L):(x0 + tile_size)
        tm <- m[rows, cols, drop = FALSE]
        rec$foreground_px <- as.integer(sum(tm != 0L))
        rec$ambiguous_px <- as.integer(sum(covers[rows, cols] > 1L))
        vals <- sort(unique(as.integer(tm[tm != 0L])))
        rec$classes <- as.list(vals)
        if (rec$foreground_px == 0L && empty_tiles == "exclude") {
          rec$status <- "excluded"
          rec$reason <- "empty"
          tiles[[length(tiles) + 1L]] <- rec
          next
        }
        if (rec$foreground_px == 0L) rec$reason <- "empty"
        if (rec$ambiguous_px > 0L) rec$reason <- "ambiguous_overlap"
        mdir <- file.path(stage, "masks", sp)
        dir.create(mdir, recursive = TRUE, showWarnings = FALSE)
        if (mask_format == "tiff") {
          mk <- .new_annot_mask(tm, tibble::tibble(value = integer(), label = character(),
                                                   layer = character(), roi_id = character(),
                                                   n_px = integer(), colour = character()),
                                level, c(tile_size, tile_size), mask_type)
          bits <- if (max(tm, 0L) > 255L) 16L else 8L
          if (max(tm, 0L) > 65535L) {
            .at_abort("Mask values exceed 16 bits; use {.code mask_format = \"npy\"}.",
                      class = "limit", code = "MASK_RANGE", call = call)
          }
          f <- file.path(mdir, paste0(tid, ".tif"))
          at_write_mask(mk, f, format = "tiff", bits = bits, legend = FALSE)
        } else {
          f <- file.path(mdir, paste0(tid, ".npy"))
          .npy_write_matrix(tm, f, dtype = "int32")
        }
        rec$mask_file <- .relative_to(f, stage)
        if (include_images) {
          bsel <- bands %||% seq_len(img$n_bands)
          arr <- at_tile(img, level = level, xrange = c(x0 + 1L, x0 + tile_size),
                         yrange = c(y0 + 1L, y0 + tile_size), bands = bsel)
          idir <- file.path(stage, "images", sp)
          dir.create(idir, recursive = TRUE, showWarnings = FALSE)
          fi <- file.path(idir, paste0(tid, ".npy"))
          .npy_write_array3(arr, fi)
          rec$image_file <- .relative_to(fi, stage)
        }
        for (v in vals) {
          key <- paste(sp, v, sep = "|")
          class_px[[key]] <- (class_px[[key]] %||% 0) + sum(tm == v)
        }
        tiles[[length(tiles) + 1L]] <- rec
      }
    }
  }

  first_img <- entries[[1]]$project$image
  bsel <- bands %||% seq_len(first_img$n_bands)
  bt <- at_bands(first_img)[bsel, ]
  status <- vapply(tiles, `[[`, character(1), "status")
  reason <- vapply(tiles, function(t) t$reason %||% NA_character_, character(1))
  tsplit <- vapply(tiles, `[[`, character(1), "split")
  counts <- list(
    tiles = sum(status == "included"),
    tiles_by_split = as.list(table(factor(tsplit[status == "included"], levels = names(fractions)))),
    images_by_split = as.list(table(factor(vapply(images, `[[`, character(1), "split"), levels = names(fractions)))),
    excluded = list(partial = sum(reason == "partial_tile", na.rm = TRUE),
                    empty = sum(status == "excluded" & reason == "empty", na.rm = TRUE)),
    flagged = list(empty = sum(status == "included" & reason == "empty", na.rm = TRUE),
                   ambiguous = sum(status == "included" & reason == "ambiguous_overlap", na.rm = TRUE)),
    class_balance = lapply(stats::setNames(names(fractions), names(fractions)), function(sp) {
      keys <- grep(paste0("^", sp, "\\|"), names(class_px), value = TRUE)
      stats::setNames(lapply(keys, function(k) class_px[[k]]), sub("^.*\\|", "", keys))
    })
  )
  code_dtype <- if (mask_format == "npy") "int32" else if (max(c(label_map, 0L)) > 255L || mask_type == "instance") "uint16" else "uint8"
  manifest <- list(
    schema = .contract$training,
    schema_version = .contract$version,
    document = "training_manifest",
    consumer = .contract$consumer,
    annotatr_version = .pkg_version(),
    qupflowr_version = NA_character_,
    source_revision = .source_revision(),
    capability_digest = at_interop_capabilities()$digest,
    created = .utc_stamp(),
    seed = seed,
    split_policy = list(group_by = group_by, fractions = as.list(fractions), explicit = !is.null(split),
                        algorithm = "groups ranked by sha256('<seed>:<group_id>'), cut by cumulative fractions"),
    groups = lapply(unique(group_ids), function(g) list(group_id = g, split = split_of[[g]],
                                                         entry_ids = as.list(vapply(entries[group_ids == g], `[[`, character(1), "entry_id")))),
    tile_policy = list(tile_size = tile_size, overlap = overlap, stride = step, level = level,
                       partial_tiles = "excluded", empty_tiles = empty_tiles,
                       pixel_origin = "top_left", axis_order = "[y, x] masks; images (height, width, bands)",
                       coverage_rule = "pixel centre inside geometry; half-open [lower, upper) ties",
                       overlap_rule = "later z-order wins; ambiguous pixels counted per tile"),
    mask_encoding = list(mask_type = mask_type,
                         annotatr_mask_type = switch(mask_type, labelled = "multiclass",
                                                     instance = "labelled", binary = "binary"),
                         dtype = code_dtype, background = 0L, mask_format = mask_format,
                         class_legend = lapply(names(label_map), function(l) list(code = unname(label_map[[l]]), label = l)),
                         instance_ids = if (mask_type == "instance") "per image, see images[].instance_legend" else "not produced"),
    bands = lapply(seq_len(nrow(bt)), function(i) list(index = bt$index[i], name = bt$name[i],
                                                       wavelength = bt$wavelength[i], fwhm = bt$fwhm[i],
                                                       unit = bt$unit[i])),
    value_unit = at_hsi_meta(first_img)$value_unit,
    normalization = normalization %||% list(policy = "none", range = NULL),
    include_images = include_images,
    images = images,
    tiles = tiles,
    counts = counts,
    model = list(model_digest = NA_character_, prediction_digest = NA_character_,
                 confidence_policy = NA_character_),
    extensions = .json_object()
  )
  .schema_assert(.as_json_value(manifest), .contract$handoff, "training-manifest",
                 what = "training manifest", call = call)
  .write_json_atomic(manifest, file.path(stage, "training-manifest.json"))
  integrity <- .build_integrity(stage)
  .write_json_atomic(integrity, file.path(stage, "integrity.json"))
  if (file.exists(dest)) {
    backup <- paste0(dest, ".previous-", .random_hex(4L))
    file.rename(dest, backup)
    on.exit(unlink(backup, recursive = TRUE), add = TRUE)
  }
  if (!file.rename(stage, dest)) {
    .at_abort("Could not move the dataset into place.", class = "io", code = "WRITE_FAILED", call = call)
  }
  ok <- TRUE
  checks <- at_training_check(dest, call = call)
  structure(list(destination = dest, dataset_digest = .handoff_digest(integrity), manifest = manifest,
                 files = vapply(integrity$files, `[[`, character(1), "path"), checks = checks),
            class = "at_training_export")
}

#' @export
print.at_training_export <- function(x, ...) {
  cat(cli::format_inline("{.cls at_training_export} {.path {x$destination}}"), "\n", sep = "")
  cat("  tiles: ", x$manifest$counts$tiles, "  |  digest: ", x$dataset_digest, "\n", sep = "")
  print(x$checks)
  invisible(x)
}

.read_tile_mask <- function(dir, rel) {
  f <- file.path(dir, rel)
  if (grepl("\\.npy$", f)) {
    m <- .npy_read_matrix(f)
  } else {
    m <- .read_mask_matrix(f, call = rlang::caller_env())$m
  }
  storage.mode(m) <- "integer"
  m
}

#' Check a training dataset
#'
#' Run independent checks on an exported training dataset: the integrity
#' inventory, split leakage (every group and image in exactly one split, every
#' tile in its image's split), mask dimensions and orientation, integer label
#' range against the class legend, the recorded overlap counts, and a
#' mask -> ROI -> mask round trip on a sample of tiles. When the source `x` is
#' supplied, each sampled tile is also re-rasterised from the annotations and
#' compared exactly.
#'
#' @param dataset Path of a dataset written by [at_training_export()].
#' @param x Optional source [annot_session] or [annot_project].
#' @param max_roundtrip_tiles Maximum number of tiles sampled for round trips.
#' @param call The calling environment, for error reporting.
#' @return A tibble of class `at_training_check` with `check`, `status`
#'   (`"ok"`, `"warn"`, `"fail"`) and `detail`.
#' @family training
#' @export
at_training_check <- function(dataset, x = NULL, max_roundtrip_tiles = 20L,
                              call = rlang::caller_env()) {
  .check_string(dataset, call = call)
  max_roundtrip_tiles <- .check_count(max_roundtrip_tiles, call = call)
  dir <- normalizePath(dataset, winslash = "/", mustWork = TRUE)
  rows <- list()
  add <- function(check, status, detail) rows[[length(rows) + 1L]] <<- .check_row(check, status, detail)
  integ <- tryCatch({
    doc <- .read_json_doc(file.path(dir, "integrity.json"), call = call)
    actual <- .list_payload_files(dir)
    listed <- vapply(doc$files, `[[`, character(1), "path")
    bad <- Filter(function(f) !file.exists(file.path(dir, f$path)) ||
                    !identical(.sha256_file(file.path(dir, f$path)), f$sha256), doc$files)
    extra <- setdiff(actual, listed)
    if (length(bad) || length(extra)) stop_msg <- sprintf("%d altered/missing, %d extra", length(bad), length(extra)) else stop_msg <- NULL
    stop_msg
  }, error = function(e) conditionMessage(e))
  if (is.null(integ)) add("integrity", "ok", "inventory verified") else add("integrity", "fail", integ)
  man <- .read_json_doc(file.path(dir, "training-manifest.json"), call = call)
  .check_major_version(man$schema_version, 1L, "training manifest", call = call)

  img_split <- stats::setNames(vapply(man$images, `[[`, character(1), "split"),
                               vapply(man$images, `[[`, character(1), "entry_id"))
  grp <- vapply(man$images, `[[`, character(1), "group_id")
  leak_groups <- names(which(tapply(unname(img_split), grp, function(s) length(unique(s))) > 1L))
  iid <- vapply(man$images, `[[`, character(1), "image_id")
  leak_images <- names(which(tapply(unname(img_split), iid, function(s) length(unique(s))) > 1L))
  tile_bad <- Filter(function(t) !identical(t$split, img_split[[t$entry_id]]), man$tiles)
  if (length(leak_groups) || length(leak_images) || length(tile_bad)) {
    add("split_leakage", "fail", sprintf("groups %s; images %s; %d tiles outside their image split",
                                         paste(leak_groups, collapse = ","),
                                         paste(leak_images, collapse = ","), length(tile_bad)))
  } else {
    add("split_leakage", "ok", sprintf("%d groups, %d images, no shared source across splits",
                                       length(unique(grp)), length(iid)))
  }

  included <- Filter(function(t) identical(t$status, "included"), man$tiles)
  codes <- vapply(man$mask_encoding$class_legend, function(l) as.integer(l$code), integer(1))
  allowed <- switch(man$mask_encoding$mask_type,
                    labelled = c(0L, codes),
                    binary = c(0L, 1L),
                    instance = NULL)
  dim_bad <- 0L
  range_bad <- 0L
  for (t in included) {
    m <- tryCatch(.read_tile_mask(dir, t$mask_file), error = function(e) NULL)
    if (is.null(m) || nrow(m) != t$height || ncol(m) != t$width) {
      dim_bad <- dim_bad + 1L
      next
    }
    vals <- unique(as.integer(m))
    if (!is.null(allowed) && length(setdiff(vals, allowed))) range_bad <- range_bad + 1L
    if (is.null(allowed)) {
      inst <- Filter(function(im) identical(im$entry_id, t$entry_id), man$images)[[1]]$instance_legend
      ids <- vapply(inst, function(l) as.integer(l$instance_id), integer(1))
      if (length(setdiff(vals, c(0L, ids)))) range_bad <- range_bad + 1L
    }
  }
  add("mask_dimensions", if (dim_bad) "fail" else "ok",
      sprintf("%d of %d tiles with wrong or unreadable dimensions", dim_bad, length(included)))
  add("label_range", if (range_bad) "fail" else "ok",
      sprintf("%d of %d tiles with codes outside the legend", range_bad, length(included)))
  amb <- sum(vapply(included, function(t) as.integer(t$ambiguous_px), integer(1)))
  add("overlap", if (amb > 0L) "warn" else "ok", sprintf("%d ambiguous (overlapping) pixels in included tiles", amb))

  sample <- utils::head(Filter(function(t) as.integer(t$foreground_px) > 0L, included), max_roundtrip_tiles)
  rt_bad <- 0L
  src_bad <- 0L
  entries <- if (is.null(x)) NULL else .training_entries(x, call)
  for (t in sample) {
    m <- .read_tile_mask(dir, t$mask_file)
    tmp <- tempfile(fileext = ".npy")
    .npy_write_matrix(m, tmp, dtype = "int32")
    vals <- sort(setdiff(unique(as.integer(m)), 0L))
    lg <- tibble::tibble(value = vals, label = as.character(vals))
    lyr <- suppressWarnings(at_read_mask(tmp, legend = lg))
    unlink(tmp)
    back <- matrix(0L, nrow(m), ncol(m))
    for (r in lyr$rois) {
      back[.cover(r$geometry[[1]], c(ncol(m), nrow(m)))] <- as.integer(r$label)
    }
    if (!identical(back, m)) rt_bad <- rt_bad + 1L
    if (!is.null(entries)) {
      e <- Filter(function(en) identical(en$entry_id, t$entry_id), entries)
      if (length(e)) {
        proj <- e[[1]]$project
        lm <- stats::setNames(codes, vapply(man$mask_encoding$class_legend, `[[`, character(1), "label"))
        full <- switch(man$mask_encoding$mask_type,
                       labelled = at_mask(proj, type = "multiclass", level = t$level,
                                          values = lm[unique(at_rois(proj)$label)]),
                       instance = at_mask(proj, type = "labelled", level = t$level),
                       binary = at_mask(proj, type = "binary", level = t$level))
        fm <- as.matrix(full)
        storage.mode(fm) <- "integer"
        if (!identical(fm[(t$y + 1L):(t$y + t$height), (t$x + 1L):(t$x + t$width), drop = FALSE], m)) {
          src_bad <- src_bad + 1L
        }
      }
    }
  }
  add("mask_roi_roundtrip", if (rt_bad) "fail" else "ok",
      sprintf("%d of %d sampled tiles differ after mask -> ROI -> mask", rt_bad, length(sample)))
  if (!is.null(entries)) {
    add("source_agreement", if (src_bad) "fail" else "ok",
        sprintf("%d of %d sampled tiles differ from re-rasterised annotations", src_bad, length(sample)))
  }
  out <- do.call(rbind, rows)
  class(out) <- c("at_training_check", class(out))
  out
}

#' Import model predictions as staged annotations
#'
#' Convert an integer prediction mask into ROIs and stage them against a
#' project; nothing is committed. The prediction must match the image
#' dimensions at `level`, contain only integers, and every non-background value
#' must be in `label_map`; otherwise the import aborts. Optional per-pixel
#' confidence below `min_confidence` is set to background first. Model and
#' prediction digests and the confidence policy are recorded on every ROI,
#' which starts as `review_status = "unreviewed"`. Reviewed or locked
#' annotations are never overwritten: with `replace = TRUE` they become staged
#' conflicts.
#'
#' @param x An [annot_project].
#' @param predictions A mask file (TIFF/PNG/NPY), an `annot_mask`, or an
#'   integer matrix `[y, x]`.
#' @param label_map Named integer vector `label = code` (codes >= 1; 0 is
#'   background).
#' @param level Pyramid level of the prediction grid.
#' @param source ROI source string. Default `"dnn_prediction"`.
#' @param model List with `name`, `version` and `sha256` of the model.
#' @param confidence Optional numeric matrix of per-pixel confidence.
#' @param min_confidence Optional threshold applied to `confidence`.
#' @param layer Target layer name. Default `"predictions"`.
#' @param replace Logical; stage removal of existing unreviewed ROIs of `layer`
#'   not present in the prediction.
#' @param stage Logical; return an `at_staged_patch` (default) or, with
#'   `FALSE`, the prediction layer only.
#' @param call The calling environment, for error reporting.
#' @return An `at_staged_patch` (or an [annot_layer] when `stage = FALSE`)
#'   with attribute `prediction_digest`.
#' @family training
#' @seealso [at_commit_qupflowr()]
#' @export
at_training_import <- function(x, predictions, label_map, level = 0L, source = "dnn_prediction",
                               model = list(name = NA_character_, version = NA_character_,
                                            sha256 = NA_character_),
                               confidence = NULL, min_confidence = NULL, layer = "predictions",
                               replace = FALSE, stage = TRUE, call = rlang::caller_env()) {
  .check_project(x, call = call)
  level <- .check_count(level, call = call)
  .check_string(source, call = call)
  .check_string(layer, call = call)
  .check_flag(replace, call = call)
  .check_flag(stage, call = call)
  label_map <- .check_values_map(label_map, "multiclass", call = call)
  if (any(label_map < 1L) || anyDuplicated(label_map)) {
    .at_abort("{.arg label_map} codes must be unique and >= 1.", call = call)
  }
  m <- if (inherits(predictions, "annot_mask")) {
    as.matrix(predictions)
  } else if (is.matrix(predictions)) {
    predictions
  } else if (.is_string(predictions)) {
    .check_file(predictions, call = call)
    if (grepl("\\.npy$", predictions, ignore.case = TRUE)) .npy_read_matrix(predictions, call = call)
    else .read_mask_matrix(predictions, call)$m
  } else {
    .at_abort("{.arg predictions} must be a mask file, an annot_mask or an integer matrix.", call = call)
  }
  if (!is.numeric(m) || any(!is.na(m) & m != round(m))) {
    .at_abort("Predictions must be integer class codes.", code = "DTYPE_INVALID", call = call)
  }
  storage.mode(m) <- "integer"
  d <- at_dims(x$image, level)
  if (nrow(m) != d[2] || ncol(m) != d[1]) {
    .at_abort("Predictions are {ncol(m)} x {nrow(m)} px but the image is {d[1]} x {d[2]} px at level {level}.",
              code = "MASK_DIMENSIONS", call = call)
  }
  bad <- setdiff(unique(as.integer(m[!is.na(m) & m != 0L])), unname(label_map))
  if (length(bad)) {
    .at_abort("Prediction values {.val {bad}} are not in {.arg label_map}.", code = "LABEL_OUT_OF_RANGE",
              call = call)
  }
  policy <- list(min_confidence = min_confidence %||% NA_real_,
                 rule = if (is.null(min_confidence)) "none" else "pixels below min_confidence set to background")
  if (!is.null(confidence)) {
    if (!is.matrix(confidence) || !identical(dim(confidence), dim(m))) {
      .at_abort("{.arg confidence} must be a matrix with the prediction's dimensions.", call = call)
    }
    if (!is.null(min_confidence)) m[confidence < min_confidence] <- 0L
  }
  m[is.na(m)] <- 0L
  pred_digest <- .sha256_bytes(writeBin(as.integer(m), raw(), size = 4L, endian = "little"))
  tmp <- tempfile(fileext = ".npy")
  on.exit(unlink(tmp), add = TRUE)
  .npy_write_matrix(m, tmp, dtype = "int32")
  lg <- tibble::tibble(value = unname(label_map), label = names(label_map))
  plyr <- suppressWarnings(at_read_mask(tmp, level = level, legend = lg))
  out <- at_layer(layer, labels = names(label_map))
  k <- 0L
  for (r in plyr$rois) {
    k <- k + 1L
    r$id <- sprintf("pred-%s-%05d", substr(pred_digest, 1L, 8L), k)
    r$source <- source
    r$attributes$review_status <- "unreviewed"
    r$attributes$prediction <- list(model_name = model$name %||% NA_character_,
                                    model_version = model$version %||% NA_character_,
                                    model_sha256 = model$sha256 %||% NA_character_,
                                    prediction_sha256 = pred_digest, confidence_policy = policy,
                                    label_map_sha256 = .digest_json(as.list(label_map)))
    out$rois <- c(out$rois, list(r))
  }
  if (!stage) {
    attr(out, "prediction_digest") <- pred_digest
    return(out)
  }
  patch <- at_stage_qupflowr(x, out, delete_missing = replace, call = call)
  attr(patch, "prediction_digest") <- pred_digest
  patch
}
