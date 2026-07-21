# NumPy `.npy` integer-mask I/O. Ground-truth HSI masks (anatomy / state /
# uncertain / artefact) are numpy integer arrays, so a lossless bridge is needed
# to compare annotatR masks against them and to hand masks back to Python tools.
#
# The bridge is pure base R (no numpy/reticulate/RcppCNPy dependency), mirroring
# the ENVI reader's `readBin`/`writeBin` approach. Only integer dtypes are
# supported -- label masks are never floating point.
#
# ORIENTATION. numpy is C-order (row-major) by default; R matrices are
# column-major. `.npy_read_matrix()` honours whichever order a foreign file
# declares, returning an R matrix `m` with `m[i, j] == numpy_array[i-1, j-1]` and
# `dim(m)` equal to the numpy shape.
#
# annotatR masks are `[y, x]` (rows = height, cols = width). A numpy array in the
# standard image convention is `(height, width)` = `[y, x]`, so `at_read_npy()`
# and `at_write_npy()` round-trip losslessly with no transpose. But some tools --
# notably TIVITA/HyperGui HSI masks -- store the native cube order `(width,
# height)` = `[x, y]`, the transpose. For those, pass `transpose = TRUE` so reads
# land in annotatR's `[y, x]` convention (and writes produce `(width, height)`
# files the external tool expects). Without it, comparing against such a mask
# aborts on the dimension guard (non-square) or silently transposes (square).

.NPY_MAGIC <- c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59)

# Map an annotatR dtype name to a numpy descr and a byte size.
.npy_descr <- function(dtype) {
  switch(
    dtype,
    int32 = list(descr = "<i4", size = 4L),
    uint8 = list(descr = "|u1", size = 1L),
    int16 = list(descr = "<i2", size = 2L),
    cli::cli_abort("Unsupported {.arg dtype} {.val {dtype}}.")
  )
}

.npy_write_matrix <- function(m, path, dtype = "int32") {
  storage.mode(m) <- "integer"
  d <- .npy_descr(dtype)
  # fortran_order = TRUE stores the column-major R matrix verbatim.
  dict <- sprintf("{'descr': '%s', 'fortran_order': True, 'shape': (%d, %d), }",
                  d$descr, nrow(m), ncol(m))
  preamble <- length(.NPY_MAGIC) + 2L + 2L # magic + version + uint16 header len
  pad <- (64L - ((preamble + nchar(dict) + 1L) %% 64L)) %% 64L
  dict <- paste0(dict, strrep(" ", pad), "\n")
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.raw(c(.NPY_MAGIC, 1, 0)), con)
  writeBin(as.integer(nchar(dict)), con, size = 2L, endian = "little")
  writeBin(charToRaw(dict), con)
  writeBin(as.integer(m), con, size = d$size, endian = "little")
  invisible(path)
}

.npy_read_matrix <- function(path, call = rlang::caller_env()) {
  con <- file(path, "rb")
  on.exit(close(con))
  magic <- as.integer(readBin(con, "raw", n = 6L))
  if (!identical(magic, as.integer(.NPY_MAGIC))) {
    cli::cli_abort("{.path {path}} is not a NumPy {.file .npy} file.", call = call)
  }
  ver <- as.integer(readBin(con, "raw", n = 2L))
  hlen <- if (ver[1] >= 2L) {
    readBin(con, "integer", n = 1L, size = 4L, endian = "little")
  } else {
    readBin(con, "integer", n = 1L, size = 2L, signed = FALSE, endian = "little")
  }
  hdr <- rawToChar(readBin(con, "raw", n = hlen))
  descr <- sub(".*'descr'\\s*:\\s*'([^']*)'.*", "\\1", hdr)
  fortran <- grepl("'fortran_order'\\s*:\\s*True", hdr)
  shp <- sub(".*'shape'\\s*:\\s*\\(([^)]*)\\).*", "\\1", hdr)
  dims <- as.integer(stats::na.omit(as.integer(trimws(strsplit(shp, ",")[[1]]))))
  if (length(dims) != 2L) {
    cli::cli_abort(c(
      "Only 2-D integer {.file .npy} masks are supported.",
      "x" = "{.path {path}} has shape {.val {shp}}."
    ), call = call)
  }
  endc <- substr(descr, 1L, 1L)
  kind <- substr(descr, 2L, 2L)
  sz <- as.integer(substr(descr, 3L, nchar(descr)))
  if (!kind %in% c("i", "u")) {
    cli::cli_abort(c(
      "Only integer {.file .npy} masks are supported.",
      "x" = "{.path {path}} has dtype {.val {descr}}."
    ), call = call)
  }
  endian <- if (endc == ">") "big" else "little"
  total <- as.double(dims[1]) * dims[2]
  if (sz == 8L) {
    # No native 64-bit integer in R: read 32-bit words and keep the low word
    # (label masks fit comfortably in 32 bits).
    words <- readBin(con, "integer", n = 2L * total, size = 4L, endian = endian)
    v <- if (endian == "little") words[c(TRUE, FALSE)] else words[c(FALSE, TRUE)]
  } else {
    signed <- if (sz <= 2L) kind == "i" else TRUE
    v <- readBin(con, "integer", n = total, size = sz, signed = signed, endian = endian)
  }
  m <- if (fortran) {
    matrix(v, nrow = dims[1], ncol = dims[2])
  } else {
    matrix(v, nrow = dims[1], ncol = dims[2], byrow = TRUE)
  }
  storage.mode(m) <- "integer"
  m
}

#' Write a mask to a NumPy `.npy` file
#'
#' Write an `annot_mask` as a lossless integer NumPy array, for interchange with
#' Python tools. A `<path>.legend.json` sidecar (value -> label) is written
#' alongside so the array stays self-describing. Unlike [at_write_mask()], values
#' are stored raw (no bit-depth normalisation), so bitfield artefact masks
#' survive intact.
#'
#' @param mask An `annot_mask`.
#' @param path Output file path.
#' @param dtype NumPy integer dtype: `"int32"` (default, wide enough for bitfield
#'   codes), `"uint8"`, or `"int16"`.
#' @param transpose Logical; write the transpose, i.e. numpy shape
#'   `(width, height)` = `[x, y]`, matching tools that store the native cube
#'   order (e.g. TIVITA/HyperGui). Default `FALSE` writes the standard image
#'   convention `(height, width)`.
#' @param legend Logical; also write a `<path>.legend.json` sidecar. Default
#'   `TRUE`.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return The output path, invisibly.
#' @family masks
#' @seealso [at_read_npy()], [at_write_mask()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "labelled")
#' f <- tempfile(fileext = ".npy")
#' at_write_npy(m, f)
at_write_npy <- function(mask, path, dtype = c("int32", "uint8", "int16"),
                         transpose = FALSE, legend = TRUE, overwrite = FALSE,
                         call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  .check_string(path, call = call)
  dtype <- .check_choice(dtype, c("int32", "uint8", "int16"), call = call)
  .check_flag(transpose, call = call)
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
  if (isTRUE(transpose)) m <- t(m)
  storage.mode(m) <- "integer"
  maxv <- max(m, 0L)
  cap <- switch(dtype, uint8 = 255L, int16 = 32767L, int32 = .Machine$integer.max)
  if (maxv > cap) {
    cli::cli_abort(
      c("Mask values up to {maxv} exceed the {.val {dtype}} range.",
        "i" = "Use {.code dtype = \"int32\"}."),
      call = call
    )
  }
  .npy_write_matrix(m, path, dtype = dtype)
  if (legend) {
    .write_legend_json(mask, paste0(path, ".legend.json"))
  }
  invisible(path)
}

#' Read a NumPy `.npy` integer mask
#'
#' Read a NumPy integer array (e.g. a ground-truth annotation mask) into a
#' lossless `annot_mask` -- values are preserved exactly, including composite
#' bitfield codes. Use this (not [at_read_mask()], which polygonises) when the
#' raw integer matrix is what you need, for example to derive a training mask or
#' compute agreement against another mask.
#'
#' @param path Path to a `.npy` file.
#' @param level Integer pyramid level to record. Default `0`.
#' @param transpose Logical; transpose the array on read, for files stored in
#'   the native cube order `(width, height)` = `[x, y]` (e.g. TIVITA/HyperGui
#'   masks) so the result lands in annotatR's `[y, x]` convention. Default
#'   `FALSE` assumes the standard image convention `(height, width)`.
#' @param legend Optional legend tibble (`value`, `label`) overriding the sidecar
#'   / pixel-value labelling.
#' @param call The calling environment, for error reporting.
#'
#' @return An `annot_mask`.
#' @family masks
#' @seealso [at_write_npy()], [at_read_mask()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "labelled")
#' f <- tempfile(fileext = ".npy")
#' at_write_npy(m, f)
#' at_read_npy(f)
at_read_npy <- function(path, level = 0L, transpose = FALSE, legend = NULL,
                        call = rlang::caller_env()) {
  .check_file(path, call = call)
  level <- .check_count(level, call = call)
  .check_flag(transpose, call = call)
  m <- .npy_read_matrix(path, call = call)
  if (isTRUE(transpose)) m <- t(m)
  side <- paste0(path, ".legend.json")
  meta <- if (file.exists(side)) {
    tryCatch(jsonlite::read_json(side, simplifyVector = TRUE), error = function(e) NULL)
  } else {
    NULL
  }
  lg <- legend
  if (is.null(lg) && !is.null(meta)) {
    lg <- tryCatch(tibble::as_tibble(meta$legend), error = function(e) NULL)
  }
  if (is.null(lg)) {
    vals <- sort(unique(as.integer(m[m != 0L])))
    lg <- tibble::tibble(
      value = vals, label = as.character(vals), layer = NA_character_,
      roi_id = NA_character_,
      n_px = vapply(vals, function(v) as.integer(sum(m == v)), integer(1)),
      colour = rep("#5E2C8E", length(vals))
    )
  }
  mask_type <- if (!is.null(meta)) meta$mask_type %||% "labelled" else "labelled"
  .new_annot_mask(m, lg, level, c(ncol(m), nrow(m)), mask_type, source = NA_character_)
}
