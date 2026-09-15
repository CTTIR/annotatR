# Cubert hyperspectral backend via the optional `cuvis.r` binding to the
# proprietary CUVIS SDK. Reads `.cu3s` session files (and `.cu3` where the
# installed SDK accepts them) and records SDK, device, processing-mode and
# calibration metadata. No proprietary library is copied into annotatR; the
# SDK is found at use time only.
#
# `cuvis.r` is not on CRAN or any public repository, so it is NOT declared in
# Suggests (a dependency resolver such as pak cannot install it). It is called
# dynamically behind an availability guard, so annotatR builds, loads and
# checks cleanly without it. Tested against cuvis.r 0.1.0 with CUVIS SDK 3.5.3.

.cuvis_tested_versions <- c(cuvis.r = "0.1.0", sdk = "3.5.3")

# Map CUVIS processing modes to annotatR value semantics.
.cuvis_value_units <- c(
  Raw = "raw", DarkSubtract = "raw", Reflectance = "reflectance",
  SpectralRadiance = "radiance", Preview = "unknown"
)

.cuvis_fn <- function(name) getExportedValue("cuvis.r", name)

# Availability: the package must be installed and its SDK library usable.
# Returns list(available, reason).
.cuvis_status <- function() {
  if (!nzchar(system.file(package = "cuvis.r"))) {
    return(list(available = FALSE, reason = "package cuvis.r is not installed"))
  }
  ok <- tryCatch(isTRUE(.cuvis_fn("cuvis_available")()), error = function(e) FALSE)
  if (!ok) {
    return(list(available = FALSE, reason = "cuvis.r is installed but the CUVIS SDK library is not usable"))
  }
  list(available = TRUE, reason = NA_character_)
}

.cuvis_available <- function() isTRUE(.cuvis_status()$available)

.cuvis_read <- function(path, measurement = 1L, value_unit = NULL, ...,
                        call = rlang::caller_env()) {
  st <- .cuvis_status()
  if (!st$available) {
    .at_abort(c(
      "The {.val cuvis} backend is unavailable: {st$reason}.",
      "i" = "Install cuvis.r and the Cubert CUVIS SDK, or read an ENVI/TIFF export made with the SDK.",
      "i" = "See available backends with {.fn at_backend_list}."
    ), class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call)
  }
  measurement <- .check_count(measurement, min = 1L, call = call)
  .cuvis_fn("cuvis_init")()
  session <- tryCatch(
    suppressWarnings(.cuvis_fn("cuvis_session")(path)),
    error = function(e) {
      .at_abort(c("The CUVIS SDK could not open {.path {basename(path)}}.",
                  "x" = conditionMessage(e)),
                class = "io", code = "IMAGE_UNAVAILABLE", call = call)
    }
  )
  mesu <- .cuvis_fn("cuvis_get_measurement")(session, measurement)
  if (is.null(mesu)) {
    .at_abort("Measurement {measurement} does not exist in {.path {basename(path)}}.",
              class = "io", code = "IMAGE_UNAVAILABLE", call = call)
  }
  cube <- .cuvis_fn("cuvis_get_cube")(mesu) # [rows = y, cols = x, bands]
  md <- tryCatch(.cuvis_fn("cuvis_get_metadata")(mesu), error = function(e) list())
  sdk_version <- tryCatch(.cuvis_fn("cuvis_version")(), error = function(e) NA_character_)
  wl <- as.numeric(attr(cube, "wavelengths"))
  d <- dim(cube)
  if (length(d) == 2L) {
    d <- c(d, 1L)
  }
  arr <- array(as.double(cube), dim = d)
  mode_codes <- c(Raw = 0L, DarkSubtract = 1L, Reflectance = 2L, SpectralRadiance = 3L, Preview = 5L)
  mode <- names(mode_codes)[match(as.integer(md$processing_mode %||% NA_integer_), mode_codes)]
  mode <- if (length(mode) == 1L && !is.na(mode)) mode else "unknown"
  calib <- list(
    status = if (mode %in% c("Reflectance", "SpectralRadiance")) "applied_by_sdk" else "missing",
    processing_mode = mode,
    integration_time_ms = md$integration_time %||% NA_real_,
    averages = md$averages %||% NA_real_,
    distance = md$distance %||% NA_real_,
    product_name = md$product_name %||% NA_character_,
    serial_number = md$serial_number %||% NA_character_,
    assembly = md$assembly %||% NA_character_,
    sdk_version = sdk_version
  )
  new_annot_image(
    source = path, backend = "cuvis",
    dims = c(d[2], d[1]), n_levels = 1L, level_dims = list(c(d[2], d[1])),
    n_bands = d[3], band_names = NA_character_,
    wavelengths = if (length(wl) == d[3]) wl else NULL,
    wavelength_unit = if (length(wl) == d[3]) "nm" else NULL,
    pixel_size = c(1, 1), pixel_unit = "px", dtype = "float64",
    handle = list(data = arr),
    meta = list(
      vendor = "Cubert", instrument = md$product_name %||% NA_character_,
      acquisition_id = if (.is_string(md$name)) paste0("sha256:", substr(.sha256_bytes(md$name), 1, 16)) else NA_character_,
      format = if (grepl("\\.cu3s$", path, ignore.case = TRUE)) "cu3s" else "cu3",
      measurement_index = measurement, measurement_count = session$count %||% NA_integer_,
      value_unit = value_unit %||% (.cuvis_value_units[[mode]] %||% "unknown"),
      calibration = calib, calibration_digest = .digest_json(calib),
      pan_sharpened = NA, pan_sharpening_status = "not_reported_by_sdk",
      sdk = list(package = "cuvis.r", package_version = .pkg_version_or_na("cuvis.r"),
                 sdk_version = sdk_version),
      axis_order = "y,x,band", window_read = FALSE,
      capture_time_ms = md$capture_time %||% NA_real_
    )
  )
}

.cuvis_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$data
  if (is.null(arr)) {
    .at_abort("This Cubert image handle holds no cube; re-open it with {.fn at_read_image}.",
              class = "io", code = "IMAGE_UNAVAILABLE")
  }
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[yrange[1]:yrange[2], xrange[1]:xrange[2], bs, drop = FALSE]
}

.cuvis_detect <- function(path) {
  grepl("\\.(cu3|cu3s)$", path, ignore.case = TRUE)
}

#' Export a Cubert measurement to a portable ENVI cube
#'
#' The portable fallback for Cubert data: the CUVIS SDK itself writes an ENVI
#' export, which annotatR (and tools without the SDK) can then read through the
#' `envi` backend. Requires `cuvis.r` and a usable CUVIS SDK.
#'
#' @param path Path to a `.cu3s` session file.
#' @param dir Output directory for the SDK's ENVI export (created if needed).
#' @param measurement 1-based measurement index within the session.
#' @param call The calling environment, for error reporting.
#'
#' @return The files written into `dir` (character), invisibly.
#' @family backends
#' @family hsi
#' @export
#' @examples
#' \dontrun{
#' at_cubert_export_envi("measurement.cu3s", tempfile("envi-"))
#' }
at_cubert_export_envi <- function(path, dir, measurement = 1L, call = rlang::caller_env()) {
  .check_file(path, call = call)
  .check_string(dir, call = call)
  st <- .cuvis_status()
  if (!st$available) {
    .at_abort("Cubert export is unavailable: {st$reason}.", class = "capability",
              code = "CAPABILITY_UNAVAILABLE", call = call)
  }
  .cuvis_fn("cuvis_init")()
  session <- suppressWarnings(.cuvis_fn("cuvis_session")(path))
  mesu <- .cuvis_fn("cuvis_get_measurement")(session, .check_count(measurement, min = 1L, call = call))
  before <- if (dir.exists(dir)) list.files(dir, recursive = TRUE, full.names = TRUE) else character()
  .cuvis_fn("cuvis_export_envi")(mesu, dir)
  after <- list.files(dir, recursive = TRUE, full.names = TRUE)
  invisible(setdiff(after, before))
}
