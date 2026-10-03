window_fixture <- function(n, group='binary') test_path('fixtures','readers',group,n)
window_cube <- function() {
  a <- array(0,c(4,5,3))
  for (b in 1:3) a[,,b] <- outer(1:4,1:5,function(y,x) 100*b+10*y+x)
  a
}
test_that('ENVI opens metadata only and reads bounded ordered duplicate bands', {
  for (layout in c('bsq','bil','bip')) for (e in 0:1) {
    .read_telemetry_reset()
    path <- window_fixture(paste0(layout,'-',e,'.hdr'))
    img <- at_read_image(path)
    expect_null(img$handle$data)
    expect_true(img$meta$capabilities$window_read)
    expect_identical(img$source_descriptor$reader_contract,list(axes='yxb',samples='raw-scalar-v1'))
    expect_equal(.read_telemetry()$binary_bytes,file.info(path)$size)
    tile <- at_tile(img,xrange=c(2,4),yrange=c(2,3),bands=c(3,1,3))
    expect_equal(tile,window_cube()[2:3,2:4,c(3,1,3),drop=FALSE])
    expect_lte(.read_telemetry()$binary_bytes-file.info(path)$size,36)
    expect_gt(.read_telemetry()$binary_calls,1)
    before <- .read_telemetry()
    expect_equal(at_tile(img,xrange=c(2,4),yrange=c(2,3),bands=c(3,1,3)),tile)
    expect_identical(.read_telemetry(),before)
  }
})
test_that('bands reject invalid values before integer conversion', {
  img<-at_read_image(window_fixture('bsq-0.hdr'))
  for (b in list(1.5,NA_real_,Inf,NaN,character(),numeric())) expect_error(at_tile(img,bands=b),'bands|Bands')
  expect_equal(at_tile(img,bands=c(3,1,3)),window_cube()[,,c(3,1,3),drop=FALSE])
})
test_that('composite source changes reject cached and uncached windows and mask alignment', {
  for (input in c('hdr','bin')) for (changed in c('hdr','bin')) {
    td<-tempfile();dir.create(td);withr::defer(unlink(td,recursive=TRUE))
    for (ext in c('hdr','bin')) file.copy(window_fixture(paste0('bsq-0.',ext)),file.path(td,paste0('cube.',ext)))
    img<-at_read_image(file.path(td,paste0('cube.',input)))
    a<-at_tile(img,xrange=c(1,2),yrange=c(1,2))
    m<-at_mask(at_roi_rect(0,0,1,1,label='1'),'multiclass',dims=img$dims,image=img)
    change<-file.path(td,paste0('cube.',changed))
    cat(if(changed=='hdr') '\n; change\n' else 'padding',file=change,append=TRUE)
    expect_error(at_tile(img,xrange=c(1,2),yrange=c(1,2)),'changed')
    expect_error(at_tile(img,xrange=c(3,4),yrange=c(2,3)),'changed')
    fresh<-at_relink_source(img,img$source)
    n<-at_mask(at_roi_rect(0,0,1,1,label='1'),'multiclass',dims=fresh$dims,image=fresh)
    expect_error(at_mask_derive(m,n,keep_label='1'),'conflict')
    expect_no_error(at_mask_derive(m,n,keep_label='1',alignment='assert'))
    p<-file.path(td,'mask.npy');at_write_npy(m,p)
    back<-at_read_npy(p)
    expect_equal(attr(back,'mask_metadata')$source$descriptor$files,img$source_descriptor$files)
    expect_error(at_mask_derive(back,n,keep_label='1'),'conflict')
    old<-img;old$source_descriptor$files<-NULL;old$handle<-NULL
    expect_error(at_tile(old),'changed|unverified|revalidat')
  }
})
test_that('legacy ENVI memory snapshots survive source replacement and remain unverified', {
  td<-tempfile();dir.create(td);withr::defer(unlink(td,recursive=TRUE))
  for (ext in c('hdr','bin')) file.copy(window_fixture(paste0('bsq-0.',ext)),file.path(td,paste0('cube.',ext)))
  img<-at_read_image(file.path(td,'cube.bin'));img$handle<-list(data=window_cube())
  img$source_descriptor$files<-NULL
  cat('changed',file=file.path(td,'cube.bin'),append=TRUE)
  expect_equal(at_tile(img),window_cube())
  m<-at_mask(at_roi_rect(0,0,1,1,label='1'),'multiclass',dims=img$dims,image=img)
  n<-m;attr(n,'mask_metadata')$source$entry_id<-'other'
  expect_error(at_mask_derive(m,n,keep_label='1'),'unverified')
  p<-file.path(td,'snapshot.rds');at_save_project(at_project(img),p)
  expect_equal(at_tile(at_load_project(p)$image),window_cube())
})
test_that('binary metadata opens above eager limits and budgets apply to windows', {
  p<-tempfile(fileext='.bin');hdr<-paste0(p,'.hdr');withr::defer(unlink(c(p,hdr)))
  con<-file(p,'wb');seek(con,where=2^31-1,origin='start');writeBin(as.raw(0),con);close(con)
  writeLines(c('ENVI','samples = 65536','lines = 32768','bands = 1','data type = 1','interleave = bsq'),hdr)
  .read_telemetry_reset();img<-at_read_image(hdr)
  expect_null(img$handle$data);expect_lt(as.numeric(object.size(img)),50000)
  expect_equal(at_tile(img,xrange=c(1,2),yrange=c(1,2)),array(0,c(2,2,1)))
  expect_equal(.read_telemetry()$binary_bytes,file.info(hdr)$size+4)
  withr::local_options(annotatR.max_read_bytes=16)
  expect_error(at_tile(img,xrange=c(2,3),yrange=c(1,2)),'budget|limit')
})
test_that('SpecCube window orientation and legacy eager handle both work', {
  img<-at_read_image(window_fixture('reference_SpecCube.dat'),backend='tivita',nx=5,ny=4,nb=3)
  expect_null(img$handle$data)
  expect_equal(at_tile(img,xrange=c(2,4),yrange=c(2,3),bands=c(3,1,3)),window_cube()[2:3,2:4,c(3,1,3),drop=FALSE])
})
test_that('OME metadata open and optional native subwindows preserve levels and duplicates', {
  skip_if_not_installed('RBioFormats');skip_if_not_installed('xml2')
  .read_telemetry_reset()
  img<-at_read_image(window_fixture('reference-pyramid.ome.tif','images'))
  expect_null(img$handle$levels);expect_true(img$meta$capabilities$window_read)
  expect_equal(.read_telemetry()$decoded_bytes,0)
  expect_true(is.na(.read_telemetry()$native_file_bytes))
  got<-at_tile(img,level=1,xrange=c(2,3),yrange=c(1,2),bands=c(3,1,3))
  a<-matrix(c(115,119,135,139),2,2,byrow=TRUE)
  expect_equal(got[,,1],a+200);expect_equal(got[,,2],a);expect_equal(got[,,3],a+200)
  expect_equal(.read_telemetry()$decoded_bytes,12*8)
  expect_equal(.read_telemetry()$native_window_calls,1)
  expect_equal(img$level_dims,list(c(64L,48L),c(16L,24L),c(8L,12L)))
  img$handle<-NULL
  expect_equal(at_tile(img,level=1,xrange=c(2,3),yrange=c(1,2),bands=c(3,1,3)),got)
})
test_that('additive capabilities and close lifecycle keep third party registration compatible', {
  img<-at_read_image(window_fixture('bsq-0.hdr'))
  closed<-at_close_image(img)
  expect_null(closed$handle)
  expect_equal(at_tile(closed,xrange=c(1,2),yrange=c(1,2)),window_cube()[1:2,1:2,,drop=FALSE])
  expect_true(at_image_capabilities(img)$window_read)
  img$handle<-list(data=window_cube())
  expect_false(at_image_capabilities(img)$window_read)
  expect_equal(at_image_capabilities(img)$io,'memory')
  n<-'window-test-custom';withr::defer(rm(list=n,envir=.backend_registry))
  at_backend_register(n,function(path,...) img,.envi_tile,function(path) TRUE,function() TRUE)
  expect_true(is.na(at_backend_get(n)$capabilities$window_read))
  expect_true(at_backend_list()$window_read[at_backend_list()$name=='envi'])
  closed_count<-0
  at_backend_register(n,function(path,...) img,.envi_tile,function(path) TRUE,function() TRUE,
    close_fn=function(image) {closed_count<<-closed_count+1})
  img$backend<-n
  expect_null(at_close_image(img)$handle);expect_equal(closed_count,1)
})
test_that('missing and malformed composite fingerprints never certify interpretation', {
  img<-at_read_image(window_fixture('bsq-0.hdr'))
  for (change in c('files_extra','header_extra','signature_extra','size_extra')) {
    old<-img
    if (change=='files_extra') names(old$source_descriptor)[names(old$source_descriptor)=='files']<-change
    if (change=='header_extra') names(old$source_descriptor$files)[1]<-change
    if (change=='signature_extra') names(old$source_descriptor$files$header)[2]<-change
    if (change=='size_extra') names(old$source_descriptor$files$header$signature)[1]<-change
    expect_error(at_tile(old),'unverified|signature|revalidat')
  }
  m<-at_mask(at_roi_rect(0,0,1,1,label='1'),'multiclass',dims=img$dims,image=img)
  p<-tempfile(fileext='.npy');withr::defer(unlink(c(p,paste0(p,'.legend.json'))))
  at_write_npy(m,p);expect_no_error(at_mask_derive(m,at_read_npy(p),keep_label='1'))
})
test_that('bounded ENVI preserves raw nonfinite samples and unknown wavelength units', {
  td<-tempfile();dir.create(td);withr::defer(unlink(td,recursive=TRUE))
  p<-file.path(td,'nonfinite.bin');h<-paste0(p,'.hdr')
  writeLines(c('ENVI','samples = 2','lines = 2','bands = 2','data type = 5','interleave = bip',
    'wavelength = {450,650}'),h)
  writeBin(c(NaN,Inf,-Inf,1,2,3,4,5),p,size=8,endian='little')
  img<-at_read_image(h)
  expected<-array(c(NaN,2,-Inf,4,Inf,3,1,5),c(2,2,2))
  expect_equal(at_tile(img,bands=c(2,1,2)),expected[,,c(2,1,2),drop=FALSE])
  expect_null(img$wavelength_unit)
})
test_that('native OME subsets preserve independent scalar types and nonfinite values', {
  skip_if_not_installed('RBioFormats');skip_if_not_installed('xml2')
  cases<-list(uint8=c(0,1,127,255,255,100,2,0),uint16=c(0,1,32767,65535,65535,100,2,0),
    int16=c(-32768,-1,0,32767,1,2,3,4),int32=c(-2147483648,-1,0,2147483647,1,2,3,4),
    uint32=c(0,1,2147483648,4294967295,1,2,3,4),
    float32=c(-2,.5,NaN,Inf,-Inf,4,5,6),float64=c(-2,.5,NaN,Inf,-Inf,4,5,6))
  for (nm in names(cases)) {
    img<-at_read_image(test_path('fixtures','windows',paste0(nm,'.ome.tif')))
    want<-matrix(cases[[nm]],2,4,byrow=TRUE)
    expect_equal(at_tile(img,xrange=c(2,4),yrange=c(1,2))[,,1],want[,2:4])
    expect_equal(as.vector(at_tile(img,xrange=c(1,1),yrange=c(1,1))),want[1,1])
    expect_equal(as.vector(at_tile(img,xrange=c(1,1),yrange=c(2,2))),want[2,1])
    expect_equal(at_tile(img,bands=c(1,1))[,,2],want)
  }
})
test_that('OME cached windows reject replaced files and reopen after explicit relink', {
  skip_if_not_installed('RBioFormats');skip_if_not_installed('xml2')
  p<-file.path(withr::local_tempdir(),'copy.ome.tif')
  file.copy(window_fixture('reference.ome.tif','images'),p)
  img<-at_read_image(p);before<-at_tile(img,xrange=c(1,2),yrange=c(1,2))
  Sys.setFileTime(p,file.info(p)$mtime+2)
  expect_error(at_tile(img,xrange=c(1,2),yrange=c(1,2)),'changed')
  expect_error(at_tile(img,xrange=c(2,3),yrange=c(1,2)),'changed')
  expect_equal(at_tile(at_relink_source(img,p),xrange=c(1,2),yrange=c(1,2)),before)
})
test_that('SpecCube float-header counts cannot encode fractional offsets', {
  p<-file.path(withr::local_tempdir(),'invalid_SpecCube.dat')
  writeBin(as.raw(rep(0,241)),p)
  expect_error(at_read_image(p,backend='tivita',nx=5,ny=4,nb=3,header=.25),'header')
})
test_that('capability and close APIs do not use prefix backend declarations', {
  img<-at_read_image(window_fixture('bsq-0.hdr'))
  img$meta$capabilities<-NULL
  names(img)[names(img)=='backend']<-'backend_extra'
  expect_error(at_image_capabilities(img),'backend|character|string')
  expect_error(at_close_image(img),'backend|character|string')
})
