# The annot_image class: a lightweight, backend-agnostic image handle holding
# metadata and a lazy accessor, never pixel data for large images.

# Internal constructor. Users obtain an annot_image from at_read_image().
new_annot_image <- function(source,
                            backend,
                            dims,
                            n_levels,
                            level_dims,
                            n_bands,
                            band_names = NA_character_,
                            wavelengths = NULL,
                            wavelength_unit = NULL,
                            pixel_size = c(1, 1),
                            pixel_unit = "px",
                            dtype = "uint8",
                            handle = NULL,
                            meta = list()) {
  structure(
    list(
      source          = as.character(source),
      backend         = as.character(backend),
      dims            = as.integer(dims),
      n_levels        = as.integer(n_levels),
      level_dims      = lapply(level_dims, as.integer),
      n_bands         = as.integer(n_bands),
      band_names      = band_names,
      wavelengths     = wavelengths,
      wavelength_unit = wavelength_unit,
      pixel_size      = as.numeric(pixel_size),
      pixel_unit      = as.character(pixel_unit),
      dtype           = as.character(dtype),
      handle          = handle,
      meta            = meta
    ),
    class = "annot_image"
  )
}

#' Image dimensions at a pyramid level
#'
#' Return the pixel dimensions `c(width, height)` of an [annot_image] at a
#' given pyramid level.
#'
#' @param x An [annot_image].
#' @param level Integer pyramid level, `0` for full resolution. Must be in
#'   `0:(at_n_levels(x) - 1)`.
#' @param call The calling environment, for error reporting.
#'
#' @return An integer vector of length 2, `c(width, height)`.
#' @family images
#' @seealso [at_n_levels()], [at_is_pyramidal()]
#' @export
#' @examples
#' # Image handles come from at_read_image(); see the images vignette.
at_dims <- function(x, level = 0L, call = rlang::caller_env()) {
  .check_image(x, call = call)
  level <- .check_count(level, call = call)
  if (level > x$n_levels - 1L) {
    cli::cli_abort(
      c(
        "{.arg level} exceeds the available pyramid levels.",
        "x" = "Level {level} was requested but only levels {.val {0:(x$n_levels - 1L)}} exist."
      ),
      call = call
    )
  }
  x$level_dims[[level + 1L]]
}

#' Number of pyramid levels
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return An integer scalar; `1` when the image has no pyramid.
#' @family images
#' @export
at_n_levels <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  x$n_levels
}

#' Number of bands (channels)
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return An integer scalar.
#' @family images
#' @export
at_n_bands <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  x$n_bands
}

#' Band (channel) table
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with one row per band and the columns:
#'   \describe{
#'     \item{`index`}{Band index, 1-based (integer).}
#'     \item{`name`}{Band name (character); a default `"Band k"` when unnamed.}
#'     \item{`wavelength`}{Centre wavelength (double); `NA` when not spectral.}
#'     \item{`unit`}{Wavelength unit (character); `NA` when not spectral.}
#'   }
#'   Always has `at_n_bands(x)` rows.
#' @family images
#' @export
at_bands <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  n <- x$n_bands
  nm <- x$band_names
  if (length(nm) != n || all(is.na(nm))) {
    nm <- paste0("Band ", seq_len(n))
  } else {
    nm <- as.character(nm)
    nm[is.na(nm)] <- paste0("Band ", which(is.na(nm)))
  }
  spectral <- at_is_spectral(x)
  wl <- if (spectral) as.numeric(x$wavelengths)[seq_len(n)] else rep(NA_real_, n)
  unit <- if (spectral) rep(x$wavelength_unit %||% NA_character_, n) else rep(NA_character_, n)
  tibble::tibble(
    index      = seq_len(n),
    name       = nm,
    wavelength = wl,
    unit       = unit
  )
}

#' Band centre wavelengths
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return A numeric vector of length `at_n_bands(x)` for a spectral image, or
#'   `numeric(0)` when the image is not spectral.
#' @family images
#' @seealso [at_is_spectral()]
#' @export
at_wavelengths <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  if (!at_is_spectral(x)) {
    return(numeric(0))
  }
  as.numeric(x$wavelengths)[seq_len(x$n_bands)]
}

#' Is the image a spectral cube?
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return A logical scalar. `TRUE` when the image carries per-band wavelengths.
#' @family images
#' @export
at_is_spectral <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  !is.null(x$wavelengths) && length(x$wavelengths) > 0L && any(!is.na(x$wavelengths))
}

#' Is the image pyramidal?
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return A logical scalar. `TRUE` when more than one pyramid level exists.
#' @family images
#' @export
at_is_pyramidal <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  x$n_levels > 1L
}

#' Physical pixel size
#'
#' @param x An [annot_image].
#' @param call The calling environment, for error reporting.
#' @return A numeric vector of length 2, the physical size of one level-0 pixel
#'   as `c(x, y)`, in the units given by `at_meta(x, "pixel_unit")`.
#' @family images
#' @export
at_pixel_size <- function(x, call = rlang::caller_env()) {
  .check_image(x, call = call)
  x$pixel_size
}

#' Image metadata
#'
#' @param x An [annot_image].
#' @param key Optional single string. When supplied, the corresponding metadata
#'   element is returned; otherwise the whole metadata list is returned.
#' @param call The calling environment, for error reporting.
#' @return When `key` is `NULL`, a list of all metadata (including `source`,
#'   `backend`, `dtype`, `pixel_unit`, and any backend-specific entries). When
#'   `key` is supplied, the single element (or `NULL` if absent).
#' @family images
#' @export
at_meta <- function(x, key = NULL, call = rlang::caller_env()) {
  .check_image(x, call = call)
  base <- list(
    source     = x$source,
    backend    = x$backend,
    dtype      = x$dtype,
    pixel_unit = x$pixel_unit
  )
  full <- utils::modifyList(base, x$meta)
  if (is.null(key)) {
    return(full)
  }
  .check_string(key, call = call)
  full[[key]]
}

#' @export
format.annot_image <- function(x, ...) {
  d <- x$level_dims[[1]]
  spectral <- at_is_spectral(x)
  lines <- c(
    cli::format_inline("{.cls annot_image} {.field {basename(x$source)}}"),
    cli::format_inline("backend: {.val {x$backend}}  |  dtype: {.val {x$dtype}}"),
    cli::format_inline("size: {d[1]} x {d[2]} px  |  levels: {x$n_levels}  |  bands: {x$n_bands}")
  )
  if (spectral) {
    wl <- range(x$wavelengths, na.rm = TRUE)
    lines <- c(lines, cli::format_inline(
      "spectral: {wl[1]}-{wl[2]} {x$wavelength_unit}"
    ))
  }
  lines <- c(lines, cli::format_inline(
    "pixel size: {x$pixel_size[1]} x {x$pixel_size[2]} {x$pixel_unit}"
  ))
  lines
}

#' @export
print.annot_image <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

#' @export
summary.annot_image <- function(object, ...) {
  print(object, ...)
  invisible(at_bands(object))
}

#' @export
dim.annot_image <- function(x) {
  c(x$level_dims[[1]], x$n_bands)
}
