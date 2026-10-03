args <- commandArgs(TRUE)
mode <- args[[1]]
path <- normalizePath("inst/extdata/example_multiplex.tif")
cat("R", as.character(getRversion()), "tiff", as.character(packageVersion("tiff")), "magick", as.character(packageVersion("magick")), "mode", mode, "\n")
if (mode != "tiff-only") {
  tmp <- tempfile(fileext=".tif")
  on.exit <- NULL
  tiff::writeTIFF(matrix(c(0,1,1,0),2L,2L),tmp,bits.per.sample=8L,compression="none")
  cat("tiff initialised\n"); flush.console()
  image <- magick::image_read(tmp)
  cat("magick TIFF read completed\n"); flush.console()
  if (mode == "destroy") {
    rm(image)
    invisible(gc())
    cat("magick image removed and GC completed\n"); flush.console()
  }
  unlink(tmp)
}
cat("reading four-channel fixture with tiff\n"); flush.console()
x <- tiff::readTIFF(path,all=TRUE,as.is=FALSE,info=TRUE)
cat("completed TIFF read; result class",class(x),"\n")
