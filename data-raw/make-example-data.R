# Generate the bundled example data into inst/extdata/.
# Run with: Rscript data-raw/make-example-data.R
# Deterministic (seeded); total inst/extdata must stay < 4 MB.

set.seed(20260720)
outdir <- file.path("inst", "extdata")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

# ---- 1. example_tissue.png : 512x512 RGB, three visually distinct regions ----

make_tissue <- function(sz = 512L) {
  gx <- matrix(rep(seq_len(sz), each = sz), sz, sz) / sz
  gy <- matrix(rep(seq_len(sz), times = sz), sz, sz) / sz
  # Region masks: a stromal background, a rounded "tumour" nest, a necrotic band.
  r_tumour <- ((gx - 0.35)^2 + (gy - 0.4)^2) < 0.03
  r_necro <- (gy > 0.72)
  base_r <- 0.62 + 0.08 * gx
  base_g <- 0.45 + 0.05 * gy
  base_b <- 0.60 + 0.05 * gx
  base_r[r_tumour] <- 0.75; base_g[r_tumour] <- 0.35; base_b[r_tumour] <- 0.65
  base_r[r_necro] <- 0.40; base_g[r_necro] <- 0.32; base_b[r_necro] <- 0.30
  noise <- function() matrix(stats::rnorm(sz * sz, 0, 0.03), sz, sz)
  arr <- array(0, dim = c(sz, sz, 3))
  arr[, , 1] <- pmin(pmax(base_r + noise(), 0), 1)
  arr[, , 2] <- pmin(pmax(base_g + noise(), 0), 1)
  arr[, , 3] <- pmin(pmax(base_b + noise(), 0), 1)
  arr
}

tissue <- make_tissue()
img <- magick::image_read(as.raster(tissue))
img <- magick::image_convert(img, matte = FALSE) # drop alpha -> RGB
magick::image_write(img, file.path(outdir, "example_tissue.png"), format = "png")

# ---- 2. example_multiplex.tif : 512x512 x 4 uint16, pyramidal L0/L1/L2 --------

multiplex_level <- function(sz) {
  gx <- matrix(rep(seq_len(sz), each = sz), sz, sz) / sz
  gy <- matrix(rep(seq_len(sz), times = sz), sz, sz) / sz
  dapi <- 0.3 + 0.4 * (sin(gx * 12) * sin(gy * 12))^2          # nuclei-like
  cd3 <- as.numeric(((gx - 0.3)^2 + (gy - 0.35)^2) < 0.02)     # T-cell nest
  cd8 <- as.numeric(((gx - 0.32)^2 + (gy - 0.37)^2) < 0.008)   # CD8 subset
  panck <- as.numeric(gx > 0.55 & gy < 0.5)                    # epithelium
  a <- array(0, dim = c(sz, sz, 4))
  a[, , 1] <- pmin(pmax(dapi, 0), 1)
  a[, , 2] <- cd3 * 0.9
  a[, , 3] <- cd8 * 0.9
  a[, , 4] <- panck * 0.85
  a
}

levels <- list(multiplex_level(512L), multiplex_level(256L), multiplex_level(128L))
tiff::writeTIFF(levels, file.path(outdir, "example_multiplex.tif"),
                bits.per.sample = 16L, compression = "LZW")

# ---- 3. example_cube : 128x128 x 40 bands, ENVI BSQ uint16, 3 signatures ------

make_cube <- function(sz = 128L, nb = 40L) {
  wl <- seq(450, 900, length.out = nb)
  # Three endmember spectra (reflectance 0-1).
  sig1 <- 0.2 + 0.6 * exp(-((wl - 550) / 40)^2)               # green peak
  sig2 <- 0.15 + 0.7 * (wl > 700)                              # NIR step
  sig3 <- 0.5 + 0.3 * sin((wl - 450) / 60)                     # oscillating
  gx <- matrix(rep(seq_len(sz), each = sz), sz, sz) / sz
  gy <- matrix(rep(seq_len(sz), times = sz), sz, sz) / sz
  reg1 <- ((gx - 0.3)^2 + (gy - 0.3)^2) < 0.02
  reg2 <- ((gx - 0.7)^2 + (gy - 0.6)^2) < 0.02
  arr <- array(0, dim = c(sz, sz, nb)) # [y, x, band]
  for (b in seq_len(nb)) {
    plane <- matrix(sig3[b], sz, sz)
    plane[reg1] <- sig1[b]
    plane[reg2] <- sig2[b]
    plane <- plane + matrix(stats::rnorm(sz * sz, 0, 0.01), sz, sz)
    arr[, , b] <- pmin(pmax(plane, 0), 1)
  }
  list(arr = arr, wl = wl)
}

cube <- make_cube()
sz <- 128L; nb <- 40L
u16 <- as.integer(round(cube$arr * 65535))
# BSQ order: band, then line, then sample (sample fastest).
vec <- as.vector(aperm(array(u16, dim = c(sz, sz, nb)), c(2, 1, 3)))
con <- file(file.path(outdir, "example_cube.dat"), "wb")
writeBin(as.integer(vec), con, size = 2L)
close(con)
hdr <- c(
  "ENVI",
  "description = {annotatR synthetic example cube}",
  sprintf("samples = %d", sz),
  sprintf("lines = %d", sz),
  sprintf("bands = %d", nb),
  "header offset = 0",
  "file type = ENVI Standard",
  "data type = 12",
  "interleave = bsq",
  "byte order = 0",
  paste0("wavelength units = Nanometers"),
  paste0("wavelength = {", paste(round(cube$wl, 1), collapse = ", "), "}")
)
writeLines(hdr, file.path(outdir, "example_cube.hdr"))

# ---- 4. example_annotations.geojson : reference annotations for the tissue ----

feature <- function(coords, label) {
  list(
    type = "Feature",
    properties = list(label = label, level = 0L),
    geometry = list(
      type = "Polygon",
      coordinates = list(coords)
    )
  )
}
poly <- function(x0, y0, x1, y1) {
  list(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0))
}
fc <- list(
  type = "FeatureCollection",
  features = list(
    feature(poly(120, 150, 260, 290), "tumour"),
    feature(poly(0, 370, 512, 512), "necrosis"),
    feature(poly(300, 30, 480, 220), "stroma")
  )
)
jsonlite::write_json(fc, file.path(outdir, "example_annotations.geojson"),
                     auto_unbox = TRUE, digits = 6)

# ---- Report ----------------------------------------------------------------

files <- list.files(outdir, full.names = TRUE)
info <- file.info(files)
cat(sprintf("%-32s %8.1f KB\n", basename(files), info$size / 1024), sep = "")
cat(sprintf("TOTAL: %.2f MB\n", sum(info$size) / 1024^2))
