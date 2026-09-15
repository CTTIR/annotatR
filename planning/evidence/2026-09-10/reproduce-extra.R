# Run from the repository root. Diagnostic output is not a pass/fail test result.
pkgload::load_all('.',quiet=TRUE)
source('tests/testthat/helper-annotatR.R')
check <- function(name,expr) {cat('\nCASE:',name,'\n');tryCatch(force(expr),error=function(e)cat('ERROR:',conditionMessage(e),'\n'))}
check('mask plot overlay scale mismatch', {
  img<-new_annot_image('audit-big.tif','raster',c(2048L,2048L),1L,list(c(2048L,2048L)),1L,handle=list(data=array(0,c(2048,2048,1))))
  p<-at_project(img,at_layer_add(at_layer('L'),at_roi_rect(1800,1800,1900,1900,'a')))
  plt<-at_plot_overlay(p)
  cat('image x-range:',range(plt$data$x),'ROI x-range:',range(plt$layers[[2]]$data$x),'\n')
})
check('RDS mask labels disappear', {
  m<-at_mask(at_layer_add(at_layer('L'),square_roi('tumour')),type='multiclass',dims=c(10,10))
  f<-tempfile(fileext='.rds');at_write_mask(m,f,format='rds')
  cat('original labels:',at_mask_legend(m)$label,'reimported:',at_read_mask(f)$labels,'\n')
})
check('mask stats drop bitfield overlaps', {
  l<-at_layer_add(at_layer_add(at_layer('L'),at_roi_rect(0,0,6,6,'a')),at_roi_rect(4,4,10,10,'b'))
  m<-at_mask(l,type='multiclass',values=c(a=1L,b=2L),overlap='bitor',dims=c(10,10))
  cat('legend counts:',at_mask_legend(m)$n_px,'stats counts:',at_mask_stats(m)$n_px,'\n')
})
check('per-ROI mask export on anisotropic pyramid', {
  img<-new_annot_image('audit-pyramid.tif','tiff',c(100L,80L),2L,list(c(100L,80L),c(25L,40L)),1L)
  r<-at_roi_rect(2,2,5,5,'a',level=1L)
  p<-at_project(img,at_layer_add(at_layer('L'),r))
  d<-tempfile();rc<-at_write_masks(p,d,per='roi')
  cat('project mask pixels:',sum(at_mask(p)),'per ROI exported pixels:',rc$n_px,'\n')
})
check('export path escapes destination', {
  d<-tempfile();dir.create(d);out<-file.path(d,'out');dir.create(out)
  p<-at_project(tiny_image(),at_layer_add(at_layer('L'),square_roi()),name='../escaped')
  rc<-at_write_masks(p,out,per='project')
  cat('written outside output dir:',file.exists(file.path(d,'escaped.tif')),'\n')
})
check('default session save ignores overwrite FALSE', {
  s<-demo_session();at_save_session(s);s$manifest$status[1]<-'complete';at_save_session(s,overwrite=FALSE)
  cat('default save replaced existing status:',at_load_session(file.path(s$out_dir,'_session.rds'))$manifest$status[1],'\n')
})
