pkgload::load_all('/data/GitHub/CTTIR/public/annotatR-roadmap/.superpowers/sdd/ROADMAP/snapshots/T05', quiet=TRUE)
m <- matrix(c(0L,1L,255L,256L,4096L,32767L,32768L,65535L),2,4,byrow=TRUE)
mask <- annotatR:::.new_annot_mask(m,tibble::tibble(value=integer(),label=character()),0L,c(4L,2L),'multiclass')
writer <- annotatR:::.write_mask_raster
environment(writer) <- list2env(list(requireNamespace=function(package,...) {
  if (identical(package,'tiff')) FALSE else base::requireNamespace(package,...)
}), parent=environment(writer))
p <- '/tmp/annotatr-roadmap-mask-fallback.tif'
writer(m,p,bits=16L,format='tiff',call=environment())
actual <- tiff::readTIFF(p,as.is=TRUE,info=TRUE)
print(list(expected=m,actual=actual,bits=attr(actual,'bits.per.sample')))
unlink(p)
