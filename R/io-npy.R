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
  .npy_validate_output(m, dtype)
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

.npy_layout <- function(path, con) {
  magic <- as.integer(.read_exact_raw(con,6L))
  if (!identical(magic, as.integer(.NPY_MAGIC))) cli::cli_abort("Not a NumPy .npy file.")
  ver <- as.integer(.read_exact_raw(con,2L))
  if (!ver[1] %in% 1:3 || ver[2] != 0L) cli::cli_abort("Unsupported NPY version.")
  hbytes <- if (ver[1] == 1L) 2L else 4L
  hlen <- sum(as.integer(.read_exact_raw(con,hbytes)) * 256^(seq_len(hbytes)-1))
  limit <- getOption("annotatR.max_npy_header_bytes",1024^2)
  if (!is.numeric(limit) || length(limit)!=1L || !is.finite(limit) || limit < 1) cli::cli_abort("Invalid NPY header byte limit.")
  if (hlen < 1 || hlen > limit) cli::cli_abort("NPY header exceeds supported byte limit.")
  if (file.info(path)$size < 8+hbytes+hlen) cli::cli_abort("Short/truncated NPY header.")
  hdr <- rawToChar(.read_exact_raw(con,hlen))
  if (!endsWith(hdr,"\n")) cli::cli_abort("Invalid NPY header: expected newline terminator.")
  txt <- trimws(hdr)
  if (!startsWith(txt,"{") || !endsWith(txt,"}")) cli::cli_abort("Invalid NPY header dictionary.")
  txt <- trimws(substr(txt,2,nchar(txt)-1)); fields <- list()
  # Only supported scalar literals are parsed. No Python evaluation, object
  # descriptors, duplicate keys, or unrecognised dictionary content.
  pat <- "^(['\"])(descr|fortran_order|shape)\\1[[:space:]]*:[[:space:]]*('[^']*'|\"[^\"]*\"|True|False|\\([^)]*\\))[[:space:]]*(,|$)"
  while (nzchar(txt)) {
    hit <- regexec(pat,txt,perl=TRUE); parts <- regmatches(txt,hit)[[1]]
    if (!length(parts) || parts[3] %in% names(fields)) cli::cli_abort("Invalid or duplicate NPY header fields.")
    fields[[parts[3]]] <- parts[4]
    txt <- trimws(substring(txt,nchar(parts[1])+1))
  }
  if (!setequal(names(fields),c("descr","fortran_order","shape"))) cli::cli_abort("Missing required NPY header fields.")
  if (!fields$fortran_order %in% c("True","False")) cli::cli_abort("Invalid NPY fortran_order.")
  if (!grepl("^\\([[:space:]]*[0-9]+[[:space:]]*,[[:space:]]*[0-9]+[[:space:]]*,?[[:space:]]*\\)$",fields$shape)) cli::cli_abort("Only 2-D integer NPY shapes are supported.")
  dims <- as.numeric(strsplit(gsub("[()[:space:]]","",fields$shape),",")[[1]])
  if (!grepl("^(['\"])[<>=|][iu][1248]\\1$",fields$descr,perl=TRUE)) cli::cli_abort("Only supported scalar integer NPY dtypes are allowed.")
  descr <- substr(fields$descr,2,nchar(fields$descr)-1)
  endc <- substr(descr,1,1); size <- as.integer(substr(descr,3,3))
  if (endc == "|" && size != 1L) cli::cli_abort("Invalid NPY byte order for multibyte dtype.")
  layout <- .binary_layout(path,dims,size,8+hbytes+hlen)
  c(layout,list(endian=if(endc==">") "big" else if(endc=="=") .Platform$endian else "little",
    signed=substr(descr,2,2)=="i",fortran=fields$fortran_order=="True",descr=descr,version=ver))
}
.npy_read_matrix <- function(path, call = rlang::caller_env()) {
  con <- file(path,"rb"); on.exit(close(con))
  layout <- .npy_layout(path,con)
  v <- .decode_integer_bytes(.read_exact_raw(con,layout$bytes), layout$size,
    layout$signed,layout$endian,mask=TRUE)
  matrix(v,nrow=layout$dims[1],ncol=layout$dims[2],byrow=!layout$fortran)
}

#' Write a mask to a NumPy `.npy` file
#'
#' Write an `annot_mask` as a lossless integer NumPy array, for interchange with
#' Python tools. A `<path>.legend.json` sidecar (value -> label) is written
#' alongside so the array stays self-describing. Unlike [at_write_mask()], values
#' are stored raw (no bit-depth normalisation), so bitfield artefact masks
#' survive intact. The array and legend are staged as one output bundle; an
#' existing sidecar also requires `overwrite=TRUE`. The explicit caller-selected
#' path is respected. Concurrent writers must be serialized.
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
  dtype <- .check_choice(dtype, c("int32", "uint8", "int16"), default = missing(dtype), call = call)
  .check_flag(transpose, call = call)
  .check_flag(legend, call = call)
  .check_flag(overwrite, call = call)
  m <- .mask_info(mask)$m
  if (isTRUE(transpose)) m <- t(m)
  .npy_validate_output(m, dtype)
  paths <- c(path,if(legend) paste0(path,".legend.json"))
  .export_bundle(paths,function(stage) {
    .npy_write_matrix(m, stage[1], dtype = dtype)
    if (legend) {
      .write_legend_json(mask, stage[2],
                         storage = list(axes = if (transpose) "xy" else "yx", shape = as.integer(dim(m))))
    }
  },overwrite)
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
#' @param level Integer pyramid level to record. `NULL` (default) recovers the
#'   sidecar level, falling back to 0 without metadata. Explicit values override
#'   the sidecar declaration without resampling pixels.
#' @param transpose Logical; transpose the array on read, for files stored in
#'   the native cube order `(width, height)` = `[x, y]` (e.g. TIVITA/HyperGui
#'   masks) so the result lands in annotatR's `[y, x]` convention. Default
#'   `FALSE` assumes the standard image convention `(height, width)`.
#' @param legend Optional legend tibble (`value`, `label`) overriding the sidecar
#'   / pixel-value labelling.
#' @param metadata Optional named list overriding semantic `mask_metadata`
#'   fields, such as `encoding`, `background`, or `source`. Nested grid fields
#'   merge; explicit `level` and `legend` take precedence. No pixels are resampled.
#'   Versioned declarations must be structurally valid before overrides apply.
#' @param call The calling environment, for error reporting.
#'
#' @return An integer `annot_mask` preserving encoding, background, codebook,
#'   grid and source metadata. Without encoding metadata, imports use exclusive
#'   instance values and zero background with status `legacy-default`; signed
#'   representable codes are preserved. A declared storage orientation must
#'   match `transpose`, even for square arrays. Malformed sidecars are rejected.
#' @family masks
#' @seealso [at_write_npy()], [at_read_mask()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "labelled")
#' f <- tempfile(fileext = ".npy")
#' at_write_npy(m, f)
#' at_read_npy(f)
at_read_npy <- function(path, level = NULL, transpose = FALSE, legend = NULL,
                        call = rlang::caller_env(), metadata = NULL) {
  .check_file(path, call = call)
  .check_flag(transpose, call = call)
  m <- .npy_read_matrix(path, call = call)
  sidecar <- .mask_read_sidecar(path)
  if (!is.null(sidecar[["storage"]])) {
    storage <- sidecar[["storage"]]
    .mask_validate_storage(m, storage)
    if (isTRUE(transpose) != identical(storage[['axes']], "xy")) {
      cli::cli_abort("NPY storage orientation requires transpose = {identical(storage[['axes']], 'xy')}.", call = call)
    }
  }
  if (isTRUE(transpose)) m <- t(m)
  .mask_recover(m, sidecar = sidecar, level = level, legend = legend, metadata = metadata)
}

.npy_validate_output <- function(m, dtype) {
  .mask_integers(m, "NPY output samples")
  lower <- switch(dtype,uint8=0,int16=-32768,int32=-.Machine$integer.max)
  upper <- switch(dtype,uint8=255,int16=32767,int32=.Machine$integer.max)
  if (is.null(lower) || any(m < lower | m > upper)) cli::cli_abort("Mask samples exceed the {.val {dtype}} range.")
  invisible(m)
}
