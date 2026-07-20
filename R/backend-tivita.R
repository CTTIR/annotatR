# Diaspective Vision Tivita hyperspectral backend.
#
# Many Tivita exports are ENVI-conformant, so the ENVI-compatible path is
# implemented by delegating to the ENVI reader. The proprietary binary layout is
# not documented in this environment and is deliberately not fabricated: reading
# such a file aborts with a message naming the missing specification (recorded in
# STATE.md under "Blocked").

.tivita_read <- function(path, ...) {
  p <- .envi_paths(path)
  if (!is.na(p$dat) && file.exists(p$dat) && file.exists(p$hdr)) {
    img <- .envi_read(path, ...)
    img$backend <- "tivita"
    img$meta$vendor <- "Diaspective Vision Tivita"
    return(img)
  }
  cli::cli_abort(c(
    "Cannot read {.path {path}} as a proprietary Tivita cube.",
    "x" = "The proprietary Tivita binary layout is not implemented.",
    "i" = "Export the cube in ENVI format (a {.file .hdr} plus binary), which is supported."
  ))
}

.tivita_tile <- function(img, level, xrange, yrange, bands) {
  .envi_tile(img, level, xrange, yrange, bands)
}

# No reliable content marker for auto-detection without the proprietary spec;
# select this backend explicitly via `at_read_image(path, backend = "tivita")`.
.tivita_detect <- function(path) FALSE

.tivita_available <- function() TRUE
