# Package hooks.

.register_backends <- function() {
  at_backend_register(
    "raster", .raster_read, .raster_tile, .raster_detect, .raster_available,
    description = "PNG, JPEG, and single-plane TIFF",
    extensions = c("png", "jpg", "jpeg", "bmp", "gif", "tif", "tiff")
  )
  at_backend_register(
    "tiff", .tiff_read, .tiff_tile, .tiff_detect, .tiff_available,
    description = "Pyramidal / multi-directory TIFF",
    extensions = c("tif", "tiff")
  )
  at_backend_register(
    "ometiff", .ometiff_read, .ometiff_tile, .ometiff_detect, .ometiff_available,
    description = "OME-TIFF and qptiff (RBioFormats)",
    extensions = c("ome.tif", "ome.tiff", "qptiff")
  )
  at_backend_register(
    "cuvis", .cuvis_read, .cuvis_tile, .cuvis_detect, .cuvis_available,
    description = "Cubert hyperspectral (cuvis.r)",
    extensions = c("cu3", "cu3s")
  )
  at_backend_register(
    "tivita", .tivita_read, .tivita_tile, .tivita_detect, .tivita_available,
    description = "Diaspective Vision Tivita (ENVI-compatible)",
    extensions = c("dat", "hdr")
  )
  at_backend_register(
    "envi", .envi_read, .envi_tile, .envi_detect, .envi_available,
    description = "ENVI header + binary cube",
    extensions = c("hdr", "dat", "img", "raw")
  )
  invisible(NULL)
}

.onLoad <- function(libname, pkgname) {
  .register_backends()
}
