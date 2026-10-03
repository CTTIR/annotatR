# The image backend system: a registry mapping backend names to reader
# implementations, plus the universal tile accessor and image reader that
# everything upstream uses. New formats register without touching core code.

# The registry is a package-private environment. Availability of a backend's
# optional dependencies is checked lazily at read time, never at load time, so a
# missing optional package never breaks package loading.
.backend_registry <- new.env(parent = emptyenv())

# Detection priority: more specific backends are tried before general ones so a
# .tif that is really an OME-TIFF is not claimed by the plain raster backend.
.backend_priority <- c("envi", "cuvis", "tivita", "ometiff", "tiff", "raster")

new_annot_backend <- function(name, read_fn, tile_fn, detect_fn, available_fn,
                              description, extensions, capabilities = list(), close_fn = NULL) {
  structure(
    list(
      name         = name,
      read_fn      = read_fn,
      tile_fn      = tile_fn,
      detect_fn    = detect_fn,
      available_fn = available_fn,
      description  = description,
      extensions   = extensions,
      capabilities = capabilities,
      close_fn     = close_fn
    ),
    class = "annot_backend"
  )
}

#' Register an image backend
#'
#' Backends are how annotatR reads image formats. Each supplies functions to
#' read an image's metadata, fetch tiles, detect whether it can read a file, and
#' report whether its optional dependencies are installed.
#'
#' @param name Single string backend name (unique).
#' @param read_fn `function(path, ...)` returning an [annot_image].
#' @param tile_fn `function(img, level, xrange, yrange, bands)` returning a
#'   numeric array `[y, x, band]`.
#' @param detect_fn `function(path)` returning `TRUE` if the backend can read the
#'   file.
#' @param available_fn `function()` returning `TRUE` if the backend's
#'   dependencies are installed.
#' @param description Single string human-readable description.
#' @param extensions Character vector of file extensions the backend handles.
#' @param capabilities Additive list declaring metadata_only, window_read,
#'   samples and io. Omitted capabilities are unknown. Readers can override
#'   these per image in meta$capabilities.
#' @param close_fn Optional function(img) releasing runtime resources.
#' @param call The calling environment, for error reporting.
#'
#' @return The registered `annot_backend`, invisibly.
#' @family backends
#' @seealso [at_backend_list()], [at_read_image()]
#' @export
at_backend_register <- function(name, read_fn, tile_fn, detect_fn, available_fn,
                                description = "", extensions = character(),
                                call = rlang::caller_env(),
                                capabilities = list(metadata_only=NA,window_read=NA,samples="unqualified",io="unknown"),
                                close_fn = NULL) {
  .check_string(name, call = call)
  stopifnot(is.function(read_fn), is.function(tile_fn), is.function(detect_fn),
            is.function(available_fn))
  stopifnot(is.list(capabilities), is.null(close_fn) || is.function(close_fn))
  b <- new_annot_backend(name, read_fn, tile_fn, detect_fn, available_fn,
                         description, as.character(extensions), capabilities, close_fn)
  assign(name, b, envir = .backend_registry)
  invisible(b)
}

#' List registered image backends
#'
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with columns `name` (character), `description`
#'   (character), `extensions` (character, comma-separated), and `available`
#'   (logical), plus metadata_only and window_read (logical; NA when unknown).
#'   A 0-row tibble with these columns when nothing is registered.
#' @family backends
#' @export
#' @examples
#' at_backend_list()
at_backend_list <- function(call = rlang::caller_env()) {
  nms <- ls(.backend_registry, sorted = TRUE)
  if (length(nms) == 0L) {
    return(tibble::tibble(
      name = character(0), description = character(0),
      extensions = character(0), available = logical(0), metadata_only=logical(0), window_read=logical(0)
    ))
  }
  tibble::tibble(
    name        = nms,
    description = vapply(nms, function(n) .backend_registry[[n]]$description, character(1)),
    extensions  = vapply(nms, function(n) paste(.backend_registry[[n]]$extensions, collapse = ", "), character(1)),
    available   = vapply(nms, function(n) isTRUE(tryCatch(.backend_registry[[n]]$available_fn(), error = function(e) FALSE)), logical(1)),
    metadata_only = vapply(nms,function(n) .backend_registry[[n]]$capabilities[["metadata_only"]] %||% NA,logical(1)),
    window_read = vapply(nms,function(n) .backend_registry[[n]]$capabilities[["window_read"]] %||% NA,logical(1))
  )
}

#' Get a registered backend
#'
#' @param name Single string backend name.
#' @param call The calling environment, for error reporting.
#' @return The `annot_backend` object.
#' @family backends
#' @export
at_backend_get <- function(name, call = rlang::caller_env()) {
  .check_string(name, call = call)
  if (!exists(name, envir = .backend_registry, inherits = FALSE)) {
    cli::cli_abort(
      c(
        "No backend named {.val {name}}.",
        "i" = "Registered backends: {.val {ls(.backend_registry, sorted = TRUE)}}."
      ),
      call = call
    )
  }
  get(name, envir = .backend_registry, inherits = FALSE)
}

#' Detect the backend for a file
#'
#' @param path Single string file path.
#' @param call The calling environment, for error reporting.
#' @return The name of the first available backend (in priority order) that can
#'   read `path`. Errors informatively if none can.
#' @family backends
#' @export
at_backend_detect <- function(path, call = rlang::caller_env()) {
  .check_string(path, call = call)
  registered <- ls(.backend_registry, sorted = FALSE)
  order <- c(intersect(.backend_priority, registered), setdiff(registered, .backend_priority))
  matched <- character()
  for (n in order) {
    b <- .backend_registry[[n]]
    can <- isTRUE(tryCatch(b$detect_fn(path), error = function(e) FALSE))
    if (can) {
      matched <- c(matched, n)
      if (isTRUE(tryCatch(b$available_fn(), error = function(e) FALSE))) {
        return(n)
      }
      if (n %in% c("tiff","ometiff")) {
        cli::cli_abort("Raw {n} capability requires its optional reader package(s), which are not installed. See at_backend_list(); explicit backend = 'raster' selects display conversion.",call=call)
      }
    }
  }
  if (length(matched) > 0L) {
    cli::cli_abort(
      c(
        "No available backend can read {.path {path}}.",
        "x" = "{cli::qty(length(matched))}The matching backend{?s} {?is/are} not installed: {.val {matched}}.",
        "i" = "Install the required optional package(s); see {.fn at_backend_list}."
      ),
      call = call
    )
  }
  cli::cli_abort(
    c(
      "No backend recognises {.path {path}}.",
      "i" = "Supported extensions are listed by {.fn at_backend_list}."
    ),
    call = call
  )
}

#' Read an image
#'
#' Read an image into a lightweight [annot_image] handle, auto-detecting the
#' backend from the file unless one is named.
#'
#' @param path Single string path to an image file.
#' @param backend Optional backend name; auto-detected when `NULL`.
#' @param ... Passed to the backend's reader.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_image].
#' @family images
#' @family backends
#' @seealso [at_backend_list()], [at_tile()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' img <- at_read_image(at_example_path("tissue"))
#' at_dims(img)
at_read_image <- function(path, backend = NULL, ..., call = rlang::caller_env()) {
  .check_file(path, call = call)
  path <- normalizePath(path, mustWork = TRUE)
  reader_options <- list(...)
  if (!.serializable_options(reader_options)) stop("Reader options must be serializable values, not runtime handles or functions.")
  options_identity <- tryCatch(
    .identity_fingerprint(reader_options),
    error = function(e) {
      cli::cli_abort(
        c(
          "Reader options must be serializable.",
          "x" = "Could not record the options for {.path {path}}: {conditionMessage(e)}"
        ),
        call = call
      )
    }
  )
  if (is.null(backend)) {
    backend <- at_backend_detect(path, call = call)
  }
  b <- at_backend_get(backend, call = call)
  if (!isTRUE(tryCatch(b$available_fn(), error = function(e) FALSE))) {
    cli::cli_abort(
      c(
        "Backend {.val {backend}} is not available.",
        "x" = "Its required optional package(s) are not installed."
      ),
      call = call
    )
  }
  img <- b$read_fn(path, ...)
  .check_image(img, arg = "backend result", call = call)
  .check_provenance_keys(img, "meta", "image source")
  .check_provenance_keys(img[["meta"]], "reader_contract", "image reader contract")
  generation <- .new_identity_id("read")
  img$source <- path
  img$source_descriptor <- list(
    schema_version = .source_schema,
    signature = .source_signature(path),
    files = if (is.list(img[["handle"]])) img[["handle"]][["files"]] else NULL,
    path = path,
    backend = backend,
    options = reader_options,
    options_identity = options_identity,
    reader_contract = img[["meta"]][["reader_contract"]]
  )
  if (is.list(img[["meta"]]) && is.null(img[["meta"]][["capabilities"]])) {
    img[["meta"]][["capabilities"]] <- b[["capabilities"]]
  }
  img$read_generation <- generation
  img$cache_identity <- generation
  img
}

#' Read a tile from an image
#'
#' The single, format-independent tile accessor. Returns a numeric array with
#' dimensions `[y, x, band]` — always three-dimensional, even for a single band.
#'
#' @param img An [annot_image].
#' @param level Integer pyramid level. Default `0`.
#' @param xrange,yrange Optional integer `c(min, max)` pixel ranges (1-based,
#'   inclusive) at `level`. `NULL` (default) means the full extent.
#' @param bands Optional integer band indices. `NULL` (default) means all bands.
#' @param call The calling environment, for error reporting.
#'
#' @return A numeric array with dimensions `[y, x, band]`.
#' @family images
#' @family backends
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' img <- at_example_image("tissue")
#' dim(at_tile(img, xrange = c(1, 16), yrange = c(1, 16)))
at_tile <- function(img, level = 0L, xrange = NULL, yrange = NULL, bands = NULL,
                    call = rlang::caller_env()) {
  .check_image(img, call = call)
  level <- .check_count(level, call = call)
  if (level > img$n_levels - 1L) {
    cli::cli_abort(
      c("{.arg level} exceeds the available pyramid levels.",
        "x" = "Level {level} requested; levels {.val {0:(img$n_levels - 1L)}} exist."),
      call = call
    )
  }
  d <- at_dims(img, level)
  xrange <- .validate_range(xrange, d[1], "xrange", call)
  yrange <- .validate_range(yrange, d[2], "yrange", call)
  if (!is.null(bands)) {
    if (!is.numeric(bands) || !length(bands) || any(!is.finite(bands)) ||
        any(bands != trunc(bands)) || any(bands < 1 | bands > img$n_bands)) {
      cli::cli_abort("bands are out of range or invalid; use finite whole band indices.",call=call)
    }
    bands <- as.integer(bands)
    if (any(bands < 1L) || any(bands > img$n_bands)) {
      cli::cli_abort(
        c("{.arg bands} out of range.",
          "x" = "Bands must be in {.val {1:img$n_bands}}; got {.val {bands}}."),
        call = call
      )
    }
  }
  img <- .reopen_image(img, require_pixels = TRUE)
  b <- at_backend_get(img[["backend"]], call = call)
  key <- .tile_key(img, level, xrange, yrange, bands)
  cached <- .tile_cache_get(key)
  if (!is.null(cached)) {
    return(cached)
  }
  arr <- b$tile_fn(img, level, xrange, yrange, bands)
  if (isTRUE(img$handle[["windowed"]]) && .source_status(img)!="available") {
    cli::cli_abort("Image source changed during window read; revalidate with at_relink_source().")
  }
  # Guarantee a 3D [y, x, band] array.
  if (length(dim(arr)) == 2L) {
    arr <- array(arr, dim = c(dim(arr), 1L))
  }
  .tile_cache_put(key, arr)
  arr
}

# Validate an optional pixel range against an extent; return c(min, max).
.validate_range <- function(range, extent, arg, call) {
  if (is.null(range)) {
    return(c(1L, extent))
  }
  if (!is.numeric(range) || length(range) != 2L || anyNA(range)) {
    cli::cli_abort(
      c("{.arg {arg}} must be a length-2 numeric range or {.code NULL}.",
        "x" = "You supplied {.cls {class(range)[1]}} of length {length(range)}."),
      call = call
    )
  }
  range <- as.integer(round(range))
  if (range[1] < 1L || range[2] > extent || range[1] > range[2]) {
    cli::cli_abort(
      c("{.arg {arg}} is out of bounds.",
        "x" = "Requested [{range[1]}, {range[2]}] but the extent is [1, {extent}]."),
      call = call
    )
  }
  range
}
