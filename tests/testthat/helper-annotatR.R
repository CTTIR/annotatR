# Shared test fixtures for annotatR.
#
# Fixtures are deterministic: the identifier counter is reset where identifier
# stability matters, and nothing depends on wall-clock time or locale. Internal
# package objects are reachable directly from tests under testthat edition 3.

# ---- Image fixtures --------------------------------------------------------

# 10x10 single-band image for exact pixel arithmetic (the mask reference case).
tiny_image <- function() {
  new_annot_image(
    source = "tiny.tif", backend = "raster",
    dims = c(10L, 10L), n_levels = 1L, level_dims = list(c(10L, 10L)),
    n_bands = 1L, dtype = "uint8"
  )
}

# 100x100 three-band pyramidal image.
small_image <- function() {
  new_annot_image(
    source = "small.tif", backend = "tiff",
    dims = c(100L, 100L), n_levels = 3L,
    level_dims = list(c(100L, 100L), c(50L, 50L), c(25L, 25L)),
    n_bands = 3L, band_names = c("R", "G", "B"),
    pixel_size = c(0.5, 0.5), pixel_unit = "um", dtype = "uint16"
  )
}

# 32x32 ten-band spectral cube.
cube_image <- function() {
  new_annot_image(
    source = "cube.hdr", backend = "envi",
    dims = c(32L, 32L), n_levels = 1L, level_dims = list(c(32L, 32L)),
    n_bands = 10L, wavelengths = seq(450, 900, length.out = 10),
    wavelength_unit = "nm", dtype = "float32"
  )
}

# ---- ROI fixtures ----------------------------------------------------------

# An exact 3x3 square with lower-left corner at (2, 2): the mask reference ROI.
square_roi <- function(label = "square") {
  at_roi_rect(2, 2, 5, 5, label = label)
}

# A triangle with vertices on exact pixel centres.
tri_roi <- function(label = "tri") {
  co <- matrix(c(1, 1, 8, 1, 4, 7), ncol = 2, byrow = TRUE)
  at_roi_polygon(co, label = label)
}

# A polygon with a hole (a donut).
donut_roi <- function(label = "donut") {
  outer <- matrix(c(0, 0, 10, 0, 10, 10, 0, 10), ncol = 2, byrow = TRUE)
  inner <- matrix(c(3, 3, 7, 3, 7, 7, 3, 7), ncol = 2, byrow = TRUE)
  at_roi_polygon(list(outer, inner), label = label)
}

# Two deliberately overlapping rectangles.
overlap_pair <- function() {
  list(
    a = at_roi_rect(0, 0, 6, 6, label = "a"),
    b = at_roi_rect(4, 4, 10, 10, label = "b")
  )
}

# ---- Project and session fixtures ------------------------------------------

# A populated project with two layers.
demo_project <- function() {
  .reset_id_counter()
  img <- small_image()
  tissue <- at_layer("tissue", labels = "tissue")
  tissue <- at_layer_add(tissue, at_roi_rect(0, 0, 10, 10, label = "tissue"))
  tissue <- at_layer_add(tissue, at_roi_circle(50, 50, 5, label = "tissue"))
  tumour <- at_layer("tumour", labels = "tumour", style = at_style(z = 2L))
  tumour <- at_layer_add(tumour, at_roi_rect(20, 20, 40, 40, label = "tumour"))
  at_project(img, list(tissue, tumour), name = "demo")
}

# A session over `n` temporary image files.
demo_session <- function(n = 4L, labels = c("tumour", "stroma")) {
  dir <- tempfile("annotatR-session-")
  dir.create(dir)
  paths <- file.path(dir, paste0("img", seq_len(n), ".png"))
  for (p in paths) writeLines("placeholder", p)
  at_session(paths, labels = labels, out_dir = dir)
}
