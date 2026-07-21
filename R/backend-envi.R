# ENVI backend: a .hdr text header plus a binary data file. Pure base R (no
# optional dependencies), so it doubles as the reference implementation for
# spectral cube handling and the substrate for spectral example data.

# Map an ENVI "data type" code to readBin parameters.
.envi_dtype <- function(code) {
  switch(
    as.character(code),
    "1"  = list(what = "integer", size = 1L, signed = FALSE, dtype = "uint8"),
    "2"  = list(what = "integer", size = 2L, signed = TRUE,  dtype = "int16"),
    "3"  = list(what = "integer", size = 4L, signed = TRUE,  dtype = "int32"),
    "4"  = list(what = "double",  size = 4L, signed = TRUE,  dtype = "float32"),
    "5"  = list(what = "double",  size = 8L, signed = TRUE,  dtype = "float64"),
    "12" = list(what = "integer", size = 2L, signed = FALSE, dtype = "uint16"),
    cli::cli_abort("Unsupported ENVI data type code {.val {code}}.")
  )
}

# Locate the .hdr and binary data file given either.
.envi_paths <- function(path) {
  if (grepl("\\.hdr$", path, ignore.case = TRUE)) {
    hdr <- path
    base <- sub("\\.hdr$", "", path, ignore.case = TRUE)
    cand <- c(base, paste0(base, c(".dat", ".img", ".raw", ".bin", ".bsq", ".bil", ".bip")))
    dat <- cand[file.exists(cand)]
    dat <- if (length(dat)) dat[1] else NA_character_
  } else {
    dat <- path
    hdr <- paste0(path, ".hdr")
    if (!file.exists(hdr)) {
      hdr <- sub("\\.[^.]+$", ".hdr", path)
    }
  }
  list(hdr = hdr, dat = dat)
}

# Extract a single ENVI header field (scalar or brace list) as a trimmed string.
.envi_field <- function(txt, key) {
  key_pat <- gsub(" ", "[ \\t]+", key)
  brace <- paste0("(?im)^[ \\t]*", key_pat, "[ \\t]*=[ \\t]*\\{([^}]*)\\}")
  m <- regexpr(brace, txt, perl = TRUE)
  if (m != -1L) {
    val <- regmatches(txt, m)
    return(trimws(sub(brace, "\\1", val, perl = TRUE)))
  }
  scal <- paste0("(?im)^[ \\t]*", key_pat, "[ \\t]*=[ \\t]*(.*)$")
  m <- regexpr(scal, txt, perl = TRUE)
  if (m == -1L) {
    return(NULL)
  }
  val <- regmatches(txt, m)
  trimws(sub(scal, "\\1", val, perl = TRUE))
}

# Parse the ENVI header into a list.
.parse_envi_hdr <- function(hdr) {
  txt <- paste(readLines(hdr, warn = FALSE), collapse = "\n")
  num <- function(key) {
    v <- .envi_field(txt, key)
    if (is.null(v)) NULL else as.numeric(v)
  }
  split_list <- function(key) {
    v <- .envi_field(txt, key)
    if (is.null(v)) {
      return(NULL)
    }
    trimws(strsplit(v, ",")[[1]])
  }
  samples <- num("samples")
  lines <- num("lines")
  bands <- num("bands")
  if (is.null(samples) || is.null(lines) || is.null(bands)) {
    cli::cli_abort("ENVI header {.path {hdr}} is missing samples/lines/bands.")
  }
  interleave <- tolower(.envi_field(txt, "interleave") %||% "bsq")
  byte_order <- num("byte order") %||% 0
  data_type <- num("data type") %||% 4
  wl <- split_list("wavelength")
  wl <- if (is.null(wl)) NULL else as.numeric(wl)
  wl_units <- .envi_field(txt, "wavelength units")
  bn <- split_list("band names")
  list(
    samples = as.integer(samples), lines = as.integer(lines),
    bands = as.integer(bands), interleave = interleave,
    endian = if (byte_order >= 1) "big" else "little",
    data_type = data_type, wavelengths = wl,
    wavelength_units = wl_units, band_names = bn
  )
}

# Read the binary payload and reshape to a [y, x, band] array.
.read_envi_data <- function(dat, h) {
  spec <- .envi_dtype(h$data_type)
  n <- h$samples * h$lines * h$bands
  con <- file(dat, "rb")
  on.exit(close(con))
  vec <- readBin(con, what = spec$what, n = n, size = spec$size,
                 signed = spec$signed, endian = h$endian)
  if (spec$what == "integer" && !spec$signed && spec$size == 2L) {
    vec[vec < 0] <- vec[vec < 0] + 65536L
  }
  arr <- switch(
    h$interleave,
    "bsq" = aperm(array(vec, dim = c(h$samples, h$lines, h$bands)), c(2, 1, 3)),
    "bip" = aperm(array(vec, dim = c(h$bands, h$samples, h$lines)), c(3, 2, 1)),
    "bil" = aperm(array(vec, dim = c(h$samples, h$bands, h$lines)), c(3, 1, 2)),
    cli::cli_abort("Unsupported ENVI interleave {.val {h$interleave}}.")
  )
  storage.mode(arr) <- "double"
  arr
}

.envi_read <- function(path, ...) {
  p <- .envi_paths(path)
  if (is.na(p$dat) || !file.exists(p$dat)) {
    cli::cli_abort(c(
      "Could not find the ENVI binary data file for {.path {path}}.",
      "i" = "Expected a data file alongside the {.file .hdr} header."
    ))
  }
  h <- .parse_envi_hdr(p$hdr)
  arr <- .read_envi_data(p$dat, h)
  spec <- .envi_dtype(h$data_type)
  bn <- h$band_names
  if (is.null(bn) || length(bn) != h$bands) {
    bn <- NA_character_
  }
  new_annot_image(
    source = path, backend = "envi",
    dims = c(h$samples, h$lines), n_levels = 1L,
    level_dims = list(c(h$samples, h$lines)),
    n_bands = h$bands, band_names = bn,
    wavelengths = h$wavelengths,
    wavelength_unit = if (is.null(h$wavelengths)) NULL else (h$wavelength_units %||% "nm"),
    pixel_size = c(1, 1), pixel_unit = "px", dtype = spec$dtype,
    handle = list(data = arr), meta = list(interleave = h$interleave)
  )
}

.envi_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$data
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.envi_detect <- function(path) {
  if (grepl("\\.hdr$", path, ignore.case = TRUE)) {
    return(TRUE)
  }
  # A data file with a sibling .hdr.
  hdr <- .envi_paths(path)$hdr
  file.exists(hdr) && grepl("\\.(dat|img|raw|bin|bsq|bil|bip)$", path, ignore.case = TRUE)
}

.envi_available <- function() TRUE
