# Run save and resume as separate Rscript processes using an installed package.
args<-commandArgs(TRUE)
.libPaths(c(args[1],'/tmp/annotatr-roadmap-r-library',.libPaths()))
options(java.parameters='--enable-native-access=ALL-UNNAMED')
library(annotatR)
mode<-args[2];target<-args[3];fixtures<-normalizePath(args[4],mustWork=TRUE)
dir.create(target,recursive=TRUE,showWarnings=FALSE)
if(mode=='save') {
  images<-list(envi=at_read_image(file.path(fixtures,'binary','bsq-0.hdr')),
    tivita=at_read_image(file.path(fixtures,'binary','reference_SpecCube.dat'),nx=5,ny=4,nb=3),
    ometiff=at_read_image(file.path(fixtures,'images','reference.ome.tif')))
  for(n in names(images)) {
    p<-at_project(images[[n]],at_layer('L'))
    p<-at_add_roi(p,'L',at_roi_rect(0,0,1,1,'reference'))
    at_save_project(p,file.path(target,paste0(n,'.rds')))
    saveRDS(at_rois(p)$roi_id,file.path(target,paste0(n,'-ids.rds')))
  }
} else {
  for(n in c('envi','tivita','ometiff')) {
    annotatR:::.read_telemetry_reset()
    p<-at_load_project(file.path(target,paste0(n,'.rds')))
    stopifnot(annotatR:::.read_telemetry()$decoded_bytes==0,
      is.null(p$image$handle$data),is.null(p$image$handle$levels),
      identical(at_rois(p)$roi_id,readRDS(file.path(target,paste0(n,'-ids.rds')))))
    tile<-at_tile(p$image,xrange=c(2,3),yrange=c(2,3),bands=c(3,1,3))
    stopifnot(identical(as.vector(tile[,,1]),c(322,332,323,333)),
      identical(as.vector(tile[,,2]),c(122,132,123,133)),identical(tile[,,1],tile[,,3]))
    closed<-at_close_image(p)
    stopifnot(is.null(closed$image$handle),identical(at_tile(closed$image,xrange=c(2,3),yrange=c(2,3),bands=c(3,1,3)),tile))
    cat(n,': metadata reopen, original ROI identity, raw windows and close/reopen passed\n')
  }
}
