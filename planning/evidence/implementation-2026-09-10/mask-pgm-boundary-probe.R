p <- commandArgs(trailingOnly=TRUE)[1]
for (bits in c(8L,16L)) for (nm in c('zeros','binary','extremes')) {
  stem <- file.path(p,paste0(nm,bits)); img <- magick::image_read(paste0(stem,'.pgm'))
  for (fmt in c('tiff','png')) magick::image_write(img,paste0(stem,'.',fmt),format=fmt,depth=bits,compression='none')
  magick::image_write(img,paste0(stem,'-forced.png'),format='png',depth=bits,defines=c('png:bit-depth'=as.character(bits),'png:color-type'='0'))
}
