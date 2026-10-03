# Versioned semantic metadata. Runtime image generation/cache IDs are never
# source identity. Grid dimensions always describe logical [y, x] samples.
.mask_empty_legend <- function() {
  tibble::tibble(value = integer(), label = character(), layer = character(),
                roi_id = character(), n_px = integer(), colour = character())
}

.mask_integers <- function(x, what = "Mask values") {
  if (!(is.numeric(x) || is.logical(x)) || anyNA(x) || any(!is.finite(x)) ||
      any(x != trunc(x)) || any(abs(x) > .Machine$integer.max)) {
    cli::cli_abort("{what} must be finite representable integers.")
  }
  as.integer(x)
}

.mask_legend_normalize <- function(lg) {
  if (is.null(lg)) return(NULL)
  # JSON [] is the canonical empty table representation.
  if (is.list(lg) && !length(lg)) return(.mask_empty_legend())
  if (!is.data.frame(lg) && is.list(lg)) lg <- tryCatch(as.data.frame(lg), error = function(e) NULL)
  if (!is.data.frame(lg) || !all(c("value", "label") %in% names(lg))) {
    cli::cli_abort("Malformed mask legend: expected value and label columns.")
  }
  lg <- tibble::as_tibble(lg)
  lg[["value"]] <- .mask_integers(lg[["value"]], "Legend codes")
  if (!is.character(lg[["label"]]) || anyNA(lg[["label"]]) || any(!nzchar(lg[["label"]])) || anyDuplicated(lg[["value"]])) {
    cli::cli_abort("Mask legend needs non-empty labels and unique codes.")
  }
  for (nm in c("layer", "roi_id", "colour")) {
    if (is.null(lg[[nm]])) lg[[nm]] <- rep(if (nm == "colour") "#5E2C8E" else NA_character_, nrow(lg))
    lg[[nm]] <- as.character(lg[[nm]])
  }
  if (!"n_px" %in% names(lg)) lg[["n_px"]] <- integer(nrow(lg))
  lg[["n_px"]] <- .mask_integers(lg[["n_px"]], "Legend counts")
  lg[, names(.mask_empty_legend())]
}

.mask_membership <- function(m, value, encoding) {
  if (encoding == "bitfield") {
    matrix(bitwAnd(as.integer(m), as.integer(value)) != 0L, nrow(m), ncol(m))
  } else m == value
}

.mask_recount <- function(m, lg, encoding) {
  lg[["n_px"]] <- vapply(lg[["value"]], function(v) as.integer(sum(.mask_membership(m, v, encoding))), integer(1))
  lg
}

.mask_source <- function(image, project = NULL) {
  if (is.null(image)) return(NULL)
  .check_provenance_keys(image, "source_descriptor", "image source")
  list(entry_id = project[["meta"]][["entry_id"]] %||% NULL,
       descriptor = image[["source_descriptor"]] %||% NULL)
}

.mask_default_metadata <- function(m, lg, level, type, status = "legacy-default",
                                   encoding = NULL, background = 0L, overlap = "last",
                                   source = NULL, grid = NULL) {
  list(schema_version = 1L, status = status,
       encoding = encoding %||% switch(type, binary = "binary", multiclass = "categorical", "instance"),
       background = as.integer(background), overlap = overlap,
       grid = grid %||% list(dims = as.integer(c(ncol(m), nrow(m))), level = as.integer(level),
                            origin = c(0, 0), stride = c(1, 1)),
       source = source, codebook = lg[, c("value", "label")])
}

.mask_check_metadata_keys <- function(md) {
  if (!is.list(md)) return(invisible(md))
  .check_provenance_keys(md, c("schema_version", "status", "encoding", "background", "overlap", "grid", "codebook", "source"), "mask")
  .check_provenance_keys(md[["grid"]], c("dims", "level", "origin", "stride"), "mask grid")
  src <- md[["source"]]
  .check_provenance_keys(src, c("entry_id", "descriptor", "options_status"), "mask source")
  if (is.list(src)) .check_descriptor_keys(src[["descriptor"]])
  invisible(md)
}

.mask_validate_metadata <- function(m, md, lg, dims = NULL, level = NULL) {
  actual <- attr(m, "dim")
  if (length(actual) != 2L || any(actual < 1L)) cli::cli_abort("Mask must have two positive matrix dimensions.")
  .mask_integers(m)
  required <- c("schema_version", "status", "encoding", "background", "overlap", "grid", "codebook")
  .mask_check_metadata_keys(md)
  if (!is.list(md) || !all(required %in% names(md)) ||
      !is.numeric(md[["schema_version"]]) || length(md[["schema_version"]]) != 1L || is.na(md[["schema_version"]]) || md[["schema_version"]] != 1L) {
    cli::cli_abort("Malformed or unsupported mask metadata schema.")
  }
  if (length(md[["encoding"]]) != 1L || !md[["encoding"]] %in% c("binary", "categorical", "instance", "bitfield") ||
      length(md[["overlap"]]) != 1L || !md[["overlap"]] %in% c("last", "first", "min", "max", "error", "bitor") ||
      length(md[["status"]]) != 1L || !md[["status"]] %in% c("declared", "legacy-default")) {
    cli::cli_abort("Invalid mask encoding, overlap, or metadata status.")
  }
  if (!is.null(md[["source"]])) {
    src <- md[["source"]]
    if (!is.list(src) || (!is.null(src[["entry_id"]]) &&
        (!is.character(src[["entry_id"]]) || length(src[["entry_id"]]) != 1L || is.na(src[["entry_id"]]) || !nzchar(src[["entry_id"]])))) {
      cli::cli_abort("Invalid mask source metadata.")
    }
    if (!is.null(src[["descriptor"]])) {
      tryCatch(.validate_descriptor(src[["descriptor"]]), error = function(e) cli::cli_abort("Invalid mask source descriptor: {conditionMessage(e)}"))
    }
  }
  bg <- .mask_integers(md[["background"]], "Mask background")
  if (length(bg) != 1L) cli::cli_abort("Mask background must be one integer.")
  g <- md[["grid"]]
  if (!is.list(g) || !all(c("dims", "level", "origin", "stride") %in% names(g))) cli::cli_abort("Malformed mask grid.")
  gd <- .mask_integers(g[["dims"]], "Grid dimensions")
  gl <- .mask_integers(g[["level"]], "Grid level")
  if (!identical(gd, as.integer(rev(actual))) ||
      (!is.null(dims) && !identical(.mask_integers(dims, "Mask dimensions"), gd))) {
    cli::cli_abort("Mask metadata dimensions disagree with actual matrix dimensions.")
  }
  if (length(gl) != 1L || gl < 0L || (!is.null(level) && !identical(.mask_integers(level), gl)) ||
      !is.numeric(g[["origin"]]) || length(g[["origin"]]) != 2L || any(!is.finite(g[["origin"]])) ||
      !is.numeric(g[["stride"]]) || length(g[["stride"]]) != 2L || any(!is.finite(g[["stride"]])) || any(g[["stride"]] <= 0)) {
    cli::cli_abort("Invalid or inconsistent mask grid level, origin, or stride.")
  }
  cb <- .mask_legend_normalize(md[["codebook"]])
  if (!identical(cb[, c("value", "label")], lg[, c("value", "label")])) cli::cli_abort("Mask codebook conflicts with legend.")
  if (any(lg[["value"]] == bg)) cli::cli_abort("Foreground codes collide with mask background.")
  if (md[["encoding"]] != "instance" && anyDuplicated(lg[["label"]])) cli::cli_abort("Mask labels must have unique codes.")
  if (md[["encoding"]] %in% c("binary", "bitfield") && bg != 0L) cli::cli_abort("Binary/bitfield background must be zero.")
  if (md[["encoding"]] == "binary" && (any(!m %in% c(0L, 1L)) || any(lg[["value"]] != 1L))) cli::cli_abort("Binary mask values must be zero or one.")
  if (md[["encoding"]] == "bitfield") {
    codes <- lg[["value"]]
    if (any(codes <= 0L) || any(bitwAnd(codes, codes - 1L) != 0L)) cli::cli_abort("Bitfield codes must be positive single-bit powers of two.")
    allowed <- Reduce(bitwOr, codes, init = 0L)
    if (any(m < 0L) || any(bitwAnd(as.integer(m), bitwNot(allowed)) != 0L)) cli::cli_abort("Mask contains bits absent from its codebook.")
  } else if (any(!m %in% c(bg, lg[["value"]]))) cli::cli_abort("Mask contains values absent from its codebook.")
  md[["schema_version"]] <- 1L; md[["background"]] <- bg
  md[["grid"]][["dims"]] <- gd; md[["grid"]][["level"]] <- gl
  md[["grid"]][["origin"]] <- as.numeric(g[["origin"]]); md[["grid"]][["stride"]] <- as.numeric(g[["stride"]])
  md[["codebook"]] <- cb[, c("value", "label")]
  md
}

.mask_info <- function(mask) {
  m <- as.matrix(mask)
  lg <- .mask_legend_normalize(attr(mask, "legend"))
  if (is.null(lg)) cli::cli_abort("Mask has no legend.")
  md <- attr(mask, "mask_metadata") %||%
    .mask_default_metadata(m, lg, attr(mask, "level") %||% 0L, attr(mask, "mask_type") %||% "labelled")
  md <- .mask_validate_metadata(m, md, lg, attr(mask, "dims"), attr(mask, "level"))
  list(m = m, legend = .mask_recount(m, lg, md[["encoding"]]), metadata = md)
}

.mask_read_sidecar <- function(path) {
  side <- paste0(path, ".legend.json")
  if (!file.exists(side)) return(NULL)
  tryCatch({
    payload <- jsonlite::read_json(side, simplifyVector = TRUE)
    # Decode the option subtree without JSON vector/data-frame simplification.
    raw <- jsonlite::read_json(side, simplifyVector = FALSE)
    # Check ambiguity before decoding or assigning any supported fields.
    .check_provenance_keys(raw, c("mask_metadata", "storage", "mask_type", "level", "dims", "legend"), "mask sidecar")
    .mask_check_metadata_keys(raw[["mask_metadata"]])
    descriptor <- raw[["mask_metadata"]][["source"]][["descriptor"]]
    if (!is.null(descriptor)) .validate_descriptor(descriptor)
    if ("options_encoding" %in% names(descriptor)) {
      encoding <- descriptor[["options_encoding"]]
      if (!is.character(encoding) || length(encoding) != 1L || is.na(encoding) ||
          !encoding %in% c("typed-json-v1", "typed-json-v2") || !is.list(descriptor[["options"]])) {
        cli::cli_abort("Unsupported source option encoding.")
      }
      expected_version <- if (encoding == "typed-json-v1") 1L else 2L
      version <- descriptor[["options"]][["schema_version"]]
      if (!is.numeric(version) || length(version) != 1L || is.na(version) || version != expected_version) {
        cli::cli_abort("Unsupported or inconsistent source option encoding.")
      }
      payload[["mask_metadata"]][["source"]][["descriptor"]][["options"]] <- .mask_options_decode(descriptor[["options"]])
      payload[["mask_metadata"]][["source"]][["descriptor"]][["options_encoding"]] <- NULL
      if (expected_version == 1L) {
        # Version 1 did not retain formal-object flags, even on atomic values.
        payload[["mask_metadata"]][["source"]][["options_status"]] <- "legacy-json"
      }
    } else if (!is.null(descriptor)) {
      # Older JSON did not record enough structure to establish option identity.
      payload[["mask_metadata"]][["source"]][["options_status"]] <- "legacy-json"
    }
    payload
  }, error = function(e) {
    cli::cli_abort("Malformed mask legend sidecar: {conditionMessage(e)}")
  })
}

# Metadata overrides replace individual semantic fields; grid overrides merge
# so an explicit level does not discard the declared physical sampling grid.
.mask_recover <- function(m, embedded = NULL, sidecar = NULL, level = NULL,
                          legend = NULL, metadata = NULL) {
  has_embedded <- inherits(embedded, "annot_mask")
  emb_md <- if (has_embedded) attr(embedded, "mask_metadata") else NULL
  payload <- if (!is.null(emb_md)) NULL else sidecar
  emb_lg <- if (has_embedded) attr(embedded, "legend") else NULL
  emb_level <- if (has_embedded) attr(embedded, "level") else NULL
  emb_dims <- if (has_embedded) attr(embedded, "dims") else NULL
  if (!is.null(emb_dims) && !identical(.mask_integers(emb_dims), as.integer(c(ncol(m), nrow(m))))) cli::cli_abort("Embedded mask dimensions disagree with actual matrix dimensions.")
  md <- emb_md %||% payload[["mask_metadata"]]
  lg <- .mask_legend_normalize(legend %||% emb_lg %||% payload[["legend"]])
  type <- attr(embedded, "mask_type") %||% payload[["mask_type"]] %||% "labelled"
  lv <- level %||% emb_level %||% payload[["level"]] %||% md[["grid"]][["level"]] %||% 0L
  if (is.null(lg)) {
    bg <- metadata[["background"]] %||% md[["background"]] %||% 0L
    vals <- sort(unique(.mask_integers(m[m != bg])))
    lg <- .mask_legend_normalize(data.frame(value = vals, label = as.character(vals)))
  }
  if (is.null(md)) {
    md <- .mask_default_metadata(m, lg, lv, type)
    if (!is.null(payload[["dims"]]) && !identical(.mask_integers(payload[["dims"]]), as.integer(c(ncol(m), nrow(m))))) cli::cli_abort("Legacy mask dimensions disagree with matrix dimensions.")
  } else {
    # Validate persisted declarations before applying deliberate overrides.
    original_lg <- .mask_legend_normalize(if (!is.null(emb_md)) emb_lg else payload[["legend"]])
    if (is.null(original_lg)) cli::cli_abort("Versioned mask metadata requires a legend.")
    .mask_validate_metadata(m, md, original_lg,
      if (!is.null(emb_md)) emb_dims else payload[["dims"]],
      if (!is.null(emb_md)) emb_level else payload[["level"]])
  }
  md[["grid"]][["level"]] <- .check_count(lv)
  md[["codebook"]] <- lg[, c("value", "label")]
  if (!is.null(metadata)) {
    if (!is.list(metadata) || is.null(names(metadata)) || any(!names(metadata) %in% names(md))) cli::cli_abort("Invalid explicit mask metadata override.")
    .mask_check_metadata_keys(metadata)
    md <- utils::modifyList(md, metadata)
    md[["status"]] <- "declared"
  }
  if (!is.null(level)) md[["grid"]][["level"]] <- .check_count(level)
  if (!is.null(legend)) md[["codebook"]] <- lg[, c("value", "label")]
  .new_annot_mask(m, lg, md[["grid"]][["level"]], c(ncol(m), nrow(m)), type, metadata = md)
}

.mask_alignment <- function(a, b, alignment) {
  if (!identical(dim(a[["m"]]), dim(b[["m"]]))) cli::cli_abort("Masks must have the same dimensions.")
  if (alignment == "assert") return("asserted")
  if (!isTRUE(all.equal(a[["metadata"]][["grid"]], b[["metadata"]][["grid"]], check.attributes = FALSE, tolerance = 0))) cli::cli_abort("Mask grids/levels differ; an explicit alignment assertion is required.")
  sa <- a[["metadata"]][["source"]][["descriptor"]]; sb <- b[["metadata"]][["source"]][["descriptor"]]
  if (!is.null(sa) && !is.null(sb)) {
    # Entry provenance and runtime tokens are deliberately excluded.
    if (isTRUE(sa[["options_inferred"]]) || isTRUE(sb[["options_inferred"]])) {
      cli::cli_abort("Inferred source options are unverified; an explicit alignment assertion is required.")
    }
    if (identical(a[["metadata"]][["source"]][["options_status"]], "legacy-json") ||
        identical(b[["metadata"]][["source"]][["options_status"]], "legacy-json")) {
      cli::cli_abort("Legacy source option structure is unverified; an explicit alignment assertion is required.")
    }
    affected <- c("tiff","ometiff")
    if ((sa[["backend"]] %in% affected && is.null(sa[["reader_contract"]])) ||
        (sb[["backend"]] %in% affected && is.null(sb[["reader_contract"]]))) {
      cli::cli_abort("Legacy TIFF/OME reader contract is unverified; an explicit alignment assertion is required.")
    }
    if (.composite_unverified(sa) || .composite_unverified(sb)) {
      cli::cli_abort("Legacy composite source provenance is unverified; an explicit alignment assertion is required.")
    }
    fields <- c("path", "backend", "signature")
    if (is.null(sa[["path"]]) || is.null(sb[["path"]]) ||
        !identical(sa[["options"]], sb[["options"]]) ||
        !identical(sa[["reader_contract"]], sb[["reader_contract"]]) ||
        !isTRUE(all.equal(sa[["files"]],sb[["files"]],check.attributes=TRUE,tolerance=0)) ||
        !isTRUE(all.equal(sa[fields], sb[fields], check.attributes = TRUE, tolerance = 0))) {
      cli::cli_abort("Mask source descriptors conflict; an explicit alignment assertion is required.")
    }
    return("verified")
  }
  if (a[["metadata"]][["status"]] == "legacy-default" && b[["metadata"]][["status"]] == "legacy-default") return("legacy-assumed")
  cli::cli_abort("Mask source provenance is insufficient; use alignment = 'assert' to assert alignment.")
}

# Composite display uses a stable joined label and mean class colour.
.mask_display <- function(mask) {
  info <- .mask_info(mask); m <- info[["m"]]; lg <- info[["legend"]]; md <- info[["metadata"]]
  vals <- sort(unique(as.integer(m[m != md[["background"]]])))
  labs <- colours <- character(length(vals))
  for (i in seq_along(vals)) {
    members <- vapply(lg[["value"]], function(v) .mask_membership(matrix(vals[i]), v, md[["encoding"]])[1], logical(1))
    labs[i] <- paste(lg[["label"]][members], collapse = " + ")
    rgb <- grDevices::col2rgb(lg[["colour"]][members])
    colours[i] <- grDevices::rgb(mean(rgb[1, ]), mean(rgb[2, ]), mean(rgb[3, ]), maxColorValue = 255)
  }
  list(value = vals, label = labs, colour = colours, background = md[["background"]])
}

.mask_validate_storage <- function(m, storage) {
  .check_provenance_keys(storage, c("shape", "axes"), "mask storage")
  if (!is.list(storage) || !identical(.mask_integers(storage[["shape"]], "Storage shape"), as.integer(dim(m))) ||
      length(storage[["axes"]]) != 1L || !storage[["axes"]] %in% c("xy", "yx")) {
    cli::cli_abort("Invalid NPY storage shape/orientation metadata.")
  }
  invisible(storage)
}
