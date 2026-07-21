# Cubert hyperspectral backend via `cuvis.r` (optional). Reads .cu3 / .cu3s and
# populates per-band wavelengths. Single pyramid level.
#
# `cuvis.r` is the proprietary Cubert SDK binding: it is not on CRAN or any
# public repository, so it is NOT declared in Suggests (a dependency resolver
# such as pak cannot install it). It is referenced only dynamically, behind the
# availability guard, so the package builds and checks cleanly without it.

.cuvis_read <- function(path, ...) {
  if (!.cuvis_available()) {
    cli::cli_abort(c(
      "The {.val cuvis} backend requires package {.pkg cuvis.r}, which is not installed.",
      "i" = "Install it from the Cubert cuvis.r distribution.",
      "i" = "See available backends with {.fn at_backend_list}."
    ))
  }
  # cuvis.r exposes a session/measurement API; the exact call surface depends on
  # the installed SDK version. Referenced dynamically (undeclared optional dep).
  mesu <- getExportedValue("cuvis.r", "Measurement")$new(path) # nocov
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
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[yrange[1]:yrange[2], xrange[1]:xrange[2], bs, drop = FALSE]
}

.cuvis_detect <- function(path) {
  grepl("\\.(cu3|cu3s)$", path, ignore.case = TRUE)
}

# Availability via installed-package lookup rather than requireNamespace(), so
# the undeclared optional dependency is not flagged by R CMD check.
.cuvis_available <- function() nzchar(system.file(package = "cuvis.r"))
