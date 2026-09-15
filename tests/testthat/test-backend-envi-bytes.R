# Independent ENVI byte fixtures. Values follow value(y, x, b) = 100*b + 10*y + x
# (1-based) and are written value by value in each interleave's documented
# storage order with explicit loops, not with annotatR code or aperm().

envi_value <- function(y, x, b) 100 * b + 10 * y + x

write_envi_bytes <- function(dir, samples = 4L, lines = 3L, bands = 2L, interleave = "bsq",
                             dtype = 12L, endian = "little", offset = 0L, sentinel = 255L,
                             extra = character(), trailing = 0L) {
  size <- switch(as.character(dtype), "1" = 1L, "2" = 2L, "3" = 4L, "4" = 4L, "5" = 8L,
                 "12" = 2L, "13" = 4L)
  what <- if (dtype %in% c(4L, 5L)) "double" else "integer"
  dat <- file.path(dir, "cube.dat")
  con <- file(dat, "wb")
  if (offset > 0L) writeBin(as.raw(rep(sentinel, offset)), con)
  put <- function(v) {
    if (dtype == 13L && v >= 2^31) v <- v - 2^32
    writeBin(if (what == "double") as.double(v) else as.integer(v), con, size = size,
             endian = endian)
  }
  if (interleave == "bsq") {
    for (b in seq_len(bands)) for (y in seq_len(lines)) for (x in seq_len(samples)) put(envi_value(y, x, b))
  } else if (interleave == "bil") {
    for (y in seq_len(lines)) for (b in seq_len(bands)) for (x in seq_len(samples)) put(envi_value(y, x, b))
  } else {
    for (y in seq_len(lines)) for (x in seq_len(samples)) for (b in seq_len(bands)) put(envi_value(y, x, b))
  }
  if (trailing > 0L) writeBin(as.raw(rep(0L, trailing)), con)
  close(con)
  writeLines(c("ENVI", sprintf("samples = %d", samples), sprintf("lines = %d", lines),
               sprintf("bands = %d", bands), sprintf("header offset = %d", offset),
               sprintf("data type = %d", dtype), sprintf("interleave = %s", interleave),
               sprintf("byte order = %d", as.integer(endian == "big")), extra),
             file.path(dir, "cube.hdr"))
  file.path(dir, "cube.hdr")
}

expected_cube <- function(samples = 4L, lines = 3L, bands = 2L) {
  arr <- array(NA_real_, dim = c(lines, samples, bands))
  for (y in seq_len(lines)) for (x in seq_len(samples)) for (b in seq_len(bands)) arr[y, x, b] <- envi_value(y, x, b)
  arr
}

test_that("every interleave, dtype and byte order decodes to the independent formula", {
  combos <- expand.grid(interleave = c("bsq", "bil", "bip"), dtype = c(2L, 3L, 4L, 5L, 12L, 13L),
                        endian = c("little", "big"), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(combos))) {
    cb <- combos[i, ]
    d <- withr::local_tempdir()
    hdr <- write_envi_bytes(d, interleave = cb$interleave, dtype = cb$dtype, endian = cb$endian)
    img <- at_read_image(hdr)
    lab <- paste(cb$interleave, cb$dtype, cb$endian)
    expect_equal(at_tile(img), expected_cube(), tolerance = 0, label = lab)
    expect_equal(at_tile(img, xrange = c(2, 4), yrange = c(2, 3), bands = 2L),
                 expected_cube()[2:3, 2:4, 2, drop = FALSE], tolerance = 0, label = lab)
  }
})

test_that("uint8 and uint32 values above the signed range are exact", {
  d <- withr::local_tempdir()
  hdr <- write_envi_bytes(d, samples = 2L, lines = 1L, bands = 1L, dtype = 13L)
  con <- file(file.path(d, "cube.dat"), "wb")
  writeBin(as.integer(c(-1L, 7L)), con, size = 4L, endian = "little")  # 4294967295, 7
  close(con)
  expect_equal(as.numeric(at_tile(read <- at_read_image(hdr))), c(4294967295, 7))
  expect_identical(read$dtype, "uint32")
  d8 <- withr::local_tempdir()
  hdr8 <- write_envi_bytes(d8, samples = 2L, lines = 1L, bands = 1L, dtype = 1L)
  con <- file(file.path(d8, "cube.dat"), "wb")
  writeBin(as.raw(c(250, 3)), con)
  close(con)
  expect_equal(as.numeric(at_tile(at_read_image(hdr8))), c(250, 3))
})

test_that("the header offset is honoured, so sentinel bytes never become pixels (A10)", {
  d <- withr::local_tempdir()
  hdr <- write_envi_bytes(d, offset = 16L, sentinel = 255L, dtype = 1L)
  img <- at_read_image(hdr)
  expect_equal(at_tile(img), expected_cube(), tolerance = 0)
  expect_identical(at_hsi_meta(img)$header_bytes, 16L)
})

test_that("short payloads fail before reading and trailing bytes are recorded (A13)", {
  d <- withr::local_tempdir()
  hdr <- write_envi_bytes(d, dtype = 12L)
  con <- file(file.path(d, "cube.dat"), "wb")
  writeBin(as.integer(1:5), con, size = 2L)
  close(con)
  err <- tryCatch(at_read_image(hdr), error = function(e) e)
  expect_s3_class(err, "at_validation_error")
  expect_identical(err$code, "PAYLOAD_SHORT")
  d2 <- withr::local_tempdir()
  hdr2 <- write_envi_bytes(d2, trailing = 6L)
  expect_identical(at_read_image(hdr2)$meta$trailing_bytes, 6)
})

test_that("malformed headers and unsupported types are refused with codes", {
  d <- withr::local_tempdir()
  hdr <- write_envi_bytes(d)
  writeLines(c("ENVI", "samples = 4", "lines = 3", "data type = 12"), hdr)
  expect_identical(tryCatch(at_read_image(hdr), error = function(e) e$code), "ENVI_HEADER_INVALID")
  writeLines(c("ENVI", "samples = 4", "lines = 3", "bands = 2", "data type = 14"), hdr)
  expect_identical(tryCatch(at_read_image(hdr), error = function(e) e$code), "ENVI_DTYPE_UNSUPPORTED")
  writeLines(c("ENVI", "samples = 4", "lines = 3", "bands = 2", "interleave = xyz"), hdr)
  expect_identical(tryCatch(at_read_image(hdr), error = function(e) e$code), "ENVI_HEADER_INVALID")
  writeLines(c("NOT ENVI", "samples = 4"), hdr)
  expect_identical(tryCatch(at_read_image(hdr), error = function(e) e$code), "ENVI_HEADER_INVALID")
  writeLines(c("ENVI", "samples = 4.5", "lines = 3", "bands = 2"), hdr)
  expect_identical(tryCatch(at_read_image(hdr), error = function(e) e$code), "ENVI_HEADER_INVALID")
})

test_that("wavelengths, FWHM, band names, ignore value and scale factor are preserved", {
  d <- withr::local_tempdir()
  hdr <- write_envi_bytes(d, bands = 3L, extra = c(
    "wavelength units = Nanometers", "wavelength = {500, 600, 600}", "fwhm = {5, 5.5, 6}",
    "band names = {blue, green, red}", "data ignore value = -9999",
    "reflectance scale factor = 10000"
  ))
  img <- at_read_image(hdr)
  b <- at_bands(img)
  expect_identical(b$name, c("blue", "green", "red"))
  expect_equal(b$wavelength, c(500, 600, 600))
  expect_equal(b$fwhm, c(5, 5.5, 6))
  expect_identical(b$unit, rep("nm", 3))
  expect_identical(b$wavelength_status, c("ok", "duplicate", "duplicate"))
  hm <- at_hsi_meta(img)
  expect_identical(hm$nodata, -9999)
  expect_identical(hm$scale_factor, 10000)
  expect_identical(hm$calibration$status, "declared")
  expect_match(hm$calibration_digest, "^[0-9a-f]{64}$")
  expect_identical(hm$value_unit, "unknown")
  expect_identical(at_read_image(hdr, value_unit = "reflectance")$meta$value_unit, "reflectance")
  d2 <- withr::local_tempdir()
  hdr2 <- write_envi_bytes(d2, bands = 3L, extra = "wavelength = {500, 600}")
  b2 <- at_bands(at_read_image(hdr2))
  expect_identical(b2$wavelength_status, c("ok", "ok", "missing"))
  expect_true(is.na(b2$wavelength[3]))
  expect_match(at_read_image(hdr2)$meta$header_issues, "wavelength count")
})

test_that("windowed reads touch only the requested bytes and never the whole cube", {
  d <- withr::local_tempdir()
  hdr <- write_envi_bytes(d, samples = 40L, lines = 30L, bands = 5L, dtype = 4L)
  img <- at_read_image(hdr)
  .tile_cache_clear()
  at_read_stats(img, reset = TRUE)
  expect_identical(at_read_stats(img)$tiles, 0L)   # opening reads the header only
  tile <- at_tile(img, xrange = c(11, 14), yrange = c(21, 22), bands = c(2L, 5L))
  expect_equal(tile[, , 2], matrix(c(envi_value(21, 11:14, 5), envi_value(22, 11:14, 5)),
                                   nrow = 2, byrow = TRUE))
  st <- at_read_stats(img)
  expect_identical(st$tiles, 1L)
  expect_identical(st$file_bytes, 4 * 2 * 2 * 4)   # 4 columns, 2 rows, 2 bands, float32
  expect_lt(st$file_bytes, file.size(file.path(d, "cube.dat")))
  withr::local_options(annotatR.max_tile_bytes = 100)
  expect_identical(tryCatch(at_tile(img), error = function(e) e$code), "TILE_TOO_LARGE")
})
