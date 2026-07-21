# Optional backends: skip the read paths when their packages are absent, but
# always verify that a missing dependency produces an informative error rather
# than a crash.

test_that("reading a .cu3 without cuvis.r errors informatively", {
  skip_if(nzchar(system.file(package = "cuvis.r")))
  f <- withr::local_tempfile(fileext = ".cu3")
  writeLines("x", f)
  expect_error(at_read_image(f), "not installed|cuvis|not available")
})

test_that("reading a .qptiff without RBioFormats errors informatively", {
  skip_if(requireNamespace("RBioFormats", quietly = TRUE))
  f <- withr::local_tempfile(fileext = ".qptiff")
  writeLines("x", f)
  expect_error(at_read_image(f), "not installed|RBioFormats|not available")
})

test_that("the tivita backend reads ENVI-conformant cubes and rejects proprietary", {
  # ENVI-conformant path.
  arr <- array(as.integer(runif(3 * 3 * 4) * 1000), dim = c(3, 3, 4))
  dir <- withr::local_tempdir()
  hdr <- file.path(dir, "t.hdr")
  con <- file(file.path(dir, "t.dat"), "wb")
  writeBin(as.integer(as.vector(aperm(arr, c(2, 1, 3)))), con, size = 2L)
  close(con)
  writeLines(c("ENVI", "samples = 3", "lines = 3", "bands = 4",
               "data type = 12", "interleave = bsq", "byte order = 0"), hdr)
  img <- at_read_image(hdr, backend = "tivita")
  expect_identical(img$backend, "tivita")
  expect_equal(at_tile(img), arr, tolerance = 0)
  # Neither an ENVI export nor a SpecCube: aborts with a clear message.
  prop <- withr::local_tempfile(fileext = ".tvcube")
  writeLines("binary", prop)
  expect_error(at_read_image(prop, backend = "tivita"), "ENVI|SpecCube|Tivita cube")
})

test_that("cuvis and ometiff report availability matching installation", {
  expect_identical(
    at_backend_get("cuvis")$available_fn(),
    nzchar(system.file(package = "cuvis.r"))
  )
  expect_identical(
    at_backend_get("ometiff")$available_fn(),
    requireNamespace("RBioFormats", quietly = TRUE)
  )
})
