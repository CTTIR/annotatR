# Exact binary grayscale transport. PGM P5 stores rows in image order, with
# unsigned 16-bit samples most-significant byte first and no colour mapping.
.mask_pgm_encode <- function(m, bits) {
  values <- as.vector(t(m))
  samples <- if (bits == 8L) as.raw(values) else as.raw(rbind(values %/% 256, values %% 256))
  c(charToRaw(sprintf("P5\n%d %d\n%d\n", ncol(m), nrow(m), 2^bits - 1)), samples)
}

.mask_pgm_decode <- function(bytes, bits) {
  pos <- 1L; n <- length(bytes)
  whitespace <- c(9L, 10L, 11L, 12L, 13L, 32L)
  token <- function() {
    repeat {
      while (pos <= n && as.integer(bytes[pos]) %in% whitespace) pos <<- pos + 1L
      if (pos > n || bytes[pos] != as.raw(35L)) break
      while (pos <= n && bytes[pos] != as.raw(10L)) pos <<- pos + 1L
    }
    start <- pos
    while (pos <= n && !as.integer(bytes[pos]) %in% c(whitespace, 35L)) pos <<- pos + 1L
    if (start == pos) cli::cli_abort("Invalid/short binary grayscale header.")
    rawToChar(bytes[seq.int(start, pos - 1L)])
  }
  if (token() != "P5") cli::cli_abort("Exact grayscale decoder requires binary PGM P5 capability.")
  fields <- vapply(seq_len(3L), function(i) token(), character(1))
  if (any(!grepl("^[0-9]+$", fields))) cli::cli_abort("Invalid binary grayscale dimensions/depth.")
  fields <- as.double(fields)
  width <- fields[1]; height <- fields[2]; maximum <- fields[3]
  count <- width * height
  if (any(!is.finite(fields)) || min(width, height) < 1 || count > .Machine$integer.max || maximum != 2^bits - 1) {
    cli::cli_abort("Unsupported binary grayscale dimensions/depth.")
  }
  .read_budget(count * 8)
  # Maxval has exactly one terminating whitespace byte. Never skip binary
  # whitespace: a first sample of 9, 10, 13 or 32 is a class code.
  if (pos > n || !as.integer(bytes[pos]) %in% whitespace || n - pos != count * (bits / 8)) {
    cli::cli_abort("Short or inconsistent binary grayscale payload.")
  }
  values <- .decode_integer_bytes(bytes[seq.int(pos + 1L, n)], bits / 8L, FALSE, "big", mask = TRUE)
  matrix(values, nrow = as.integer(height), ncol = as.integer(width), byrow = TRUE)
}

.mask_magick_probe <- function(bits) {
  values <- if (bits == 16L) c(0L, 1L, 255L, 256L, 4096L, 32767L, 32768L, 65535L) else c(0L, 1L, 9L, 10L, 13L, 32L, 128L, 255L)
  m <- matrix(values, nrow = 2L, byrow = TRUE)
  tryCatch({
    img <- magick::image_read(.mask_pgm_encode(m, bits))
    identical(.mask_pgm_decode(magick::image_write(img, format = "pgm", depth = bits), bits), m)
  }, error = function(e) FALSE)
}

.mask_magick_require <- function(bits, call) {
  if (!requireNamespace("magick", quietly = TRUE)) cli::cli_abort("Exact grayscale PNG/raster conversion requires package magick.", call = call)
  if (!.mask_magick_probe(bits)) {
    cli::cli_abort("ImageMagick lacks exact {bits}-bit grayscale capability; use a build with sufficient quantum depth and PGM support.", call = call)
  }
}

.mask_png_header <- function(path, call) {
  con <- file(path, "rb")
  on.exit(close(con))
  head <- readBin(con, "raw", n = 33L)
  signature <- as.raw(c(137L, 80L, 78L, 71L, 13L, 10L, 26L, 10L))
  if (length(head) != 33L || !identical(head[1:8], signature) ||
      !identical(head[9:12], as.raw(c(0, 0, 0, 13))) || rawToChar(head[13:16]) != "IHDR") {
    cli::cli_abort("Invalid or truncated PNG header.", call = call)
  }
  bits <- as.integer(head[25]); colour <- as.integer(head[26])
  if (!bits %in% c(8L, 16L) || colour != 0L) {
    cli::cli_abort("PNG masks require unsigned 8/16-bit grayscale samples without colour, palette or alpha channels.", call = call)
  }
  dims <- .decode_integer_bytes(head[17:24], 4L, FALSE, "big")
  if (any(dims < 1 | dims > .Machine$integer.max) || prod(dims) > .Machine$integer.max) {
    cli::cli_abort("Unsupported PNG mask dimensions.", call = call)
  }
  .read_budget(prod(dims) * 8)
  # Grayscale colour type 0 can still declare transparency in a tRNS chunk.
  # Inspect chunk headers without allocating compressed image/ancillary data;
  # searching raw file bytes would confuse chunk names with payload contents.
  offset <- 33
  file_size <- file.info(path)$size
  repeat {
    chunk <- readBin(con, "raw", n = 8L)
    if (length(chunk) != 8L) cli::cli_abort("Truncated PNG chunk header or missing IEND.", call = call)
    size <- .decode_integer_bytes(chunk[1:4], 4L, FALSE, "big")
    if (size > .Machine$integer.max || offset + size + 12 > file_size) {
      cli::cli_abort("Invalid or truncated PNG chunk payload.", call = call)
    }
    if (identical(chunk[5:8], charToRaw("tRNS"))) {
      cli::cli_abort("PNG masks cannot contain transparency (tRNS) or alpha channels.", call = call)
    }
    if (identical(chunk[5:8], charToRaw("IEND"))) {
      if (size != 0) cli::cli_abort("Invalid PNG IEND chunk.", call = call)
      break
    }
    offset <- offset + size + 12
    seek(con, where = offset, origin = "start")
  }
  list(width = as.integer(dims[1]), height = as.integer(dims[2]), bits = bits)
}
