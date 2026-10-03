# Two independent installed-package processes save and resume raster and
# spectral sessions, then render, extract the same values and continue editing.
args <- commandArgs(trailingOnly=TRUE)
if (length(args)!=1L) stop('Usage: Rscript tests/qualification/installed-persistence.R <library>')
lib <- normalizePath(args[1],mustWork=TRUE)
dir <- tempfile('annotatr-installed-persistence-'); dir.create(dir)
on.exit(unlink(dir,recursive=TRUE),add=TRUE)
child <- file.path(dir,'child.R')
writeLines(c(
  'args <- commandArgs(trailingOnly=TRUE)',
  'library(annotatR,lib.loc=args[1])',
  'dir <- args[3]',
  "if (args[2]=='save') {",
  "  tiff::writeTIFF(matrix(c(0,1,1,0),2,2),file.path(dir,'raster.tif'),bits.per.sample=8L,compression='none')",
  "  con <- file(file.path(dir,'tiny_SpecCube.dat'),'wb')",
  "  writeBin(as.double(c(0,0,0,1:12)),con,size=4L,endian='big'); close(con)",
  "  images <- list(at_read_image(file.path(dir,'raster.tif'),backend='raster'),",
  "    at_read_image(file.path(dir,'tiny_SpecCube.dat'),backend='tivita',nx=3L,ny=2L,nb=2L,wavelengths=c(500,600)))",
  '  rgb <- file.path(dir,"rgb.tif")',
  '  tiff::writeTIFF(array(rep(c(0,1,1,0),3),c(2,2,3)),rgb,bits.per.sample=8L,compression="none")',
  '  linked <- at_relink_source(at_read_image(rgb,backend="raster"),rgb,backend="tiff")',
  '  fresh <- at_read_image(rgb,backend="tiff")',
  '  fields <- c("backend","band_names","dtype","pixel_size","pixel_unit","meta")',
  '  stopifnot(identical(linked[fields],fresh[fields]),identical(at_tile(linked),at_tile(fresh)))',
  '  images[[3]] <- linked',
  '  for (i in seq_along(images)) {',
  '    img <- images[[i]]',
  '    s <- at_session(img$source,out_dir=file.path(dir,paste0("session",i)))',
  '    p <- at_project(img,at_layer("L"),entry_id=s$manifest$entry_id[1])',
  '    p <- at_add_roi(p,"L",at_roi_rect(0,0,1,1,"original"))',
  '    s$projects[[1]] <- p; s <- annotatR:::.save_checkpoint(s,1)',
  '    saveRDS(list(tile=at_tile(img),extract=at_extract(p),ids=at_rois(p)$roi_id,entry=s$manifest$entry_id,metadata=img[fields]),file.path(dir,paste0("expected",i,".rds")))',
  '  }',
  '} else {',
  '  fields <- c("backend","band_names","dtype","pixel_size","pixel_unit","meta")',
  '  for (i in 1:3) {',
  '    path <- file.path(dir,paste0("session",i),"_session.rds")',
  '    expected <- readRDS(file.path(dir,paste0("expected",i,".rds")))',
  '    s <- at_resume(path); p <- at_current(s)',
  '    stopifnot(identical(p$image[fields],expected$metadata),identical(s$manifest$entry_id,expected$entry), identical(at_tile(p$image),expected$tile),identical(at_extract(p),expected$extract),identical(at_rois(p)$roi_id,expected$ids))',
  '    png <- file.path(dir,paste0("render",i,".png")); grDevices::png(png)',
  '    print(at_plot_image(p$image,bands=1)); grDevices::dev.off()',
  '    stopifnot(file.info(png)$size>0)',
  '    p <- at_add_roi(p,"L",at_roi_point(1,1,"continued")); s$projects[[1]] <- p',
  '    s <- annotatR:::.save_checkpoint(s,1)',
  '    stopifnot(nrow(at_rois(at_current(at_resume(path))))==2,anyDuplicated(at_rois(p)$roi_id)==0)',
  '  }',
  '}'
),child)
for (mode in c('save','resume')) {
  log <- file.path(dir,paste0(mode,'.log'))
  status <- system2(file.path(R.home('bin'),'Rscript'),shQuote(c(child,lib,mode,dir)),stdout=log,stderr=log)
  if (status!=0L) stop(paste(readLines(log,warn=FALSE),collapse='\n'))
}
cat('installed persistence: raster, spectral and relinked-backend fresh-process pixels, extraction, rendering, IDs, and continued checkpoint editing passed\n')
