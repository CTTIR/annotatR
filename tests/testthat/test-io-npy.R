# NumPy .npy integer-mask I/O: the interchange format for the HSI ground-truth
# masks (anatomy/state/uncertain/artefact) written by the Python annotator. The
# bridge must be lossless (bitfield codes survive) and faithful to numpy's
# C/Fortran order so a round trip and a Python consumer agree on every pixel.

# A minimal, independent C-order uint8 .npy writer, to check the reader without
# depending on the package's own writer (avoids a circular test).
write_npy_c_u1 <- function(m, path) {
  H <- nrow(m); W <- ncol(m)
  dict <- sprintf("{'descr': '|u1', 'fortran_order': False, 'shape': (%d, %d), }", H, W)
  total <- 10L + nchar(dict) + 1L
  pad <- (64L - (total %% 64L)) %% 64L
  dict <- paste0(dict, strrep(" ", pad), "\n")
  con <- file(path, "wb"); on.exit(close(con))
  writeBin(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)), con)
  writeBin(as.integer(nchar(dict)), con, size = 2L, endian = "little")
  writeBin(charToRaw(dict), con)
  writeBin(as.integer(t(m)), con, size = 1L, endian = "little") # row-major
}

anat_mask <- function() {
  lyr <- at_layer("anatomy", labels = c("wound", "healthy"))
  lyr <- at_layer_add(lyr, at_roi_rect(1, 1, 5, 5, label = "wound"))
  lyr <- at_layer_add(lyr, at_roi_rect(6, 6, 9, 9, label = "healthy"))
  at_mask(lyr, type = "multiclass", values = c(wound = 1L, healthy = 3L),
          dims = c(10, 10))
}

test_that(".npy_read_matrix reads a C-order uint8 array faithfully", {
  m0 <- matrix(c(1, 2, 3, 4, 5, 6), nrow = 2, ncol = 3, byrow = TRUE)
  p <- tempfile(fileext = ".npy")
  write_npy_c_u1(m0, p)
  got <- .npy_read_matrix(p)
  expect_identical(dim(got), c(2L, 3L))
  expect_equal(got, matrix(c(1L, 2L, 3L, 4L, 5L, 6L), 2, 3, byrow = TRUE))
})

test_that("an annot_mask round-trips through .npy losslessly", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  m2 <- at_read_npy(p)
  expect_equal(as.matrix(m2), as.matrix(m))
  expect_identical(attr(m2, "dims"), attr(m, "dims"))
})

test_that("the sidecar legend recovers labels on read", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  lg <- at_mask_legend(at_read_npy(p))
  expect_identical(lg$label[lg$value == 1L], "wound")
  expect_identical(lg$label[lg$value == 3L], "healthy")
})

test_that("composite bitfield codes survive a round trip (not polygonised away)", {
  lyr <- at_layer("artefact", labels = c("specular", "blood"))
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 6, 6, label = "specular"))
  lyr <- at_layer_add(lyr, at_roi_rect(4, 4, 10, 10, label = "blood"))
  m <- at_mask(lyr, type = "multiclass", values = c(specular = 1L, blood = 2L),
               overlap = "bitor", dims = c(10, 10))
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p, dtype = "int32")
  expect_identical(.npy_read_matrix(p)[5, 5], 3L)
})

test_that("at_write_npy refuses to overwrite without overwrite = TRUE", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  expect_error(at_write_npy(m, p), "exists")
  expect_invisible(at_write_npy(m, p, overwrite = TRUE))
})

test_that("at_read_mask polygonises a .npy via the wired reader", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  lyr <- at_read_mask(p)
  expect_s3_class(lyr, "annot_layer")
  expect_true("wound" %in% vapply(lyr$rois, `[[`, character(1), "label"))
})

test_that("transpose reconciles native-order (x, y) files with annotatR [y, x]", {
  lyr <- at_layer("a", labels = "a")
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 3, 4, label = "a"))
  m <- at_mask(lyr, type = "multiclass", values = c(a = 1L), dims = c(6, 4))
  expect_identical(dim(as.matrix(m)), c(4L, 6L)) # [y, x]
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p, transpose = TRUE) # writes numpy shape (width, height) = (6, 4)
  expect_identical(dim(.npy_read_matrix(p)), c(6L, 4L)) # faithful read is [x, y]
  back <- at_read_npy(p, transpose = TRUE) # brings it back to [y, x]
  expect_equal(as.matrix(back), as.matrix(m))
  expect_identical(attr(back, "dims"), attr(m, "dims"))
})

test_that("transpose brings a TIVITA (width, height) ground truth into [y, x] (integration)", {
  f <- file.path("..", "..", "hsi-workbench", "reference", "annotations",
                 "HSI-BVZ-001_2019_11_11_22_11_52", "anatomy.npy")
  skip_if(!file.exists(f), "no workbench reference annotation present")
  gt <- at_read_npy(f, transpose = TRUE)
  expect_identical(dim(as.matrix(gt)), c(480L, 640L)) # [y, x], matches the cube
})

test_that("reads a real Python-written ground-truth .npy (integration)", {
  f <- file.path("..", "..", "hsi-workbench", "reference", "annotations",
                 "HSI-BVZ-001_2019_11_11_22_11_52", "anatomy.npy")
  skip_if(!file.exists(f), "no workbench reference annotation present")
  m <- .npy_read_matrix(f)
  expect_identical(dim(m), c(640L, 480L)) # numpy shape (640, 480), native (x, y)
  expect_true(all(unique(as.integer(m)) %in% 0:5))
  expect_gt(sum(m == 1L), 0L) # some 'wound' pixels
})
