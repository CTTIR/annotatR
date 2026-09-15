# Hyperspectral (and multichannel) metadata: the backend-agnostic field list
# shared with the partner contract, value semantics, named value conversions,
# a whitelist of display band operations, and read accounting. The universal
# tile contract `[y, x, band]` is unchanged; everything here is additive
# metadata and validation around it.

# Allowed value semantics. Raw counts, reflectance, radiance, intensity and
# absorbance are never mixed: a conversion is a named, tested function.
.value_units <- c("raw", "reflectance", "radiance", "intensity", "absorbance", "unknown")

# ---- Band table ------------------------------------------------------------

# Wavelength validity per band: "ok", "missing", "duplicate" or "non_numeric".
.wavelength_status <- function(wl, n) {
  if (is.null(wl) || length(wl) == 0L) {
    return(rep("missing", n))
  }
  raw <- rep_len(as.character(wl), n)
  if (length(wl) != n) {
    raw[seq_len(n) > length(wl)] <- NA_character_
  }
  num <- suppressWarnings(as.numeric(raw))
  status <- ifelse(is.na(raw), "missing", ifelse(is.na(num), "non_numeric", "ok"))
  dup <- status == "ok" & (duplicated(num) | duplicated(num, fromLast = TRUE))
  status[dup] <- "duplicate"
  status
}

# ---- The HSI field list ------------------------------------------------------

#' Hyperspectral and acquisition metadata of an image
#'
#' Return the backend-agnostic metadata record annotatR keeps for an image:
#' acquisition identity, storage layout, value semantics, geometry convention,
#' plane selection, and calibration/transform digests. Fields a backend cannot
#' establish are `NA` (never guessed), and `wavelength_status` in [at_bands()]
#' flags missing or duplicated wavelengths instead of interpolating them.
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#'
#' @return A named list with the elements `vendor`, `instrument`,
#'   `acquisition_id`, `format`, `backend`, `image_kind` (`"spectral"`,
#'   `"multichannel"`, `"rgb"` or `"grayscale"`), `width`, `height`, `n_bands`,
#'   `n_levels`, `dtype`, `value_unit` (one of `"raw"`, `"reflectance"`,
#'   `"radiance"`, `"intensity"`, `"absorbance"`, `"unknown"`), `scale_factor`,
#'   `offset`, `nodata`, `valid_range`, `interleave`, `byte_order`,
#'   `header_bytes`, `axis_order`, `pixel_size`, `pixel_unit`, `origin`,
#'   `y_direction`, `series_id`, `plane` (list of zero-based `c`, `z`, `t`),
#'   `wavelength_unit`, `calibration`, `calibration_digest`, `transform_digest`,
#'   `profile`, `window_read` and `pan_sharpened`.
#' @family images
#' @family hsi
#' @seealso [at_bands()], [at_read_stats()]
#' @export
#' @examples
#' at_hsi_meta(at_example_image("cube"))[c("image_kind", "value_unit", "interleave")]
at_hsi_meta <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  m <- x$meta %||% list()
  d <- x$level_dims[[1]]
  value_unit <- m$value_unit %||% "unknown"
  if (!value_unit %in% .value_units) value_unit <- "unknown"
  list(
    vendor          = m$vendor %||% NA_character_,
    instrument      = m$instrument %||% NA_character_,
    acquisition_id  = m$acquisition_id %||% NA_character_,
    format          = m$format %||% x$backend,
    backend         = x$backend,
    image_kind      = .image_kind(x),
    width           = as.integer(d[1]),
    height          = as.integer(d[2]),
    n_bands         = as.integer(x$n_bands),
    n_levels        = as.integer(x$n_levels),
    dtype           = x$dtype,
    value_unit      = value_unit,
    scale_factor    = m$scale_factor %||% NA_real_,
    offset          = m$offset %||% NA_real_,
    nodata          = m$nodata %||% NA_real_,
    valid_range     = m$valid_range %||% c(NA_real_, NA_real_),
    interleave      = m$interleave %||% NA_character_,
    byte_order      = m$byte_order %||% NA_character_,
    header_bytes    = m$header_bytes %||% NA_real_,
    axis_order      = m$axis_order %||% "y,x,band",
    pixel_size      = as.numeric(x$pixel_size),
    pixel_unit      = x$pixel_unit,
    origin          = "top_left",
    y_direction     = "down",
    series_id       = m$series_id %||% 0L,
    plane           = m$plane %||% list(c = NA_integer_, z = 0L, t = 0L),
    wavelength_unit = x$wavelength_unit %||% NA_character_,
    calibration     = m$calibration %||% list(status = "missing"),
    calibration_digest = m$calibration_digest %||% NA_character_,
    transform_digest = .transform_digest(x),
    profile         = m$profile %||% NA_character_,
    window_read     = isTRUE(m$window_read),
    pan_sharpened   = m$pan_sharpened %||% NA
  )
}

# Classify an image honestly: spectral only with per-band wavelength metadata.
.image_kind <- function(x) {
  if (at_is_spectral(x)) {
    return("spectral")
  }
  if (x$n_bands %in% 3:4 && identical(as.character(x$band_names)[1:3], c("R", "G", "B"))) {
    return("rgb")
  }
  if (x$n_bands <= 2L) {
    return("grayscale")
  }
  "multichannel"
}

# Digest of the pixel-grid transform: level dimensions, pixel size and
# orientation convention. Changes whenever a coordinate would map differently.
.transform_digest <- function(x) {
  .digest_json(list(
    level_dims = lapply(x$level_dims, as.list),
    pixel_size = as.list(as.numeric(x$pixel_size)),
    pixel_unit = x$pixel_unit,
    origin = "top_left",
    y_direction = "down",
    axis_order = "y,x,band"
  ))
}

# ---- Value conversions -------------------------------------------------------

#' Convert spectral values between declared units
#'
#' The only supported ways to change value semantics. Raw counts become
#' reflectance through an explicit dark/white calibration, and reflectance
#' becomes (pseudo-)absorbance as `-log10(reflectance)`. Anything else, or a
#' conversion without the calibration it needs, is refused with a classified
#' error instead of being approximated.
#'
#' @param x A numeric vector, matrix or `[y, x, band]` array of values.
#' @param from The unit of `x`: one of `"raw"`, `"reflectance"`, `"radiance"`,
#'   `"intensity"`, `"absorbance"`. Taken from `attr(x, "value_unit")` when
#'   `NULL`.
#' @param to Target unit: `"reflectance"` or `"absorbance"`.
#' @param calibration For `raw -> reflectance`, a list with numeric `white`
#'   and `dark` references (scalars, or one value per band for arrays).
#' @param call The calling environment, for error reporting.
#'
#' @return `x` converted, with attribute `value_unit` set to `to` and
#'   `conversion` recording the operation. Reflectance values `<= 0` give `NA`
#'   absorbance; a zero white-minus-dark denominator gives `NA`.
#' @family hsi
#' @export
#' @examples
#' at_convert_values(c(0.5, 0.1), from = "reflectance", to = "absorbance")
#' at_convert_values(c(100, 550, 1000), from = "raw", to = "reflectance",
#'                   calibration = list(white = 1000, dark = 100))
at_convert_values <- function(x, from = NULL, to = c("reflectance", "absorbance"),
                              calibration = NULL, call = rlang::caller_env()) {
  if (!is.numeric(x)) {
    .at_abort("{.arg x} must be numeric.", call = call)
  }
  to <- .check_choice(to, c("reflectance", "absorbance"), call = call)
  from <- from %||% attr(x, "value_unit")
  if (!.is_string(from) || !from %in% setdiff(.value_units, "unknown")) {
    .at_abort(
      c("The value unit of {.arg x} is not declared.",
        "i" = "Pass {.arg from}; annotatR never guesses whether values are raw or calibrated."),
      code = "VALUE_UNIT_UNKNOWN", call = call
    )
  }
  key <- paste(from, to, sep = "->")
  out <- switch(
    key,
    "reflectance->reflectance" = x,
    "absorbance->absorbance" = x,
    "raw->reflectance" = .raw_to_reflectance(x, calibration, call),
    "reflectance->absorbance" = {
      v <- x
      v[!is.na(v) & v <= 0] <- NA_real_
      -log10(v)
    },
    "raw->absorbance" = {
      r <- .raw_to_reflectance(x, calibration, call)
      r[!is.na(r) & r <= 0] <- NA_real_
      -log10(r)
    },
    .at_abort(
      c("No registered conversion from {.val {from}} to {.val {to}}.",
        "i" = "Supported: raw -> reflectance (with calibration), reflectance -> absorbance."),
      class = "capability", code = "CONVERSION_UNSUPPORTED", call = call
    )
  )
  attributes(out) <- attributes(x)
  attr(out, "value_unit") <- to
  attr(out, "conversion") <- key
  out
}

.raw_to_reflectance <- function(x, calibration, call) {
  if (is.null(calibration) || is.null(calibration$white) || is.null(calibration$dark)) {
    .at_abort(
      c("Converting raw values to reflectance needs a dark/white calibration.",
        "i" = "Supply {.code calibration = list(white = ..., dark = ...)}."),
      class = "capability", code = "CALIBRATION_MISSING", call = call
    )
  }
  white <- as.numeric(calibration$white)
  dark <- as.numeric(calibration$dark)
  d <- dim(x)
  if (length(d) == 3L && (length(white) > 1L || length(dark) > 1L)) {
    nb <- d[3]
    if (!length(white) %in% c(1L, nb) || !length(dark) %in% c(1L, nb)) {
      .at_abort("Calibration references must have one value per band ({nb}).",
                code = "CALIBRATION_INVALID", call = call)
    }
    white <- rep_len(white, nb)
    dark <- rep_len(dark, nb)
    out <- x
    for (b in seq_len(nb)) {
      den <- white[b] - dark[b]
      out[, , b] <- if (den == 0) NA_real_ else (x[, , b] - dark[b]) / den
    }
    return(out)
  }
  den <- white - dark
  out <- (x - dark) / den
  out[den == 0] <- NA_real_
  out
}

# ---- Band operations (display products) -------------------------------------

# The whitelist of display band operations. Each entry declares how many bands
# it takes and which numeric parameters it accepts; there is no expression
# evaluation anywhere.
.band_ops <- list(
  single = list(n_bands = 1L, params = character(),
                description = "One band shown as greyscale."),
  rgb = list(n_bands = 3L, params = character(),
             description = "Three bands as a pseudo-RGB / false-colour composite."),
  ratio = list(n_bands = 2L, params = character(),
               description = "Band ratio a / b; a zero denominator gives NA."),
  normalized_difference = list(n_bands = 2L, params = character(),
                               description = "(a - b) / (a + b); a zero denominator gives NA."),
  band_mean = list(n_bands = NA_integer_, params = character(),
                   description = "Mean over the selected bands."),
  wavelength_window_mean = list(n_bands = NA_integer_,
                                params = c("wavelength_min", "wavelength_max"),
                                description = "Mean over bands whose wavelength lies in a window.")
)

#' Registered band operations
#'
#' List the display band operations the app and the control service accept.
#' Derived views are display products: they carry their parent digest, band
#' list, operation and parameters, and are never written back as analysis
#' input.
#'
#' @return A [tibble::tibble] with columns `operation`, `n_bands` (integer;
#'   `NA` means one or more), `params` (comma-separated parameter names) and
#'   `description`.
#' @family hsi
#' @export
#' @examples
#' at_band_operations()
at_band_operations <- function() {
  tibble::tibble(
    operation = names(.band_ops),
    n_bands = vapply(.band_ops, `[[`, integer(1), "n_bands", USE.NAMES = FALSE),
    params = vapply(.band_ops, function(o) paste(o$params, collapse = ","), character(1),
                    USE.NAMES = FALSE),
    description = vapply(.band_ops, `[[`, character(1), "description", USE.NAMES = FALSE)
  )
}

# Validate a band-view specification and return it normalised:
# list(operation, bands (integer), params (named numeric list)).
.check_band_view <- function(img, operation = "rgb", bands = NULL, params = list(),
                             call = rlang::caller_env()) {
  operation <- .check_choice(operation, names(.band_ops), call = call)
  op <- .band_ops[[operation]]
  nb <- img$n_bands
  if (operation == "wavelength_window_mean") {
    if (!at_is_spectral(img)) {
      .at_abort("{.val wavelength_window_mean} needs a spectral image.", call = call)
    }
    lo <- params$wavelength_min
    hi <- params$wavelength_max
    if (!is.numeric(lo) || !is.numeric(hi) || length(lo) != 1L || length(hi) != 1L || lo > hi) {
      .at_abort("Pass numeric {.field wavelength_min} <= {.field wavelength_max}.", call = call)
    }
    wl <- at_wavelengths(img)
    bands <- which(!is.na(wl) & wl >= lo & wl <= hi)
    if (length(bands) == 0L) {
      .at_abort("No band lies within [{lo}, {hi}] {img$wavelength_unit %||% ''}.", call = call)
    }
    params <- list(wavelength_min = as.numeric(lo), wavelength_max = as.numeric(hi))
  } else {
    unknown <- setdiff(names(params), op$params)
    if (length(unknown) > 0L) {
      .at_abort("Operation {.val {operation}} takes no parameter{?s} {.val {unknown}}.",
                call = call)
    }
    if (is.null(bands)) {
      bands <- switch(operation, rgb = .default_rgb_bands(img, nb), single = 1L,
                      ratio = , normalized_difference = c(1L, min(2L, nb)),
                      seq_len(nb))
    }
  }
  bands <- as.integer(bands)
  if (length(bands) == 0L || anyNA(bands) || any(bands < 1L | bands > nb)) {
    .at_abort("{.arg bands} must be band indices in 1..{nb}.", code = "BAND_OUT_OF_RANGE",
              call = call)
  }
  if (!is.na(op$n_bands) && length(bands) != op$n_bands) {
    .at_abort("Operation {.val {operation}} needs exactly {op$n_bands} band{?s}.",
              code = "BAND_COUNT", call = call)
  }
  list(operation = operation, bands = bands, params = params)
}

#' Compute a registered band view
#'
#' Evaluate one of [at_band_operations()] on a window of an image. The result
#' is a display product: a `[y, x, k]` array (`k = 3` for `"rgb"`, otherwise 1)
#' with provenance attributes, which annotatR never uses as analysis input.
#'
#' @param img An [annot_image].
#' @param operation A registered operation name.
#' @param bands Band indices (defaults depend on the operation).
#' @param params Named list of operation parameters.
#' @param level,xrange,yrange Passed to [at_tile()].
#' @param call The calling environment, for error reporting.
#'
#' @return A numeric array with attributes `operation`, `bands`,
#'   `wavelengths`, `params`, `parent_digest`, `transform_digest`, `level` and
#'   `display_product = TRUE`.
#' @family hsi
#' @export
#' @examples
#' cube <- at_example_image("cube")
#' v <- at_band_view(cube, "normalized_difference", bands = c(30, 10))
#' attr(v, "operation")
at_band_view <- function(img, operation = "rgb", bands = NULL, params = list(),
                         level = 0L, xrange = NULL, yrange = NULL,
                         call = rlang::caller_env()) {
  .check_image(img, call = call)
  spec <- .check_band_view(img, operation, bands, params, call = call)
  tile <- at_tile(img, level = level, xrange = xrange, yrange = yrange,
                  bands = spec$bands, call = call)
  a <- function(k) tile[, , k]
  den_na <- function(num, den) {
    out <- num / den
    out[den == 0] <- NA_real_
    out
  }
  vals <- switch(
    spec$operation,
    single = tile,
    rgb = tile,
    ratio = array(den_na(a(1), a(2)), dim = c(dim(tile)[1:2], 1L)),
    normalized_difference = array(den_na(a(1) - a(2), a(1) + a(2)), dim = c(dim(tile)[1:2], 1L)),
    array(apply(tile, c(1, 2), mean), dim = c(dim(tile)[1:2], 1L))
  )
  wl <- if (at_is_spectral(img)) at_wavelengths(img)[spec$bands] else rep(NA_real_, length(spec$bands))
  structure(
    vals,
    operation = spec$operation,
    bands = spec$bands,
    wavelengths = wl,
    params = spec$params,
    parent_digest = .image_identity_digest(img),
    transform_digest = .transform_digest(img),
    level = as.integer(level),
    display_product = TRUE
  )
}

# A digest identifying an image handle without reading pixels: backend, source
# basename, size and modification time of the file when present, dimensions.
.image_identity_digest <- function(img) {
  info <- if (file.exists(img$source)) file.info(img$source) else NULL
  .digest_json(list(
    backend = img$backend,
    source_name = basename(img$source),
    size_bytes = if (is.null(info)) NULL else as.numeric(info$size),
    level_dims = lapply(img$level_dims, as.list),
    n_bands = img$n_bands
  ))
}

# ---- Read accounting ---------------------------------------------------------

.read_stats_env <- new.env(parent = emptyenv())

.read_stats_key <- function(img) paste(img$backend, img$source, sep = "|")

# Record one tile request: bytes read from the file (0 when served from memory)
# and bytes returned in the decoded array.
.read_stats_add <- function(img, file_bytes = 0, decoded_bytes = 0) {
  key <- .read_stats_key(img)
  cur <- .read_stats_env[[key]] %||%
    list(tiles = 0L, file_bytes = 0, decoded_bytes = 0, max_tile_bytes = 0)
  cur$tiles <- cur$tiles + 1L
  cur$file_bytes <- cur$file_bytes + file_bytes
  cur$decoded_bytes <- cur$decoded_bytes + decoded_bytes
  cur$max_tile_bytes <- max(cur$max_tile_bytes, decoded_bytes)
  assign(key, cur, envir = .read_stats_env)
  invisible(cur)
}

#' Read accounting for an image
#'
#' Report how many tiles were requested from an image's backend, how many
#' payload bytes were read from its file by windowed readers, and how many bytes
#' were returned as decoded arrays. Cache hits are not counted as reads.
#'
#' @param img An [annot_image].
#' @param reset Logical; reset the counters for this image after reporting.
#' @param call The calling environment, for error reporting.
#'
#' @return A list with `tiles` (integer), `file_bytes`, `decoded_bytes` and
#'   `max_tile_bytes` (doubles), plus `window_read` (logical) and the current
#'   `max_tile_bytes_limit` from option `annotatR.max_tile_bytes`.
#' @family hsi
#' @export
#' @examples
#' cube <- at_example_image("cube")
#' invisible(at_tile(cube, xrange = c(1, 4), yrange = c(1, 4), bands = 1:2))
#' at_read_stats(cube)$tiles
at_read_stats <- function(img, reset = FALSE, call = rlang::caller_env()) {
  .check_image(img, call = call)
  .check_flag(reset, call = call)
  key <- .read_stats_key(img)
  cur <- .read_stats_env[[key]] %||%
    list(tiles = 0L, file_bytes = 0, decoded_bytes = 0, max_tile_bytes = 0)
  if (reset && exists(key, envir = .read_stats_env, inherits = FALSE)) {
    rm(list = key, envir = .read_stats_env)
  }
  c(cur, list(window_read = isTRUE(img$meta$window_read),
              max_tile_bytes_limit = .max_tile_bytes()))
}

.max_tile_bytes <- function() {
  as.numeric(getOption("annotatR.max_tile_bytes", default = 2 * 1024^3))
}
