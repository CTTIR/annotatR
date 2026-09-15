# Shared foundations for the partner interop contract: classified conditions,
# canonical JSON and SHA-256 digests, safe relative paths, atomic writes and
# random identifiers. None of these are exported.

# ---- Classified conditions -------------------------------------------------

# Abort with a stable condition class and machine-readable code. Classes are
# `at_<class>_error` plus the parent `at_error`, so callers (and the control
# service) can map a failure without parsing its message. `details` must never
# carry tokens or unbounded file contents.
.at_abort <- function(message, class = "validation", code = "VALIDATION_FAILED",
                      details = list(), call = rlang::caller_env(),
                      .envir = parent.frame()) {
  cli::cli_abort(
    message,
    class = c(paste0("at_", class, "_error"), "at_error"),
    code = code,
    details = details,
    call = call,
    .envir = .envir
  )
}

# The code of a classified annotatR condition, or a generic fallback.
.condition_code <- function(cnd) {
  cnd$code %||% if (inherits(cnd, "at_error")) "VALIDATION_FAILED" else "INTERNAL_ERROR"
}

# ---- JSON ------------------------------------------------------------------

# An empty JSON object (jsonlite writes an empty named list as `{}`).
.json_object <- function() stats::setNames(list(), character(0))

# Serialise a value to canonical JSON: object keys sorted by their UTF-8 bytes,
# no insignificant whitespace, whole numbers without a fraction, no trailing
# newline. The mapping from R matches jsonlite with `auto_unbox = TRUE`: a named
# list is an object, an unnamed list an array, a length-1 atomic a scalar, any
# other atomic an array, and `NULL`/`NA` are `null`. This is the byte string the
# handoff and control digests are computed over.
.canonical_json <- function(x) {
  if (is.null(x)) {
    return("null")
  }
  if (is.list(x)) {
    nms <- names(x)
    if (!is.null(nms)) {
      if (length(x) == 0L) {
        return("{}")
      }
      if (anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms)) {
        .at_abort("Cannot serialise an object with missing or duplicated keys.",
                  code = "INVALID_JSON")
      }
      ord <- order(.utf8_sort_key(nms), method = "radix")
      parts <- vapply(ord, function(i) {
        paste0(.json_string(nms[[i]]), ":", .canonical_json(x[[i]]))
      }, character(1))
      return(paste0("{", paste(parts, collapse = ","), "}"))
    }
    parts <- vapply(x, .canonical_json, character(1))
    return(paste0("[", paste(parts, collapse = ","), "]"))
  }
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (!is.atomic(x)) {
    .at_abort("Cannot serialise an object of class {.cls {class(x)[1]}} to JSON.",
              code = "INVALID_JSON")
  }
  vals <- vapply(seq_along(x), function(i) .json_scalar(x[i]), character(1))
  if (length(x) == 1L && !inherits(x, "AsIs")) {
    return(vals)
  }
  paste0("[", paste(vals, collapse = ","), "]")
}

# Sort key that orders strings by UTF-8 byte values independent of locale.
.utf8_sort_key <- function(x) {
  vapply(x, function(s) {
    paste(sprintf("%02x", as.integer(charToRaw(enc2utf8(s)))), collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

.json_scalar <- function(v) {
  if (is.na(v)) {
    return("null")
  }
  if (is.logical(v)) {
    return(if (v) "true" else "false")
  }
  if (is.character(v)) {
    return(.json_string(v))
  }
  if (is.numeric(v)) {
    if (!is.finite(v)) {
      .at_abort("Non-finite numbers cannot be written as JSON.", code = "INVALID_JSON")
    }
    if (v == round(v) && abs(v) < 2^53) {
      return(formatC(v, format = "f", digits = 0, big.mark = ""))
    }
    for (d in 15:17) {
      s <- sprintf(paste0("%.", d, "g"), v)
      if (as.numeric(s) == v) {
        return(s)
      }
    }
    return(sprintf("%.17g", v))
  }
  .at_abort("Cannot serialise a {.cls {class(v)[1]}} scalar to JSON.", code = "INVALID_JSON")
}

.json_string <- function(s) {
  s <- enc2utf8(as.character(s))
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub("\"", "\\\"", s, fixed = TRUE)
  s <- gsub("\n", "\\n", s, fixed = TRUE)
  s <- gsub("\r", "\\r", s, fixed = TRUE)
  s <- gsub("\t", "\\t", s, fixed = TRUE)
  s <- gsub("\b", "\\b", s, fixed = TRUE)
  s <- gsub("\f", "\\f", s, fixed = TRUE)
  bytes <- charToRaw(s)
  if (any(bytes < as.raw(0x20))) {
    chars <- strsplit(s, "", useBytes = TRUE)[[1]]
    ctrl <- vapply(chars, function(ch) {
      b <- charToRaw(ch)
      length(b) == 1L && b < as.raw(0x20)
    }, logical(1))
    chars[ctrl] <- sprintf("\\u%04x", vapply(chars[ctrl], function(ch) {
      as.integer(charToRaw(ch))
    }, integer(1)))
    s <- paste(chars, collapse = "")
  }
  paste0("\"", s, "\"")
}

# Write a value as pretty JSON atomically (temporary file in the same directory,
# then rename), so a reader never observes a half-written document.
.write_json_atomic <- function(x, path, pretty = TRUE) {
  txt <- jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null",
                          digits = NA, pretty = pretty)
  .write_text_atomic(as.character(txt), path)
}

.write_text_atomic <- function(text, path) {
  dir <- dirname(path)
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }
  tmp <- tempfile(pattern = ".annotatR-", tmpdir = dir, fileext = ".tmp")
  con <- file(tmp, open = "wb")
  writeBin(charToRaw(enc2utf8(paste0(text, "\n"))), con)
  close(con)
  if (!file.rename(tmp, path)) {
    unlink(tmp)
    .at_abort("Could not write {.path {basename(path)}}.", class = "io", code = "WRITE_FAILED")
  }
  invisible(path)
}

# Read a JSON document as nested lists (objects are named lists).
.read_json_doc <- function(path, max_bytes = 16 * 1024^2, call = rlang::caller_env()) {
  size <- file.info(path)$size
  if (is.na(size)) {
    .at_abort("{.path {basename(path)}} does not exist.", class = "io",
              code = "FILE_MISSING", call = call)
  }
  if (size > max_bytes) {
    .at_abort("{.path {basename(path)}} is larger than the {max_bytes}-byte JSON limit.",
              class = "limit", code = "PAYLOAD_TOO_LARGE", call = call)
  }
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) {
      .at_abort("{.path {basename(path)}} is not valid JSON.", code = "INVALID_JSON",
                details = list(file = basename(path)), call = call)
    }
  )
}

# ---- Digests ---------------------------------------------------------------

# SHA-256 of a file as 64 lowercase hex characters. `tools::sha256sum()` exists
# from R 4.5.0; older R falls back to the optional `digest` package.
.sha256_file <- function(path, call = rlang::caller_env()) {
  tools_ns <- asNamespace("tools")
  if (exists("sha256sum", envir = tools_ns, inherits = FALSE)) {
    return(unname(get("sha256sum", envir = tools_ns)(path)))
  }
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = path, algo = "sha256"))
  }
  .at_abort(
    c("SHA-256 hashing needs R >= 4.5.0 or the {.pkg digest} package.",
      "i" = "Install it with {.code install.packages(\"digest\")}."),
    class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call
  )
}

# SHA-256 of a raw vector or a string (as UTF-8 bytes).
.sha256_bytes <- function(x, call = rlang::caller_env()) {
  if (is.character(x)) {
    x <- charToRaw(enc2utf8(paste(x, collapse = "")))
  }
  tools_ns <- asNamespace("tools")
  if (exists("sha256sum", envir = tools_ns, inherits = FALSE) &&
      "bytes" %in% names(formals(get("sha256sum", envir = tools_ns)))) {
    return(unname(get("sha256sum", envir = tools_ns)(bytes = x)))
  }
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  writeBin(x, tmp)
  .sha256_file(tmp, call = call)
}

# SHA-256 of the canonical JSON form of a value.
.digest_json <- function(x) .sha256_bytes(.canonical_json(x))

# ---- Identifiers and tokens ------------------------------------------------

# `n` cryptographically random bytes. Uses the operating-system source where
# available and never disturbs the caller's R random-number stream.
.random_bytes <- function(n) {
  if (file.exists("/dev/urandom")) {
    con <- file("/dev/urandom", "rb", raw = TRUE)
    on.exit(close(con), add = TRUE)
    return(readBin(con, "raw", n = n))
  }
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had_seed) get(".Random.seed", envir = globalenv()) else NULL
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }, add = TRUE)
  set.seed(NULL)
  as.raw(sample.int(256L, n, replace = TRUE) - 1L)
}

.random_hex <- function(n_bytes = 16L) {
  paste(sprintf("%02x", as.integer(.random_bytes(n_bytes))), collapse = "")
}

# A random RFC 4122 version-4 UUID string.
.uuid <- function() {
  b <- as.integer(.random_bytes(16L))
  b[7] <- bitwOr(bitwAnd(b[7], 0x0f), 0x40)
  b[9] <- bitwOr(bitwAnd(b[9], 0x3f), 0x80)
  h <- sprintf("%02x", b)
  paste(paste(h[1:4], collapse = ""), paste(h[5:6], collapse = ""),
        paste(h[7:8], collapse = ""), paste(h[9:10], collapse = ""),
        paste(h[11:16], collapse = ""), sep = "-")
}

# ---- Time --------------------------------------------------------------------

.utc_stamp <- function(time = Sys.time()) {
  format(time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# ---- Paths -----------------------------------------------------------------

# A safe single path component derived from a user-visible name. The original
# name is always kept in metadata; only the file name is sanitised.
.safe_component <- function(x, max_chars = 64L) {
  x <- enc2utf8(as.character(x))
  out <- gsub("[^A-Za-z0-9._-]+", "_", iconv(x, to = "ASCII//TRANSLIT", sub = "_"))
  out[is.na(out)] <- "item"
  out <- gsub("^[._]+", "", out)
  out <- substr(out, 1L, max_chars)
  out[!nzchar(out) | out %in% c(".", "..")] <- "item"
  out
}

# Make sanitised components unique within one directory, case-insensitively.
.unique_components <- function(x) {
  lower <- tolower(x)
  seen <- character()
  out <- x
  for (i in seq_along(x)) {
    cand <- x[i]
    k <- 1L
    while (tolower(cand) %in% seen) {
      k <- k + 1L
      cand <- paste0(x[i], "_", k)
    }
    seen <- c(seen, tolower(cand))
    out[i] <- cand
  }
  out
}

# Is `rel` a clean relative path (no absolute prefix, drive, `..`, empty or
# control-character component)?
.is_clean_relative <- function(rel) {
  if (!.is_string(rel) || !nzchar(rel) || nchar(rel) > 1024L) {
    return(FALSE)
  }
  if (grepl("^([/\\\\~]|[A-Za-z]:)", rel) || grepl("[[:cntrl:]]", rel)) {
    return(FALSE)
  }
  parts <- strsplit(rel, "[/\\\\]")[[1]]
  length(parts) > 0L && all(nzchar(parts)) && !any(parts %in% c(".", ".."))
}

# Resolve `rel` under `root`, refusing absolute paths, traversal and symlink
# escapes. Returns the normalised absolute path.
.resolve_under_root <- function(root, rel, must_exist = TRUE, call = rlang::caller_env()) {
  if (!.is_clean_relative(rel)) {
    .at_abort("Path references must be relative to the negotiated root.",
              class = "io", code = "PATH_OUTSIDE_ROOT", call = call)
  }
  root_n <- normalizePath(root, winslash = "/", mustWork = TRUE)
  full <- file.path(root_n, rel)
  if (must_exist) {
    if (!file.exists(full)) {
      .at_abort("The referenced path does not exist under the root.",
                class = "io", code = "FILE_MISSING", details = list(path = rel), call = call)
    }
    real <- normalizePath(full, winslash = "/", mustWork = TRUE)
  } else {
    parent <- dirname(full)
    real_parent <- if (dir.exists(parent)) normalizePath(parent, winslash = "/") else parent
    real <- file.path(real_parent, basename(full))
  }
  if (!identical(real, root_n) && !startsWith(real, paste0(root_n, "/"))) {
    .at_abort("The referenced path resolves outside the negotiated root.",
              class = "io", code = "PATH_OUTSIDE_ROOT", call = call)
  }
  real
}

# Relative path of `path` below `root` using forward slashes.
.relative_to <- function(path, root) {
  root_n <- normalizePath(root, winslash = "/", mustWork = TRUE)
  p <- normalizePath(path, winslash = "/", mustWork = TRUE)
  sub(paste0("^", .regex_escape(root_n), "/"), "", p)
}

.regex_escape <- function(x) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)

# Is `path` a symbolic link? (Sys.readlink returns "" for non-links.)
.is_symlink <- function(path) {
  link <- Sys.readlink(path)
  !is.na(link) & nzchar(link)
}

# ---- Package provenance ----------------------------------------------------

# Source revision of the installed package when recorded by the installer
# (pak/remotes write RemoteSha); otherwise NA.
.source_revision <- function() {
  desc <- tryCatch(utils::packageDescription("annotatR"), error = function(e) NULL)
  sha <- if (is.list(desc)) desc$RemoteSha else NULL
  if (.is_string(sha) && nzchar(sha)) sha else NA_character_
}

# Installed version of an optional package, or NA when absent.
.pkg_version_or_na <- function(pkg) {
  if (!nzchar(system.file(package = pkg))) {
    return(NA_character_)
  }
  tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NA_character_)
}
