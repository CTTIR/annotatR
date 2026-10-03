test_that("A14 numeric bits choices accept explicit integers", {
  skip_if_not_installed("tiff")
  mask <- at_mask(square_roi(), dims=c(10,10))
  for (bits in c(8L,16L)) {
    path <- tempfile(fileext=".tif")
    withr::defer(unlink(c(path,paste0(path,".legend.json"))))
    expect_no_error(at_write_mask(mask,path,bits=bits))
  }
})

test_that("A14 numeric connectivity choices accept explicit integers", {
  path <- tempfile(fileext=".rds"); withr::defer(unlink(path))
  saveRDS(matrix(c(1L,0L,0L,1L),2,2),path)
  for (connectivity in c(4L,8L)) {
    expect_no_error(at_read_mask(path,connectivity=connectivity))
  }
})

test_that("A14 default eight-connectivity joins diagonal foreground pixels", {
  path <- tempfile(fileext=".rds"); withr::defer(unlink(path))
  saveRDS(matrix(c(1L,0L,0L,1L),2,2),path)
  # This independently reaches polygonisation without explicit-choice validation.
  layer <- at_read_mask(path)
  expect_length(layer$rois, 1L)
  expect_equal(sum(vapply(layer$rois, at_roi_area, numeric(1))), 2)
})

test_that("A14 four-connectivity separates diagonal foreground pixels", {
  path <- tempfile(fileext=".rds"); withr::defer(unlink(path))
  saveRDS(matrix(c(1L,0L,0L,1L),2,2),path)
  layer <- at_read_mask(path, connectivity=4L)
  expect_length(layer$rois, 2L)
})

test_that("A17 binary masks reject colliding nonzero background", {
  expect_error(at_mask(square_roi(),dims=c(10,10),background=1L),
               "[Bb]ackground|[Bb]inary|[Cc]ollision")
})

test_that("A19 RDS mask import restores stored label semantics", {
  mask <- at_mask(at_layer_add(at_layer("L"),square_roi("tumour")),
                  type="multiclass",dims=c(10,10))
  path <- tempfile(fileext=".rds"); withr::defer(unlink(path))
  at_write_mask(mask,path,format="rds")
  layer <- at_read_mask(path)
  expect_identical(layer$labels, "tumour")
  expect_equal(sum(vapply(layer$rois, at_roi_area, numeric(1))), 9)
})

test_that("A20 bitfield statistics include overlapping class membership", {
  layer <- at_layer_add(at_layer_add(at_layer("L"),at_roi_rect(0,0,6,6,"a")),
                        at_roi_rect(4,4,10,10,"b"))
  mask <- at_mask(layer,type="multiclass",values=c(a=1L,b=2L),overlap="bitor",dims=c(10,10))
  stats <- at_mask_stats(mask)
  expect_equal(stats$n_px, c(36L,36L))
  expect_equal(stats$frac_total, c(.36,.36))
  expect_equal(stats$centroid_x, c(3,7))
  expect_equal(at_mask_legend(at_mask_preview(mask,max_dim=5L))$n_px,c(9L,9L))
})
