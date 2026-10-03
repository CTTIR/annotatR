reader_fixture <- function(name, group = 'binary') test_path('fixtures','readers',group,name)
reader_cube <- function() {
  a <- array(0,c(4,5,3))
  for (b in 1:3) a[,,b] <- matrix(c(111:115,121:125,131:135,141:145),4,5,byrow=TRUE)+100*(b-1)
  a
}
reader_npy_header <- function(header, payload = as.raw(c(1,2,3,4)), version=c(1,0)) {
  p <- tempfile(fileext='.npy'); con <- file(p,'wb')
  writeBin(as.raw(c(147,78,85,77,80,89,version)),con)
  header <- paste0(header,'\n')
  writeBin(as.integer(nchar(header)),con,size=if(version[1]==1) 2 else 4,endian='little')
  writeBin(charToRaw(header),con);writeBin(payload,con);close(con);p
}
test_that('A10 all independent ENVI offsets, interleaves and byte orders decode exactly', {
  for (i in c('bsq','bil','bip')) for(e in 0:1) {
    img <- at_read_image(reader_fixture(paste0(i,'-',e,'.hdr')))
    expect_equal(at_tile(img),reader_cube())
  }
})
test_that('A30 ENVI int32 preserves both boundaries as quantitative doubles', {
  for(e in c('little','big')) expect_equal(as.vector(at_tile(at_read_image(
    reader_fixture(paste0('int32-',e,'.hdr'))))), c(-2147483648,-2147483647,0,2147483647))
})
test_that('A13 ENVI declarations and resource budgets fail before reads', {
  original <- readLines(reader_fixture('bsq-0.hdr'))
  td <- tempfile();dir.create(td);withr::defer(unlink(td,recursive=TRUE))
  file.copy(reader_fixture('bsq-0.bin'),file.path(td,'bad.bin'))
  for (field in c('samples = 1.5','lines = -1','bands = 0','byte order = 2',
                  'interleave = nonsense','header offset = -1','data type = 99')) {
    key <- sub(' =.*','',field)
    writeLines(c(original[!startsWith(original,paste0(key,' ='))],field),file.path(td,'bad.hdr'))
    expect_error(at_read_image(file.path(td,'bad.hdr')))
  }
  withr::local_options(annotatR.max_read_bytes=64)
  expect_error(at_tile(at_read_image(reader_fixture('bsq-0.hdr'))),'limit|budget')
})
test_that('A13 independent C and Fortran NPY files retain orientation', {
  want <- matrix(c(0,1,1,0,2,3,0,2,0,0,3,3),3,4,byrow=TRUE)
  for (order in c('c','f')) expect_equal(as.matrix(at_read_npy(reader_fixture(paste0('reference-',order,'.npy'),'images'))),want)
  expect_equal(as.matrix(at_read_npy(reader_fixture('big-endian-int16.npy'))),matrix(c(0,1,256,-2,3,4),2,3,byrow=TRUE))
})
test_that('A13 integer NPY checks all words and reserved NA at both byte orders', {
  for (p in list.files(reader_fixture(''),pattern='^(i[48]|u[48])-.*npy$',full.names=TRUE)) {
    if(grepl('overflow|underflow|reserved',p)) expect_error(at_read_npy(p),'range|represent')
    else expect_equal(as.numeric(as.matrix(at_read_npy(p))),if(grepl('-min',p)) -2147483647 else 2147483647)
  }
  expect_equal(as.matrix(at_read_npy(reader_fixture('int64-safe.npy'))),matrix(c(-2,0,1,2147483647),2,2,byrow=TRUE))
  expect_error(at_read_npy(reader_fixture('uint64-too-large.npy')),'range|represent')
})
test_that('A13 NPY versions, complete headers, shape and dtype are validated', {
  good <- "{'descr': '|u1', 'fortran_order': False, 'shape': (2, 2), }"
  for (v in 1:3) {
    p <- reader_npy_header(good,version=c(v,0));withr::defer(unlink(p))
    expect_equal(as.matrix(at_read_npy(p)),matrix(1:4,2,2,byrow=TRUE))
  }
  invalid <- c(sub('False','Maybe',good), sub('2, 2','2, nope',good),
    sub('2, 2','0, 2',good),sub('2, 2','2.5, 2',good),sub('|u1','|i2',good,fixed=TRUE),
    sub('|u1','<i3',good,fixed=TRUE),sub("'descr'","'bogus'",good),
    sub('}',", 'descr': '|u1'}",good,fixed=TRUE))
  for(h in invalid) {p <- reader_npy_header(h);withr::defer(unlink(p));expect_error(at_read_npy(p))}
  for(v in list(c(4,0),c(1,1))) {p<-reader_npy_header(good,version=v);withr::defer(unlink(p));expect_error(at_read_npy(p),'version')}
  p <- reader_npy_header(good,as.raw(c(1,2)));withr::defer(unlink(p));expect_error(at_read_npy(p),'payload|short|truncat')
  p <- reader_npy_header(good,as.raw(1:6));withr::defer(unlink(p));expect_equal(as.matrix(at_read_npy(p)),matrix(1:4,2,2,byrow=TRUE))
  withr::local_options(annotatR.max_read_bytes=8)
  expect_error(at_read_npy(reader_fixture('int64-safe.npy')),'limit|budget')
})
test_that('A28 invalid export values fail before creating or overwriting output', {
  for (case in list(list(v=-2,d='uint8'),list(v=-40000,d='int16'),list(v=1.5,d='int32'),list(v=Inf,d='int32'),list(v=NA_real_,d='int32'))) {
    mask <- .mask_recover(matrix(if(isTRUE(is.finite(case$v))) trunc(case$v) else 1,1,1))
    mask[] <- case$v
    p <- tempfile(fileext='.npy');withr::defer(unlink(p))
    expect_error(at_write_npy(mask,p,dtype=case$d,legend=FALSE))
    expect_false(file.exists(p))
    writeBin(as.raw(17),p)
    expect_error(at_write_npy(mask,p,dtype=case$d,legend=FALSE,overwrite=TRUE))
    expect_identical(readBin(p,'raw',n=100),as.raw(17))
  }
})
test_that('A26 TIFF quantitative samples and dtype are raw and correctly oriented', {
  skip_if_not_installed('tiff')
  cases <- list(uint8=c(0,1,127,255,255,100,2,0),uint16=c(0,1,32767,65535,65535,100,2,0),
    int16=c(-32768,-1,0,32767,1,2,3,4),float32=c(-2,.5,NaN,Inf,3,4,5,6))
  for (nm in names(cases)) {
    img<-at_read_image(reader_fixture(paste0('reference-',nm,'.tif'),'images'),backend='tiff')
    expect_equal(at_tile(img)[,,1],matrix(cases[[nm]],2,4,byrow=TRUE))
    expect_identical(img$dtype,nm)
  }
  img <- at_read_image(reader_fixture('reference-rgb.tif','images'),backend='tiff')
  expect_equal(at_tile(img),reader_cube());expect_identical(img$dtype,'uint16')
  rd <- .read_mask_matrix(reader_fixture('reference-int16.tif','images'),rlang::current_env())
  expect_equal(rd$m,matrix(cases$int16,2,4,byrow=TRUE))
  expect_error(.read_mask_matrix(reader_fixture('reference-rgb.tif','images'),rlang::current_env()),'plane')
  expect_error(.read_mask_matrix(reader_fixture('reference-float32.tif','images'),rlang::current_env()),'integer|finite')
})
test_that('A26 A27 automatic detection refuses lossy generic fallback', {
  for (backend in c('tiff','ometiff')) {
    orig <- .backend_registry[[backend]]
    replacement <- orig;replacement$available_fn<-function() FALSE
    .backend_registry[[backend]]<-replacement
    tryCatch(expect_error(at_read_image(reader_fixture(if(backend=='tiff') 'reference-rgb.tif' else 'reference.ome.tif','images')),
      'requires|capability|installed'),finally={.backend_registry[[backend]]<-orig})
  }
})
test_that('A27 OME axes calibration channels and actual anisotropic levels agree', {
  skip_if_not_installed('RBioFormats');skip_if_not_installed('xml2')
  img <- at_read_image(reader_fixture('reference.ome.tif','images'))
  expect_identical(img$dims,c(5L,4L));expect_equal(as.vector(at_tile(img)),as.vector(reader_cube()))
  expect_equal(img$pixel_size,c(.5,2));expect_equal(img$pixel_unit,'µm')
  expect_equal(img$wavelengths,c(450,550,650));expect_equal(img$wavelength_unit,'nm')
  expect_equal(img$band_names,c('blue','green','red'));expect_equal(img$dtype,'uint16')
  pyr <- at_read_image(reader_fixture('reference-pyramid.ome.tif','images'))
  expect_equal(pyr$level_dims,list(c(64L,48L),c(16L,24L),c(8L,12L)))
  expect_equal(at_tile(pyr,level=1,xrange=c(2,3),yrange=c(1,2),bands=1)[,,1],matrix(c(115,119,135,139),2,2,byrow=TRUE))
  p <- tempfile(fileext='.rds');withr::defer(unlink(p))
  at_save_project(at_project(pyr),p)
  back <- at_load_project(p)$image
  expect_equal(at_tile(back,level=1),at_tile(pyr,level=1))
  expect_identical(back$source_descriptor$reader_contract,pyr$source_descriptor$reader_contract)
  for(axes in c('ZCYX','TCYX')) expect_error(at_read_image(reader_fixture(paste0('reference-',axes,'.ome.tif'),'images')),'Z|time|axes|selection')
})
test_that('reader persistence refuses stale decoding contracts and reopens corrected data', {
  skip_if_not_installed('tiff')
  img <- at_read_image(reader_fixture('reference-uint8.tif','images'),backend='tiff')
  project <- at_project(img);p<-tempfile(fileext='.rds');withr::defer(unlink(p))
  at_save_project(project,p);expect_equal(at_tile(at_load_project(p)$image),at_tile(img))
  for (field in c('dtype','pixel_size','pixel_unit','wavelengths','band_names')) {
    stale <- readRDS(p)
    stale$image[[field]] <- switch(field,dtype='uint16',pixel_size=c(2,3),pixel_unit='mm',wavelengths=500,band_names='wrong')
    saveRDS(stale,p)
    restored<-at_load_project(p)
    expect_null(restored$image$handle)
    expect_error(at_tile(restored$image),'metadata|contract|revalidat')
    at_save_project(project,p,overwrite=TRUE)
  }
})
test_that('A26 independent RGB TIFF channels retain 16-bit raw codes', {
  skip_if_not_installed('tiff')
  expect_equal(at_tile(at_read_image(reader_fixture('reference-rgb.tif','images'),backend='tiff')),reader_cube())
  expect_equal(.read_mask_matrix(reader_fixture('reference-int16.tif','images'),rlang::current_env())$m,
    matrix(c(-32768,-1,0,32767,1,2,3,4),2,4,byrow=TRUE))
})
test_that('A26 missing raw TIFF capability never falls through for masks', {
  testthat::local_mocked_bindings(.tiff_available=function() FALSE)
  expect_error(.read_mask_matrix(reader_fixture('reference-uint16.tif','images'),rlang::current_env()),'requires|capability')
})
test_that('plain TIFF ambiguous directories cannot silently discard planes', {
  skip_if_not_installed('tiff')
  p<-tempfile(fileext='.tif');withr::defer(unlink(p))
  tiff::writeTIFF(list(matrix(0,2,3),matrix(1,2,3)),p,bits.per.sample=8L)
  expect_error(at_read_image(p,backend='tiff'),'ambiguous|pyramid|directories')
})
test_that('A13 truncated NPY preambles and bounded headers fail explicitly', {
  for (n in 0:9) {
    p<-tempfile(fileext='.npy');withr::defer(unlink(p))
    writeBin(as.raw(c(147,78,85,77,80,89,1,0,80,0)[seq_len(n)]),p)
    expect_error(at_read_npy(p),'[Ss]hort|truncat|header')
  }
  p<-reader_npy_header("{'descr':'|u1', 'fortran_order':False, 'shape':(1,1)}")
  withr::defer(unlink(p));withr::local_options(annotatR.max_npy_header_bytes=10)
  expect_error(at_read_npy(p),'header.*limit')
})
test_that('legacy reader metadata requires deliberate source revalidation', {
  skip_if_not_installed('tiff')
  img <- at_read_image(reader_fixture('reference-uint16.tif','images'),backend='tiff')
  img$handle<-NULL;img$meta$reader_contract<-NULL
  restored <- .reopen_image(img)
  expect_null(restored$handle);expect_error(at_tile(restored),'revalidate')
  fresh <- at_relink_source(restored,img$source)
  expect_equal(as.vector(at_tile(fresh)),c(0,65535,1,100,32767,2,65535,0))
})

test_that('unsupported TIFF integer32 and float64 types fail explicitly', {
  skip_if_not_installed('tiff')
  for (nm in c('int32','uint32','float64')) expect_error(
    at_read_image(reader_fixture(paste0('reference-',nm,'.tif'),'images'),backend='tiff'),'Unsupported|unsupported')
})
