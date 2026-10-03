# Validated eager layouts are also reusable by bounded/windowed readers.
.read_budget <- function(bytes) {
  limit <- getOption('annotatR.max_read_bytes', 1024^3)
  if (!is.numeric(limit) || length(limit) != 1L || !is.finite(limit) || limit <= 0) {
    cli::cli_abort('Option annotatR.max_read_bytes must be a positive finite byte limit.')
  }
  if (!is.finite(bytes) || bytes > limit) {
    cli::cli_abort('Requested read exceeds the byte budget/limit ({limit}); raise options(annotatR.max_read_bytes = ...) for a trusted large file.')
  }
}
.binary_layout <- function(path, dims, size, offset = 0, eager = TRUE) {
  if (!is.numeric(dims) || !length(dims) || any(!is.finite(dims)) ||
      any(dims < 1 | dims != trunc(dims) | dims > .Machine$integer.max)) {
    cli::cli_abort('Image/mask dimensions must be positive representable integers; zero-sized arrays are unsupported.')
  }
  if (length(offset) != 1L || !is.finite(offset) || offset < 0 || offset != trunc(offset) || offset > 2^53-1) {
    cli::cli_abort('Invalid binary header offset; expected a nonnegative exact integer.')
  }
  count <- prod(as.double(dims)); bytes <- count * size
  if (!is.finite(bytes) || count > 2^53-1 || bytes > 2^53-1-offset) {
    cli::cli_abort('Binary dimensions/payload size exceed supported resource limits.')
  }
  if (eager) {
    if (count > .Machine$integer.max) cli::cli_abort("Eager array exceeds integer indexing limits.")
    .read_budget(max(bytes, count * 8))
  }
  actual <- file.info(path)$size
  if (length(actual) != 1L || !is.finite(actual) || actual < offset + bytes) {
    cli::cli_abort('Short/truncated binary payload: expected at least {offset + bytes} bytes.')
  }
  list(dims=as.integer(dims), count=count, size=size, offset=offset, bytes=bytes)
}
.read_exact_raw <- function(con, n) {
  x <- readBin(con, 'raw', n=n)
  if (length(x) != n) cli::cli_abort('Short/truncated binary payload or header.')
  x
}
# Decode bytes through exact unsigned 32-bit double words. R readBin(integer,
# size=4) reserves INT_MIN for NA, which is a valid quantitative image value.
.decode_integer_bytes <- function(bytes, size, signed, endian, mask = FALSE) {
  if (!size %in% c(1L,2L,4L,8L) || length(bytes) %% size != 0) cli::cli_abort('Unsupported integer encoding or short payload.')
  b <- matrix(as.integer(bytes),nrow=size)
  if (endian == 'big') b <- b[rev(seq_len(size)),,drop=FALSE]
  word <- function(x) as.vector(crossprod(256^(seq_len(nrow(x))-1),x))
  low <- word(b[seq_len(min(size,4L)),,drop=FALSE])
  if (size == 8L) {
    high <- word(b[5:8,,drop=FALSE])
    negative <- signed & high == 4294967295 & low > 2147483648
    positive <- high == 0 & low <= .Machine$integer.max
    if (any(!(negative | positive))) cli::cli_abort('Integer samples are outside the finite representable mask range.')
    low[negative] <- low[negative] - 4294967296
  } else if (signed) {
    negative <- low >= 2^(8*size-1)
    low[negative] <- low[negative] - 2^(8*size)
  }
  if (mask) {
    if (any(abs(low) > .Machine$integer.max)) cli::cli_abort('Integer samples are outside the finite representable mask range.')
    low <- as.integer(low)
  }
  low
}
