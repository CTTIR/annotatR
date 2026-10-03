# Run from the repository root. Diagnostic output is not a pass/fail test result.
pkgload::load_all('.', quiet=TRUE)
source('tests/testthat/helper-annotatR.R')
source('inst/shiny/annotatR/modules/mod_session.R')
check <- function(name, expr) {
  cat('\nCASE:', name, '\n')
  tryCatch(force(expr), error=function(e) cat('ERROR:', conditionMessage(e), '\n'))
}
check('triangle short-circuit', {
  r <- at_roi_polygon(rbind(c(0,0),c(5,0),c(5,5)), 'tri')
  single <- at_mask(r, dims=c(10,10))
  l <- at_layer_add(at_layer_add(at_layer('L'),r),at_roi_point(9,9,'extra'))
  batch <- at_mask(l, type='labelled', dims=c(10,10))
  cat('same triangle pixels alone:',sum(single),'with another ROI:',sum(batch==1),'\n')
})
check('lightweight save and resume', {
  p <- at_example_project()
  f <- tempfile(fileext='.rds')
  at_save_project(.lite_project(p),f)
  .tile_cache_clear()
  p2 <- at_load_project(f)
  cat('original tile dimensions:',dim(at_tile(p$image)),'\n')
  .tile_cache_clear()
  cat('resumed tile dimensions:',dim(at_tile(p2$image)),'length:',length(at_tile(p2$image)),'\n')
  cat('resumed canvas has image:',!is.null(at_tile_source(p2$image)$dataUri),'\n')
})
check('GeoJSON and CSV pyramid round-trips', {
  p <- at_project(small_image(),at_layer('L'))
  p <- at_add_roi(p,'L',at_roi_rect(2,2,5,5,'a',level=1L))
  before <- at_rois(p)$area_px
  for (fmt in c('json','csv')) {
    f <- tempfile(fileext=paste0('.',fmt))
    if(fmt=='json') {at_write_geojson(p,f); l <- at_read_geojson(f)[[1]]} else {at_write_rois_csv(p,f); l <- at_read_rois_csv(f)}
    after <- at_rois(at_project(p$image,l))$area_px
    cat(fmt,'original area:',before,'round-trip area:',after,'\n')
  }
})
check('ID collision after restart', {
  .reset_id_counter()
  l <- at_layer('L')
  for(i in 1:4) l <- at_layer_add(l,at_roi_rect(i,i,i+1,i+1,'a'))
  p <- at_project(tiny_image(),l)
  f <- tempfile(fileext='.rds'); at_save_project(p,f)
  .reset_id_counter()
  p <- at_load_project(f)
  p <- at_add_roi(p,'L',at_roi_rect(6,6,7,7,'a'))
  cat('IDs:',at_rois(p)$roi_id,'\n')
  at_validate(p)
})
check('explicit numeric bits', {
  m <- at_mask(square_roi(),dims=c(10,10))
  at_write_mask(m,tempfile(fileext='.tif'),bits=8L)
})
check('explicit numeric connectivity', {
  f <- tempfile(fileext='.tif');at_write_mask(at_mask(square_roi(),dims=c(10,10)),f)
  at_read_mask(f,connectivity=4L)
})
check('point extraction', {
  img <- tiny_image(); img$handle <- list(data=array(seq_len(100),c(10,10,1)))
  p <- at_project(img,at_layer_add(at_layer('L'),at_roi_point(5,5,'a')))
  .tile_cache_clear()
  cat('mask pixels:',sum(at_mask(p)),'extraction rows:',nrow(at_extract(p)),'\n')
})
check('ENVI offset and short payload', {
  f <- tempfile(); h <- paste0(f,'.hdr')
  writeLines(c('ENVI','samples = 2','lines = 2','bands = 1','data type = 4','interleave = bsq','byte order = 0','header offset = 4'),h)
  writeBin(c(999,1,2,3,4),f,size=4L,endian='little')
  cat('offset payload should be 1,2,3,4; read:',as.vector(at_tile(at_read_image(h))),'\n')
  f2 <- tempfile();h2 <- paste0(f2,'.hdr')
  writeLines(c('ENVI','samples = 2','lines = 2','bands = 1','data type = 4','interleave = bsq'),h2)
  writeBin(c(1,2),f2,size=4L,endian='little')
  cat('truncated read:',as.vector(at_tile(at_read_image(h2))),'\n')
})
check('NPY short payload', {
  f <- tempfile(fileext='.npy');.npy_write_matrix(matrix(1:4,2,2),f)
  raw <- readBin(f,'raw',n=file.info(f)$size);writeBin(head(raw,-8),f)
  cat('declares 4 values, contains 2, read:',as.vector(as.matrix(at_read_npy(f))),'\n')
})
check('cache collision between relative sources', {
  d1 <- tempfile();d2 <- tempfile();dir.create(d1);dir.create(d2)
  for (d in c(d1,d2)) tiff::writeTIFF(matrix(if(d==d1) 0 else 1,2,2),file.path(d,'same.tif'))
  .tile_cache_clear()
  a <- withr::with_dir(d1,at_read_image('same.tif')); b <- withr::with_dir(d2,at_read_image('same.tif'))
  cat('first:',as.vector(at_tile(a)),'second:',as.vector(at_tile(b)),'expected second:',as.vector(b$handle$levels[[1]]),'\n')
})
check('duplicate basename export', {
  d <- tempfile();dir.create(d);d1<-file.path(d,'A');d2<-file.path(d,'B');dir.create(d1);dir.create(d2)
  for (dd in c(d1,d2)) tiff::writeTIFF(matrix(0,10,10),file.path(dd,'same.tif'))
  s<-at_session(file.path(c(d1,d2),'same.tif'));s$projects<-list(at_project(tiny_image(),at_layer_add(at_layer('L'),square_roi('first'))),at_project(tiny_image(),at_layer_add(at_layer('L'),square_roi('second'))))
  out<-tempfile();rc<-at_export_all(s,out,formats='geojson',scope='all',overwrite=TRUE,progress=FALSE)
  cat('success receipts:',sum(rc$status=='ok'),'unique exported paths:',length(unique(rc$path)),'surviving label:',at_read_geojson(rc$path[1])[[1]]$labels,'\n')
})
check('set operations mix pyramid levels', {
  a<-at_roi_rect(0,0,10,10,'a'); b<-at_roi_rect(0,0,5,5,'a',level=1)
  cat('same physical ROI difference area:',at_roi_area(at_roi_difference(a,b)),'\n')
})
check('nonzero background and binary foreground collision', {
  m <- at_mask(square_roi(),dims=c(10,10),background=1L)
  cat('foreground expected 9, got:',sum(m),'\n')
})
