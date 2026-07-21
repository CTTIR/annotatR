# Raster backend: PNG, JPEG, and single-plane TIFF via `magick` or `tiff`. No
# pyramid (n_levels = 1). This is the fallback path and the one used by the
# raster example data, so it must work with at most one optional package.

.raster_band_names <- function(nb) {
  switch(
    as.character(nb),
    "1" = "Gray",
    "2" = c("Gray", "Alpha"),
    "3" = c("R", "G", "B"),
    "4" = c("R", "G", "B", "Alpha"),
    paste0("Band ", seq_len(nb))
  )
}

.raster_read <- function(path, ...) {
  if (requireNamespace("magick", quietly = TRUE)) {
    m <- magick::image_read(path)
    dat <- magick::image_data(m)
    d <- dim(dat) # [channels, width, height]
    arr <- aperm(array(as.integer(dat), d), c(3, 2, 1)) # [y, x, band], 0-255
    storage.mode(arr) <- "double"
    w <- d[2]
    h <- d[3]
    nb <- d[1]
    dtype <- "uint8"
  } else if (requireNamespace("tiff", quietly = TRUE)) {
    t <- tiff::readTIFF(path, as.is = FALSE)
    if (length(dim(t)) == 2L) {
      t <- array(t, dim = c(dim(t), 1L))
    }
    arr <- t * 255 # readTIFF returns [0, 1]; match the 0-255 convention
    h <- dim(arr)[1]
    w <- dim(arr)[2]
    nb <- dim(arr)[3]
    dtype <- "uint8"
  } else {
    cli::cli_abort(c(
      "The {.val raster} backend requires package {.pkg magick} or {.pkg tiff}.",
      "i" = "Install one with {.code install.packages(\"magick\")}."
    ))
  }
  new_annot_image(
    source = path, backend = "raster",
    dims = c(w, h), n_levels = 1L, level_dims = list(c(w, h)),
    n_bands = nb, band_names = .raster_band_names(nb),
    pixel_size = c(1, 1), pixel_unit = "px", dtype = dtype,
    handle = list(data = arr), meta = list()
  )
}

.raster_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$data
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.raster_detect <- function(path) {
  grepl("\\.(png|jpe?g|bmp|gif|tiff?)$", path, ignore.case = TRUE)
}

.raster_available <- function() {
  requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
}
