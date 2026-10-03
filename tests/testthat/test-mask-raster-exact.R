mask_raster_fixture <- function(name) test_path('fixtures', 'mask-raster', name)
mask_raster_reference <- matrix(c(0L,1L,255L,256L,4096L,32767L,32768L,65535L), 2, byrow=TRUE)

# Simulate only package discovery; all encoding/decoding remains real.
mask_raster_without <- function(fun, packages) {
  env <- new.env(parent=environment(fun))
  env$requireNamespace <- function(package, ...) !package %in% packages && base::requireNamespace(package, ...)
  environment(fun) <- env
  fun
}

test_that('A14 choices accept scalar whole numbers and reject explicit vectors', {
  for (x in list(8L, 8, 16L, 16)) expect_equal(.check_choice(x,c(16L,8L)), x)
  for (x in list(NULL, NA, NA_real_, NaN, Inf, -Inf, 8.5, 0, 32, '8', TRUE, c(16L,8L), 8+0i, list(8L))) {
    expect_error(.check_choice(x,c(16L,8L)), 'must be')
  }
  for (x in list(c('a','b'), c('b','a'), 'a-long', NA_character_, 1, list('a'))) {
    expect_error(.check_choice(x,c('a','b')), 'must be')
  }
  expect_identical(.check_choice('a',c('a','b')), 'a')
  expect_true(file.exists(at_example_path()))
  expect_error(at_example_path(c('tissue','multiplex','cube')), 'must be')
  mask <- at_mask(square_roi(), dims=c(10,10))
  path <- withr::local_tempfile(fileext='.rds')
  expect_invisible(at_write_mask(mask,path,format='rds'))
  expect_error(at_write_mask(mask,path,format='rds',bits=c(16L,8L)), 'bits')
  expect_error(at_read_mask(path,connectivity=c(8L,4L)), 'connectivity')
  expect_error(at_mask(square_roi(),dims=c(10,10),type=c('binary','labelled','multiclass')), 'type')
})

test_that('A32 PNG grayscale raw codes survive depth and gamma without relabelling', {
  skip_if_not_installed('magick')
  for (name in c('gray16.png',paste0('gray16-gamma',c('20000','100000','220000'),'.png'))) {
    expect_identical(.read_mask_matrix(mask_raster_fixture(name),call=environment())$m, mask_raster_reference)
  }
  expect_identical(.read_mask_matrix(mask_raster_fixture('gray8.png'),call=environment())$m,
                   matrix(c(0L,1L,9L,10L,13L,32L,128L,255L),2,byrow=TRUE))
  expect_identical(.read_mask_matrix(mask_raster_fixture('whitespace8.png'),call=environment())$m,
                   matrix(c(10L,13L,32L,9L,35L,0L,1L,255L),2,byrow=TRUE))
  for (bits in c(8L,16L)) for (kind in c('zero','binary','extrema')) {
    expected <- switch(kind,zero=matrix(0L,2,3),binary=matrix(c(0L,1L,0L,1L,0L,1L),2,byrow=TRUE),
      extrema=matrix(c(0L,2^bits-1L,0L,2^bits-1L,0L,2^bits-1L),2,byrow=TRUE))
    expect_equal(.read_mask_matrix(mask_raster_fixture(paste0(kind,bits,'.png')),environment())$m,expected)
  }
  layer <- at_read_mask(mask_raster_fixture('gray16.png'))
  expect_setequal(layer$meta$mask_metadata$codebook$value, c(1L,255L,256L,4096L,32767L,32768L,65535L))
})

test_that('A32 PNG colour, alpha and palette samples reject before polygonisation', {
  skip_if_not_installed('magick')
  for (name in c('rgb8.png','rgba8.png','grayalpha8.png','palette8.png','gray1.png')) {
    expect_error(at_read_mask(mask_raster_fixture(name)), 'grayscale|colour|color|channel|alpha')
  }
})

test_that('A29 optional magick writer preserves requested TIFF depth and raw codes', {
  skip_if_not_installed('magick'); skip_if_not_installed('tiff')
  writer <- mask_raster_without(.write_mask_raster,'tiff')
  for (bits in c(8L,16L)) {
    samples <- list(matrix(0L,2,3), matrix(c(0L,1L,0L,1L,0L,1L),2,byrow=TRUE),
                    matrix(c(0L,2^bits-1L,0L,2^bits-1L,0L,2^bits-1L),2,byrow=TRUE))
    if (bits==16L) samples <- c(samples,list(mask_raster_reference))
    for (m in samples) {
      path <- withr::local_tempfile(fileext='.tif')
      writer(m,path,bits,'tiff',environment())
      raw <- tiff::readTIFF(path,as.is=TRUE,info=TRUE)
      expect_equal(attr(raw,'bits.per.sample'),bits)
      expect_equal(as.vector(raw),as.vector(m))
      expect_identical(dim(raw),dim(m))
    }
  }
})

test_that('A29 PNG output declares exact 8/16-bit grayscale even for binary samples', {
  skip_if_not_installed('magick')
  for (bits in c(8L,16L)) {
    for (kind in c('zero','binary','extrema')) {
      path <- withr::local_tempfile(fileext='.png')
      maximum <- 2^bits-1L
      m <- switch(kind,zero=matrix(0L,2,3),binary=matrix(c(0L,1L,0L,1L,0L,1L),2,byrow=TRUE),
                  extrema=matrix(c(0L,maximum,0L,maximum,0L,maximum),2,byrow=TRUE))
      .write_mask_raster(m,path,bits,'png',environment())
      head <- readBin(path,'raw',n=26)
      expect_equal(as.integer(head[25:26]),c(bits,0L))
      expect_equal(.read_mask_matrix(path,environment())$m,m)
    }
  }
})

test_that('A29 raster export rejects unsigned range errors before touching output', {
  for (format in c('tiff','png')) for (value in c(-1,-2147483648,2147483648,Inf,NaN,.5,65536)) {
    m <- matrix(0L,2,2)
    code <- if (value %in% c(-1,65536)) as.integer(value) else 1L
    lg <- tibble::tibble(value=code,label='x')
    mask <- .new_annot_mask(m,lg,0L,c(2L,2L),'labelled')
    mask[1,1] <- value
    path <- withr::local_tempfile(fileext=paste0('.',format))
    expect_error(at_write_mask(mask,path,format=format,legend=FALSE), 'integer|range|8-bit|16-bit|unsigned')
    expect_false(file.exists(path))
    writeBin(charToRaw('preserve'),path)
    expect_error(at_write_mask(mask,path,format=format,legend=FALSE,overwrite=TRUE), 'integer|range|8-bit|16-bit|unsigned')
    expect_identical(readBin(path,'raw',n=8),charToRaw('preserve'))
  }
})

test_that('A29 absent exact raster writers fail explicitly without creating output', {
  writer <- mask_raster_without(.write_mask_raster,c('tiff','magick'))
  path <- withr::local_tempfile(fileext='.tif')
  expect_error(writer(matrix(0L,2,2),path,16L,'tiff',environment()),'requires|capability')
  expect_false(file.exists(path))
})

test_that('exact grayscale capability failures reject without output', {
  skip_if_not_installed('magick')
  testthat::local_mocked_bindings(.mask_magick_probe=function(bits) FALSE)
  expect_error(at_read_mask(mask_raster_fixture('gray16.png')), 'capability|quantum')
  writer <- mask_raster_without(.write_mask_raster,'tiff')
  path <- withr::local_tempfile(fileext='.tif')
  expect_error(writer(mask_raster_reference,path,16L,'tiff',environment()), 'capability|quantum')
  expect_false(file.exists(path))
})

test_that('PGM binary whitespace and malformed headers are handled exactly', {
  samples <- as.raw(c(9L,10L,13L,32L,35L,255L))
  for (i in seq_along(samples)) {
    bytes <- c(charToRaw('P5\n# fixture\n1 1\n255\n'),samples[i])
    expect_identical(.mask_pgm_decode(bytes,8L),matrix(as.integer(samples[i]),1,1))
  }
  for (bytes in list(charToRaw('P2\n1 1\n255\n0'), charToRaw('P5\n0 1\n255\n'),
                     c(charToRaw('P5\n1 1\n65535\n'),as.raw(0L)),
                     c(charToRaw('P5\n1 1\n255\n'),as.raw(c(0L,0L))))) {
    expect_error(.mask_pgm_decode(bytes,8L), 'grayscale|payload')
  }
  path <- withr::local_tempfile(fileext='.png')
  writeBin(charToRaw('not a PNG'),path)
  expect_error(at_read_mask(path),'PNG header')
})

test_that('A14 connectivity preserves diagonal membership and disconnected regions', {
  path <- withr::local_tempfile(fileext='.rds')
  # One diagonal pair and one distant pixel: one joined component plus one
  # isolated component under eight-connectivity, three under four-connectivity.
  m <- matrix(c(1L,0L,0L,0L,0L, 0L,1L,0L,0L,1L),2,byrow=TRUE)
  saveRDS(m,path)
  for (connectivity in c(4L,8L)) {
    expect_warning(layer <- at_read_mask(path,connectivity=connectivity), NA)
    expect_length(layer$rois,if(connectivity==4L) 3L else 2L)
    expect_equal(sum(vapply(layer$rois,at_roi_area,numeric(1))),3)
    expect_identical(as.matrix(at_mask(layer,'binary',dims=c(5,2)))!=0,m!=0)
  }
  for (bad in list(NULL, NA_integer_, Inf, 4.5, 0, 3, 9, '8', TRUE)) {
    expect_error(at_read_mask(path,connectivity=bad),'connectivity')
  }
})


test_that('A32 grayscale PNG tRNS rejects before transparency is discarded', {
  for (name in c('gray8-trns.png','gray16-trns.png','gray16-trns-unused.png')) {
    path <- mask_raster_fixture(name)
    expect_error(.mask_png_header(path, environment()), 'transparen|alpha')
    # No optional decoder is required: the file declares unsupported semantics.
    expect_error(.read_mask_matrix(path, environment()), 'transparen|alpha')
    expect_error(at_read_mask(path), 'transparen|alpha')
  }
})

test_that('PNG chunk validation rejects truncated payloads before decoding', {
  original <- readBin(mask_raster_fixture('gray8.png'), 'raw', n=1000)
  # The first post-IHDR chunk is IDAT: its length occupies bytes 34:37.
  oversized <- original
  oversized[34:37] <- as.raw(c(127L,255L,255L,255L))
  for (bytes in list(original[1:37], original[1:45], oversized, original[1:(length(original)-12L)])) {
    path <- withr::local_tempfile(fileext='.png')
    writeBin(bytes,path)
    expect_error(.mask_png_header(path,environment()), 'PNG|chunk|truncated')
  }
})
