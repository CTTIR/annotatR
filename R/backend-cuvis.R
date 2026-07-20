# Cubert hyperspectral backend via `cuvis.r` (optional). Reads .cu3 / .cu3s and
# populates per-band wavelengths. Single pyramid level.

.cuvis_read <- function(path, ...) {
  if (!requireNamespace("cuvis.r", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.val cuvis} backend requires package {.pkg cuvis.r}, which is not installed.",
      "i" = "Install it from the Cubert cuvis.r distribution.",
      "i" = "See available backends with {.fn at_backend_list}."
    ))
  }
  # cuvis.r exposes a session/measurement API; the exact call surface depends on
  # the installed SDK version. Kept behind the availability guard.
  mesu <- cuvis.r::Measurement$new(path) # nocov
  cube <- mesu$get_data()[["cube"]] # nocov
  arr <- aperm(cube$array, c(2, 1, 3)) # nocov -> [y, x, band]
  wl <- cube$wavelength # nocov
  new_annot_image( # nocov
    source = path, backend = "cuvis",
    dims = c(dim(arr)[2], dim(arr)[1]), n_levels = 1L,
    level_dims = list(c(dim(arr)[2], dim(arr)[1])),
    n_bands = dim(arr)[3], wavelengths = wl, wavelength_unit = "nm",
    pixel_size = c(1, 1), pixel_unit = "px", dtype = "float32",
    handle = list(data = arr), meta = list()
  )
}

.cuvis_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$data
  bs <- if (is.null(bands)) seq_len(dim(arr)[3]) else bands
  arr[yrange[1]:yrange[2], xrange[1]:xrange[2], bs, drop = FALSE]
}

.cuvis_detect <- function(path) {
  grepl("\\.(cu3|cu3s)$", path, ignore.case = TRUE)
}

.cuvis_available <- function() requireNamespace("cuvis.r", quietly = TRUE)
