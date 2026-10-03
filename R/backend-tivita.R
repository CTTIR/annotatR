# Diaspective Vision Tivita hyperspectral backend.
#
# Two on-disk shapes are supported:
#   * an ENVI-conformant export (a `.hdr` text header plus a binary cube), read
#     through the ENVI backend; and
#   * a bare Tivita "SpecCube" (`*_SpecCube.dat`): big-endian float32 with three
#     leading header floats, laid out in numpy C-order as (cols = x, rows = y,
#     band) -- the band axis varies fastest, then rows (y), then columns (x).
#     This is what the Tivita camera and its Python tooling write, and it is NOT
#     any of the ENVI interleaves (BSQ/BIL/BIP), so it is decoded explicitly.

# Canonical Tivita SpecCube geometry: 640 columns (x) x 480 rows (y) x 100 bands
# spanning 500-995 nm in 5 nm steps, preceded by three float32 header values.
.TIVITA_NX <- 640L
.TIVITA_NY <- 480L
.TIVITA_NB <- 100L
.TIVITA_HEADER <- 3L

.tivita_wavelengths <- function(nb) if (nb == 100L) seq(500, 995, by = 5) else NULL

.tivita_speccube_bytes <- function(nx, ny, nb, header = .TIVITA_HEADER) {
  (as.double(nx) * ny * nb + header) * 4
}

# TRUE for a bare "*_SpecCube.dat" without a sibling ENVI header. An export that
# also ships a `.hdr` is left to the higher-priority envi backend, so the two
# never both claim a file.
.tivita_is_speccube <- function(path) {
  grepl("_SpecCube\\.dat$", path, ignore.case = TRUE) &&
    !file.exists(.envi_paths(path)$hdr)
}

.tivita_read_speccube <- function(path, nx = .TIVITA_NX, ny = .TIVITA_NY,
                                  nb = .TIVITA_NB, header = .TIVITA_HEADER,
                                  wavelengths = .tivita_wavelengths(nb), ...) {
  if (!is.numeric(header) || length(header)!=1L || !is.finite(header) ||
      header<0 || header!=trunc(header)) cli::cli_abort("SpecCube header must be a nonnegative whole float count.")
  expected <- .tivita_speccube_bytes(nx, ny, nb, header)
  size <- file.info(path)$size
  if (!isTRUE(size == expected)) {
    cli::cli_abort(c(
      "{.path {path}} is not a {nx}x{ny}x{nb} Tivita SpecCube.",
      "x" = "Expected a file size of {expected} bytes but found {size %||% NA}.",
      "i" = "Pass {.arg nx}/{.arg ny}/{.arg nb} to {.fn at_read_image} for a non-standard cube."
    ))
  }
  layout <- .binary_layout(path,c(nx,ny,nb),4,header*4,eager=FALSE)
  layout$interleave <- "speccube"
  layout$endian <- "big"
  spectral <- !is.null(wavelengths) && length(wavelengths) == nb
  new_annot_image(
    source = path, backend = "tivita",
    dims = c(nx, ny), n_levels = 1L, level_dims = list(c(nx, ny)),
    n_bands = nb, band_names = NA_character_,
    wavelengths = if (spectral) wavelengths else NULL,
    wavelength_unit = if (spectral) "nm" else NULL,
    pixel_size = c(1, 1), pixel_unit = "px", dtype = "float32",
    handle = list(windowed=TRUE,path=path,layout=layout,
      spec=list(what="double",size=4L,signed=TRUE),files=.source_files(c(payload=path))),
    meta = list(vendor = "Diaspective Vision Tivita", format = "SpecCube",
      reader_contract=list(axes="yxb",samples="raw-scalar-v1"),capabilities=.window_capabilities("binary"))
  )
}

.tivita_read <- function(path, ...) {
  p <- .envi_paths(path)
  if (!is.na(p$dat) && file.exists(p$dat) && file.exists(p$hdr)) {
    img <- .envi_read(path, ...)
    img$backend <- "tivita"
    img$meta$vendor <- "Diaspective Vision Tivita"
    return(img)
  }
  if (.tivita_is_speccube(path)) {
    return(.tivita_read_speccube(path, ...))
  }
  cli::cli_abort(c(
    "Cannot read {.path {path}} as a Tivita cube.",
    "x" = "It is neither an ENVI export (a {.file .hdr} plus binary) nor a {.file *_SpecCube.dat}.",
    "i" = "Export the cube in ENVI format (a {.file .hdr} plus binary), which is supported."
  ))
}

.tivita_tile <- function(img, level, xrange, yrange, bands) {
  .envi_tile(img, level, xrange, yrange, bands)
}

# Auto-detect a bare SpecCube; ENVI-with-header exports go to the envi backend.
.tivita_detect <- function(path) .tivita_is_speccube(path)

.tivita_available <- function() TRUE
