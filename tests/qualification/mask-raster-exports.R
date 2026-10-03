# Run from the package root, then verify the outputs with the adjacent Python
# script. Only package discovery is masked for the optional TIFF writer path.
pkgload::load_all()
dest <- commandArgs(TRUE)[1]
dir.create(dest,recursive=TRUE,showWarnings=FALSE)
normal <- .write_mask_raster
fallback <- .write_mask_raster
env <- new.env(parent=environment(fallback))
env$requireNamespace <- function(package, ...) package != 'tiff' && base::requireNamespace(package,...)
environment(fallback) <- env
for (bits in c(8L,16L)) {
  arrays <- list(zero=matrix(0L,2,3),binary=matrix(c(0L,1L,0L,1L,0L,1L),2,byrow=TRUE),
                 extrema=matrix(c(0,2^bits-1,0,2^bits-1,0,2^bits-1),2,byrow=TRUE))
  arrays$codes <- if(bits==16L) matrix(c(0L,1L,255L,256L,4096L,32767L,32768L,65535L),2,byrow=TRUE) else matrix(c(0L,1L,9L,10L,13L,32L,128L,255L),2,byrow=TRUE)
  for (name in names(arrays)) for (format in c('tiff','png')) for (mode in c('normal','fallback')) {
    writer <- if(mode=='normal') normal else fallback
    writer(arrays[[name]],file.path(dest,sprintf('%s-%s-%s.%s',mode,bits,name,format)),bits,format,environment())
  }
}
