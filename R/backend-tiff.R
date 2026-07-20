# TIFF backends.
#
# "tiff"    - pyramidal / multi-directory TIFF via the base `tiff` package,
#             treating IFDs as pyramid levels when their dims decrease.
# "ometiff" - OME-TIFF, qptiff (Akoya PhenoImager), and vendor formats via
#             `RBioFormats` (Bioconductor, optional). Exposes pyramid levels and
#             channel metadata where present.

# ---- tiff backend ----------------------------------------------------------

# Coerce a readTIFF result (a single image or a list of them) into a list of
# [y, x, band] arrays, ordered by decreasing size (level 0 first).
.tiff_to_levels <- function(x) {
  imgs <- if (is.list(x)) x else list(x)
  imgs <- lapply(imgs, function(a) {
    if (length(dim(a)) == 2L) array(a, dim = c(dim(a), 1L)) else a
  })
  sizes <- vapply(imgs, function(a) dim(a)[1] * dim(a)[2], numeric(1))
  imgs <- imgs[order(sizes, decreasing = TRUE)]
  lapply(imgs, function(a) {
    storage.mode(a) <- "double"
    a
  })
}

# Parse channel names from an OME-XML / qptiff ImageDescription, degrading
# gracefully. Never errors.
.tiff_channel_names <- function(desc, n) {
  default <- paste0("Channel ", seq_len(n))
  if (is.null(desc) || !nzchar(desc)) {
    return(default)
  }
  nm <- tryCatch(
    {
      if (requireNamespace("xml2", quietly = TRUE) && grepl("<", desc, fixed = TRUE)) {
        doc <- xml2::read_xml(desc)
        ch <- xml2::xml_find_all(doc, "//*[local-name()='Channel']")
        vals <- xml2::xml_attr(ch, "Name")
        vals[!is.na(vals)]
      } else {
        m <- regmatches(desc, gregexpr("<Name>([^<]*)</Name>", desc, perl = TRUE))[[1]]
        sub("<Name>([^<]*)</Name>", "\\1", m)
      }
    },
    error = function(e) character(0)
  )
  if (length(nm) == n) nm else default
}

.tiff_read <- function(path, ...) {
  if (!requireNamespace("tiff", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.val tiff} backend requires package {.pkg tiff}.",
      "i" = "Install it with {.code install.packages(\"tiff\")}."
    ))
  }
  # Multi-channel TIFFs can emit benign libtiff ExtraSamples warnings; the read
  # itself is correct, so they are suppressed here.
  raw <- suppressWarnings(tiff::readTIFF(path, all = TRUE, as.is = TRUE, info = TRUE))
  desc <- attr(if (is.list(raw)) raw[[1]] else raw, "description")
  levels <- .tiff_to_levels(raw)
  level_dims <- lapply(levels, function(a) c(dim(a)[2], dim(a)[1]))
  nb <- dim(levels[[1]])[3]
  # Distinct decreasing sizes make it a pyramid; equal-size IFDs are not.
  is_pyr <- length(levels) > 1L &&
    !anyDuplicated(vapply(level_dims, function(d) d[1], numeric(1)))
  if (!is_pyr) {
    levels <- levels[1]
    level_dims <- level_dims[1]
  }
  new_annot_image(
    source = path, backend = "tiff",
    dims = level_dims[[1]], n_levels = length(levels), level_dims = level_dims,
    n_bands = nb, band_names = .tiff_channel_names(desc, nb),
    pixel_size = c(1, 1), pixel_unit = "px", dtype = "uint16",
    handle = list(levels = levels), meta = list()
  )
}

.tiff_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$levels[[level + 1L]]
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(dim(arr)[3]) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.tiff_detect <- function(path) {
  grepl("\\.(tiff?)$", path, ignore.case = TRUE) &&
    !grepl("\\.(ome\\.tif|ome\\.tiff|qptiff)$", path, ignore.case = TRUE)
}

.tiff_available <- function() requireNamespace("tiff", quietly = TRUE)

# ---- ometiff backend (RBioFormats) -----------------------------------------

.ometiff_read <- function(path, ...) {
  if (!requireNamespace("RBioFormats", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.val ometiff} backend requires package {.pkg RBioFormats}.",
      "i" = "Install it from Bioconductor: {.code BiocManager::install(\"RBioFormats\")}."
    ))
  }
  meta <- RBioFormats::read.metadata(path)
  core <- RBioFormats::coreMetadata(meta, series = 1)
  n_levels <- tryCatch(as.integer(core$resolutionCount %||% 1L), error = function(e) 1L)
  read_level <- function(l) {
    im <- RBioFormats::read.image(path, series = 1, resolution = l, normalize = FALSE)
    a <- as.array(im)
    if (length(dim(a)) == 2L) array(a, dim = c(dim(a), 1L)) else a
  }
  levels <- lapply(seq_len(n_levels), read_level)
  level_dims <- lapply(levels, function(a) c(dim(a)[2], dim(a)[1]))
  nb <- dim(levels[[1]])[3]
  ch <- tryCatch(RBioFormats::channelNames(meta), error = function(e) NULL)
  bn <- if (length(ch) == nb) ch else paste0("Channel ", seq_len(nb))
  new_annot_image(
    source = path, backend = "ometiff",
    dims = level_dims[[1]], n_levels = n_levels, level_dims = level_dims,
    n_bands = nb, band_names = bn,
    pixel_size = c(1, 1), pixel_unit = "px", dtype = "uint16",
    handle = list(levels = levels), meta = list()
  )
}

.ometiff_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$levels[[level + 1L]]
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(dim(arr)[3]) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.ometiff_detect <- function(path) {
  grepl("\\.(ome\\.tif|ome\\.tiff|qptiff)$", path, ignore.case = TRUE)
}

.ometiff_available <- function() requireNamespace("RBioFormats", quietly = TRUE)
