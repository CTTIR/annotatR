mode <- commandArgs(TRUE)[[1]]
cat("mode",mode,"R",as.character(getRversion()),"tiff",as.character(packageVersion("tiff")),"magick",as.character(packageVersion("magick")),"\n")
tmp <- tempfile(fileext=".tif")
tiff::writeTIFF(matrix(c(0,1,1,0),2L,2L),tmp,bits.per.sample=8L,compression="none")
unlink(tmp)
if (mode == "png") image <- magick::image_read("inst/extdata/example_tissue.png")
if (mode == "array") {
 image <- magick::image_read(array(0.5,c(2L,2L,3L)))
 bytes <- magick::image_write(image,format="png")
 cat("PNG encoded bytes",length(bytes),"\n")
}
cat("non-TIFF magick operation completed\n"); flush.console()
x <- tiff::readTIFF("inst/extdata/example_multiplex.tif",all=TRUE,as.is=FALSE,info=TRUE)
cat("completed TIFF read; result class",class(x),"\n")
