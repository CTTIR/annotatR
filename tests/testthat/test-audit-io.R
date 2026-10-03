# Fixtures are written with base R, independently of the package encoders.
audit_envi <- function(values, offset = 0L) {
  path <- tempfile("audit-envi-")
  hdr <- paste0(path,".hdr")
  writeLines(c("ENVI", "samples = 2", "lines = 2", "bands = 1",
               "data type = 4", "interleave = bsq", "byte order = 0",
               paste("header offset =",offset)),hdr)
  writeBin(as.double(values),path,size=4L,endian="little")
  c(path,hdr)
}

audit_npy <- function(path, values) {
  header <- "{'descr': '<i4', 'fortran_order': False, 'shape': (2, 2), }"
  header <- paste0(header, strrep(" ",(64L - (10L+nchar(header)+1L) %% 64L) %% 64L), "\n")
  con <- file(path,"wb"); on.exit(close(con))
  writeBin(as.raw(c(147,78,85,77,80,89,1,0)),con)
  writeBin(as.integer(nchar(header)),con,size=2L,endian="little")
  writeBin(charToRaw(header),con)
  writeBin(as.integer(values),con,size=4L,endian="little")
}

test_that("A09 equal relative filenames refer to distinct source pixels", {
  skip_if_not_installed("tiff")
  dirs <- c(tempfile(),tempfile()); lapply(dirs,dir.create)
  withr::defer(lapply(dirs,unlink,recursive=TRUE))
  tiff::writeTIFF(matrix(0,2,2), file.path(dirs[1],"same.tif"),
                  bits.per.sample = 8L, compression = "none")
  tiff::writeTIFF(matrix(1,2,2), file.path(dirs[2],"same.tif"),
                  bits.per.sample = 8L, compression = "none")
  .tile_cache_clear(); withr::defer(.tile_cache_clear())
  a <- withr::with_dir(dirs[1],at_read_image("same.tif"))
  b <- withr::with_dir(dirs[2],at_read_image("same.tif"))
  expect_equal(as.vector(at_tile(a)),rep(0,4))
  expect_equal(as.vector(at_tile(b)), rep(255,4))
})

test_that("A10 ENVI header offset excludes the sentinel", {
  paths <- audit_envi(c(999,1,2,3,4),4L); withr::defer(unlink(paths))
  .tile_cache_clear(); withr::defer(.tile_cache_clear())
  # BSQ stream rows are (1,2), (3,4), independent of R storage order.
  expected <- array(c(1,3,2,4),c(2,2,1))
  expect_equal(at_tile(at_read_image(paths[2])),expected)
})

test_that("A13 ENVI truncated payload is rejected before materialisation", {
  paths <- audit_envi(c(1,2)); withr::defer(unlink(paths))
  expect_error(at_tile(at_read_image(paths[2])), "[Ss]hort|[Tt]runcat|[Pp]ayload|[Ss]ize|[Ll]ength")
})

test_that("A13 NPY truncated payload is rejected rather than recycled", {
  path <- tempfile(fileext=".npy"); withr::defer(unlink(path))
  audit_npy(path,c(1L,2L))
  expect_error(at_read_npy(path), "[Ss]hort|[Tt]runcat|[Pp]ayload|[Ss]ize|[Ll]ength")
})

test_that("A13 independent complete NPY control has correct orientation", {
  path <- tempfile(fileext=".npy"); withr::defer(unlink(path))
  audit_npy(path,c(1L,2L,3L,4L))
  expect_identical(as.matrix(at_read_npy(path)),matrix(1:4,2,2,byrow=TRUE))
})
