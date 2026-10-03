# Fresh-process measurement, including open and (for OME) native initialization.
args<-commandArgs(TRUE);backend<-args[1];side<-as.integer(args[2]);out<-args[3]
if(backend=='ometiff') {
  options(java.parameters='--enable-native-access=ALL-UNNAMED')
  .libPaths(c('/tmp/annotatr-roadmap-r-library',.libPaths()))
}
pkgload::load_all(quiet=TRUE)
if (backend %in% c('envi','tivita')) {
  path<-tempfile(fileext=if(backend=='tivita') '_SpecCube.dat' else '.bin');header<-paste0(path,'.hdr')
  encoded_size<-if(backend=='envi') 2 else 4
  offset<-if(backend=='envi') 0 else 12
  con<-file(path,'wb');seek(con,where=as.double(side)*side*3*encoded_size+offset-1,origin='start')
  writeBin(as.raw(0),con);close(con)
  if (backend=='envi') writeLines(c('ENVI',paste('samples =',side),paste('lines =',side),'bands = 3',
    'data type = 12','interleave = bsq'),header)
  source_path<-if(backend=='envi') header else path
} else source_path<-args[4]
rss<-function() {
  lines<-readLines('/proc/self/status')
  as.numeric(sub('.*:\\s*([0-9]+).*','\\1',lines[grepl('^Vm(RSS|HWM):',lines)]))*1024
}
annotatR:::.tile_cache_clear();annotatR:::.read_telemetry_reset()
before<-rss();Rprofmem(paste0(out,'.allocations.log'))
timing<-system.time({
  img<-if(backend=='tivita') at_read_image(source_path,backend=backend,nx=side,ny=side,nb=3) else at_read_image(source_path,backend=backend)
  after_open<-rss();open_counts<-annotatR:::.read_telemetry()
  tile<-at_tile(img,xrange=c(11,74),yrange=c(21,84),bands=if(backend!='ometiff') c(3,1,3) else c(1,1,1))
  after_tile<-rss()
})
Rprofmem(NULL)
stopifnot(identical(dim(tile),c(64L,64L,3L)),all(tile==if(backend!='ometiff') 0 else 7),
  isTRUE(at_image_capabilities(img)$window_read),is.null(img$handle$data),is.null(img$handle$levels))
if (backend=='tivita') stopifnot(identical(img$meta$format,'SpecCube'))
counts<-annotatR:::.read_telemetry()
alloc<-readLines(paste0(out,'.allocations.log'));sizes<-suppressWarnings(as.numeric(sub(' .*','',alloc)))
result<-list(backend=backend,dimensions=c(side,side),source_bytes=file.info(if(backend!='ometiff') path else source_path)$size,
  hypothetical_double_cube_bytes=as.double(side)*side*if(backend!='ometiff') 3*8 else 8,
  rss_and_hwm_before=before,rss_and_hwm_after_open=after_open,rss_and_hwm_after_tile=after_tile,
  max_R_allocation=max(sizes,na.rm=TRUE),total_R_allocations=sum(sizes,na.rm=TRUE),
  image_object_bytes=as.numeric(object.size(img)),tile_bytes=as.numeric(object.size(tile)),
  open_counts=open_counts,final_counts=counts,elapsed=timing[['elapsed']],
  R=R.version.string,platform=R.version$platform)
dput(result,file=paste0(out,'.result.R'));print(result)
if (backend!='ometiff') unlink(c(path,header))
