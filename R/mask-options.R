# Source reader options accept recursive lists and atomic vectors. JSON arrays
# alone cannot distinguish their types, names, dimensions, or attributes. This
# data-only encoding never evaluates code or deserializes executable objects.
.mask_options_encode <- function(options) {
  number <- function(x) {
    if (is.nan(x)) "NaN" else if (is.na(x)) "NA" else sprintf("%.17g", x)
  }
  node <- function(x) {
    kind <- typeof(x)
    if (!kind %in% c("NULL", "list", "pairlist", "logical", "integer", "double", "complex", "character", "raw")) {
      cli::cli_abort("Unsupported source option encoding type {.val {kind}}.")
    }
    formal <- isS4(x)
    attrs <- attributes(x)
    attributes(x) <- NULL
    data <- switch(kind,
      NULL = list(),
      list = lapply(x, node),
      pairlist = lapply(as.list(x), node),
      logical = lapply(x, function(v) if (is.na(v)) "NA" else if (v) "TRUE" else "FALSE"),
      integer = lapply(x, function(v) if (is.na(v)) "NA" else as.character(v)),
      double = lapply(x, number),
      complex = lapply(x, function(v) list(real = number(Re(v)), imaginary = number(Im(v)))),
      character = lapply(x, function(v) if (is.na(v)) NULL else v),
      raw = lapply(x, function(v) sprintf("%02x", as.integer(v))))
    list(type = kind, data = data, s4 = formal, attributes = if (is.null(attrs)) NULL else
      lapply(seq_along(attrs), function(i) list(name = names(attrs)[i], value = node(attrs[[i]]))))
  }
  list(schema_version = 2L, node = node(options))
}

.mask_options_decode <- function(encoded) {
  bad <- function() cli::cli_abort("Malformed or unsupported source option encoding.")
  fields <- function(x, expected) {
    is.list(x) && !is.null(names(x)) && !anyDuplicated(names(x)) && setequal(names(x), expected)
  }
  scalar <- function(x) is.character(x) && length(x) == 1L && !is.na(x)
  number <- function(x) {
    if (!scalar(x)) bad()
    if (x == "NA") return(NA_real_)
    if (x == "NaN") return(NaN)
    if (x == "Inf") return(Inf)
    if (x == "-Inf") return(-Inf)
    if (!grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$", x)) bad()
    v <- suppressWarnings(as.double(x))
    if (!is.finite(v)) bad()
    v
  }
  node <- function(x) {
    expected <- c("type", "data", "attributes", if (version == 2L) "s4")
    if (!fields(x, expected) || !scalar(x$type) ||
        !is.list(x$data) || !is.null(names(x$data))) bad()
    formal <- if (version == 2L) x$s4 else FALSE
    if (!is.logical(formal) || length(formal) != 1L || is.na(formal)) bad()
    data <- x$data
    out <- switch(x$type,
      NULL = { if (length(data) || !is.null(x$attributes)) bad(); NULL },
      list = lapply(data, node),
      pairlist = as.pairlist(lapply(data, node)),
      logical = vapply(data, function(v) {
        if (!scalar(v) || !v %in% c("TRUE", "FALSE", "NA")) bad()
        if (v == "NA") NA else v == "TRUE"
      }, logical(1)),
      integer = vapply(data, function(v) {
        if (identical(v, "NA")) return(NA_integer_)
        n <- number(v)
        if (!is.finite(n) || n != trunc(n) || abs(n) > .Machine$integer.max) bad()
        as.integer(n)
      }, integer(1)),
      double = vapply(data, number, double(1)),
      complex = vapply(data, function(v) {
        if (!fields(v, c("real", "imaginary"))) bad()
        complex(real = number(v$real), imaginary = number(v$imaginary))
      }, complex(1)),
      character = vapply(data, function(v) {
        if (is.null(v)) return(NA_character_)
        if (!scalar(v)) bad()
        v
      }, character(1)),
      raw = as.raw(vapply(data, function(v) {
        if (!scalar(v) || !grepl("^[0-9a-f]{2}$", v)) bad()
        strtoi(v, base = 16L)
      }, integer(1))),
      bad())
    if (!is.null(x$attributes)) {
      entries <- x$attributes
      if (!is.list(entries) || !is.null(names(entries)) || !length(entries)) bad()
      nms <- vapply(entries, function(entry) {
        if (!fields(entry, c("name", "value")) || !scalar(entry$name) || !nzchar(entry$name)) bad()
        entry$name
      }, character(1))
      if (anyDuplicated(nms)) bad()
      attrs <- stats::setNames(lapply(entries, function(entry) node(entry$value)), nms)
      tryCatch(attributes(out) <- attrs, error = function(e) bad())
      # R may coerce malformed attributes (e.g. fractional dimensions); do not
      # silently accept a shape other than the declaration being decoded.
      if (!identical(attributes(out), attrs)) bad()
    }
    if (formal) {
      # Set the formal-object bit directly, without invoking constructors,
      # validity methods, or requiring the class definition to be installed.
      out <- tryCatch(asS4(out, complete = FALSE), error = function(e) bad())
    }
    if (!identical(isS4(out), formal)) bad()
    out
  }
  if (!fields(encoded, c("schema_version", "node")) ||
      !is.numeric(encoded$schema_version) || length(encoded$schema_version) != 1L ||
      is.na(encoded$schema_version) || !encoded$schema_version %in% c(1L, 2L)) bad()
  version <- as.integer(encoded$schema_version)
  result <- node(encoded$node)
  if (!is.list(result) || !.serializable_options(result)) bad()
  result
}
