# Diaspective Vision TIVITA hyperspectral backend.
#
# Two on-disk shapes are supported:
#   * an ENVI-conformant export (a `.hdr` text header plus a binary cube), read
#     through the ENVI backend; and
#   * a bare TIVITA "SpecCube" (`*_SpecCube.dat`) read ONLY through an explicit
#     profile: dimensions, number of leading header values, value width,
#     endianness, axis order, wavelengths and value unit. The known layout
#     (640 x 480 x 100, three leading big-endian float32 header values,
#     500-995 nm in 5 nm steps, numpy C-order with the band axis varying
#     fastest, then rows y, then columns x) is shipped as a named, overridable
#     profile -- not as a universal device claim. A `<cube>.tivita.json`
#     sidecar can declare a different device profile; when the file size
#     matches no declared profile the read aborts instead of guessing.

.TIVITA_DEFAULT_PROFILE <- "tivita_640x480x100_v1"

#' Declare a TIVITA SpecCube layout profile
#'
#' A profile states everything needed to decode a bare `*_SpecCube.dat` file;
#' annotatR never infers these from a file name. The default arguments describe
#' the documented 640 x 480 x 100-band layout (500-995 nm), which is a profile
#' like any other and can be replaced for a different device.
#'
#' @param name Profile identifier recorded in the image metadata.
#' @param width,height,bands Cube dimensions (columns x, rows y, bands).
#' @param header_values Number of leading values before the payload.
#' @param value_bytes Bytes per value (`4` for float32, `8` for float64).
#' @param endian `"big"` or `"little"`.
#' @param axis_order Storage order from slowest to fastest varying axis; only
#'   `"x,y,band"` (the numpy C-order TIVITA layout) is supported.
#' @param wavelengths Numeric band-centre wavelengths (length `bands`) or
#'   `NULL` when unknown.
#' @param wavelength_unit Wavelength unit, default `"nm"`.
#' @param value_unit What the values mean: one of `"raw"`, `"reflectance"`,
#'   `"radiance"`, `"intensity"`, `"absorbance"`, `"unknown"`.
#' @param call The calling environment, for error reporting.
#'
#' @return A list of class `at_tivita_profile`.
#' @family hsi
#' @family backends
#' @seealso [at_read_image()]
#' @export
#' @examples
#' at_tivita_profile()$bands
#' small <- at_tivita_profile("bench_4x3x2", width = 4, height = 3, bands = 2,
#'                            wavelengths = c(600, 700))
at_tivita_profile <- function(name = .TIVITA_DEFAULT_PROFILE, width = 640L, height = 480L,
                              bands = 100L, header_values = 3L, value_bytes = 4L,
                              endian = c("big", "little"), axis_order = "x,y,band",
                              wavelengths = seq(500, 995, by = 5), wavelength_unit = "nm",
                              value_unit = "reflectance", call = rlang::caller_env()) {
  .check_string(name, call = call)
  width <- .check_count(width, min = 1L, call = call)
  height <- .check_count(height, min = 1L, call = call)
  bands <- .check_count(bands, min = 1L, call = call)
  header_values <- .check_count(header_values, min = 0L, call = call)
  value_bytes <- .check_count(value_bytes, min = 1L, call = call)
  if (!value_bytes %in% c(4L, 8L)) {
    .at_abort("{.arg value_bytes} must be 4 or 8.", call = call)
  }
  endian <- .check_choice(endian, c("big", "little"), call = call)
  if (!identical(axis_order, "x,y,band")) {
    .at_abort("Only the {.val x,y,band} TIVITA storage order is supported.",
              code = "PROFILE_UNSUPPORTED", call = call)
  }
  if (!is.null(wavelengths)) {
    wavelengths <- suppressWarnings(as.numeric(unlist(wavelengths)))
    if (length(wavelengths) != bands) {
      .at_abort("{.arg wavelengths} must have one value per band ({bands}); got {length(wavelengths)}.",
                code = "PROFILE_INVALID", call = call)
    }
  }
  value_unit <- .check_choice(value_unit, .value_units, call = call)
  structure(
    list(name = name, width = width, height = height, bands = bands,
         header_values = header_values, value_bytes = value_bytes, endian = endian,
         axis_order = axis_order, wavelengths = wavelengths,
         wavelength_unit = wavelength_unit, value_unit = value_unit),
    class = "at_tivita_profile"
  )
}

.tivita_speccube_bytes <- function(profile) {
  (as.double(profile$width) * profile$height * profile$bands + profile$header_values) *
    profile$value_bytes
}

# Sidecar location for a SpecCube.
.tivita_sidecar <- function(path) {
  cand <- c(paste0(path, ".tivita.json"),
            sub("\\.dat$", ".tivita.json", path, ignore.case = TRUE))
  cand <- unique(cand[file.exists(cand)])
  if (length(cand)) cand[1] else NA_character_
}

# Build and validate a profile from a sidecar JSON document.
.tivita_profile_from_sidecar <- function(file, call = rlang::caller_env()) {
  doc <- .read_json_doc(file, max_bytes = 1024^2, call = call)
  .schema_assert(doc, "annotatr-hsi-v1", "tivita-profile", what = "TIVITA sidecar", call = call)
  .check_major_version(doc$profile_version, 1L, "TIVITA sidecar", call = call)
  at_tivita_profile(
    name = doc$name, width = doc$width, height = doc$height, bands = doc$bands,
    header_values = doc$header_values, value_bytes = doc$value_bytes,
    endian = doc$endian, axis_order = doc$axis_order,
    wavelengths = if (is.null(doc$wavelengths)) NULL else unlist(doc$wavelengths),
    wavelength_unit = doc$wavelength_unit %||% "nm",
    value_unit = doc$value_unit %||% "unknown", call = call
  )
}

# TRUE for a bare "*_SpecCube.dat" without a sibling ENVI header. An export that
# also ships a `.hdr` is left to the higher-priority envi backend, so the two
# never both claim a file.
.tivita_is_speccube <- function(path) {
  grepl("_SpecCube\\.dat$", path, ignore.case = TRUE) &&
    !file.exists(.envi_paths(path)$hdr)
}

.tivita_read_speccube <- function(path, profile = NULL, nx = NULL, ny = NULL, nb = NULL,
                                  header = NULL, wavelengths = NULL, value_unit = NULL,
                                  ..., call = rlang::caller_env()) {
  source_of_profile <- "explicit"
  legacy <- !is.null(nx) || !is.null(ny) || !is.null(nb) || !is.null(header)
  if (is.null(profile) && legacy) {
    # Legacy dimension arguments build an ad hoc profile. The canonical
    # 500-995 nm grid is applied only to 100-band cubes, as in annotatR 0.1.
    nb <- nb %||% 100L
    wl <- wavelengths %||% (if (as.integer(nb) == 100L) seq(500, 995, by = 5) else NULL)
    profile <- at_tivita_profile(
      name = "custom", width = nx %||% 640L, height = ny %||% 480L, bands = nb,
      header_values = header %||% 3L, wavelengths = wl, call = call
    )
    source_of_profile <- "arguments"
  }
  if (is.null(profile)) {
    side <- .tivita_sidecar(path)
    if (!is.na(side)) {
      profile <- .tivita_profile_from_sidecar(side, call = call)
      source_of_profile <- "sidecar"
    } else {
      profile <- at_tivita_profile(call = call)
      source_of_profile <- "default_profile"
    }
  }
  if (!inherits(profile, "at_tivita_profile")) {
    .at_abort("{.arg profile} must come from {.fn at_tivita_profile}.", call = call)
  }
  expected <- .tivita_speccube_bytes(profile)
  size <- file.info(path)$size
  if (!isTRUE(size == expected)) {
    .at_abort(c(
      "{.path {basename(path)}} does not match the {.val {profile$name}} SpecCube profile.",
      "x" = "Expected a file size of {format(expected, scientific = FALSE)} bytes but found {size %||% NA}.",
      "i" = "Declare the device layout with {.fn at_tivita_profile} or a {.file <cube>.tivita.json} sidecar; annotatR does not guess."
    ), code = "PROFILE_MISMATCH",
    details = list(profile = profile$name, expected_bytes = expected, actual_bytes = size),
    call = call)
  }
  con <- file(path, "rb")
  header_vals <- if (profile$header_values > 0L) {
    readBin(con, "double", n = profile$header_values, size = profile$value_bytes,
            endian = profile$endian)
  } else {
    numeric(0)
  }
  close(con)
  spectral <- !is.null(profile$wavelengths)
  new_annot_image(
    source = path, backend = "tivita",
    dims = c(profile$width, profile$height), n_levels = 1L,
    level_dims = list(c(profile$width, profile$height)),
    n_bands = profile$bands, band_names = NA_character_,
    wavelengths = if (spectral) profile$wavelengths else NULL,
    wavelength_unit = if (spectral) profile$wavelength_unit else NULL,
    pixel_size = c(1, 1), pixel_unit = "px",
    dtype = if (profile$value_bytes == 4L) "float32" else "float64",
    handle = list(dat = normalizePath(path), profile = unclass(profile)),
    meta = list(
      vendor = "Diaspective Vision Tivita", format = "SpecCube",
      profile = profile$name, profile_source = source_of_profile,
      header_bytes = profile$header_values * profile$value_bytes,
      header_values = as.list(header_vals),
      byte_order = profile$endian, interleave = "tivita_x_y_band",
      axis_order = "y,x,band", value_unit = value_unit %||% profile$value_unit,
      window_read = TRUE, calibration = list(status = "missing"),
      calibration_digest = NA_character_,
      profile_digest = .digest_json(c(unclass(profile)[setdiff(names(profile), "wavelengths")],
                                      list(wavelengths = as.list(profile$wavelengths))))
    )
  )
}

# Windowed SpecCube read. Storage index of (x, y, band), zero-based:
# header + ((x * height + y) * bands + band) * value_bytes.
.tivita_read_window <- function(dat, profile, xrange, yrange, bands) {
  nx <- xrange[2] - xrange[1] + 1L
  ny <- yrange[2] - yrange[1] + 1L
  H <- as.double(profile$height)
  B <- as.double(profile$bands)
  vb <- profile$value_bytes
  hb <- profile$header_values * vb
  out <- array(NA_real_, dim = c(ny, nx, length(bands)))
  con <- file(dat, "rb")
  on.exit(close(con), add = TRUE)
  for (ix in seq_len(nx)) {
    x <- xrange[1] - 1 + ix - 1
    off <- hb + ((x * H + (yrange[1] - 1)) * B) * vb
    seek(con, where = off, origin = "start", rw = "read")
    v <- readBin(con, "double", n = ny * profile$bands, size = vb, endian = profile$endian)
    if (length(v) != ny * profile$bands) {
      .at_abort("The SpecCube payload ended before the requested window.", code = "PAYLOAD_SHORT")
    }
    m <- matrix(v, nrow = profile$bands) # [band, y]
    out[, ix, ] <- t(m[bands, , drop = FALSE])
  }
  attr(out, "file_bytes") <- nx * ny * as.double(profile$bands) * vb
  out
}

.tivita_read <- function(path, ..., call = rlang::caller_env()) {
  p <- .envi_paths(path)
  if (!is.na(p$dat) && file.exists(p$dat) && file.exists(p$hdr)) {
    img <- .envi_read(path, ..., call = call)
    img$backend <- "tivita"
    img$meta$vendor <- "Diaspective Vision Tivita"
    return(img)
  }
  if (.tivita_is_speccube(path)) {
    return(.tivita_read_speccube(path, ..., call = call))
  }
  .at_abort(c(
    "Cannot read {.path {path}} as a Tivita cube.",
    "x" = "It is neither an ENVI export (a {.file .hdr} plus binary) nor a {.file *_SpecCube.dat}.",
    "i" = "Export the cube in ENVI format (a {.file .hdr} plus binary), which is supported."
  ), code = "FORMAT_UNRECOGNISED", call = call)
}

.tivita_tile <- function(img, level, xrange, yrange, bands) {
  if (!is.null(img$handle$profile)) {
    bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
    return(.tivita_read_window(img$handle$dat, img$handle$profile, xrange, yrange, bs))
  }
  .envi_tile(img, level, xrange, yrange, bands)
}

# Auto-detect a bare SpecCube; ENVI-with-header exports go to the envi backend.
.tivita_detect <- function(path) .tivita_is_speccube(path)

.tivita_available <- function() TRUE
